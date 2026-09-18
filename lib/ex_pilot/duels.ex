defmodule ExPilot.Duels do
  @moduledoc """
  Challenges between two pilots: each is an arena of its own on a map both know, no
  robots, the two of them the only ones who may fly (anyone may watch), the first to a
  number of kills the winner; the arena closes ten seconds after. The challenged may
  decline and the challenger withdraw (`cancel/2`), and a duel nobody has flown for ten
  minutes expires; either way the arena goes.

      {:ok, duel} = ExPilot.Duels.challenge("alice", "bob", :dogfight, first_to: 5)
      :ok = ExPilot.Duels.cancel(duel.id, "bob")
      ExPilot.Duels.list()

  A duel is `%{id, arena, base, challenger, challenged, first_to, winner, ended, at}`:
  `arena` the id of its arena (`:"duel_<n>"`, in the lobby like any other, kind
  `duel`), `base` the arena it borrows the map from, `winner` `nil` until decided,
  `ended` `nil` while it is on, else `:won`, `:declined`, `:withdrawn` or `:expired`.
  `result/2` is what the ledger's recorder tells it when a duel ends;
  `ExPilot.Web.PubSub` topic `"duels"` carries `{:duels, :changed}` on every change.
  Ended duels stay listed for a minute.
  """

  use GenServer

  alias ExPilot.Arenas

  @close_after_ms 10_000
  @keep_done_ms 60_000
  @expire_after_ms 600_000

  @type duel :: %{
          id: pos_integer(),
          arena: atom(),
          base: atom(),
          challenger: String.t(),
          challenged: String.t(),
          first_to: pos_integer(),
          winner: String.t() | nil,
          ended: nil | :won | :declined | :withdrawn | :expired,
          at: DateTime.t()
        }

  @doc "Start the duels; `:name` (default the module, `nil` for none), `:expire_after` milliseconds a duel nobody flies lasts (default ten minutes)."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, if(name, do: [name: name], else: []))
  end

  @doc "Challenge `challenged` on arena `base`: `{:ok, duel}`, or `{:error, :unknown_arena | :yourself}`. Options: `:first_to` (default 5), `:duels` (the server, default the module)."
  @spec challenge(String.t(), String.t(), atom(), keyword()) :: {:ok, duel()} | {:error, term()}
  def challenge(challenger, challenged, base, opts \\ [])
  def challenge(same, same, _base, _opts), do: {:error, :yourself}

  def challenge(challenger, challenged, base, opts) do
    GenServer.call(
      Keyword.get(opts, :duels, __MODULE__),
      {:challenge, challenger, challenged, base, Keyword.get(opts, :first_to, 5)}
    )
  end

  @doc "Every duel: open ones first, then the last minute's ended ones."
  @spec list(GenServer.server()) :: [duel()]
  def list(duels \\ __MODULE__), do: GenServer.call(duels, :list)

  @doc "End duel `id` before it is fought: the challenged declines it, the challenger withdraws it. `{:error, :not_yours}` for anyone else, `{:error, :over}` once it has ended, `{:error, :unknown}` for no such duel."
  @spec cancel(pos_integer(), String.t(), keyword()) ::
          :ok | {:error, :not_yours | :over | :unknown}
  def cancel(id, by, opts \\ []),
    do: GenServer.call(Keyword.get(opts, :duels, __MODULE__), {:cancel, id, by})

  @doc "A result from a duel's arena, as the ledger's recorder saw it; a won one decides the duel."
  @spec result(GenServer.server(), atom(), map()) :: :ok
  def result(duels \\ __MODULE__, arena, row), do: GenServer.cast(duels, {:result, arena, row})

  @impl GenServer
  def init(opts),
    do:
      {:ok,
       %{duels: %{}, next: 1, expire_after: Keyword.get(opts, :expire_after, @expire_after_ms)}}

  @impl GenServer
  def handle_call({:challenge, challenger, challenged, base, first_to}, _from, state) do
    with %{map: map_name, hz: hz} <- Arenas.registration(base) || {:error, :unknown_arena},
         %ExPilot.Map{} = map <- Arenas.map(map_name) || {:error, :unknown_arena} do
      id = state.next
      arena = :"duel_#{id}"
      note = "#{challenger} vs #{challenged} · first to #{first_to}"

      :ok =
        Arenas.register(arena, map,
          robots: 0,
          lives: :unlimited,
          only: [challenger, challenged],
          first_to: first_to,
          note: note,
          mode: :duel,
          hz: hz
        )

      duel = %{
        id: id,
        arena: arena,
        base: base,
        challenger: challenger,
        challenged: challenged,
        first_to: first_to,
        winner: nil,
        ended: nil,
        at: DateTime.utc_now()
      }

      Process.send_after(self(), {:expire, id}, state.expire_after)
      changed()
      {:reply, {:ok, duel}, %{state | duels: Map.put(state.duels, id, duel), next: id + 1}}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:list, _from, state) do
    {open, done} =
      state.duels |> Map.values() |> Enum.sort_by(& &1.id) |> Enum.split_with(&(&1.ended == nil))

    {:reply, open ++ done, state}
  end

  def handle_call({:cancel, id, by}, _from, state) do
    case Map.get(state.duels, id) do
      nil -> {:reply, {:error, :unknown}, state}
      %{ended: ended} when ended != nil -> {:reply, {:error, :over}, state}
      %{challenged: ^by} = duel -> {:reply, :ok, ended(state, duel, :declined)}
      %{challenger: ^by} = duel -> {:reply, :ok, ended(state, duel, :withdrawn)}
      _other -> {:reply, {:error, :not_yours}, state}
    end
  end

  defp ended(state, duel, how) do
    Arenas.close(duel.arena)
    Process.send_after(self(), {:forget, duel.id}, @keep_done_ms)
    changed()
    %{state | duels: Map.put(state.duels, duel.id, %{duel | ended: how})}
  end

  @impl GenServer
  def handle_cast({:result, arena, %{won?: true, name: winner}}, state) do
    case Enum.find(state.duels, fn {_, duel} -> duel.arena == arena and duel.ended == nil end) do
      {id, duel} ->
        Process.send_after(self(), {:close, id}, @close_after_ms)
        Process.send_after(self(), {:forget, id}, @keep_done_ms)
        changed()

        {:noreply,
         %{state | duels: Map.put(state.duels, id, %{duel | winner: winner, ended: :won})}}

      nil ->
        {:noreply, state}
    end
  end

  def handle_cast({:result, _arena, _row}, state), do: {:noreply, state}

  @impl GenServer
  def handle_info({:close, id}, state) do
    case Map.get(state.duels, id) do
      nil -> :ok
      duel -> Arenas.close(duel.arena)
    end

    changed()
    {:noreply, state}
  end

  def handle_info({:forget, id}, state),
    do: {:noreply, %{state | duels: Map.delete(state.duels, id)}}

  def handle_info({:expire, id}, state) do
    case Map.get(state.duels, id) do
      %{ended: nil, arena: arena} = duel ->
        if Arenas.humans(arena) == [] and not fought?(arena),
          do: {:noreply, ended(state, duel, :expired)},
          else: Process.send_after(self(), {:expire, id}, state.expire_after) && {:noreply, state}

      _gone_or_over ->
        {:noreply, state}
    end
  end

  defp fought?(arena) do
    Arenas.running?(arena) and Cauldron2D.World.players(Arenas.world_name(arena)) != []
  end

  defp changed, do: Phoenix.PubSub.broadcast(ExPilot.Web.PubSub, "duels", {:duels, :changed})
end
