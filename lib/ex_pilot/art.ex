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
  @wall_rgb {70, 100, 230}
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

  @doc """
  The art for a ship drawn with its own shipshape, installing the shape's headings into
  the atlas the first time it is seen. `nil` or a shape that does not parse draws the
  default ship.
  """
  @spec ship_shape(String.t() | nil, integer() | nil, non_neg_integer()) ::
          {:ship, term(), non_neg_integer()}
  def ship_shape(nil, team, heading), do: ship(team, heading)

  def ship_shape(shape, team, heading) do
    case Shipshape.parse(shape) do
      {:ok, parsed} ->
        key = {team_index(team), :erlang.phash2(parsed.outline)}
        ensure_shape(key, parsed.outline, team)
        {:ship, key, heading}

      {:error, _} ->
        ship(team, heading)
    end
  end

  defp ensure_shape({_index, hash} = key, outline, team) do
    atlas = Atlas.fetch(name())

    unless Map.has_key?(atlas.entries, {:ship, key, 0}) do
      colour = Map.fetch!(@team_colours, team_index(team))

      rasters =
        Linocut.Cache.fetch("ex_pilot/shape-#{hash}-#{team_index(team)}", fingerprint(), fn ->
          Linocut.headings(outline, Ship.headings(),
            size: {@tile, @tile},
            fill: colour,
            stroke: "#303030"
          )
        end)

      rasters
      |> Enum.with_index()
      |> Enum.reduce(atlas, fn {raster, heading}, acc ->
        Atlas.put(acc, {:ship, key, heading}, raster,
          glyph: arrow(heading),
          color: Linocut.Palette.color(colour) |> Tuple.delete_at(3)
        )
      end)
      |> Atlas.install()
    end

    :ok
  end

  defp team_index(nil), do: 0
  defp team_index(team), do: rem(team - 1, 4) + 1

  @doc "The atlas as a value, without installing it."
  @spec build() :: Atlas.t()
  def build do
    atlas =
      Atlas.new(name(), tile: @tile, void: {4, 5, 10})
      |> Atlas.put(:space, Linocut.sprite(space(), space_palette()),
        glyph: "  ",
        color: {4, 5, 10}
      )
      |> Atlas.put(:wall, Linocut.sprite(wall(), wall_palette()), glyph: "██", color: @wall_rgb)
      |> Atlas.put(:wall_se, half(:se), glyph: "◢█", color: @wall_rgb)
      |> Atlas.put(:wall_sw, half(:sw), glyph: "█◣", color: @wall_rgb)
      |> Atlas.put(:wall_ne, half(:ne), glyph: "◥█", color: @wall_rgb)
      |> Atlas.put(:wall_nw, half(:nw), glyph: "█◤", color: @wall_rgb)
      |> Atlas.put(:fuel, Linocut.sprite(fuel(), fuel_palette()),
        glyph: "▓▓",
        color: {80, 220, 100}
      )
      |> Atlas.put(:base_up, Linocut.sprite(base(), base_palette()),
        glyph: "▁▁",
        color: {235, 235, 245}
      )
      |> Atlas.put(:base_down, Linocut.sprite(base(), base_palette()) |> flip_vertical(),
        glyph: "▔▔",
        color: {235, 235, 245}
      )
      |> Atlas.put(:base_left, Linocut.sprite(base(), base_palette()) |> rotate_left(),
        glyph: " ▕",
        color: {235, 235, 245}
      )
      |> Atlas.put(:base_right, Linocut.sprite(base(), base_palette()) |> rotate_right(),
        glyph: "▏ ",
        color: {235, 235, 245}
      )
      |> Atlas.put(:cannon_up, Linocut.sprite(cannon(), cannon_palette()),
        glyph: "╥╥",
        color: {200, 90, 90}
      )
      |> Atlas.put(:cannon_down, Linocut.sprite(cannon(), cannon_palette()) |> flip_vertical(),
        glyph: "╨╨",
        color: {200, 90, 90}
      )
      |> Atlas.put(:cannon_left, Linocut.sprite(cannon(), cannon_palette()) |> rotate_left(),
        glyph: "╡ ",
        color: {200, 90, 90}
      )
      |> Atlas.put(:cannon_right, Linocut.sprite(cannon(), cannon_palette()) |> rotate_right(),
        glyph: " ╞",
        color: {200, 90, 90}
      )
      |> Atlas.put(:wormhole, Linocut.sprite(wormhole(), wormhole_palette()),
        glyph: "◎ ",
        color: {170, 120, 255}
      )
      |> Atlas.put(:gravity, Linocut.sprite(gravity(), gravity_palette()),
        glyph: "·˚",
        color: {120, 120, 160}
      )
      |> Atlas.put(:treasure, Linocut.sprite(treasure(), treasure_palette()),
        glyph: "◆ ",
        color: {255, 210, 60}
      )
      |> Atlas.put(:target, Linocut.sprite(target(), target_palette()),
        glyph: "⊕ ",
        color: {255, 90, 90}
      )
      |> Atlas.put(:checkpoint, Linocut.sprite(target(), checkpoint_palette()),
        glyph: "◇ ",
        color: {120, 255, 120}
      )
      |> Atlas.put(:shot, Linocut.sprite(dot(), s: "#ffffff"),
        glyph: "· ",
        color: {255, 255, 255}
      )
      |> Atlas.put(:spark, Linocut.sprite(dot(), s: "#ffb040"),
        glyph: "· ",
        color: {255, 176, 64}
      )
      |> Atlas.put(:debris, Linocut.sprite(dot(), s: "#ff6040"),
        glyph: "· ",
        color: {255, 96, 64}
      )
      |> Atlas.put(:shield, Linocut.outline(ring(), size: {@tile, @tile}, stroke: "#70e0ff"),
        glyph: "()",
        color: {112, 224, 255}
      )
      |> Atlas.put(:target_gone, Linocut.sprite(target(), r: "#5a3030"),
        glyph: "⊗ ",
        color: {90, 48, 48}
      )
      |> Atlas.put(
        :ball,
        Linocut.outline(ring(),
          size: {@tile, @tile},
          fill: "#ffb040",
          stroke: "#ffe0a0",
          scale: 3.0
        ),
        glyph: "● ",
        color: {255, 176, 64}
      )
      |> Atlas.put(:mine, Linocut.sprite(mine(), M: "#c04040", m: "#602020"),
        glyph: "✱ ",
        color: {192, 64, 64}
      )
      |> Atlas.put(:torpedo, Linocut.sprite(missile(), m: "#f0f0f0"),
        glyph: "➤ ",
        color: {240, 240, 240}
      )
      |> Atlas.put(:smart, Linocut.sprite(missile(), m: "#60ff80"),
        glyph: "➤ ",
        color: {96, 255, 128}
      )
      |> Atlas.put(:heat, Linocut.sprite(missile(), m: "#ff6060"),
        glyph: "➤ ",
        color: {255, 96, 96}
      )
      |> Atlas.put(:beam, Linocut.sprite(dot(), s: "#ff60ff"), glyph: "· ", color: {255, 96, 255})
      |> Atlas.put(:string, Linocut.sprite(dot(), s: "#c0a060"),
        glyph: "· ",
        color: {192, 160, 96}
      )
      |> put_items()

    Enum.reduce(@teams, atlas, &put_ship_headings(&2, &1))
  end

  @item_colours %{
    fuel: "#50e070",
    tank: "#40c0a0",
    ecm: "#c080ff",
    armor: "#b0b0c0",
    mine: "#e05050",
    missile: "#ff9040",
    cloak: "#8080ff",
    sensor: "#80ffff",
    wideangle: "#ffff60",
    rearshot: "#ffc060",
    afterburner: "#ff8000",
    transporter: "#ff60c0",
    mirror: "#e0e0ff",
    deflector: "#60c0ff",
    hyperjump: "#c0ff60",
    phasing: "#a0a0ff",
    laser: "#ff40ff",
    emergency_thrust: "#ffa000",
    emergency_shield: "#40e0ff",
    tractor_beam: "#d0d060",
    autopilot: "#80ff80"
  }

  @doc "The art for an item of `kind`."
  @spec item(atom()) :: {:item, atom()}
  def item(kind), do: {:item, kind}

  defp put_items(atlas) do
    Enum.reduce(@item_colours, atlas, fn {kind, colour}, acc ->
      {r, g, b, _} = Linocut.Palette.color(colour)

      Atlas.put(acc, {:item, kind}, Linocut.sprite(item_box(), b: colour, x: "#202030"),
        glyph: item_glyph(kind),
        color: {r, g, b}
      )
    end)
  end

  defp item_glyph(kind),
    do: kind |> Atom.to_string() |> String.first() |> String.upcase() |> Kernel.<>(" ")

  defp item_box do
    """
    ................
    ................
    ................
    ....bbbbbbbb....
    ...bxxxxxxxxb...
    ...bxbbbbbbxb...
    ...bxbxxxxbxb...
    ...bxbxbbxbxb...
    ...bxbxbbxbxb...
    ...bxbxxxxbxb...
    ...bxbbbbbbxb...
    ...bxxxxxxxxb...
    ....bbbbbbbb....
    ................
    ................
    ................
    """
  end

  defp mine do
    """
    ................
    ................
    ................
    .......M........
    ....M..M..M.....
    .....MmmmM......
    ....mmMMMmm.....
    .MMMmMMMMMmMMM..
    ....mmMMMmm.....
    .....MmmmM......
    ....M..M..M.....
    .......M........
    ................
    ................
    ................
    ................
    """
  end

  defp missile do
    """
    ................
    ................
    ................
    ................
    ................
    ................
    ......m.........
    ...mmmmmmmmm....
    ..mmmmmmmmmmmm..
    ...mmmmmmmmm....
    ......m.........
    ................
    ................
    ................
    ................
    ................
    """
  end

  defp put_ship_headings(atlas, team) do
    colour = Map.fetch!(@team_colours, team)
    outline = Shipshape.default().outline

    rasters =
      Linocut.Cache.fetch("ex_pilot/ship-#{team_index(team)}", fingerprint(), fn ->
        Linocut.headings(outline, Ship.headings(),
          size: {@tile, @tile},
          fill: colour,
          stroke: "#303030"
        )
      end)

    rasters
    |> Enum.with_index()
    |> Enum.reduce(atlas, fn {raster, heading}, acc ->
      Atlas.put(acc, ship(team, heading), raster,
        glyph: arrow(heading),
        color: Linocut.Palette.color(colour) |> Tuple.delete_at(3)
      )
    end)
  end

  defp fingerprint,
    do:
      :erlang.phash2({Shipshape.default(), @tile, Ship.headings(), @team_colours})
      |> Integer.to_string()

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
    |> FrenchCurve.Draw.fill_polygon(points, Tuple.insert_at(@wall_rgb, 3, 255))
  end

  defp flip_vertical(raster), do: transform(raster, fn {x, y} -> {x, @tile - 1 - y} end)
  defp rotate_left(raster), do: transform(raster, fn {x, y} -> {y, @tile - 1 - x} end)
  defp rotate_right(raster), do: transform(raster, fn {x, y} -> {@tile - 1 - y, x} end)

  defp transform(raster, fun) do
    for y <- 0..(@tile - 1),
        x <- 0..(@tile - 1),
        reduce: FrenchCurve.Raster.new(@tile, @tile, background: {0, 0, 0, 0}) do
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

  defp wall_palette, do: ["#": "#5a7cf0", .: "#3450b4"]

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

  defp fuel_palette, do: [F: "#3cc864", h: "#a0ffb4"]

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
    ................
    ................
    .......bb.......
    ......bbbb......
    BBBBBBBBBBBBBBBB
    B..............B
    """
  end

  defp base_palette, do: [b: "#ebebf5", B: "#ebebf5"]

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
