defmodule ExPilot.RobotBalanceTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Grid.Coarse, as: Route
  alias ExPilot.{Game, Robot}
  alias ExPilot.Map, as: Arena

  @moduletag :balance
  @dt 1 / 50
  @decide_every 4
  @maps [
    {"dogfight, no shields", Path.join(__DIR__, "../fixtures/dogfight.map.gz")},
    {"Arena, shields", Path.join(:code.priv_dir(:ex_pilot), "maps/Arena.map.gz")}
  ]

  for {name, path} <- @maps do
    test "four robots on #{name}: kills a minute, mean life and shots a kill over three minutes" do
      measure(unquote(name), unquote(path))
    end
  end

  defp measure(name, path) do
    {:ok, arena} = Arena.parse_file(path)
    grid = Arena.grid(arena)
    stations = Arena.fuel(arena)
    route = Route.new(grid, Arena.size(arena), wrap?: Arena.wrap?(arena))
    skills = %{1 => 1.0, 2 => 0.8, 3 => 0.6, 4 => 0.4}

    game =
      Enum.reduce(skills, Game.init(arena: arena, seed: 42), fn {n, _skill}, acc ->
        {:ok, acc} = Game.join(acc, {:robot, n}, %{robot?: true})
        acc
      end)

    minutes = 3
    ticks = round(minutes * 60 / @dt)

    {game, fired, _burns, told} =
      Enum.reduce(1..ticks, {game, 0, %{}, MapSet.new()}, fn tick, {game, fired, burns, told} ->
        {game, burns} =
          if rem(tick, @decide_every) == 0,
            do: decide_all(game, grid, burns, skills, stations, route, tick),
            else: {game, burns}

        {events, game} = Game.drain_events(Game.step(game, @dt))
        told = Enum.reduce(game.messages, told, &MapSet.put(&2, &1))
        {game, fired + Enum.count(events, &match?({:fire, _}, &1)), burns, told}
      end)

    walls = Enum.count(told, fn {_, text} -> text =~ "hit a wall" end)
    collisions = Enum.count(told, fn {_, text} -> text =~ "collided" end)
    starved = Enum.count(told, fn {_, text} -> text =~ "out of fuel" end)

    kills = game.ships |> Map.values() |> Enum.map(& &1.tally.kills) |> Enum.sum()
    deaths = game.ships |> Map.values() |> Enum.map(& &1.tally.deaths) |> Enum.sum()

    IO.puts("""

    robot balance, #{minutes} min, #{name}, skills #{inspect(Map.values(skills))}:
      kills #{kills} (#{Float.round(kills / minutes, 1)} a minute), deaths #{deaths}
      mean life #{Float.round(minutes * 60 * map_size(skills) / max(deaths, 1), 1)} s; walls #{walls}, collisions #{collisions}, starved #{starved}
      shots #{fired}, #{Float.round(fired / max(kills, 1), 1)} a kill
      by robot: #{inspect(for {id, ship} <- game.ships, do: {id, ship.tally.kills, ship.tally.deaths})}
    """)

    assert deaths > 0
  end

  defp decide_all(game, grid, burns, skills, stations, route, tick) do
    Enum.reduce(skills, {game, burns}, fn {n, skill}, {game, burns} ->
      id = {:robot, n}
      view = Game.view(game, id)

      {held, burn} =
        Robot.decide(view, grid, Map.get(burns, id, 0),
          skill: skill,
          stations: stations,
          route: route,
          tick: div(tick, @decide_every)
        )

      {Game.handle_input(game, id, %{held: held, aim: nil}), Map.put(burns, id, burn)}
    end)
  end
end
