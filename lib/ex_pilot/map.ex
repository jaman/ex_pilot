defmodule ExPilot.Map do
  @moduledoc """
  A classic XPilot map read for play: the block legend, the features on it, and the
  options ExPilot honours.

      {:ok, arena} = ExPilot.Map.parse_file("priv/maps/dogfight.map.gz")
      ExPilot.Map.grid(arena).({12, 7})
      ExPilot.Map.bases(arena)
      ExPilot.Map.option(arena, :gravity)

  ## Block legend

  | char | tile |
  |---|---|
  | space, `.` | open |
  | `x` | wall |
  | `q` `s` `a` `w` | half walls filling the bottom-right, bottom-left, top-right and top-left corners |
  | `#` | fuel station |
  | `_`, `0`–`9` | base, team bases |
  | `r` `d` `f` `c` | cannons facing up, left, down and right |
  | `@` `(` `)` | wormhole, wormhole in, wormhole out |
  | `+` `-` `>` `<` | gravity attracting, repelling, clockwise, anticlockwise |
  | `i` `m` `k` `j` | gravity pulling up, down, right, left |
  | `*` | treasure |
  | `!` | target |
  | `b` `h` `g` `y` `t` | decoration, drawn as walls but not collided with |
  | `A`–`Z` | race checkpoints, in order |

  Anything else is open space.

  ## Options

  `option/2` reads `edgewrap`, `teamplay`, `gravity`, `shotspeed`, `shotlife`,
  `maxrobots`, `maxplayershots`, `limitedlives`, `worldlives`, `mapname` and `mapauthor`
  with XPilot's defaults where the map is silent.
  """

  alias Cauldron2D.Map, as: TileMap

  @type point :: {integer(), integer()}
  @type feature :: %{pos: point(), kind: atom()} | %{pos: point(), team: integer() | nil} | %{pos: point(), facing: atom()}
  @type t :: %__MODULE__{map: TileMap.t(), tiles: %{point() => atom() | {atom(), term()}}}

  defstruct [:map, :tiles]

  @defaults %{
    edgewrap: {:boolean, false},
    teamplay: {:boolean, false},
    gravity: {:float, -2.24},
    shotspeed: {:float, 21.0},
    shotlife: {:integer, 90},
    maxrobots: {:integer, 4},
    maxplayershots: {:integer, 15},
    limitedlives: {:boolean, false},
    worldlives: {:integer, 0},
    mapname: {:string, "unnamed"},
    mapauthor: {:string, "unknown"}
  }

  @doc "Parse map text; `{:error, reason}` as `Cauldron2D.Map.parse/1` gives it."
  @spec parse(String.t()) :: {:ok, t()} | {:error, term()}
  def parse(text) do
    with {:ok, map} <- TileMap.parse(text), do: {:ok, build(map)}
  end

  @doc "Read and parse a map file, gzipped or not."
  @spec parse_file(Path.t()) :: {:ok, t()} | {:error, term()}
  def parse_file(path) do
    with {:ok, map} <- TileMap.parse_file(path), do: {:ok, build(map)}
  end

  defp build(map), do: %__MODULE__{map: map, tiles: TileMap.cells(map, &legend/1)}

  @doc "What the legend makes of one character; `nil` for open space."
  @spec legend(String.t()) :: atom() | {atom(), term()} | nil
  def legend("x"), do: :wall
  def legend("q"), do: {:half, :se}
  def legend("s"), do: {:half, :sw}
  def legend("a"), do: {:half, :ne}
  def legend("w"), do: {:half, :nw}
  def legend("#"), do: :fuel
  def legend("_"), do: {:base, nil}
  def legend(digit) when digit in ~w(0 1 2 3 4 5 6 7 8 9), do: {:base, String.to_integer(digit)}
  def legend("r"), do: {:cannon, :up}
  def legend("d"), do: {:cannon, :left}
  def legend("f"), do: {:cannon, :down}
  def legend("c"), do: {:cannon, :right}
  def legend("@"), do: {:wormhole, :normal}
  def legend("("), do: {:wormhole, :in}
  def legend(")"), do: {:wormhole, :out}
  def legend("+"), do: {:gravity, :attract}
  def legend("-"), do: {:gravity, :repel}
  def legend(">"), do: {:gravity, :clockwise}
  def legend("<"), do: {:gravity, :anticlockwise}
  def legend("i"), do: {:gravity, :up}
  def legend("m"), do: {:gravity, :down}
  def legend("k"), do: {:gravity, :right}
  def legend("j"), do: {:gravity, :left}
  def legend("*"), do: :treasure
  def legend("!"), do: :target
  def legend("b"), do: :decor
  def legend(decor) when decor in ~w(h g y t), do: :decor
  def legend(<<letter>>) when letter in ?A..?Z, do: {:checkpoint, letter - ?A}
  def legend(_other), do: nil

  @doc "The map's size in tiles."
  @spec size(t()) :: {pos_integer(), pos_integer()}
  def size(%__MODULE__{map: map}), do: {map.width, map.height}

  @doc "Whether the map wraps at its edges."
  @spec wrap?(t()) :: boolean()
  def wrap?(%__MODULE__{map: map}), do: map.wrap?

  @doc """
  The collision grid as `Cauldron2D.Collision` reads it.

  Walls and half walls are solid; everything else is open. Outside a map that does not
  wrap is solid; a wrapping map reads the tile on the other side.
  """
  @spec grid(t()) :: Cauldron2D.Collision.grid()
  def grid(%__MODULE__{map: map, tiles: tiles}) do
    fn {x, y} = point ->
      cond do
        map.wrap? -> solid(Map.get(tiles, {Integer.mod(x, map.width), Integer.mod(y, map.height)}))
        x < 0 or y < 0 or x >= map.width or y >= map.height -> :solid
        true -> solid(Map.get(tiles, point))
      end
    end
  end

  defp solid(:wall), do: :solid
  defp solid({:half, corner}), do: {:diagonal, corner}
  defp solid(_other), do: :open

  @doc "The tile at `point`, wrapped when the map wraps; `nil` for open space."
  @spec tile(t(), point()) :: atom() | {atom(), term()} | nil
  def tile(%__MODULE__{map: map, tiles: tiles}, {x, y}) do
    if map.wrap? do
      Map.get(tiles, {Integer.mod(x, map.width), Integer.mod(y, map.height)})
    else
      Map.get(tiles, {x, y})
    end
  end

  @doc "The art name a tile is drawn with, or `nil` for open space."
  @spec art(t(), point()) :: atom() | nil
  def art(%__MODULE__{} = arena, point) do
    case tile(arena, point) do
      nil -> nil
      :wall -> :wall
      {:half, corner} -> :"wall_#{corner}"
      :fuel -> :fuel
      {:base, _team} -> :base
      {:cannon, facing} -> :"cannon_#{facing}"
      {:wormhole, _kind} -> :wormhole
      {:gravity, _kind} -> :gravity
      :treasure -> :treasure
      :target -> :target
      :decor -> :wall
      {:checkpoint, _n} -> :checkpoint
    end
  end

  @doc "Bases, each `%{pos: {x, y}, team: team | nil}`, in map order."
  @spec bases(t()) :: [%{pos: point(), team: integer() | nil}]
  def bases(%__MODULE__{tiles: tiles}) do
    for {pos, {:base, team}} <- ordered(tiles), do: %{pos: pos, team: team}
  end

  @doc "Fuel station tiles."
  @spec fuel(t()) :: [point()]
  def fuel(%__MODULE__{tiles: tiles}), do: for({pos, :fuel} <- ordered(tiles), do: pos)

  @doc "Cannons, each `%{pos: {x, y}, facing: :up | :down | :left | :right}`."
  @spec cannons(t()) :: [%{pos: point(), facing: atom()}]
  def cannons(%__MODULE__{tiles: tiles}) do
    for {pos, {:cannon, facing}} <- ordered(tiles), do: %{pos: pos, facing: facing}
  end

  @doc "Wormholes, each `%{pos: {x, y}, kind: :normal | :in | :out}`."
  @spec wormholes(t()) :: [%{pos: point(), kind: atom()}]
  def wormholes(%__MODULE__{tiles: tiles}) do
    for {pos, {:wormhole, kind}} <- ordered(tiles), do: %{pos: pos, kind: kind}
  end

  @doc "Gravity points, each `%{pos: {x, y}, kind: kind}` with the kinds the legend lists."
  @spec gravity_points(t()) :: [%{pos: point(), kind: atom()}]
  def gravity_points(%__MODULE__{tiles: tiles}) do
    for {pos, {:gravity, kind}} <- ordered(tiles), do: %{pos: pos, kind: kind}
  end

  @doc "Treasure tiles."
  @spec treasures(t()) :: [point()]
  def treasures(%__MODULE__{tiles: tiles}), do: for({pos, :treasure} <- ordered(tiles), do: pos)

  @doc "Race checkpoints in order."
  @spec checkpoints(t()) :: [point()]
  def checkpoints(%__MODULE__{tiles: tiles}) do
    tiles
    |> Enum.filter(&match?({_, {:checkpoint, _}}, &1))
    |> Enum.sort_by(fn {_pos, {:checkpoint, n}} -> n end)
    |> Enum.map(&elem(&1, 0))
  end

  defp ordered(tiles), do: Enum.sort_by(tiles, fn {{x, y}, _} -> {y, x} end)

  @doc "An option ExPilot honours, converted, with XPilot's default when the map is silent."
  @spec option(t(), atom()) :: term()
  def option(%__MODULE__{map: map}, name) do
    {type, default} = Map.fetch!(@defaults, name)
    TileMap.option(map, Atom.to_string(name), type, default)
  end

  @doc "The map's name from its header."
  @spec name(t()) :: String.t()
  def name(%__MODULE__{} = arena), do: option(arena, :mapname)
end
