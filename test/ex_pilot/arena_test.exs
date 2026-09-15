defmodule ExPilot.ArenaTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.{Player, World}
  alias Drafter.Test, as: DT
  alias ExPilot.{Arenas, Robot}

  @fixture Path.join(__DIR__, "../fixtures/dogfight.map.gz")

  setup_all do
    dir = Path.join(System.tmp_dir!(), "ex_pilot_arena_#{System.os_time(:nanosecond)}_#{System.unique_integer([:positive])}")
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
    assert [%{id: :dogfight, name: "dogfight", players: 0, map: "Dogfight... 6 bases"}] = Arenas.list()
    world = Arenas.world_name(:dogfight)
    assert Enum.sort(World.players(world)) == [{:robot, 1}, {:robot, 2}]
  end

  test "robots fly and fire" do
    world = Arenas.world_name(:dogfight)
    Process.sleep(1_500)
    snapshot = World.snapshot(world)
    moved = Enum.any?(snapshot.ships, fn {_, ship} -> ship.body.vel != {0.0, 0.0} or not ship.alive? end)
    assert moved
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

  test "a player joins the same world as the robots and the client draws it" do
    ctx =
      DT.start_headless(
        Cauldron2D.Drafter.Client,
        %{game: ExPilot.Client, username: "alice", sink: TuningFork.Sink.Silent, settings: %{display: :glyphs}},
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
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "s, mouse right  thrust" end, timeout: 3_000)

    Player.input(world, "alice", %{held: MapSet.new([:thrust]), aim: nil})
    Process.sleep(300)
    %{ships: %{"alice" => ship}} = World.snapshot(world)
    assert ship.body.vel != {0.0, 0.0} or not ship.alive?
  end
end
