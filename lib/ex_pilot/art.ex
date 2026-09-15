defmodule ExPilot.Art do
  @moduledoc """
  Every picture ExPilot draws, as a `Cauldron2D.Atlas` named `:ex_pilot`.

      ExPilot.Art.install()
      ExPilot.Art.ship(nil, heading)      # => {:ship, 0, 17}

  Tiles are 16 pixels. Walls, half walls, fuel stations, bases, cannons, wormholes,
  gravity points, treasures and targets are drawn from pictures; ships are the classic
  outline at 64 headings in each team's colour; shots, sparks and debris are dots.
  """

  alias Cauldron2D.Atlas
  alias ExPilot.{Ship, Shipshape}

  @tile 16
  @teams [nil, 1, 2, 3, 4]

  @team_colours %{
    nil => "#e8e8e8",
    1 => "#ff5c5c",
    2 => "#5c9cff",
    3 => "#5cff8a",
    4 => "#ffd75c"
  }

  @doc "The atlas name."
  @spec name() :: atom()
  def name, do: :ex_pilot

  @doc "Build the atlas and install it, once per boot."
  @spec install() :: atom()
  def install do
    if Atlas.installed?(name()) do
      name()
    else
      Atlas.install(build())
    end
  end

  @doc "The art for a ship of `team` at `heading`."
  @spec ship(integer() | nil, non_neg_integer()) :: {:ship, integer(), non_neg_integer()}
  def ship(team, heading), do: {:ship, team_index(team), heading}

  defp team_index(nil), do: 0
  defp team_index(team), do: rem(team - 1, 4) + 1

  @doc "The atlas as a value, without installing it."
  @spec build() :: Atlas.t()
  def build do
    atlas =
      Atlas.new(name(), tile: @tile, void: {4, 5, 10})
      |> Atlas.put(:space, Linocut.sprite(space(), space_palette()), glyph: "  ", color: {4, 5, 10})
      |> Atlas.put(:wall, Linocut.sprite(wall(), wall_palette()), glyph: "██", color: {110, 118, 140})
      |> Atlas.put(:wall_se, half(:se), glyph: "◢█", color: {110, 118, 140})
      |> Atlas.put(:wall_sw, half(:sw), glyph: "█◣", color: {110, 118, 140})
      |> Atlas.put(:wall_ne, half(:ne), glyph: "◥█", color: {110, 118, 140})
      |> Atlas.put(:wall_nw, half(:nw), glyph: "█◤", color: {110, 118, 140})
      |> Atlas.put(:fuel, Linocut.sprite(fuel(), fuel_palette()), glyph: "▓▓", color: {255, 170, 40})
      |> Atlas.put(:base, Linocut.sprite(base(), base_palette()), glyph: "▁▁", color: {120, 200, 255})
      |> Atlas.put(:cannon_up, Linocut.sprite(cannon(), cannon_palette()), glyph: "╥╥", color: {200, 90, 90})
      |> Atlas.put(:cannon_down, Linocut.sprite(cannon(), cannon_palette()) |> flip_vertical(), glyph: "╨╨", color: {200, 90, 90})
      |> Atlas.put(:cannon_left, Linocut.sprite(cannon(), cannon_palette()) |> rotate_left(), glyph: "╡ ", color: {200, 90, 90})
      |> Atlas.put(:cannon_right, Linocut.sprite(cannon(), cannon_palette()) |> rotate_right(), glyph: " ╞", color: {200, 90, 90})
      |> Atlas.put(:wormhole, Linocut.sprite(wormhole(), wormhole_palette()), glyph: "◎ ", color: {170, 120, 255})
      |> Atlas.put(:gravity, Linocut.sprite(gravity(), gravity_palette()), glyph: "·˚", color: {120, 120, 160})
      |> Atlas.put(:treasure, Linocut.sprite(treasure(), treasure_palette()), glyph: "◆ ", color: {255, 210, 60})
      |> Atlas.put(:target, Linocut.sprite(target(), target_palette()), glyph: "⊕ ", color: {255, 90, 90})
      |> Atlas.put(:checkpoint, Linocut.sprite(target(), checkpoint_palette()), glyph: "◇ ", color: {120, 255, 120})
      |> Atlas.put(:shot, Linocut.sprite(dot(), s: "#ffffff"), glyph: "· ", color: {255, 255, 255})
      |> Atlas.put(:spark, Linocut.sprite(dot(), s: "#ffb040"), glyph: "· ", color: {255, 176, 64})
      |> Atlas.put(:debris, Linocut.sprite(dot(), s: "#ff6040"), glyph: "· ", color: {255, 96, 64})
      |> Atlas.put(:shield, Linocut.outline(ring(), size: {@tile, @tile}, stroke: "#70e0ff"), glyph: "()", color: {112, 224, 255})

    Enum.reduce(@teams, atlas, &put_ship_headings(&2, &1))
  end

  defp put_ship_headings(atlas, team) do
    colour = Map.fetch!(@team_colours, team)
    outline = Shipshape.default().outline

    rasters =
      Linocut.Cache.fetch("ex_pilot/ship-#{team_index(team)}", fingerprint(), fn ->
        Linocut.headings(outline, Ship.headings(), size: {@tile, @tile}, fill: colour, stroke: "#303030")
      end)

    rasters
    |> Enum.with_index()
    |> Enum.reduce(atlas, fn {raster, heading}, acc ->
      Atlas.put(acc, ship(team, heading), raster, glyph: arrow(heading), color: Linocut.Palette.color(colour) |> Tuple.delete_at(3))
    end)
  end

  defp fingerprint, do: :erlang.phash2({Shipshape.default(), @tile, Ship.headings(), @team_colours}) |> Integer.to_string()

  defp arrow(heading) do
    eighth = rem(round(heading * 8 / Ship.headings()), 8)
    Enum.at(["→ ", "↗ ", "↑ ", "↖ ", "← ", "↙ ", "↓ ", "↘ "], eighth)
  end

  defp half(corner) do
    points =
      case corner do
        :se -> [{@tile, 0}, {@tile, @tile}, {0, @tile}]
        :sw -> [{0, 0}, {@tile, @tile}, {0, @tile}]
        :ne -> [{0, 0}, {@tile, 0}, {@tile, @tile}]
        :nw -> [{0, 0}, {@tile, 0}, {0, @tile}]
      end

    FrenchCurve.Raster.new(@tile, @tile, background: {0, 0, 0, 0})
    |> FrenchCurve.Draw.fill_polygon(points, {110, 118, 140, 255})
  end

  defp flip_vertical(raster), do: transform(raster, fn {x, y} -> {x, @tile - 1 - y} end)
  defp rotate_left(raster), do: transform(raster, fn {x, y} -> {y, @tile - 1 - x} end)
  defp rotate_right(raster), do: transform(raster, fn {x, y} -> {@tile - 1 - y, x} end)

  defp transform(raster, fun) do
    for y <- 0..(@tile - 1), x <- 0..(@tile - 1), reduce: FrenchCurve.Raster.new(@tile, @tile, background: {0, 0, 0, 0}) do
      acc ->
        {sx, sy} = fun.({x, y})
        FrenchCurve.Raster.put_pixel(acc, x, y, FrenchCurve.Raster.get_pixel(raster, sx, sy))
    end
  end

  defp space, do: String.duplicate("................\n", 16)
  defp space_palette, do: []

  defp wall do
    """
    ################
    #......#.......#
    #......#.......#
    #......#.......#
    #......#.......#
    ################
    #..........#...#
    #..........#...#
    #..........#...#
    #..........#...#
    ################
    #....#.........#
    #....#.........#
    #....#.........#
    #....#.........#
    ################
    """
  end

  defp wall_palette, do: ["#": "#7a8296", ".": "#5c6478"]

  defp fuel do
    """
    ....FFFFFFFF....
    ...F........F...
    ..F..FFFFFF..F..
    .F..F......F..F.
    .F.F..hhhh..F.F.
    .F.F.h....h.F.F.
    .F.F.h.hh.h.F.F.
    .F.F.h.hh.h.F.F.
    .F.F.h.hh.h.F.F.
    .F.F.h....h.F.F.
    .F.F..hhhh..F.F.
    .F..F......F..F.
    ..F..FFFFFF..F..
    ...F........F...
    ....FFFFFFFF....
    ................
    """
  end

  defp fuel_palette, do: [F: "#ffaa28", h: "#ffe090"]

  defp base do
    """
    ................
    ................
    ................
    ................
    ................
    ................
    ................
    ................
    ................
    ................
    ......bbbb......
    ....bbbbbbbb....
    ..bbbbbbbbbbbb..
    BBBBBBBBBBBBBBBB
    BBBBBBBBBBBBBBBB
    ................
    """
  end

  defp base_palette, do: [b: "#78c8ff", B: "#3c8ccc"]

  defp cannon do
    """
    .......cc.......
    .......cc.......
    ......cccc......
    ......cccc......
    .....cccccc.....
    .....cccccc.....
    ....CCCCCCCC....
    ....CCCCCCCC....
    ...CCCCCCCCCC...
    ...CCCCCCCCCC...
    ..CCCCCCCCCCCC..
    ..CCCCCCCCCCCC..
    ################
    ################
    ################
    ################
    """
  end

  defp cannon_palette, do: [c: "#ff7070", C: "#c85a5a", "#": "#7a8296"]

  defp wormhole do
    """
    ................
    .....wwwwww.....
    ...ww......ww...
    ..w..........w..
    .w....vvvv....w.
    .w...v....v...w.
    .w..v..vv..v..w.
    .w..v.v..v.v..w.
    .w..v.v..v.v..w.
    .w..v..vv..v..w.
    .w...v....v...w.
    .w....vvvv....w.
    ..w..........w..
    ...ww......ww...
    .....wwwwww.....
    ................
    """
  end

  defp wormhole_palette, do: [w: "#aa78ff", v: "#d8b8ff"]

  defp gravity do
    """
    ................
    ................
    ................
    ......g..g......
    .....g....g.....
    ................
    ....g......g....
    .......gg.......
    .......gg.......
    ....g......g....
    ................
    .....g....g.....
    ......g..g......
    ................
    ................
    ................
    """
  end

  defp gravity_palette, do: [g: "#7878a0"]

  defp treasure do
    """
    ................
    .......tt.......
    ......tttt......
    .....tttttt.....
    ....tttttttt....
    ...tttttttttt...
    ..tttttttttttt..
    .TTTTTTTTTTTTTT.
    .TTTTTTTTTTTTTT.
    ..tttttttttttt..
    ...tttttttttt...
    ....tttttttt....
    .....tttttt.....
    ......tttt......
    .......tt.......
    ................
    """
  end

  defp treasure_palette, do: [t: "#ffd23c", T: "#ffee90"]

  defp target do
    """
    ................
    ......rrrr......
    ....rr....rr....
    ...r........r...
    ..r....rr....r..
    ..r...r..r...r..
    .r....r..r....r.
    .r.....rr.....r.
    .r.....rr.....r.
    .r....r..r....r.
    ..r...r..r...r..
    ..r....rr....r..
    ...r........r...
    ....rr....rr....
    ......rrrr......
    ................
    """
  end

  defp target_palette, do: [r: "#ff5a5a"]
  defp checkpoint_palette, do: [r: "#78ff78"]

  defp ring do
    for step <- 0..23, angle = step * :math.pi() / 12, do: {:math.cos(angle), :math.sin(angle)}
  end

  defp dot do
    """
    ................
    ................
    ................
    ................
    ................
    ................
    .......ss.......
    ......ssss......
    ......ssss......
    .......ss.......
    ................
    ................
    ................
    ................
    ................
    ................
    """
  end
end
