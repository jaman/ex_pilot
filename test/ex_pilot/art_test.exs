defmodule ExPilot.ArtTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.Atlas
  alias ExPilot.{Art, Ship, Shipshape}

  setup_all do
    dir = Path.join(System.tmp_dir!(), "ex_pilot_art_#{System.os_time(:nanosecond)}_#{System.unique_integer([:positive])}")
    System.put_env("XDG_CACHE_HOME", dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    :ok
  end

  test "the atlas holds every tile the map legend names and a ship for every heading and team" do
    atlas = Art.build()
    arts = Atlas.arts(atlas)

    for art <- [:wall, :wall_se, :wall_sw, :wall_ne, :wall_nw, :fuel, :base_up, :base_down, :base_left, :base_right, :cannon_up, :cannon_left, :wormhole, :gravity, :treasure, :target, :shot, :spark, :debris, :shield] do
      assert art in arts, "missing #{art}"
    end

    assert Art.ship(nil, 0) in arts
    assert Art.ship(3, Ship.headings() - 1) in arts
    assert Enum.count(arts, &match?({:ship, _, _}, &1)) == 5 * Ship.headings()
  end

  test "install is idempotent" do
    assert Art.install() == :ex_pilot
    assert Art.install() == :ex_pilot
    assert Atlas.installed?(:ex_pilot)
  end

  test "shipshapes parse with defaults for missing sections" do
    assert {:ok, %{outline: [{15, 0}, {-8, 8}, {-8, -8}], engine: {-8, 0}, guns: [{15, 0}]}} =
             Shipshape.parse("(SH: 15,0 -8,8 -8,-8)")

    assert {:error, :no_outline} = Shipshape.parse("(EN: 1,1)")
  end

  test "a player's own shipshape is installed on first sight and drawn with the team's colour" do
    Art.install()
    shape = "(SH: 15,0 -8,8 -8,-8)(EN: -8,0)(MG: 15,0)"
    art = Art.ship_shape(shape, 2, 5)
    assert {:ship, {2, _}, 5} = art
    atlas = Atlas.fetch(Art.name())
    assert art in Atlas.arts(atlas)
    assert Art.ship_shape(shape, 2, 5) == art
    assert Art.ship_shape(nil, 2, 5) == Art.ship(2, 5)
    assert Art.ship_shape("nonsense", 2, 5) == Art.ship(2, 5)
  end
end
