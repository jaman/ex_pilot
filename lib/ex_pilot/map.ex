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

  `option/2` reads `edgewrap`, `teamplay`, `teamimmunity`, `gravity`, `gravityangle`,
  `gravitypoint`, `gravitypointsource`, `friction`, `shotspeed`,
  `shotlife`, `maxrobots`, `maxplayershots`, `limitedlives`, `worldlives`, `mapname`,
  `mapauthor`, `maxunshieldedwallbouncespeed` and `maxshieldedwallbouncespeed` (in
  XPilot's units per frame), `wallbouncefueldrainmult`, `racemode`, `racelaps`, `targets`,
  `itemprobmult`, `maxitemdensity`, every `item…prob`, `initialfuel` and every
  `initial…` item count, `allowshields`, `shotswallbounce`, `shotsgravity`,
  `allowplayerkilling` (`playerkillings`), `allowplayercrashes`, `allowplayerbounces`,
  `playerwallbouncebrakefactor`, `targetkillteam`, `treasurekillteam`,
  `dropitemonkillprob`, `laserisstungun`, `minefusetime` and `firerepeatrate` (frames),
  `shieldeditempickup`, `shieldedmining`, `ballswallbounce`, `checkpointradius` and
  `playersonradar`, with XPilot's defaults where the map is silent — except the
  unshielded bounce speed, whose default here is 3.5 units per frame so that a ship at
  cruising speed still crashes, the bounce brake factor (0.5) and the fire rate (4 frames).

  `gravity_point/1` is the `gravitypoint` option as a point.
  """

  alias Cauldron2D.Map, as: TileMap

  @type point :: {integer(), integer()}
  @type feature :: %{pos: point(), kind: atom()} | %{pos: point(), team: integer() | nil} | %{pos: point(), facing: atom()}
  @type t :: %__MODULE__{map: TileMap.t(), tiles: %{point() => atom() | {atom(), term()}}, features: map()}

  defstruct [:map, :tiles, :features]

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
    mapauthor: {:string, "unknown"},
    maxunshieldedwallbouncespeed: {:float, 3.5},
    maxshieldedwallbouncespeed: {:float, 50.0},
    wallbouncefueldrainmult: {:float, 1.0},
    teamimmunity: {:boolean, true},
    racemode: {:boolean, false},
    racelaps: {:integer, 3},
    targets: {:boolean, true},
    itemprobmult: {:float, 1.0},
    maxitemdensity: {:float, 0.00012},
    itemfuelpackprob: {:float, 0.00005},
    itemtankprob: {:float, 0.00002},
    itemecmprob: {:float, 0.00003},
    itemarmorprob: {:float, 0.00003},
    itemmineprob: {:float, 0.00004},
    itemmissileprob: {:float, 0.00004},
    itemcloakprob: {:float, 0.00002},
    itemsensorprob: {:float, 0.00002},
    itemwideangleprob: {:float, 0.00003},
    itemrearshotprob: {:float, 0.00003},
    itemafterburnerprob: {:float, 0.00003},
    itemtransporterprob: {:float, 0.00002},
    itemmirrorprob: {:float, 0.00002},
    itemdeflectorprob: {:float, 0.00002},
    itemhyperjumpprob: {:float, 0.00002},
    itemphasingprob: {:float, 0.00002},
    itemlaserprob: {:float, 0.00003},
    itememergencythrustprob: {:float, 0.00002},
    itememergencyshieldprob: {:float, 0.00002},
    itemtractorbeamprob: {:float, 0.00002},
    itemautopilotprob: {:float, 0.00002},
    allowshields: {:boolean, true},
    initialfuel: {:float, 1000.0},
    initialtanks: {:integer, 0},
    initialecms: {:integer, 0},
    initialarmor: {:integer, 0},
    initialmines: {:integer, 0},
    initialmissiles: {:integer, 0},
    initialcloaks: {:integer, 0},
    initialsensors: {:integer, 0},
    initialwideangles: {:integer, 0},
    initialrearshots: {:integer, 0},
    initialafterburners: {:integer, 0},
    initialtransporters: {:integer, 0},
    initialmirrors: {:integer, 0},
    initialdeflectors: {:integer, 0},
    initialhyperjumps: {:integer, 0},
    initialphasings: {:integer, 0},
    initiallasers: {:integer, 0},
    initialemergencythrusts: {:integer, 0},
    initialemergencyshields: {:integer, 0},
    initialtractorbeams: {:integer, 0},
    initialautopilots: {:integer, 0},
    shotswallbounce: {:boolean, false},
    shotsgravity: {:boolean, true},
    friction: {:float, 0.0},
    allowplayerkilling: {:boolean, true},
    playerkillings: {:boolean, true},
    allowplayercrashes: {:boolean, true},
    allowplayerbounces: {:boolean, true},
    targetkillteam: {:boolean, false},
    treasurekillteam: {:boolean, false},
    dropitemonkillprob: {:float, 1.0},
    laserisstungun: {:boolean, false},
    minefusetime: {:float, 0.0},
    firerepeatrate: {:float, 4.0},
    gravityangle: {:float, 90.0},
    gravitypoint: {:string, "0,0"},
    gravitypointsource: {:boolean, false},
    shieldeditempickup: {:boolean, false},
    shieldedmining: {:boolean, false},
    ballswallbounce: {:boolean, true},
    playerwallbouncebrakefactor: {:float, 0.5},
    checkpointradius: {:float, 1.5},
    playersonradar: {:boolean, true}
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

  defp build(map) do
    tiles = TileMap.cells(map, &legend/1)
    %__MODULE__{map: map, tiles: tiles, features: features(map, tiles)}
  end

  defp features(map, tiles) do
    ordered = Enum.sort_by(tiles, fn {{x, y}, _} -> {y, x} end)

    %{
      bases: for({pos, {:base, team}} <- ordered, do: %{pos: pos, team: team, dir: base_dir(map, tiles, pos)}),
      fuel: for({pos, :fuel} <- ordered, do: pos),
      cannons: for({pos, {:cannon, facing}} <- ordered, do: %{pos: pos, facing: facing}),
      wormholes: for({pos, {:wormhole, kind}} <- ordered, do: %{pos: pos, kind: kind}),
      gravity: for({pos, {:gravity, kind}} <- ordered, do: %{pos: pos, kind: kind}),
      treasures: for({pos, :treasure} <- ordered, do: pos),
      targets: for({pos, :target} <- ordered, do: pos),
      checkpoints: ordered |> Enum.filter(&match?({_, {:checkpoint, _}}, &1)) |> Enum.sort_by(fn {_pos, {:checkpoint, n}} -> n end) |> Enum.map(&elem(&1, 0))
    }
  end

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
  def grid(%__MODULE__{map: map, tiles: tiles}), do: &cell(map, tiles, &1)

  defp base_dir(map, tiles, {x, y}) do
    cond do
      wall?(map, tiles, {x, y + 1}) -> :up
      wall?(map, tiles, {x, y - 1}) -> :down
      wall?(map, tiles, {x - 1, y}) -> :right
      wall?(map, tiles, {x + 1, y}) -> :left
      true -> :up
    end
  end

  defp wall?(map, tiles, pos), do: cell(map, tiles, pos) != :open

  defp cell(map, tiles, {x, y} = point) do
    cond do
      map.wrap? -> solid(Map.get(tiles, {Integer.mod(x, map.width), Integer.mod(y, map.height)}))
      x < 0 or y < 0 or x >= map.width or y >= map.height -> :solid
      true -> solid(Map.get(tiles, point))
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
  def art(%__MODULE__{map: map, tiles: tiles} = arena, point) do
    case tile(arena, point) do
      nil -> nil
      :wall -> :wall
      {:half, corner} -> :"wall_#{corner}"
      :fuel -> :fuel
      {:base, _team} -> :"base_#{base_dir(map, tiles, point)}"
      {:cannon, facing} -> :"cannon_#{facing}"
      {:wormhole, _kind} -> :wormhole
      {:gravity, _kind} -> :gravity
      :treasure -> :treasure
      :target -> :target
      :decor -> :wall
      {:checkpoint, _n} -> :checkpoint
    end
  end

  @doc """
  Bases, each `%{pos: {x, y}, team: team | nil, dir: dir}`, in map order.

  `dir` is the way a ship on the base faces: away from the wall it sits on — `:up` over
  a floor, `:down` under a ceiling, `:right` off a wall on its left, `:left` off one on
  its right — and `:up` with no wall touching it.
  """
  @spec bases(t()) :: [%{pos: point(), team: integer() | nil, dir: :up | :down | :left | :right}]
  def bases(%__MODULE__{features: %{bases: bases}}), do: bases

  @doc "Fuel station tiles."
  @spec fuel(t()) :: [point()]
  def fuel(%__MODULE__{features: %{fuel: fuel}}), do: fuel

  @doc "Cannons, each `%{pos: {x, y}, facing: :up | :down | :left | :right}`."
  @spec cannons(t()) :: [%{pos: point(), facing: atom()}]
  def cannons(%__MODULE__{features: %{cannons: cannons}}), do: cannons

  @doc "Wormholes, each `%{pos: {x, y}, kind: :normal | :in | :out}`."
  @spec wormholes(t()) :: [%{pos: point(), kind: atom()}]
  def wormholes(%__MODULE__{features: %{wormholes: wormholes}}), do: wormholes

  @doc "Gravity points, each `%{pos: {x, y}, kind: kind}` with the kinds the legend lists."
  @spec gravity_points(t()) :: [%{pos: point(), kind: atom()}]
  def gravity_points(%__MODULE__{features: %{gravity: gravity}}), do: gravity

  @doc "Treasure tiles."
  @spec treasures(t()) :: [point()]
  def treasures(%__MODULE__{features: %{treasures: treasures}}), do: treasures

  @doc "Where the targets are."
  @spec targets(t()) :: [point()]
  def targets(%__MODULE__{features: %{targets: targets}}), do: targets

  @doc "Race checkpoints in order."
  @spec checkpoints(t()) :: [point()]
  def checkpoints(%__MODULE__{features: %{checkpoints: checkpoints}}), do: checkpoints

  @doc "An option ExPilot honours, converted, with XPilot's default when the map is silent."
  @spec option(t(), atom()) :: term()
  def option(%__MODULE__{map: map}, name) do
    {type, default} = Map.fetch!(@defaults, name)
    TileMap.option(map, Atom.to_string(name), type, default)
  end

  @doc "The `gravitypoint` option, `\"x,y\"` in blocks, as the centre of that block."
  @spec gravity_point(t()) :: {float(), float()}
  def gravity_point(%__MODULE__{} = arena) do
    case arena |> option(:gravitypoint) |> String.split(",") |> Enum.map(&Float.parse(String.trim(&1))) do
      [{x, _}, {y, _}] -> {x + 0.5, y + 0.5}
      _ -> {0.5, 0.5}
    end
  end

  @doc "The map's name from its header."
  @spec name(t()) :: String.t()
  def name(%__MODULE__{} = arena), do: option(arena, :mapname)
end
