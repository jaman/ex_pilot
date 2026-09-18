defmodule ExPilot.Radar do
  @moduledoc """
  XPilot's radar on `Cauldron2D.Minimap`: the whole arena in a few rows of braille,
  walls in blue, bases grey, the player's ship yellow, teammates blue and enemies red.
  With `radar.players?` false in the view (the map's `playersonradar`), only the
  player's own ship is marked.

      ExPilot.Radar.rows(arena, view, {30, 12})

  Each row is a list of `{text, colour}` runs, a hud row. The scaled walls are kept per
  map name and radar size after the first call, so a map's name must be unique among
  the maps open at once.
  """

  alias Cauldron2D.Minimap
  alias ExPilot.Map, as: Arena

  @base {150, 150, 165}
  @me {255, 220, 40}
  @enemy {255, 90, 90}
  @team {90, 200, 255}
  @walls [:wall, {:half, :se}, {:half, :sw}, {:half, :ne}, {:half, :nw}]

  @doc "The radar for `view` of `arena` fitted into `columns` cells by `rows` rows."
  @spec rows(Arena.t(), map(), {pos_integer(), pos_integer()}) :: [
          [{String.t(), {byte(), byte(), byte()}}]
        ]
  def rows(%Arena{} = arena, view, cells) do
    Minimap.rows(
      size: Arena.size(arena),
      solid?: &(Arena.tile(arena, &1) in @walls),
      cells: cells,
      marks: marks(arena, view),
      key: {__MODULE__, Arena.name(arena)}
    )
  end

  defp marks(arena, view) do
    me = view.me
    shown? = Map.get(view, :radar, %{players?: true}).players?

    ships =
      for ship <- view.ships, ship.alive?, shown? or (me != nil and ship.id == me.id) do
        {ship.pos, colour(ship, me), 2}
      end

    bases = for %{pos: {x, y}} <- Arena.bases(arena), do: {{x + 0.5, y + 0.5}, @base, 1}
    Enum.sort_by(ships, fn {_, colour, _} -> priority(colour) end) ++ bases
  end

  defp colour(ship, me) do
    cond do
      me != nil and ship.id == me.id -> @me
      me != nil and me.team != nil and ship.team == me.team -> @team
      true -> @enemy
    end
  end

  defp priority(@me), do: 0
  defp priority(@team), do: 1
  defp priority(_enemy), do: 2
end
