defmodule ExPilot.Arenas do
  @moduledoc """
  ExPilot's arenas on `Cauldron2D.Arenas`: a map each, its world an `ExPilot.Game`,
  its robots (`ExPilot.Robot`) and its ledger recorder seated beside it.

      :ok = ExPilot.Arenas.register(:dogfight, "priv/maps/dogfight.map.gz")
      ExPilot.Arenas.list()
      Cauldron2D.Player.join(ExPilot.Arenas.world_name(:dogfight), "alice", %{})

  The map of a registered arena is kept under its name for the clients to draw from;
  `map/1` reads it, `adopt/2` keeps a map that came from another node. Everything else
  — starting on the first join, stopping when idle, `humans/1`, `running/1` — is
  `Cauldron2D.Arenas`'s.
  """

  alias Cauldron2D.Arenas
  alias ExPilot.{Map, Mode, Robot}

  @type id :: atom()

  @doc """
  Make arena `id` known, on the map at `path` (or an `ExPilot.Map`), without starting it.

  ## Options

    * `:robots` — how many robots to seat, never more than the map's bases less one for
      every human in it and one to spare. Default: the map's `maxrobots`
    * `:hz` — the world's tick rate. Default `50`
    * `:seed`, `:lives`, `:only`, `:first_to` — the game's, as `ExPilot.Game.init/1` takes them
    * `:note` — what the lobby says of the arena. Default: its size and robots
    * `:mode` — its kind in the lobby. Default: `ExPilot.Game.mode/1` of the map
  """
  @spec register(id(), Path.t() | Map.t(), keyword()) :: :ok | {:error, term()}
  def register(id, path_or_map, opts \\ []) do
    with {:ok, arena} <- load(path_or_map) do
      name = Map.name(arena)
      adopt(name, arena)
      mode = Keyword.get(opts, :mode, ExPilot.Game.mode(arena))
      robots = Keyword.get(opts, :robots, Map.option(arena, :maxrobots))
      bases = length(Map.bases(arena))

      Arenas.register(id,
        game: ExPilot.Game,
        game_opts: [arena: arena] ++ Keyword.take(opts, [:seed, :lives, :only, :first_to]),
        hz: Keyword.get(opts, :hz, 50),
        name: Atom.to_string(id),
        map: name,
        note: Keyword.get(opts, :note, note(arena)),
        kind: Mode.kind(mode),
        teams: teams(arena),
        children: fn %{id: id, world: world, humans: humans} ->
          children(id, world, min(robots, bases - 1 - humans))
        end
      )
    end
  end

  defp children(id, world, robots) do
    recorder = %{
      id: {:recorder, id},
      start:
        {Cauldron2D.Ledger.Recorder, :start_link,
         [
           [
             world: world,
             arena: Atom.to_string(id),
             ledger: ExPilot.Ledger,
             on_result: &ExPilot.Duels.result(id, &1)
           ]
         ]},
      restart: :transient
    }

    seats =
      for n <- 1..max(robots, 0)//1 do
        %{
          id: {:robot, id, n},
          start:
            {Cauldron2D.Robot, :start_link,
             [[brain: Robot, world: world, number: n, brain_opts: [arena: id]]]},
          restart: :transient
        }
      end

    [recorder | seats]
  end

  @doc "Register arena `id` and start its world and robots at once."
  @spec open(id(), Path.t() | Map.t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def open(id, path_or_map, opts \\ []) do
    with :ok <- register(id, path_or_map, opts), do: Arenas.start(id)
  end

  defp load(%Map{} = arena), do: {:ok, arena}
  defp load(path) when is_binary(path), do: Map.parse_file(path)

  @doc "The name of arena `id`'s world; using it starts the world when it is not running."
  @spec world_name(id()) :: GenServer.name()
  def world_name(id), do: Arenas.world_name(id)

  @doc "Keep `arena` as the map called `name`, for a client on another node whose worlds run there; `map/1` finds it."
  @spec adopt(String.t(), Map.t()) :: :ok
  def adopt(name, %Map{} = arena), do: :persistent_term.put({__MODULE__, :map, name}, arena)

  @doc "The map a registered arena plays on, by the map's name."
  @spec map(String.t()) :: Map.t() | nil
  def map(name), do: :persistent_term.get({__MODULE__, :map, name}, nil)

  @doc "Every registered arena, as the lobby lists them, with the humans in each and its `mode` beside the kind."
  @spec list() :: [Cauldron2D.Client.Game.arena()]
  def list,
    do: for(arena <- Arenas.list(), do: Elixir.Map.put(arena, :mode, Mode.of_kind(arena.kind)))

  @doc "The map name and tick rate arena `id` was registered with, for an arena cut from the same map; `nil` for an unknown id."
  @spec registration(id()) :: %{map: String.t(), hz: pos_integer()} | nil
  def registration(id) do
    case Arenas.Table.get(id) do
      %{opts: opts} -> %{map: Keyword.fetch!(opts, :map), hz: Keyword.fetch!(opts, :hz)}
      nil -> nil
    end
  end

  @doc "The players in arena `id` who are not robots; `[]` while it is not running."
  @spec humans(id()) :: [term()]
  def humans(id), do: Arenas.humans(id)

  @doc "Whether arena `id`'s world is running."
  @spec running?(id()) :: boolean()
  def running?(id), do: Arenas.running?(id)

  @doc "Stop arena `id`'s world and robots, keeping it registered; `close/1` removes it."
  @spec stop(id()) :: :ok
  def stop(id), do: Arenas.stop(id)

  @doc "Stop arena `id` and remove it from the list."
  @spec close(id()) :: :ok
  def close(id), do: Arenas.close(id)

  defp note(arena) do
    {width, height} = Map.size(arena)

    case Map.option(arena, :maxrobots) do
      0 -> "#{width}×#{height}, no robots · practice"
      robots -> "#{width}×#{height}, #{robots} robots"
    end
  end

  defp teams(arena) do
    if Map.option(arena, :teamplay),
      do:
        arena
        |> Map.bases()
        |> Enum.map(& &1.team)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
        |> Enum.sort(),
      else: []
  end
end
