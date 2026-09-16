defmodule ExPilot.Web.GameTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.World
  alias ExPilot.Arenas
  alias ExPilot.Web.Game, as: WebGame

  @fixture Path.join(__DIR__, "../../fixtures/dogfight.map.gz")

  setup do
    dir = Path.join(System.tmp_dir!(), "ex_pilot_web_game_#{System.os_time(:nanosecond)}")
    System.put_env("XDG_CONFIG_HOME", Path.join(dir, "config"))
    System.put_env("XDG_STATE_HOME", Path.join(dir, "state"))
    ExPilot.Art.install()
    :ok = Arenas.register(:webdog, @fixture, robots: 1)
    on_exit(fn -> Arenas.close(:webdog) end)
    :ok
  end

  test "names a registered arena's world by the id the topic carries, and nothing for a stranger" do
    assert WebGame.world("webdog") == Arenas.world_name(:webdog)
    assert WebGame.world("nowhere") == nil
    assert WebGame.world("nowhere") == nil
  end

  test "a view becomes a static map with wrapping, movers with destroyed targets, and hud rows of text and colour" do
    world = WebGame.world("webdog")
    :ok = Cauldron2D.Player.join(world, "alice", %{username: "alice"})
    view = ExPilot.Game.view(World.snapshot(world), "alice")

    map = WebGame.map(view)
    assert {map.width, map.height} == {120, 120}
    assert map.wrap? == true
    assert map.cell.({0, 0}) == nil
    assert Enum.any?(for(x <- 0..119, y <- 0..119, do: map.cell.({x, y})), &(&1 == :wall))

    scene = WebGame.scene(%{view | targets_gone: MapSet.new([{3, 4}])})
    assert {fx, fy} = scene.focus
    assert is_float(fx) and is_float(fy)
    assert {:target_gone, {3, 4}} in scene.movers
    assert Enum.any?(scene.movers, fn {art, _} -> match?({:ship, _, _}, art) end)

    hud = WebGame.hud(view)
    assert Enum.any?(hud, fn row -> Enum.any?(row, fn {text, _} -> text =~ "alice" end) end)
    assert Enum.any?(hud, fn row -> Enum.any?(row, fn {text, colour} -> text =~ "fuel" and colour == {255, 255, 0} end) end)
    assert Enum.all?(hud, fn row -> Enum.all?(row, fn {text, colour} -> is_binary(text) and (colour == nil or tuple_size(colour) == 3) end) end)
  end
end
