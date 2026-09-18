defmodule ExPilot.Race do
  @moduledoc """
  Race mode: the map's checkpoints `A`–`Z` taken in order, a lap at a time.

  A ship's `race.checkpoint` is the next one it must pass; passing the last completes a lap.
  The race is over for a ship after the map's `racelaps`.

      ExPilot.Race.pass(ship, checkpoints, laps)
      ExPilot.Race.pass(ship, checkpoints, laps, reach)
  """

  alias ExPilot.Ship

  @reach 1.5

  @doc "The ship after this tick: its next checkpoint, laps and whether it has finished. A checkpoint is passed within `reach` tiles of its centre."
  @spec pass(Ship.t(), [{integer(), integer()}], pos_integer(), float()) :: Ship.t()
  def pass(ship, checkpoints, laps, reach \\ @reach)
  def pass(%Ship{} = ship, [], _laps, _reach), do: ship
  def pass(%Ship{race: %{finished?: true}} = ship, _checkpoints, _laps, _reach), do: ship

  def pass(%Ship{} = ship, checkpoints, laps, reach) do
    {cx, cy} = Enum.at(checkpoints, rem(ship.race.checkpoint, length(checkpoints)))
    {x, y} = ship.body.pos

    if (cx + 0.5 - x) * (cx + 0.5 - x) + (cy + 0.5 - y) * (cy + 0.5 - y) < reach * reach do
      advance(ship, length(checkpoints), laps)
    else
      ship
    end
  end

  defp advance(%Ship{race: %{checkpoint: checkpoint, laps: done} = race} = ship, count, laps) do
    if checkpoint + 1 >= count do
      %{ship | race: %{race | checkpoint: 0, laps: done + 1, finished?: done + 1 >= laps}}
    else
      %{ship | race: %{race | checkpoint: checkpoint + 1}}
    end
  end

  @doc "The order ships stand in: finished first, then by laps and checkpoints passed."
  @spec standings([Ship.t()]) :: [Ship.t()]
  def standings(ships) do
    Enum.sort_by(ships, fn %{race: race} -> {not race.finished?, -race.laps, -race.checkpoint} end)
  end
end
