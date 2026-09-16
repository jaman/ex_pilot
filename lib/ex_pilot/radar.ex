defmodule ExPilot.Radar do
  @moduledoc """
  XPilot's radar: the whole arena in a few rows of braille, walls in blue, bases grey,
  the player's ship yellow, teammates blue and enemies red. With `radar.players?` false
  in the view (the map's `playersonradar`), only the player's own ship is marked.

      ExPilot.Radar.rows(arena, view, {40, 6})

  Each row is a list of `{text, colour}` runs to lay side by side. A braille cell holds
  two columns and four rows of the arena scaled to fit; a ship is a two-by-two mark, a
  base a dot. The scaled walls are kept per map name and radar size after the first
  call, so a map's name must be unique among the maps open at once.
  """

  alias ExPilot.Map, as: Arena

  @wall {70, 100, 230}
  @base {150, 150, 165}
  @me {255, 220, 40}
  @enemy {255, 90, 90}
  @team {90, 200, 255}
  @empty {40, 40, 60}

  @doc "The radar for `view` of `arena` fitted into `columns` cells by `rows` rows."
  @spec rows(Arena.t(), map(), {pos_integer(), pos_integer()}) :: [[{String.t(), {byte(), byte(), byte()}}]]
  def rows(%Arena{} = arena, view, {columns, rows}) do
    {width, height} = Arena.size(arena)
    dots_across = columns * 2
    dots_down = rows * 4
    scale = min(dots_across / width, dots_down / height)
    walls = wall_dots(arena, scale, {width, height}, {dots_across, dots_down})
    marks = mark_dots(arena, view, scale)

    for row <- 0..(rows - 1) do
      0..(columns - 1)
      |> Enum.map(fn column -> cell({column, row}, walls, marks) end)
      |> runs()
    end
  end

  defp wall_dots(arena, scale, size, dots) do
    key = {__MODULE__, Arena.name(arena), dots}

    case :persistent_term.get(key, nil) do
      nil ->
        walls = scaled_walls(arena, scale, size, dots)
        :persistent_term.put(key, walls)
        walls

      walls ->
        walls
    end
  end

  defp scaled_walls(arena, scale, {width, height}, {across, down}) do
    for x <- 0..(width - 1), y <- 0..(height - 1), Arena.tile(arena, {x, y}) in [:wall, {:half, :se}, {:half, :sw}, {:half, :ne}, {:half, :nw}], reduce: MapSet.new() do
      acc ->
        dx = min(across - 1, trunc(x * scale))
        dy = min(down - 1, trunc(y * scale))
        MapSet.put(acc, {dx, dy})
    end
  end

  defp mark_dots(arena, view, scale) do
    me = view.me
    bases = for %{pos: {x, y}} <- Arena.bases(arena), do: {{trunc((x + 0.5) * scale), trunc((y + 0.5) * scale)}, @base}

    shown? = Map.get(view, :radar, %{players?: true}).players?

    ships =
      for ship <- view.ships, ship.alive?, shown? or (me != nil and ship.id == me.id) do
        colour =
          cond do
            me != nil and ship.id == me.id -> @me
            me != nil and me.team != nil and ship.team == me.team -> @team
            true -> @enemy
          end

        {x, y} = ship.pos
        {{trunc(x * scale), trunc(y * scale)}, colour}
      end

    marks = for {{x, y}, colour} <- ships, dx <- 0..1, dy <- 0..1, do: {{x - 1 + dx, y - 1 + dy}, colour}
    Map.new(bases ++ marks)
  end

  defp cell({column, row}, walls, marks) do
    dots = for dy <- 0..3, dx <- 0..1, do: {column * 2 + dx, row * 4 + dy}
    marked = dots |> Enum.map(&Map.get(marks, &1)) |> Enum.reject(&is_nil/1)

    bits =
      Enum.reduce(Enum.with_index(dots), 0, fn {dot, index}, acc ->
        if MapSet.member?(walls, dot) or Map.has_key?(marks, dot), do: Bitwise.bor(acc, bit(index)), else: acc
      end)

    colour =
      cond do
        marked != [] -> Enum.min_by(marked, &priority/1)
        bits != 0 -> @wall
        true -> @empty
      end

    {<<0x2800 + bits::utf8>>, colour}
  end

  defp priority(@me), do: 0
  defp priority(@team), do: 1
  defp priority(@enemy), do: 2
  defp priority(_other), do: 3

  defp bit(index) do
    {dx, dy} = {rem(index, 2), div(index, 2)}
    Enum.at([1, 2, 4, 64, 8, 16, 32, 128], dx * 4 + dy)
  end

  defp runs(cells) do
    cells
    |> Enum.chunk_by(&elem(&1, 1))
    |> Enum.map(fn chunk -> {Enum.map_join(chunk, &elem(&1, 0)), elem(hd(chunk), 1)} end)
  end
end
