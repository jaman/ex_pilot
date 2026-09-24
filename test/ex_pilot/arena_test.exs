defmodule ExPilot.ArenaTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.Grid.Coarse
  alias Cauldron2D.{Player, World}
  alias Cauldron2D.Worlds.Sweeper
  alias Drafter.Test, as: DT
  alias ExPilot.{Arenas, Robot}

  @fixture Path.join(__DIR__, "../fixtures/dogfight.map.gz")

  setup_all do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ex_pilot_arena_#{System.os_time(:nanosecond)}_#{System.unique_integer([:positive])}"
      )

    System.put_env("XDG_CACHE_HOME", dir)
    System.put_env("XDG_CONFIG_HOME", Path.join(dir, "config"))
    System.put_env("XDG_STATE_HOME", Path.join(dir, "state"))
    Code.ensure_loaded!(Cauldron2D.Drafter.Surface)
    Drafter.Widget.Registry.register(Cauldron2D.Drafter.Surface)
    ExPilot.Art.install()

    on_exit(fn ->
      Process.sleep(200)
      File.rm_rf(dir)
    end)

    :ok
  end

  setup do
    {:ok, _} = Arenas.open(:dogfight, @fixture, robots: 2)
    on_exit(fn -> Arenas.close(:dogfight) end)
    :ok
  end

  test "an open arena is listed with its robots seated and hidden from the player count" do
    assert [%{id: :dogfight, name: "dogfight", players: 0, map: "Dogfight... 6 bases"}] =
             Arenas.list()

    world = Arenas.world_name(:dogfight)
    assert Enum.sort(World.players(world)) == [{:robot, 1}, {:robot, 2}]
  end

  test "a registered arena is listed before its world runs, opens on the first join with its robots, and closes once idle" do
    :ok = Arenas.register(:later, @fixture, robots: 1)
    on_exit(fn -> Arenas.close(:later) end)

    assert %{id: :later, players: 0, map: "Dogfight... 6 bases"} =
             Enum.find(Arenas.list(), &(&1.id == :later))

    refute Arenas.running?(:later)

    assert :ok == Player.join(Arenas.world_name(:later), "zed", %{username: "zed"})
    assert Arenas.running?(:later)

    assert :ok ==
             wait(fn ->
               Enum.sort(World.players(Arenas.world_name(:later))) ==
                 Enum.sort(["zed", {:robot, 1}])
             end)

    assert %{players: 1} = Enum.find(Arenas.list(), &(&1.id == :later))

    {:ok, sweeper} = Sweeper.start_link(idle_after: 0, every: :never, name: nil)
    Sweeper.sweep(sweeper)
    assert Arenas.running?(:later), "a human is still in it"

    Player.leave(Arenas.world_name(:later), "zed")
    Sweeper.sweep(sweeper)
    refute Arenas.running?(:later)
    assert %{id: :later, players: 0} = Enum.find(Arenas.list(), &(&1.id == :later))
  end

  defp wait(check, tries \\ 50) do
    cond do
      check.() -> :ok
      tries == 0 -> :timeout
      true -> Process.sleep(20) && wait(check, tries - 1)
    end
  end

  test "robots never take every base: one is always left for a player" do
    {:ok, _} = Arenas.open(:crowded, @fixture, robots: 10)
    on_exit(fn -> Arenas.close(:crowded) end)
    world = Arenas.world_name(:crowded)
    assert :ok == wait(fn -> length(World.players(world)) == 5 end)
    assert :ok == Player.join(world, "late", %{username: "late"})
  end

  test "a human joining a full arena takes a robot's base, and the robots come back once there is room" do
    {:ok, _} = Arenas.open(:packed, @fixture, robots: 5)
    on_exit(fn -> Arenas.close(:packed) end)
    world = Arenas.world_name(:packed)
    assert :ok == wait(fn -> length(World.players(world)) == 5 end)

    assert :ok == Player.join(world, "one", %{username: "one"})
    assert :ok == Player.join(world, "two", %{username: "two"})
    assert :ok == wait(fn -> Enum.count(World.players(world), &match?({:robot, _}, &1)) == 4 end)
    assert Enum.count(World.snapshot(world).ships, fn {_, ship} -> ship.robot? end) == 4

    Player.leave(world, "one")
    Player.leave(world, "two")

    {:ok, sweeper} =
      Sweeper.start_link(idle_after: 3600, every: :never, name: nil)

    Sweeper.sweep(sweeper)
    assert :ok == wait(fn -> Enum.count(World.players(world), &match?({:robot, _}, &1)) == 5 end)
  end

  test "a robot fires at any enemy it has a line to within a shot's reach, leads a moving one, and holds fire while shielding" do
    grid = fn _ -> :open end
    rules = %{shields?: true, crash_speed: 6.86, shot_speed: 7.2, shot_range: 36.0}

    me = %{
      id: {:robot, 1},
      pos: {10.0, 10.0},
      heading: 0,
      vel: {0.0, 0.0},
      alive?: true,
      team: nil,
      fuel: 900
    }

    held = fn enemies, shots, skill ->
      Robot.decide(%{me: me, ships: [me | enemies], shots: shots, rules: rules}, grid, 0,
        skill: skill,
        tick: 3
      )
      |> elem(0)
    end

    far = %{id: :alice, pos: {34.0, 10.0}, vel: {0.0, 0.0}, alive?: true, team: nil}
    assert MapSet.member?(held.([far], [], 1.0), :fire)
    assert MapSet.member?(held.([far], [], 0.3), :fire)

    beyond = %{far | pos: {50.0, 10.0}}
    refute MapSet.member?(held.([beyond], [], 1.0), :fire)

    off_line = %{far | pos: {19.0, 13.0}}
    sprayed = held.([off_line], [], 1.0)
    assert MapSet.member?(sprayed, :fire)
    assert MapSet.member?(sprayed, :turn_right)

    crossing = %{far | pos: {20.0, 10.0}, vel: {0.0, -5.0}}
    assert MapSet.member?(held.([crossing], [], 1.0), :turn_left)

    threatened = held.([far], [{11.2, 10.0}], 0.3)
    assert MapSet.member?(threatened, :shield)
    refute MapSet.member?(threatened, :fire)
  end

  test "a robot's attack and defence come from its skill: an aggressive one locks on sooner and shields less" do
    grid = fn _ -> :open end
    me = %{id: {:robot, 1}, pos: {10.0, 10.0}, heading: 0, alive?: true, team: nil, fuel: 900}
    enemy = %{id: :alice, pos: {20.0, 10.0}, alive?: true, team: nil}
    view = %{me: me, ships: [me, enemy], shots: []}

    assert Robot.lock(view, grid, nil, skill: 1.0, tick: 48) == :alice
    assert Robot.lock(view, grid, nil, skill: 0.3, tick: 48) == nil
    assert Robot.lock(view, grid, nil, skill: 0.3, tick: 3) == :alice
    assert Robot.lock(view, grid, :alice, skill: 0.3, tick: 48) == :alice
    assert Robot.lock(%{view | ships: [me]}, grid, :alice, skill: 0.3, tick: 3) == nil

    unlocked = Robot.decide(view, grid, 0, skill: 0.3, tick: 48, lock: nil) |> elem(0)
    refute MapSet.member?(unlocked, :fire)

    shielding = fn skill ->
      Enum.count(1..100, fn tick ->
        Robot.decide(%{view | shots: [{11.2, 10.0}]}, grid, 0, skill: skill, tick: tick)
        |> elem(0)
        |> MapSet.member?(:shield)
      end)
    end

    assert shielding.(0.3) > shielding.(1.0)
    assert shielding.(1.0) >= 75
  end

  test "as a Cauldron2D.Robot brain it remembers its burn and answers with held actions" do
    memory = Robot.init(arena: :nowhere)
    me = %{id: {:robot, 1}, pos: {10.0, 10.0}, heading: 0, alive?: true, team: nil, fuel: 900}
    enemy = %{id: :alice, pos: {20.0, 10.0}, alive?: true, team: nil}
    view = %{me: me, ships: [me, enemy], shots: [], arena: "nowhere", mode: :dogfight}
    {%{held: held, aim: nil}, memory} = Robot.decide(view, memory, %{tick: 3, skill: 1.0})
    assert MapSet.member?(held, :fire)
    assert memory.burn == 0
    assert Robot.gone?(%{view | me: nil})
    refute Robot.gone?(view)
  end

  test "a robot low on fuel makes for a fuel station in sight, and hovers there" do
    grid = fn _ -> :open end
    me = %{id: {:robot, 1}, pos: {10.0, 10.0}, heading: 0, alive?: true, team: nil, fuel: 200}
    enemy = %{id: :alice, pos: {20.0, 10.0}, alive?: true, team: nil}
    stations = [{10, 20}]

    thirsty =
      Robot.decide(%{me: me, ships: [me, enemy], shots: []}, grid, 0, stations: stations)
      |> elem(0)

    assert MapSet.member?(thirsty, :turn_left) or MapSet.member?(thirsty, :turn_right)

    full =
      Robot.decide(%{me: %{me | fuel: 900}, ships: [me, enemy], shots: []}, grid, 0,
        stations: stations
      )
      |> elem(0)

    refute MapSet.member?(full, :turn_left) or MapSet.member?(full, :turn_right)

    far =
      Robot.decide(%{me: me, ships: [me, enemy], shots: []}, grid, 0, stations: [{10, 60}])
      |> elem(0)

    refute MapSet.member?(far, :turn_left) or MapSet.member?(far, :turn_right)

    there =
      Robot.decide(
        %{me: Map.merge(me, %{pos: {10.4, 20.6}, vel: {0.0, 0.0}}), ships: [me], shots: []},
        grid,
        0,
        stations: stations
      )
      |> elem(0)

    refute MapSet.member?(there, :thrust)
  end

  test "five robots survive a minute on dogfight without flying into walls all the time" do
    {:ok, arena} = ExPilot.Map.parse_file(@fixture)
    grid = ExPilot.Map.grid(arena)
    game = ExPilot.Game.init(arena: arena, seed: 7, lives: :unlimited)
    ids = for n <- 1..5, do: {:robot, n}

    game =
      Enum.reduce(ids, game, fn id, game ->
        {:ok, game} = ExPilot.Game.join(game, id, %{username: inspect(id), robot?: true})
        game
      end)

    {game, _burns, told} =
      Enum.reduce(1..3000, {game, Map.new(ids, &{&1, 0}), MapSet.new()}, fn tick,
                                                                            {game, burns, told} ->
        {game, burns} =
          if rem(tick, 3) == 0 do
            Enum.reduce(ids, {game, burns}, fn id, {game, burns} ->
              {held, burn} = Robot.decide(ExPilot.Game.view(game, id), grid, burns[id])

              {ExPilot.Game.handle_input(game, id, %{held: held, aim: nil}),
               Map.put(burns, id, burn)}
            end)
          else
            {game, burns}
          end

        game = ExPilot.Game.step(game, 0.02)
        {game, burns, Enum.reduce(game.messages, told, &MapSet.put(&2, &1))}
      end)

    wall_deaths = Enum.count(told, fn {_, text} -> text =~ "hit a wall" end)
    collisions = Enum.count(told, fn {_, text} -> text =~ "collided" end)
    deaths = ids |> Enum.map(&game.ships[&1].tally.deaths) |> Enum.sum()

    assert deaths <= 25,
           "#{deaths} deaths in a minute, #{wall_deaths} of them into walls, #{collisions} collisions"

    assert wall_deaths <= 2, "#{wall_deaths} deaths into walls in a minute"
  end

  test "a robot decides from its view" do
    grid = fn _ -> :open end
    me = %{id: {:robot, 1}, pos: {10.0, 10.0}, heading: 0, alive?: true, team: nil, fuel: 900}
    enemy = %{id: :alice, pos: {20.0, 10.0}, alive?: true, team: nil}
    held = Robot.decide(%{me: me, ships: [me, enemy], shots: []}, grid)
    assert MapSet.member?(held, :fire)
    assert MapSet.member?(held, :thrust)

    behind = %{enemy | pos: {0.0, 10.0}}
    held = Robot.decide(%{me: me, ships: [me, behind], shots: []}, grid)
    refute MapSet.member?(held, :fire)
    assert MapSet.member?(held, :turn_left) or MapSet.member?(held, :turn_right)

    shielded = Robot.decide(%{me: me, ships: [me], shots: [{11.0, 10.0}]}, grid)
    assert MapSet.member?(shielded, :shield)

    far_behind = %{enemy | pos: {-40.0, 10.0}}
    held = Robot.decide(%{me: me, ships: [me, far_behind], shots: []}, grid)
    assert MapSet.member?(held, :turn_left) or MapSet.member?(held, :turn_right)
    refute MapSet.member?(held, :fire)
    refute MapSet.member?(held, :thrust)
  end

  test "an enemy behind a wall is no target: the robot holds its fire and flies for the door" do
    walls = MapSet.new(for y <- 0..29, y < 20, do: {15, y})

    grid = fn {x, y} = cell ->
      if x < 0 or y < 0 or x >= 30 or y >= 30 or MapSet.member?(walls, cell),
        do: :solid,
        else: :open
    end

    route = Coarse.new(grid, {30, 30})

    me = %{
      id: {:robot, 1},
      pos: {10.0, 5.0},
      heading: 0,
      vel: {0.0, 0.0},
      alive?: true,
      team: nil,
      fuel: 900
    }

    hidden = %{id: :alice, pos: {20.0, 5.0}, alive?: true, team: nil}

    held =
      Robot.decide(%{me: me, ships: [me, hidden], shots: []}, grid, 0, route: route) |> elem(0)

    refute MapSet.member?(held, :fire)
    assert MapSet.member?(held, :turn_right)

    without_route = Robot.decide(%{me: me, ships: [me, hidden], shots: []}, grid)
    refute MapSet.member?(without_route, :fire)
    refute MapSet.member?(without_route, :turn_right) or MapSet.member?(without_route, :turn_left)

    seen = %{hidden | pos: {20.0, 25.0}}
    facing = %{me | pos: {10.0, 25.0}}

    assert MapSet.member?(
             Robot.decide(%{me: facing, ships: [facing, seen], shots: []}, grid, 0, route: route)
             |> elem(0),
             :fire
           )
  end

  test "a landed robot launches straight up out of its base pocket before hunting" do
    pocket = MapSet.new([{9, 10}, {11, 10}, {10, 11}])
    grid = fn cell -> if MapSet.member?(pocket, cell), do: :solid, else: :open end
    up = div(ExPilot.Ship.headings(), 4)

    me = %{
      id: {:robot, 1},
      pos: {10.5, 10.5},
      heading: up,
      launch_heading: up,
      vel: {0.0, 0.0},
      alive?: true,
      landed?: true,
      team: nil,
      fuel: 900
    }

    below = %{id: :alice, pos: {10.5, 30.0}, alive?: true, team: nil}

    held = Robot.decide(%{me: me, ships: [me, below], shots: []}, grid)
    assert MapSet.member?(held, :thrust)
    refute MapSet.member?(held, :turn_left) or MapSet.member?(held, :turn_right)

    turned = %{me | heading: 0}
    held = Robot.decide(%{me: turned, ships: [turned, below], shots: []}, grid)
    assert MapSet.member?(held, :turn_left)
    refute MapSet.member?(held, :thrust)

    hanging = %{me | heading: up, launch_heading: 3 * up}
    held = Robot.decide(%{me: hanging, ships: [hanging, below], shots: []}, grid)
    assert MapSet.member?(held, :turn_left) or MapSet.member?(held, :turn_right)
    refute MapSet.member?(held, :thrust)

    {_held, burn} = Robot.decide(%{me: me, ships: [me, below], shots: []}, grid, 0)
    assert burn > 0

    airborne = %{me | landed?: false, pos: {10.5, 9.8}, vel: {0.0, -0.5}}
    {held, left} = Robot.decide(%{me: airborne, ships: [airborne, below], shots: []}, grid, burn)
    assert held == MapSet.new([:thrust]), "keeps burning straight up until clear of the pocket"
    assert left == burn - 1

    route = Coarse.new(grid, {40, 40})

    {held, 0} =
      Robot.decide(%{me: airborne, ships: [airborne, below], shots: []}, grid, 0, route: route)

    refute held == MapSet.new([:thrust]),
           "with the burn spent it hunts: the way round the pocket to the enemy below"
  end

  test "a robot whose enemy is behind a wall settles on the nearest clear heading instead of nosing into the wall" do
    walls = MapSet.new(for y <- 5..15, do: {12, y})
    grid = fn cell -> if MapSet.member?(walls, cell), do: :solid, else: :open end

    me = %{
      id: {:robot, 1},
      pos: {10.5, 10.5},
      heading: 0,
      vel: {0.0, 0.0},
      alive?: true,
      team: nil,
      fuel: 900
    }

    enemy = %{id: :alice, pos: {20.0, 10.5}, alive?: true, team: nil}

    decide = fn heading ->
      Robot.decide(%{me: %{me | heading: heading}, ships: [me, enemy], shots: []}, grid)
    end

    held = decide.(0)
    assert MapSet.member?(held, :turn_left) or MapSet.member?(held, :turn_right)
    refute MapSet.member?(held, :thrust)

    almost = decide.(8)
    assert MapSet.member?(almost, :turn_left)
    refute MapSet.member?(almost, :turn_right)
    refute MapSet.member?(almost, :thrust)

    clear = decide.(11)
    refute MapSet.member?(clear, :turn_right) or MapSet.member?(clear, :turn_left)
    assert MapSet.member?(clear, :thrust)
  end

  test "a robot with a wall ahead turns toward the open side and brakes when drifting into it" do
    walls = MapSet.new(for x <- 8..12, y <- 8..12, x == 12 or y == 8, do: {x, y})
    grid = fn cell -> if MapSet.member?(walls, cell), do: :solid, else: :open end

    me = %{
      id: {:robot, 1},
      pos: {10.5, 10.5},
      heading: 0,
      vel: {0.0, 0.0},
      alive?: true,
      team: nil,
      fuel: 900
    }

    held = Robot.decide(%{me: me, ships: [me], shots: []}, grid)
    assert MapSet.member?(held, :turn_right)
    refute MapSet.member?(held, :turn_left)

    half = div(ExPilot.Ship.headings(), 2)
    drifting = %{me | heading: half, vel: {6.0, 0.0}}
    held = Robot.decide(%{me: drifting, ships: [drifting], shots: []}, grid)
    assert MapSet.member?(held, :thrust)
  end

  test "a player joins the same world as the robots and the client draws it" do
    ctx =
      DT.start_headless(
        Cauldron2D.Drafter.Client,
        %{
          game: ExPilot.Client,
          username: "alice",
          sink: TuningFork.Sink.Silent,
          settings: %{display: :glyphs}
        },
        size: {100, 30}
      )

    on_exit(fn -> DT.stop(ctx) end)

    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "dogfight" end)
    DT.send_key(ctx, :enter)

    world = Arenas.world_name(:dogfight)
    assert :ok == DT.wait_for(ctx, fn _ -> "alice" in World.players(world) end)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "fuel" end, timeout: 3_000)
    assert DT.screen_text(ctx) =~ "alice"
    assert DT.screen_text(ctx) =~ "on base"
    assert DT.screen_text(ctx) =~ "scores"
    refute DT.screen_text(ctx) =~ "Esc  lobby"

    DT.send_key(ctx, :"?")

    assert :ok ==
             DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "w, mouse right  thrust" end,
               timeout: 3_000
             )

    Player.input(world, "alice", %{held: MapSet.new([:thrust]), aim: nil})
    Process.sleep(300)
    %{ships: %{"alice" => ship}} = World.snapshot(world)
    assert ship.body.vel != {0.0, 0.0} or not ship.alive?
  end
end
