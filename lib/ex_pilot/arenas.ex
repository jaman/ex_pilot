defmodule ExPilot.Arenas do
  @moduledoc """
  The arenas a server offers: a map each, with a `Cauldron2D.World` and its robots under
  `ExPilot.ArenaSupervisor` that start on the first join and stop again once no player
  has been in them for a while.

      :ok = ExPilot.Arenas.register(:dogfight, "priv/maps/dogfight.map.gz")
      ExPilot.Arenas.list()
      Cauldron2D.Player.join(ExPilot.Arenas.world_name(:dogfight), "alice", %{})

  `register/3` makes an arena known; `world_name/1` names its world, and any call to
  that name starts the world and seats the robots if they are not running.
  `ExPilot.Arenas.Sweeper` closes worlds that have had no human in them for
  its `:idle_after`. `list/0` is what the lobby shows, running or not, from the
  `ExPilot.Arenas.Table`. The map of a registered arena is kept under its name for the
  client to draw from; `map/1` reads it.
  """

  alias Cauldron2D.World
  alias ExPilot.{Map, Robot}
  alias ExPilot.Arenas.Table

  @type id :: atom()

  @doc """
  Make arena `id` known, on the map at `path` (or an `ExPilot.Map`), without starting it.

  ## Options

    * `:robots` — how many robots to seat, never more than the map's bases less one.
      Default: the map's `maxrobots`
    * `:hz` — the world's tick rate. Default `50`
    * `:seed` — the game's seed. Default: unique
  """
  @spec register(id(), Path.t() | Map.t(), keyword()) :: :ok | {:error, term()}
  def register(id, path_or_map, opts \\ []) do
    with {:ok, arena} <- load(path_or_map) do
      name = Map.name(arena)
      :persistent_term.put({__MODULE__, :map, name}, arena)
      Table.put(id, %{id: id, name: name, opts: opts, note: note(arena), teams: teams(arena), mode: ExPilot.Game.mode(arena)})
      :ok
    end
  end

  @doc "Register arena `id` and start its world and robots at once."
  @spec open(id(), Path.t() | Map.t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def open(id, path_or_map, opts \\ []) do
    with :ok <- register(id, path_or_map, opts), do: start(id)
  end

  @doc "Start the world and robots of registered arena `id`; the running pid if it already is."
  @spec start(id()) :: {:ok, pid()} | {:error, term()}
  def start(id) do
    case Table.get(id) do
      nil ->
        {:error, :unknown_arena}

      %{name: name, opts: opts} ->
        arena = map(name)

        spec = %{
          id: {:world, id},
          start:
            {World, :start_link,
             [
               [
                 game: ExPilot.Game,
                 game_opts: [arena: arena] ++ Keyword.take(opts, [:seed]),
                 hz: Keyword.get(opts, :hz, 50),
                 name: {:via, Registry, {ExPilot.Registry, {:world, id}}}
               ]
             ]},
          restart: :transient
        }

        case DynamicSupervisor.start_child(ExPilot.ArenaSupervisor, spec) do
          {:ok, pid} ->
            seat_robots(id, min(Keyword.get(opts, :robots, Map.option(arena, :maxrobots)), length(Map.bases(arena)) - 1))
            {:ok, pid}

          {:error, {:already_started, pid}} ->
            {:ok, pid}

          other ->
            other
        end
    end
  end

  defp load(%Map{} = arena), do: {:ok, arena}
  defp load(path) when is_binary(path), do: Map.parse_file(path)

  defp seat_robots(id, count), do: seat_robots(id, Enum.to_list(1..count//1), [])

  defp seat_robots(id, numbers, seated) do
    for n <- numbers, n not in seated do
      DynamicSupervisor.start_child(ExPilot.ArenaSupervisor, %{
        id: {:robot, id, n},
        start: {Robot, :start_link, [[world: world_name(id), number: n, arena: id]]},
        restart: :transient
      })
    end

    :ok
  end

  @doc """
  Seat the robots arena `id` is short of: as many as it was opened with, never more than
  the map's bases less one for every human in it and one to spare. A robot that left to
  make room for a player comes back this way once the player has gone.
  """
  @spec reseat(id()) :: :ok
  def reseat(id) do
    with %{opts: opts, name: name} <- Table.get(id), true <- running?(id), %Map{} = arena <- map(name) do
      seated = Registry.select(ExPilot.Registry, [{{{:robot, id, :"$1"}, :_, :_}, [], [:"$1"]}])
      wanted = min(Keyword.get(opts, :robots, Map.option(arena, :maxrobots)), length(Map.bases(arena)) - 1 - length(humans(id)))
      numbers = Enum.take(Enum.reject(1..max(wanted, 0)//1, &(&1 in seated)), max(wanted - length(seated), 0))
      seat_robots(id, numbers, seated)
    else
      _ -> :ok
    end
  end

  @doc "The name of arena `id`'s world; using it starts the world when it is not running."
  @spec world_name(id()) :: GenServer.name()
  def world_name(id), do: {:via, __MODULE__.OnDemand, id}

  @doc "The pid of arena `id`'s world while it runs, else `nil`."
  @spec running(id()) :: pid() | nil
  def running(id) do
    case Registry.lookup(ExPilot.Registry, {:world, id}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc "Whether arena `id`'s world is running."
  @spec running?(id()) :: boolean()
  def running?(id), do: running(id) != nil

  @doc "The map a registered arena plays on, by the map's name."
  @spec map(String.t()) :: Map.t() | nil
  def map(name), do: :persistent_term.get({__MODULE__, :map, name}, nil)

  @doc "Every registered arena, as the lobby lists them, with the humans in each."
  @spec list() :: [Cauldron2D.Drafter.Client.Game.arena()]
  def list do
    for %{id: id, name: name, note: note, teams: teams, mode: mode} <- Table.all() do
      %{id: id, name: Atom.to_string(id), world: world_name(id), players: length(humans(id)), map: name, note: note, teams: teams, mode: mode}
    end
    |> Enum.sort_by(& &1.name)
  end

  @doc "The players in arena `id` who are not robots; `[]` while it is not running."
  @spec humans(id()) :: [term()]
  def humans(id) do
    case running(id) do
      nil -> []
      pid -> pid |> players() |> Enum.reject(&match?({:robot, _}, &1))
    end
  end

  defp players(pid) do
    World.players(pid)
  catch
    :exit, _stopped_meanwhile -> []
  end

  @doc "The ids of every arena whose world is running."
  @spec running_ids() :: [id()]
  def running_ids, do: Registry.select(ExPilot.Registry, [{{{:world, :"$1"}, :_, :_}, [], [:"$1"]}])

  defp note(arena) do
    {width, height} = Map.size(arena)

    case Map.option(arena, :maxrobots) do
      0 -> "#{width}×#{height}, no robots · practice"
      robots -> "#{width}×#{height}, #{robots} robots"
    end
  end

  defp teams(arena) do
    if Map.option(arena, :teamplay), do: team_numbers(arena), else: []
  end

  defp team_numbers(arena) do
    arena |> Map.bases() |> Enum.map(& &1.team) |> Enum.reject(&is_nil/1) |> Enum.uniq() |> Enum.sort()
  end

  @doc "Stop arena `id`'s world and robots, keeping it registered; `close/1` removes it."
  @spec stop(id()) :: :ok
  def stop(id) do
    robots = Registry.select(ExPilot.Registry, [{{{:robot, id, :_}, :"$1", :_}, [], [:"$1"]}])

    for pid <- robots ++ List.wrap(running(id)), is_pid(pid) do
      DynamicSupervisor.terminate_child(ExPilot.ArenaSupervisor, pid)
    end

    :ok
  end

  @doc "Stop arena `id` and remove it from the list."
  @spec close(id()) :: :ok
  def close(id) do
    stop(id)
    Table.delete(id)
    :ok
  end
end
