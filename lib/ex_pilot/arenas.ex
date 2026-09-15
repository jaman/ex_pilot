defmodule ExPilot.Arenas do
  @moduledoc """
  The arenas a server runs: one `Cauldron2D.World` each, with its robots, under
  `ExPilot.ArenaSupervisor`.

      {:ok, _} = ExPilot.Arenas.open(:dogfight, "priv/maps/dogfight.map.gz")
      ExPilot.Arenas.list()

  `list/0` is what the lobby shows. The map of an open arena is kept under its name for
  the client to draw from; `map/1` reads it.
  """

  alias Cauldron2D.World
  alias ExPilot.{Map, Robot}

  @type id :: atom()

  @doc """
  Open an arena `id` on the map at `path` (or an `ExPilot.Map`).

  ## Options

    * `:robots` — how many robots to seat. Default: the map's `maxrobots`
    * `:hz` — the world's tick rate. Default `50`
    * `:seed` — the game's seed. Default: unique
  """
  @spec open(id(), Path.t() | Map.t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def open(id, path_or_map, opts \\ []) do
    with {:ok, arena} <- load(path_or_map) do
      name = Map.name(arena)
      :persistent_term.put({__MODULE__, :map, name}, arena)
      :persistent_term.put({__MODULE__, :arena, id}, %{id: id, name: name})

      spec = %{
        id: {:world, id},
        start:
          {World, :start_link,
           [
             [
               game: ExPilot.Game,
               game_opts: [arena: arena] ++ Keyword.take(opts, [:seed]),
               hz: Keyword.get(opts, :hz, 50),
               name: world_name(id)
             ]
           ]},
        restart: :transient
      }

      with {:ok, pid} <- DynamicSupervisor.start_child(ExPilot.ArenaSupervisor, spec) do
        seat_robots(id, Keyword.get(opts, :robots, Map.option(arena, :maxrobots)))
        {:ok, pid}
      end
    end
  end

  defp load(%Map{} = arena), do: {:ok, arena}
  defp load(path) when is_binary(path), do: Map.parse_file(path)

  defp seat_robots(id, count) do
    for n <- 1..count//1 do
      DynamicSupervisor.start_child(ExPilot.ArenaSupervisor, %{
        id: {:robot, id, n},
        start: {Robot, :start_link, [[world: world_name(id), number: n, arena: id]]},
        restart: :transient
      })
    end

    :ok
  end

  @doc "The registered name of arena `id`'s world."
  @spec world_name(id()) :: GenServer.name()
  def world_name(id), do: {:via, Registry, {ExPilot.Registry, {:world, id}}}

  @doc "The map an open arena's world plays on, by the map's name."
  @spec map(String.t()) :: Map.t() | nil
  def map(name), do: :persistent_term.get({__MODULE__, :map, name}, nil)

  @doc "Every open arena, as the lobby lists them."
  @spec list() :: [Cauldron2D.Drafter.Client.Game.arena()]
  def list do
    for {{__MODULE__, :arena, id}, %{name: name}} <- :persistent_term.get(),
        pid = GenServer.whereis(world_name(id)),
        pid != nil do
      players = pid |> World.players() |> Enum.reject(&match?({:robot, _}, &1))
      %{id: id, name: Atom.to_string(id), world: world_name(id), players: length(players), map: name, teams: teams(name)}
    end
    |> Enum.sort_by(& &1.name)
  end

  defp teams(name) do
    case map(name) do
      nil -> []
      arena -> if Map.option(arena, :teamplay), do: team_numbers(arena), else: []
    end
  end

  defp team_numbers(arena) do
    arena |> Map.bases() |> Enum.map(& &1.team) |> Enum.reject(&is_nil/1) |> Enum.uniq() |> Enum.sort()
  end

  @doc "Close arena `id`, ending its world and robots."
  @spec close(id()) :: :ok
  def close(id) do
    robots = Registry.select(ExPilot.Registry, [{{{:robot, id, :_}, :"$1", :_}, [], [:"$1"]}])
    world = GenServer.whereis(world_name(id))

    for pid <- robots ++ List.wrap(world), is_pid(pid) do
      DynamicSupervisor.terminate_child(ExPilot.ArenaSupervisor, pid)
    end

    :persistent_term.erase({__MODULE__, :arena, id})
    :ok
  end
end
