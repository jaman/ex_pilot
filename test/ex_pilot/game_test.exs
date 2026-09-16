defmodule ExPilot.GameTest do
  use ExUnit.Case, async: true

  alias ExPilot.Game

  @dt 1 / 50

  @arena """
  mapwidth: 24
  mapheight: 12
  edgewrap: no
  gravity: 0
  mapData: \\multiline: END
  xxxxxxxxxxxxxxxxxxxxxxxx
  x                      x
  x  _                   x
  x                      x
  x         #            x
  x                    _ x
  x                      x
  x  @              @    x
  x                      x
  x                 r    x
  x   _                  x
  xxxxxxxxxxxxxxxxxxxxxxxx
  END
  """

  defp arena do
    {:ok, arena} = ExPilot.Map.parse(@arena)
    arena
  end

  defp game(opts \\ []), do: Game.init([arena: arena(), seed: 1] ++ opts)

  defp joined(game, id, props \\ %{}) do
    {:ok, game} = Game.join(game, id, props)
    game
  end

  defp holding(game, id, actions, aim \\ nil) do
    Game.handle_input(game, id, %{held: MapSet.new(actions), aim: aim})
  end

  defp play(game, steps), do: Enum.reduce(1..steps, game, fn _, g -> Game.step(g, @dt) end)

  defp ship(game, id), do: Map.fetch!(game.ships, id)
  defp events(game), do: game |> Game.drain_events() |> elem(0) |> Enum.map(&elem(&1, 0))

  test "a ship starts on a free base facing up, and a second on the next base" do
    game = game() |> joined(:a) |> joined(:b)
    assert ship(game, :a).base == {3, 2}
    assert ship(game, :b).base == {21, 5}
    assert ship(game, :a).body.heading == 16
    assert {:error, :full} = game |> joined(:c) |> Game.join(:d, %{})
  end

  test "a ship on a base under a ceiling faces down and launches downward" do
    {:ok, arena} = ExPilot.Map.parse("mapwidth: 5\nmapheight: 6\nedgewrap: no\ngravity: 0\nmapData: \\multiline: END\nxxxxx\nx_xxx\nx   x\nx   x\nx   x\nxxxxx\nEND\n")
    game = Game.init(arena: arena, seed: 1) |> joined(:a)
    assert ship(game, :a).body.heading == 48
    assert ship(game, :a).launch_heading == 48

    flown = game |> holding(:a, [:thrust]) |> play(30)
    assert ship(flown, :a).alive?
    {_x, y} = ship(flown, :a).body.pos
    assert y > 1.5
  end

  test "a ship alone in the arena is neither victorious nor defeated" do
    game = game(lives: 1) |> joined(:a)
    view = Game.view(game, :a)
    refute view.others_out?
    assert Game.outcome(view) == nil
  end

  test "a watcher has no ship and sees the arena" do
    game = game() |> joined(:w, %{spectate: true})
    view = Game.view(game, :w)
    assert view.me == nil
    assert view.focus == {12.0, 6.0}
  end

  test "thrust moves the ship along its heading and burns fuel" do
    game = game() |> joined(:a) |> holding(:a, [:thrust]) |> play(25)
    {x, y} = ship(game, :a).body.pos
    assert_in_delta x, 3.5, 0.01
    assert y < 2.5
    assert ship(game, :a).fuel < ExPilot.Ship.max_fuel()
    assert :fire not in events(game)
  end

  test "turning changes the heading at a steady rate" do
    game = game() |> joined(:a) |> holding(:a, [:turn_right]) |> play(10)
    assert ship(game, :a).body.heading < 16
    left = game() |> joined(:a) |> holding(:a, [:turn_left]) |> play(10)
    assert ship(left, :a).body.heading > 16
  end

  test "an aim turns the ship toward the point" do
    game = game() |> joined(:a) |> holding(:a, [], {20.0, 2.5}) |> play(60)
    assert ship(game, :a).body.heading == 0
  end

  test "flying fast into a wall without a shield is an explosion and a respawn" do
    game = game() |> joined(:a) |> holding(:a, [:thrust]) |> play(120)
    refute ship(game, :a).alive?
    assert :explosion in events(game)

    later = game |> holding(:a, []) |> play(200)
    assert ship(later, :a).alive?
    assert ship(later, :a).body.pos == {3.5, 2.5}
    assert ship(later, :a).deaths == 1
  end

  test "a shield bounces off the wall instead" do
    game = game() |> joined(:a) |> holding(:a, [:thrust, :shield]) |> play(120)
    assert ship(game, :a).alive?
    assert :bounce in events(game)
    {_, vy} = ship(game, :a).body.vel
    assert vy >= 0.0
  end

  test "firing spawns a shot that flies ahead and dies at a wall" do
    game = game() |> joined(:a) |> holding(:a, [:fire]) |> play(1)
    assert [shot] = game.shots
    assert :fire in events(game)
    {_, vy} = shot.body.vel
    assert vy < 0
    later = game |> holding(:a, []) |> play(100)
    assert later.shots == []
    assert :shot_wall in events(later)
  end

  test "a shot kills another ship and the killer scores" do
    game = game() |> joined(:a) |> joined(:b)
    b = %{ship(game, :b) | body: %{ship(game, :b).body | pos: {3.5, 6.5}, heading: 16}, immune_until: 0.0}
    a = %{ship(game, :a) | body: %{ship(game, :a).body | heading: 48}}
    game = %{game | ships: %{a: a, b: b}} |> holding(:a, [:fire]) |> play(30)

    refute ship(game, :b).alive?
    assert ship(game, :a).kills == 1
    assert :kill in events(game)
  end

  test "a shielded ship shrugs a shot off" do
    game = game() |> joined(:a) |> joined(:b)
    b = %{ship(game, :b) | body: %{ship(game, :b).body | pos: {3.5, 6.5}}}
    a = %{ship(game, :a) | body: %{ship(game, :a).body | heading: 48}}
    game = %{game | ships: %{a: a, b: b}} |> holding(:a, [:fire]) |> holding(:b, [:shield]) |> play(30)
    assert ship(game, :b).alive?
  end

  test "a fuel station refills a ship parked next to it" do
    game = game() |> joined(:a)
    thirsty = %{ship(game, :a) | fuel: 100.0, body: %{ship(game, :a).body | pos: {10.5, 5.5}}}
    filled = %{game | ships: %{a: thirsty}} |> play(50)
    assert ship(filled, :a).fuel > 100.0
  end

  test "a wormhole moves the ship to the other one" do
    game = game() |> joined(:a)
    at_hole = %{ship(game, :a) | body: %{ship(game, :a).body | pos: {3.5, 7.5}}}
    warped = %{game | ships: %{a: at_hole}} |> play(1)
    assert ship(warped, :a).body.pos == {18.5, 7.5}
    assert :wormhole in events(warped)
  end

  test "a cannon fires at a ship in front of it" do
    game = game() |> joined(:a)
    above = %{ship(game, :a) | body: %{ship(game, :a).body | pos: {18.5, 4.5}}}
    fired = %{game | ships: %{a: above}} |> play(2)
    assert Enum.any?(fired.shots, &match?({:cannon, _}, &1.owner))
    assert :cannon in events(fired)
  end

  test "the view carries what a player needs" do
    game = game() |> joined(:a) |> joined(:b) |> play(1)
    view = Game.view(game, :a)
    assert view.me.name == "a"
    assert length(view.ships) == 2
    assert view.bounds == {24, 12}
    assert view.wrap? == false
    assert Enum.map(view.scores, & &1.name) |> Enum.sort() == ["a", "b"]
  end

  test "a ship on its base stays put under gravity until it thrusts" do
    heavy = "mapwidth: 6\nmapheight: 4\ngravity: -9\nmapData: \\multiline: END\nxxxxxx\nx    x\nx _  x\nxxxxxx\nEND\n"
    {:ok, arena} = ExPilot.Map.parse(heavy)
    game = Game.init(arena: arena, seed: 1) |> joined(:a) |> play(200)
    assert ship(game, :a).alive?
    assert ship(game, :a).landed?
    assert ship(game, :a).body.pos == {2.5, 2.5}

    launched = game |> holding(:a, [:thrust]) |> play(5) |> holding(:a, []) |> play(1)
    refute ship(launched, :a).landed?
  end

  test "when everyone is out a new round starts with lives back" do
    game = game(lives: 1) |> joined(:a) |> joined(:b)
    dead = Map.new(game.ships, fn {id, s} -> {id, ExPilot.Ship.die(s, 0.0)} end)
    restarted = %{game | ships: dead} |> play(2)
    assert Enum.all?(restarted.ships, fn {_, s} -> s.alive? and s.lives == 1 end)
    assert :round in events(restarted)
  end

  test "with limited lives the round ends when one ship is left standing: the survivor is told, and after a pause everyone is back" do
    game = game(lives: 1) |> joined(:a) |> joined(:b) |> joined(:c)
    out = fn ship -> %{ship | alive?: false, lives: 0, respawn_in: 0.0} end
    last = %{game | ships: %{game.ships | b: out.(ship(game, :b)), c: out.(ship(game, :c))}} |> play(1)

    assert last.round_over_in != nil
    assert Enum.any?(last.messages, fn {_, text} -> text =~ "won the round" end)
    assert Game.view(last, :a).round_over?
    assert %{title: "Victory"} = Game.outcome(Game.view(last, :a))
    assert %{title: "Defeat", next: :same_arena} = Game.outcome(Game.view(last, :b))
    refute ship(last |> play(10), :b).alive?

    restarted = play(last, round(4.0 / @dt) + 2)
    for {id, s} <- restarted.ships, do: assert({id, s.alive?, s.lives} == {id, true, 1})
    assert restarted.round_over_in == nil
    assert :round in events(restarted)
  end

  test "a round with unlimited lives, or with one ship in it, never ends by standing" do
    solo = game(lives: 1) |> joined(:a) |> play(1)
    assert solo.round_over_in == nil

    game = game() |> joined(:a) |> joined(:b)
    out = fn ship -> %{ship | alive?: false, lives: :unlimited, respawn_in: 0.0} end
    still = %{game | ships: %{game.ships | b: out.(ship(game, :b))}} |> play(1)
    assert still.round_over_in == nil
  end

  test "the same seed and calls give the same game" do
    run = fn -> game(seed: 3) |> joined(:a) |> holding(:a, [:thrust, :fire, :turn_left]) |> play(200) end
    assert run.() == run.()
  end

  test "a ship never hits itself, however fast it flies into its own shots" do
    game = game() |> joined(:a)
    a = ship(game, :a)
    a = %{a | body: %{a.body | pos: {2.5, 1.5}, heading: 0, vel: {17.0, 0.0}}, landed?: false}
    game = %{game | ships: %{a: a}} |> holding(:a, [:fire, :thrust]) |> play(45)

    assert :fire in events(game)

    assert ship(game, :a).alive?
    assert ship(game, :a).deaths == 0
    refute :kill in events(game)
  end

  test "killing a ship is credited to the shooter and costs the shooter nothing" do
    game = game() |> joined(:a) |> joined(:b)
    b = %{ship(game, :b) | body: %{ship(game, :b).body | pos: {3.5, 6.5}, heading: 16}, immune_until: 0.0}
    a = %{ship(game, :a) | body: %{ship(game, :a).body | heading: 48}}
    game = %{game | ships: %{a: a, b: b}} |> holding(:a, [:fire]) |> play(30)

    refute ship(game, :b).alive?
    assert ship(game, :a).alive?
    assert ship(game, :a).deaths == 0
    assert ship(game, :a).kills == 1
    assert Enum.count(events(game), &(&1 == :kill)) == 1
  end

  test "the scene draws a ring over a shielded ship" do
    game = game() |> joined(:a) |> holding(:a, [:shield]) |> play(1)
    movers = game |> ExPilot.Game.view(:a) |> ExPilot.Client.scene() |> Map.fetch!(:movers)
    pos = game |> ship(:a) |> ExPilot.Ship.pos()
    {x, y} = pos

    assert {:shield, {x - 0.5, y - 0.5}} in movers
    refute {:shield, {x - 0.5, y - 0.5}} in (game() |> joined(:a) |> play(round(3.2 / @dt)) |> ExPilot.Game.view(:a) |> ExPilot.Client.scene() |> Map.fetch!(:movers))
  end

  test "held turn keys steer even while an aim is set" do
    game = game() |> joined(:a)
    a = ship(game, :a)
    heading = a.body.heading
    {ax, ay} = a.body.pos
    aimed = %{game | ships: %{a: a}} |> holding(:a, [:turn_left], {ax, ay - 5}) |> play(5)
    keyed = %{game | ships: %{a: a}} |> holding(:a, [:turn_left]) |> play(5)

    assert ship(keyed, :a).body.heading == ship(aimed, :a).body.heading
    assert ship(keyed, :a).body.heading != heading
  end

  test "a ship with no lives left watches the nearest living ship" do
    game = game(lives: 1) |> joined(:a) |> joined(:b) |> joined(:c)
    dead = %{ship(game, :a) | alive?: false, lives: 0, respawn_in: 0.0}
    far = %{ship(game, :b) | body: %{ship(game, :b).body | pos: {20.0, 9.0}}}
    near = %{ship(game, :c) | body: %{ship(game, :c).body | pos: {5.0, 3.0}}}
    game = %{game | ships: %{a: dead, b: far, c: near}}

    view = Game.view(game, :a)
    assert view.focus == {5.0, 3.0}
    assert view.watching == ship(game, :c).name
    assert Game.outcome(view) == nil
  end

  test "the round is over for a player when every other ship is out, or when everyone including them is" do
    game = game(lives: 1) |> joined(:a) |> joined(:b)
    out = fn ship -> %{ship | alive?: false, lives: 0, respawn_in: 0.0} end

    won = %{game | ships: %{a: ship(game, :a), b: out.(ship(game, :b))}}
    assert %{title: "Victory", lines: lines, next: :next_arena} = Game.outcome(Game.view(won, :a))
    assert Enum.any?(lines, &(&1 =~ "a"))

    lost = %{game | ships: %{a: out.(ship(game, :a)), b: out.(ship(game, :b))}}
    assert %{title: "Defeat", next: :same_arena} = Game.outcome(Game.view(lost, :a))

    still = %{game | ships: %{a: out.(ship(game, :a)), b: ship(game, :b)}}
    assert Game.outcome(Game.view(still, :a)) == nil
    assert Game.outcome(Game.view(game, :a)) == nil
    assert Game.outcome(Game.view(game(), :a)) == nil
  end

  test "the view counts the enemies still in the round" do
    game = game(lives: 1) |> joined(:a) |> joined(:b) |> joined(:c)
    assert Game.view(game, :a).enemies == 2
    out = %{ship(game, :c) | alive?: false, lives: 0, respawn_in: 0.0}
    assert Game.view(%{game | ships: %{game.ships | c: out}}, :a).enemies == 1
  end

  test "touching a wall slowly without a shield bounces and costs fuel" do
    game = game() |> joined(:a)
    a = ship(game, :a)
    slow = %{a | body: %{a.body | pos: {3.5, 1.9}, heading: 16, vel: {0.0, -3.0}}, landed?: false}
    game = %{game | ships: %{a: slow}} |> play(10)

    assert ship(game, :a).alive?
    assert :bounce in events(game)
    {_, vy} = ship(game, :a).body.vel
    assert vy > 0
    assert ship(game, :a).fuel < a.fuel
  end

  test "holding fire streams shots" do
    game = game() |> joined(:a) |> holding(:a, [:fire]) |> play(50)
    fired = game |> Game.drain_events() |> elem(0) |> Enum.count(&match?({:fire, _}, &1))
    assert fired >= 10
  end
end
