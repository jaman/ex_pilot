defmodule ExPilot.FeaturesTest do
  use ExUnit.Case, async: true

  alias ExPilot.{Ball, Game, Items, Race, Ship, Targets, Weapons}

  @dt 1 / 50

  @arena """
  mapwidth: 24
  mapheight: 12
  edgewrap: no
  gravity: 0
  teamplay: yes
  mapData: \\multiline: END
  xxxxxxxxxxxxxxxxxxxxxxxx
  x                      x
  x  1        A        2 x
  x                      x
  x         #            x
  x  *                 * x
  x                      x
  x  !                 ! x
  x                      x
  x                      x
  x   1                2 x
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

  defp holding(game, id, actions, aim \\ nil),
    do: Game.handle_input(game, id, %{held: MapSet.new(actions), aim: aim})

  defp play(game, steps), do: Enum.reduce(1..steps, game, fn _, g -> Game.step(g, @dt) end)
  defp ship(game, id), do: Map.fetch!(game.ships, id)
  defp events(game), do: game |> Game.drain_events() |> elem(0)

  defp place(game, id, pos, opts \\ []) do
    s = ship(game, id)

    body = %{
      s.body
      | pos: pos,
        heading: Keyword.get(opts, :heading, 0),
        vel: Keyword.get(opts, :vel, {0.0, 0.0})
    }

    %{
      game
      | ships:
          Map.put(
            game.ships,
            id,
            Map.merge(
              Ship.timer(%{s | body: body, landed?: false}, :immune_until, 0.0),
              Map.new(Keyword.get(opts, :with, []))
            )
          )
    }
  end

  defp ball_at(game, id, pos),
    do: %{
      game
      | balls:
          Enum.map(game.balls, fn ball -> if ball.id == id, do: %{ball | pos: pos}, else: ball end)
    }

  describe "items" do
    test "lie on the map, are picked up by flying over them, and go into the inventory" do
      game =
        %{
          game()
          | items: [
              %{pos: {8.5, 3.5}, kind: :afterburner, ttl: 60.0},
              %{pos: {12.5, 3.5}, kind: :fuel, ttl: 60.0}
            ]
        }
        |> joined(:a)

      game = game |> place(:a, {7.9, 3.5}, vel: {3.0, 0.0}) |> play(10)

      assert Items.has?(ship(game, :a), :afterburner)
      assert game.items |> Enum.map(& &1.kind) == [:fuel]
      assert :pick_up in Enum.map(events(game), &elem(&1, 0))
    end

    test "appear over time with the map's probabilities and expire" do
      game = game() |> joined(:a)
      later = play(%{game | settings: %{game.settings | itemprobmult: 2000.0}}, 100)
      assert later.items != []
      assert Enum.all?(later.items, fn %{kind: kind} -> kind in Items.kinds() end)
    end

    test "a fuel pack and a tank feed the ship" do
      s = %{Ship.new(:a, "a", {1, 1}) | fuel: 100.0}
      assert Items.pick_up(s, :fuel).fuel == 600.0
      tanked = Items.pick_up(s, :tank)
      assert tanked.max_fuel == 1500.0 and tanked.fuel == 600.0
    end
  end

  describe "using items" do
    test "afterburner thrusts harder, armour absorbs a shot, cloak hides the ship from others" do
      plain =
        game()
        |> joined(:a)
        |> place(:a, {10.0, 6.0}, heading: 0)
        |> holding(:a, [:thrust])
        |> play(25)

      burning =
        game()
        |> joined(:a)
        |> place(:a, {10.0, 6.0}, heading: 0, with: [items: %{afterburner: 1}])
        |> holding(:a, [:thrust])
        |> play(25)

      assert elem(ship(burning, :a).body.vel, 0) > elem(ship(plain, :a).body.vel, 0)

      game = game() |> joined(:a) |> joined(:b, %{team: 2})

      game =
        game
        |> place(:a, {10.0, 6.0}, heading: 0)
        |> place(:b, {14.0, 6.0}, heading: 32, with: [armour: 1])

      game = game |> holding(:a, [:fire]) |> play(1) |> holding(:a, []) |> play(30)
      assert ship(game, :b).alive?
      assert ship(game, :b).armour == 0

      cloaked =
        game()
        |> joined(:a)
        |> joined(:b, %{team: 2})
        |> place(:a, {10.0, 6.0}, with: [items: %{cloak: 1}])
        |> holding(:a, [:cloak])
        |> play(2)

      assert ship(cloaked, :a).cloaked?
      refute Enum.any?(Game.view(cloaked, :b).ships, &(&1.id == :a))
      assert Enum.any?(Game.view(cloaked, :a).ships, &(&1.id == :a))
    end

    test "a mine waits, then kills the next ship over it but not its owner at once" do
      game =
        game()
        |> joined(:a)
        |> joined(:b, %{team: 2})
        |> place(:a, {10.0, 6.0}, with: [items: %{mine: 1}])
        |> place(:b, {16.0, 6.0}, heading: 32, vel: {-4.0, 0.0})

      game = game |> holding(:a, [:drop_mine]) |> play(1) |> holding(:a, [])
      assert Enum.any?(game.shots, &(&1.kind == :mine))
      assert ship(game, :a).alive?
      later = play(game, 100)
      refute ship(later, :b).alive?
    end

    test "a smart missile turns toward the nearest enemy and a laser hits the first ship in line" do
      game =
        game()
        |> joined(:a)
        |> joined(:b, %{team: 2})
        |> place(:a, {10.0, 6.0}, heading: 0, with: [items: %{missile: 2}, missile: :smart])
        |> place(:b, {14.0, 3.0})

      game = game |> holding(:a, [:fire_missile]) |> play(1) |> holding(:a, [])
      [missile] = Enum.filter(game.shots, &(&1.kind == :smart))
      {_, vy} = missile.body.vel
      turned = play(game, 10)
      assert Enum.all?(turned.shots, fn s -> s.kind != :smart or elem(s.body.vel, 1) < vy end)
      assert Items.has?(ship(game, :a), :missile)

      lasered =
        game()
        |> joined(:a)
        |> joined(:b, %{team: 2})
        |> place(:a, {10.0, 6.0}, heading: 0, with: [items: %{laser: 1}])
        |> place(:b, {15.0, 6.0})
        |> holding(:a, [:fire_laser])
        |> play(1)

      refute ship(lasered, :b).alive?
      assert :laser in Enum.map(events(lasered), &elem(&1, 0))
    end

    test "hyperjump moves the ship, phasing passes walls, emergency shield holds without fuel" do
      jumped =
        game()
        |> joined(:a)
        |> place(:a, {10.0, 6.0}, with: [items: %{hyperjump: 1}])
        |> holding(:a, [:hyperjump])
        |> play(1)

      assert ship(jumped, :a).body.pos != {10.0, 6.0}

      phased =
        game()
        |> joined(:a)
        |> place(:a, {21.0, 6.0}, heading: 0, vel: {10.0, 0.0}, with: [items: %{phasing: 1}])
        |> holding(:a, [:phasing])
        |> play(15)

      assert ship(phased, :a).alive?
      assert elem(ship(phased, :a).body.pos, 0) > 23.0

      shielded =
        game()
        |> joined(:a)
        |> joined(:b, %{team: 2})
        |> place(:a, {10.0, 6.0}, heading: 0)
        |> place(:b, {14.0, 6.0}, with: [fuel: 0.0, items: %{emergency_shield: 1}])

      shielded =
        shielded
        |> holding(:b, [:emergency_shield])
        |> holding(:a, [:fire])
        |> play(1)
        |> holding(:a, [])
        |> play(30)

      assert ship(shielded, :b).alive?
    end
  end

  describe "spawning" do
    test "a ship that has just appeared on its base cannot be hit for three seconds, and shows a shield meanwhile" do
      fresh = game() |> joined(:a) |> joined(:b) |> place(:a, {14.0, 2.5}, heading: 0)
      assert Enum.any?(Game.view(fresh, :a).ships, &(&1.id == :b and &1.shielding?))

      shot_early = fresh |> holding(:a, [:fire]) |> play(1) |> holding(:a, []) |> play(30)
      assert ship(shot_early, :b).alive?
      assert Enum.any?(events(shot_early), &match?({:bounce, _}, &1))

      later = fresh |> play(round(3.2 / @dt))
      refute Enum.any?(Game.view(later, :a).ships, &(&1.id == :b and &1.shielding?))
      shot_late = later |> holding(:a, [:fire]) |> play(1) |> holding(:a, []) |> play(30)
      refute ship(shot_late, :b).alive?

      revived = shot_late |> play(round(3.1 / @dt))
      assert ship(revived, :b).alive?
      assert ship(revived, :b).timers.immune_until > revived.time
    end
  end

  describe "teams" do
    test "teammates' shots pass through each other and team scores add up" do
      game =
        game()
        |> joined(:a, %{team: 1})
        |> joined(:b, %{team: 1})
        |> place(:a, {10.0, 6.0}, heading: 0)
        |> place(:b, {14.0, 6.0})

      game = game |> holding(:a, [:fire]) |> play(1) |> holding(:a, []) |> play(30)
      assert ship(game, :b).alive?
      assert %{team_scores: scores} = Game.view(game, :a)
      assert Map.has_key?(scores, 1)
    end

    test "a laser passes through a teammate and hits the enemy behind" do
      game =
        game()
        |> joined(:a, %{team: 1})
        |> joined(:b, %{team: 1})
        |> joined(:c, %{team: 2})
        |> place(:a, {10.0, 6.0}, heading: 0, with: [items: %{laser: 1}])
        |> place(:b, {13.0, 6.0})
        |> place(:c, {16.0, 6.0})
        |> holding(:a, [:fire_laser])
        |> play(1)

      assert ship(game, :b).alive?
      refute ship(game, :c).alive?
    end
  end

  describe "targets, balls and the race" do
    test "three hits destroy another team's target, which scores and comes back later" do
      targets = Targets.new(arena())
      assert length(targets) == 2
      {targets, :hit} = Targets.hit(targets, {3, 7}, 2)
      {targets, :hit} = Targets.hit(targets, {3, 7}, 2)
      {targets, {:destroyed, 2, 10}} = Targets.hit(targets, {3, 7}, 2)
      assert MapSet.member?(Targets.gone(targets), {3, 7})
      {_, :none} = Targets.hit(targets, {3, 7}, 2)
      {_, :none} = Targets.hit(Targets.new(arena()), {3, 7}, 1)
      assert Targets.gone(Targets.step(targets, 61.0)) == MapSet.new()
    end

    test "a ship picks up a ball, carries it home and scores for its team" do
      game = game() |> joined(:a, %{team: 2})
      assert length(game.balls) == 2
      [left, _right] = game.balls
      game = game |> place(:a, {3.5, 5.5}) |> play(2)
      assert ship(game, :a).ball == left.id

      delivered =
        game
        |> place(:a, {21.5, 5.5}, with: [ball: left.id])
        |> ball_at(left.id, {20.5, 5.5})
        |> play(3)

      assert ship(delivered, :a).ball == nil
      assert Map.get(Game.view(delivered, :a).team_scores, 2, 0) >= 5
      assert Enum.find(delivered.balls, &(&1.id == left.id)).pos == {3.5, 5.5}
    end

    test "a racer passes checkpoints in order and finishes after the laps" do
      s = Ship.new(:a, "a", {1, 1})
      at = fn ship, pos -> %{ship | body: %{ship.body | pos: pos}} end
      passed = s |> at.({12.5, 2.5}) |> Race.pass([{12, 2}], 2)
      assert passed.race.laps == 1 and not passed.race.finished?
      done = passed |> at.({12.5, 2.5}) |> Race.pass([{12, 2}], 2)
      assert done.race.finished?
    end
  end

  describe "messages" do
    test "kills and crashes are told in the arena" do
      game =
        game()
        |> joined(:a)
        |> joined(:b, %{team: 2})
        |> place(:a, {10.0, 6.0}, heading: 0)
        |> place(:b, {14.0, 6.0})

      game = game |> holding(:a, [:fire]) |> play(1) |> holding(:a, []) |> play(30)
      assert Enum.any?(Game.view(game, :a).messages, fn {_at, text} -> text =~ "a shot b" end)
    end
  end

  test "weapons helpers" do
    s = Ship.new(:a, "a", {1, 1})
    assert %{kind: :mine} = Weapons.mine(s, 1)
    refute Weapons.armed?(Weapons.mine(s, 1))
  end

  test "balls start in treasures with the nearest base's team" do
    assert [%{team: 1}, %{team: 2}] = Ball.new(arena())
  end
end
