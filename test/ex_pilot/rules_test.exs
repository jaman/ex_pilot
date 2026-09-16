defmodule ExPilot.RulesTest do
  use ExUnit.Case, async: true

  alias ExPilot.{Game, Items, Ship}

  @dt 1 / 50

  @layout """
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

  defp arena(options) do
    header = Enum.map_join([mapwidth: 24, mapheight: 12, edgewrap: "no", gravity: 0, teamplay: "yes"] ++ options, "\n", fn {k, v} -> "#{k}: #{v}" end)
    {:ok, arena} = ExPilot.Map.parse(header <> "\n" <> @layout)
    arena
  end

  defp game(options \\ [], opts \\ []), do: Game.init([arena: arena(options), seed: 1] ++ opts)

  defp joined(game, id, props \\ %{}) do
    {:ok, game} = Game.join(game, id, props)
    game
  end

  defp holding(game, id, actions, aim \\ nil), do: Game.handle_input(game, id, %{held: MapSet.new(actions), aim: aim})
  defp play(game, steps), do: Enum.reduce(1..steps, game, fn _, g -> Game.step(g, @dt) end)
  defp seconds(game, s), do: play(game, round(s / @dt))
  defp ship(game, id), do: Map.fetch!(game.ships, id)
  defp events(game), do: game |> Game.drain_events() |> elem(0)

  defp place(game, id, pos, opts \\ []) do
    s = ship(game, id)
    body = %{s.body | pos: pos, heading: Keyword.get(opts, :heading, 0), vel: Keyword.get(opts, :vel, {0.0, 0.0})}
    %{game | ships: Map.put(game.ships, id, Map.merge(%{s | body: body, landed?: Keyword.get(opts, :landed?, false), immune_until: 0.0}, Map.new(Keyword.get(opts, :with, []))))}
  end

  defp shoot(game, shooter, steps \\ 30), do: game |> holding(shooter, [:fire]) |> play(1) |> holding(shooter, []) |> play(steps)
  defp ball_at(game, id, pos), do: %{game | balls: Enum.map(game.balls, fn ball -> if ball.id == id, do: %{ball | pos: pos}, else: ball end)}

  describe "fuel" do
    test "a ship with an empty tank, flying or on its base, is lost after ten seconds and loses a life" do
      game = game([limitedlives: "yes", worldlives: 3]) |> joined(:a) |> joined(:b, %{team: 2})
      flying = game |> place(:a, {6.0, 8.0}, with: [fuel: 0.0])
      assert ship(seconds(flying, 9.0), :a).alive?
      lost = seconds(flying, 10.5)
      refute ship(lost, :a).alive?
      assert ship(lost, :a).lives == 2
      assert Enum.any?(Game.view(lost, :b).messages, fn {_, text} -> text =~ "a ran out of fuel" end)
      assert :explosion in Enum.map(events(lost), &elem(&1, 0))

      landed = game |> place(:a, {3.5, 2.5}, landed?: true, with: [fuel: 0.0])
      refute ship(seconds(landed, 10.5), :a).alive?
    end

    test "refuelling in time keeps the ship" do
      game = game() |> joined(:a) |> place(:a, {6.0, 8.0}, with: [fuel: 0.0])
      refilled = game |> seconds(6.0) |> place(:a, {10.5, 4.5}, with: [fuel: 0.0]) |> seconds(5.0)
      assert ship(refilled, :a).alive?
      assert ship(refilled, :a).fuel > 0
    end

    test "when every ship is out of fuel the round ends with nobody standing" do
      game = game([limitedlives: "yes", worldlives: 1]) |> joined(:a) |> joined(:b, %{team: 2})
      game = game |> place(:a, {6.0, 8.0}, with: [fuel: 0.0]) |> place(:b, {18.0, 8.0}, with: [fuel: 0.0])
      over = seconds(game, 10.5)
      assert Enum.any?(events(over), &match?({:round, _}, &1))
      assert ship(over, :a).alive? and ship(over, :b).alive?
    end
  end

  describe "the ball on its string" do
    test "a carried ball trails on a string, swings with its own velocity and is pulled by gravity" do
      game = game(gravity: -1.0) |> joined(:a, %{team: 2}) |> place(:a, {3.5, 5.5}) |> play(2)
      assert ship(game, :a).ball != nil

      away = game |> place(:a, {5.5, 5.5}, vel: {6.0, 0.0}) |> play(10)
      [%{pos: {bx, by}, vel: {vx, _}, string: {sx, _}}] = Enum.filter(Game.view(away, :a).balls, &(&1.string != nil))
      assert bx < sx
      assert vx > 0
      assert by > 5.5
      assert :math.sqrt((sx - bx) * (sx - bx)) < 4.0
    end

    test "the string breaks when it is stretched too far, and the ball is loose again" do
      game = game() |> joined(:a, %{team: 2}) |> place(:a, {3.5, 5.5}) |> play(2)
      snapped = game |> place(:a, {16.0, 5.5}) |> play(1)
      assert ship(snapped, :a).ball == nil
      assert Enum.all?(Game.view(snapped, :a).balls, &(&1.string == nil))
    end

    test "a loose ball keeps moving, bounces off walls and comes to rest" do
      game = game() |> joined(:a, %{team: 2})
      [left | rest] = game.balls
      rolling = %{game | balls: [%{left | pos: {3.5, 5.5}, vel: {-8.0, 0.0}, carrier: nil} | rest]} |> play(20)
      [ball | _] = rolling.balls
      {bx, _} = ball.pos
      assert bx > 1.0
      assert elem(ball.vel, 0) > 0.0
      rested = play(rolling, 400)
      assert abs(elem(hd(rested.balls).vel, 0)) < 0.5
    end

    test "with ballswallbounce off, a ball that hits a wall goes home" do
      game = game(ballswallbounce: "no") |> joined(:a, %{team: 2})
      [left | rest] = game.balls
      home = %{game | balls: [%{left | pos: {2.0, 5.5}, vel: {-8.0, 0.0}, carrier: nil} | rest]} |> play(20)
      assert hd(home.balls).pos == {3.5, 5.5}
    end

    test "the ball is drawn on a line to its carrier" do
      game = game() |> joined(:a, %{team: 2}) |> place(:a, {3.5, 5.5}) |> play(2) |> place(:a, {5.5, 5.5}) |> play(5)
      arts = ExPilot.Client.scene(Game.view(game, :a)).movers |> Enum.map(&elem(&1, 0))
      assert :ball in arts
      assert Enum.count(arts, &(&1 == :string)) >= 2
    end
  end

  describe "watching" do
    test "a player out of lives follows the nearest ship and steps through the others with next_watch" do
      game = game([limitedlives: "yes", worldlives: 1]) |> joined(:a, %{team: 1}) |> joined(:b, %{team: 2}) |> joined(:c, %{team: 1}) |> joined(:d, %{team: 2})
      game = game |> place(:a, {10.0, 6.0}) |> place(:b, {12.0, 6.0}, heading: 32) |> place(:c, {18.0, 6.0}) |> place(:d, {20.0, 8.0})
      out = shoot(game, :b)
      refute ship(out, :a).alive?
      assert Game.view(out, :a).watching == "b"

      stepped = out |> holding(:a, [:next_watch]) |> play(1)
      assert Game.view(stepped, :a).watching == "c"
      assert Game.view(stepped, :a).focus == {18.0, 6.0}

      held = stepped |> play(5)
      assert Game.view(held, :a).watching == "c"

      again = held |> holding(:a, []) |> play(1) |> holding(:a, [:next_watch]) |> play(1)
      assert Game.view(again, :a).watching == "d"
      wrapped = again |> holding(:a, []) |> play(1) |> holding(:a, [:next_watch]) |> play(1)
      assert Game.view(wrapped, :a).watching == "b"
    end

    test "a spectator steps through the ships too and falls back to the middle when none fly" do
      game = game() |> joined(:a) |> joined(:b, %{team: 2}) |> joined(:w, %{spectate: true})
      assert Game.view(game, :w).focus == {12.0, 6.0}
      first = game |> holding(:w, [:next_watch]) |> play(1)
      assert Game.view(first, :w).watching == "a"
      assert Game.view(first, :w).focus == ship(first, :a).body.pos
    end
  end

  describe "map options" do
    test "allowshields off leaves the shield key dead" do
      game = game(allowshields: "no") |> joined(:a) |> joined(:b, %{team: 2}) |> place(:a, {10.0, 6.0}, heading: 0) |> place(:b, {14.0, 6.0})
      shot = game |> holding(:b, [:shield]) |> shoot(:a)
      refute ship(shot, :b).alive?
      refute Enum.any?(Game.view(game |> holding(:b, [:shield]) |> play(1), :a).ships, &(&1.id == :b and &1.shielding?))
    end

    test "initialfuel and the initial item counts fill a new ship" do
      game = game(initialfuel: 400, initialmines: 2, initiallasers: 1, initialtanks: 1, initialarmor: 1) |> joined(:a)
      s = ship(game, :a)
      assert s.fuel == 400.0
      assert Items.has?(s, :mine) and s.items.mine == 2
      assert Items.has?(s, :laser)
      assert s.max_fuel == 1500.0
      assert s.armour == 1
      assert ship(Game.step(%{game | ships: Map.put(game.ships, :a, Ship.die(s, 0.0))}, @dt), :a).items.mine == 2
    end

    test "shotswallbounce lets shots bounce off walls; shotsgravity off keeps them straight" do
      bouncing = game(shotswallbounce: "yes") |> joined(:a) |> place(:a, {21.0, 6.0}, heading: 0) |> holding(:a, [:fire]) |> play(1) |> holding(:a, []) |> play(20)
      assert bouncing.shots != []
      assert Enum.all?(bouncing.shots, fn %{body: %{vel: {vx, _}}} -> vx < 0 end)

      straight = game([gravity: -5.0, shotsgravity: "no"]) |> joined(:a) |> place(:a, {5.0, 6.0}, heading: 0, landed?: true) |> holding(:a, [:fire]) |> play(1) |> holding(:a, []) |> play(10)
      assert straight.shots != []
      assert Enum.all?(straight.shots, fn %{body: %{vel: {_, vy}}} -> vy == 0.0 end)
      falling = game([gravity: -5.0]) |> joined(:a) |> place(:a, {5.0, 6.0}, heading: 0, landed?: true) |> holding(:a, [:fire]) |> play(1) |> holding(:a, []) |> play(10)
      assert Enum.all?(falling.shots, fn %{body: %{vel: {_, vy}}} -> vy > 0.0 end)
    end

    test "friction slows a drifting ship" do
      drift = fn options -> game(options) |> joined(:a) |> place(:a, {10.0, 6.0}, vel: {10.0, 0.0}) |> play(50) |> ship(:a) |> Map.get(:body) |> Map.get(:vel) |> elem(0) end
      assert drift.(friction: 0.02) < drift.([]) - 1.0
    end

    test "allowplayerkilling off makes shots bounce off other ships" do
      game = game(allowplayerkilling: "no") |> joined(:a) |> joined(:b, %{team: 2}) |> place(:a, {10.0, 6.0}, heading: 0) |> place(:b, {14.0, 6.0})
      shot = shoot(game, :a)
      assert ship(shot, :b).alive?
      assert Enum.any?(events(shot), &match?({:bounce, _}, &1))
    end

    test "ships that fly into each other crash, bounce when both are shielded, and pass when crashes are off" do
      meet = fn options, shields -> game(options) |> joined(:a) |> joined(:b, %{team: 2}) |> place(:a, {10.0, 6.0}, vel: {6.0, 0.0}) |> place(:b, {11.5, 6.0}, vel: {-6.0, 0.0}) |> holding(:a, shields) |> holding(:b, shields) |> play(10) end
      crashed = meet.([], [])
      refute ship(crashed, :a).alive? or ship(crashed, :b).alive?
      assert Enum.any?(Game.view(crashed, :a).messages, fn {_, text} -> text =~ "collided" end)

      bounced = meet.([], [:shield])
      assert ship(bounced, :a).alive? and ship(bounced, :b).alive?
      assert elem(ship(bounced, :a).body.vel, 0) < 0

      passed = meet.([allowplayercrashes: "no", allowplayerbounces: "no"], [])
      assert ship(passed, :a).alive? and ship(passed, :b).alive?
      assert elem(ship(passed, :a).body.vel, 0) > 0
    end

    test "a player without a team is put on the team with fewer ships, and a team given as text is read" do
      game = game() |> joined(:a, %{team: 1}) |> joined(:b)
      assert ship(game, :b).team == 2
      assert ship(joined(game, :c), :c).team == 1
      assert ship(joined(game, :d, %{team: "2"}), :d).team == 2
    end

    test "targetkillteam kills a team whose last target falls, treasurekillteam a team whose ball is taken home" do
      game = game(targetkillteam: "yes") |> joined(:a, %{team: 1}) |> joined(:b, %{team: 2}) |> place(:a, {10.0, 6.0}) |> place(:b, {14.0, 6.0})
      {targets, :hit} = ExPilot.Targets.hit(game.targets, {21, 7}, 1)
      {targets, :hit} = ExPilot.Targets.hit(targets, {21, 7}, 1)
      struck = %{game | targets: targets, shots: [%{id: 99, owner: :a, kind: :shot, body: Cauldron2D.Body.new(pos: {21.5, 7.5}, vel: {0.0, 0.0}, radius: 0.1), life: 1.0}]}
      after_hit = play(struck, 1)
      refute ship(after_hit, :b).alive?
      assert ship(after_hit, :a).alive?

      ctf = game(treasurekillteam: "yes") |> joined(:a, %{team: 2}) |> joined(:b, %{team: 1}) |> place(:a, {3.5, 5.5}) |> place(:b, {12.0, 2.0}) |> play(2)
      [left | _] = ctf.balls
      scored = ctf |> place(:a, {21.5, 5.5}, with: [ball: left.id]) |> ball_at(left.id, {20.5, 5.5}) |> play(3)
      refute ship(scored, :b).alive?
      assert ship(scored, :a).alive?
    end

    test "dropitemonkillprob drops a killed ship's items on the floor" do
      game = game(dropitemonkillprob: 1.0, itemprobmult: 0) |> joined(:a) |> joined(:b, %{team: 2}) |> place(:a, {10.0, 6.0}, heading: 0) |> place(:b, {14.0, 6.0}, with: [items: %{mine: 2, laser: 1}])
      shot = shoot(game, :a)
      refute ship(shot, :b).alive?
      assert Enum.sort(Enum.map(shot.items, & &1.kind)) == [:laser, :mine, :mine]
      kept = game(dropitemonkillprob: 0.0, itemprobmult: 0) |> joined(:a) |> joined(:b, %{team: 2}) |> place(:a, {10.0, 6.0}, heading: 0) |> place(:b, {14.0, 6.0}, with: [items: %{mine: 2}]) |> shoot(:a)
      assert kept.items == []
    end

    test "laserisstungun leaves the victim alive but stunned" do
      game = game(laserisstungun: "yes") |> joined(:a) |> joined(:b, %{team: 2}) |> place(:a, {10.0, 6.0}, heading: 0, with: [items: %{laser: 1}]) |> place(:b, {15.0, 6.0}) |> holding(:a, [:fire_laser]) |> play(1)
      assert ship(game, :b).alive?
      assert ExPilot.Gear.confused?(ship(game, :b), game.time)
    end

    test "minefusetime and firerepeatrate set the mine's fuse and the gun's cadence" do
      slow = game(firerepeatrate: 25) |> joined(:a) |> place(:a, {10.0, 6.0}, heading: 0) |> holding(:a, [:fire]) |> play(15)
      assert length(slow.shots) == 1
      fused = game(minefusetime: 250) |> joined(:a) |> place(:a, {10.0, 6.0}, with: [items: %{mine: 1}]) |> holding(:a, [:drop_mine]) |> play(1)
      [mine] = fused.shots
      assert_in_delta mine.armed_in, 5.0, 0.05
    end

    test "gravityangle turns uniform gravity and gravitypointsource pulls toward gravitypoint" do
      sideways = game(gravity: -2.0, gravityangle: 0) |> joined(:a) |> place(:a, {10.0, 6.0}) |> play(25) |> ship(:a)
      {vx, vy} = sideways.body.vel
      assert vx < -0.1 and abs(vy) < 0.01

      point = game(gravity: -2.0, gravitypoint: "20,6", gravitypointsource: "yes") |> joined(:a) |> place(:a, {10.0, 6.0}) |> play(25) |> ship(:a)
      {px, _} = point.body.vel
      assert px > 0.1
    end

    test "a shielded ship picks up no item and drops no mine unless the map allows it" do
      with_item = fn options -> %{game(options) | items: [%{pos: {10.5, 6.5}, kind: :laser, ttl: 60.0}]} |> joined(:a) |> place(:a, {10.4, 6.5}) |> holding(:a, [:shield]) |> play(2) end
      refute Items.has?(ship(with_item.([]), :a), :laser)
      assert Items.has?(ship(with_item.(shieldeditempickup: "yes"), :a), :laser)

      mining = fn options -> game(options) |> joined(:a) |> place(:a, {10.0, 6.0}, with: [items: %{mine: 1}]) |> holding(:a, [:shield]) |> play(1) |> holding(:a, [:shield, :drop_mine]) |> play(1) end
      assert mining.([]).shots == []
      assert length(mining.(shieldedmining: "yes").shots) == 1
    end

    test "playerwallbouncebrakefactor sets how much speed a bounce keeps" do
      bounce = fn options -> game(options) |> joined(:a) |> place(:a, {21.5, 6.0}, vel: {3.0, 0.0}) |> holding(:a, [:shield]) |> play(30) |> ship(:a) |> Map.get(:body) |> Map.get(:vel) |> elem(0) end
      assert bounce.(playerwallbouncebrakefactor: 0.9) < bounce.(playerwallbouncebrakefactor: 0.2)
    end

    test "checkpointradius widens a race checkpoint" do
      s = %{Ship.new(:a, "a", {1, 1}) | body: %{Ship.new(:a, "a", {1, 1}).body | pos: {14.0, 2.5}}}
      assert ExPilot.Race.pass(s, [{12, 2}], 2, 3.0).laps == 1
      assert ExPilot.Race.pass(s, [{12, 2}], 2).laps == 0
    end

    test "playersonradar off keeps other ships off the radar" do
      view = Game.view(game(playersonradar: "no") |> joined(:a) |> joined(:b, %{team: 2}), :a)
      assert view.radar.players? == false
      assert Game.view(game() |> joined(:a), :a).radar.players?
    end
  end
end
