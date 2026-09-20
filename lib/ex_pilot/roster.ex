defmodule ExPilot.Roster do
  @moduledoc """
  Who is logged in, by what kind of client, in which arena, since when, and what
  happened lately: every session `Cauldron2D.Sessions` lists and every join and leave
  `Cauldron2D.World.Presence` announces, kept for the admin page and the lobby.

      ExPilot.Roster.online()
      #=> [%{id: "alice", kind: :web, arena: :dogfight, since: 1789718400},
      #    %{id: "bob", kind: :terminal, arena: nil, since: 1789718410}]
      ExPilot.Roster.lately()
      #=> [%{what: :left, id: "bob", kind: nil, arena: :dogfight, at: 1789718350}, ...]

  A pilot in an arena with no session of their own — a desktop client on another
  machine — is listed with `kind: nil`. Robots are left out. `lately/0` holds the last
  `#{100}` events, newest first: `:logged_in` and `:logged_out` with the session's kind,
  `:joined` and `:left` with the arena. `subscribe/0` brings `{:roster, :changed}` on every
  change, over `ExPilot.Web.PubSub`.
  """

  use GenServer

  alias Cauldron2D.Sessions
  alias Cauldron2D.World.Presence
  alias ExPilot.Arenas

  @kept 100
  @topic "roster"

  @type presence :: %{id: term(), kind: atom() | nil, arena: atom() | nil, since: integer()}
  @type event :: %{
          what: :logged_in | :logged_out | :joined | :left,
          id: term(),
          kind: atom() | nil,
          arena: atom() | nil,
          at: integer()
        }

  @doc false
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Every human logged in or in an arena, oldest first."
  @spec online() :: [presence()]
  def online, do: GenServer.call(__MODULE__, :online)

  @doc "The last logins, logouts, joins and leaves, newest first."
  @spec lately() :: [event()]
  def lately, do: GenServer.call(__MODULE__, :lately)

  @doc "Receive `{:roster, :changed}` in the calling process on every change."
  @spec subscribe() :: :ok
  def subscribe, do: Phoenix.PubSub.subscribe(ExPilot.Web.PubSub, @topic)

  @doc "Forget everyone and everything, as a test starts."
  @spec clear() :: :ok
  def clear, do: GenServer.call(__MODULE__, :clear)

  @impl true
  def init(_opts) do
    Presence.subscribe()
    Sessions.subscribe()
    {:ok, %{sessions: %{}, arenas: %{}, lately: []}}
  end

  @impl true
  def handle_call(:online, _from, state), do: {:reply, online(state), state}
  def handle_call(:lately, _from, state), do: {:reply, state.lately, state}

  def handle_call(:clear, _from, state),
    do: {:reply, :ok, %{state | sessions: %{}, arenas: %{}, lately: []}}

  @impl true
  def handle_info({:cauldron_sessions, :opened, session}, state) do
    changed(%{
      state
      | sessions: Map.put(state.sessions, session.pid, session),
        lately: noted(state.lately, :logged_in, session.id, session.kind, nil)
    })
  end

  def handle_info({:cauldron_sessions, :closed, session}, state) do
    changed(%{
      state
      | sessions: Map.delete(state.sessions, session.pid),
        lately: noted(state.lately, :logged_out, session.id, session.kind, nil)
    })
  end

  def handle_info({:cauldron_players, _world, _change, {:robot, _}}, state), do: {:noreply, state}

  def handle_info({:cauldron_players, world, :joined, id}, state) do
    arena = arena_of(world)
    presence = %{id: id, arena: arena, since: System.system_time(:second)}

    changed(%{
      state
      | arenas: Map.put(state.arenas, {world, id}, presence),
        lately: noted(state.lately, :joined, id, nil, arena)
    })
  end

  def handle_info({:cauldron_players, world, :left, id}, state) do
    changed(%{
      state
      | arenas: Map.delete(state.arenas, {world, id}),
        lately: noted(state.lately, :left, id, nil, arena_of(world))
    })
  end

  def handle_info(_other, state), do: {:noreply, state}

  defp changed(state) do
    Phoenix.PubSub.broadcast(ExPilot.Web.PubSub, @topic, {:roster, :changed})
    {:noreply, state}
  end

  defp online(state) do
    in_arenas = Map.values(state.arenas)

    sessions =
      for session <- Map.values(state.sessions) do
        arena = Enum.find_value(in_arenas, &if(&1.id == session.id, do: &1.arena))
        %{id: session.id, kind: session.kind, arena: arena, since: session.since}
      end

    logged_in = MapSet.new(sessions, & &1.id)

    only_in_arenas =
      for presence <- in_arenas,
          presence.id not in logged_in,
          do: %{id: presence.id, kind: nil, arena: presence.arena, since: presence.since}

    Enum.sort_by(sessions ++ only_in_arenas, &{&1.since, &1.id})
  end

  defp noted(lately, what, id, kind, arena) do
    event = %{what: what, id: id, kind: kind, arena: arena, at: System.system_time(:second)}
    Enum.take([event | lately], @kept)
  end

  defp arena_of(world) do
    Enum.find_value(Arenas.list(), fn %{id: id} ->
      if GenServer.whereis(Arenas.world_name(id)) == world, do: id
    end)
  end
end
