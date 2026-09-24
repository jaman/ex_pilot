defmodule ExPilot.ArtTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.Atlas
  alias ExPilot.{Art, Ship, Shipshape}

  setup_all do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ex_pilot_art_#{System.os_time(:nanosecond)}_#{System.unique_integer([:positive])}"
      )

    System.put_env("XDG_CACHE_HOME", dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    :ok
  end

  test "the atlas holds every tile the map legend names and a ship for every heading and team" do
    atlas = Art.build()
    arts = Atlas.arts(atlas)

    for art <- [
          :wall,
          :wall_se,
          :wall_sw,
          :wall_ne,
          :wall_nw,
          :fuel,
          :fuel_low,
          :fuel_empty,
          :base_up,
          :base_down,
          :base_left,
          :base_right,
          :cannon_up,
          :cannon_gone,
          :cannon_left,
          :wormhole,
          :gravity,
          :treasure,
          :target,
          :shot,
          :spark,
          :debris,
          :shield
        ] do
      assert art in arts, "missing #{art}"
    end

    assert Art.ship(nil, 0) in arts
    assert Art.ship(3, Ship.headings() - 1) in arts
    assert Enum.count(arts, &match?({:ship, _, _}, &1)) == 5 * Ship.headings()
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

  test "a ship without a team gets its own shape in the plain colour, like the default ship" do
    Art.install()
    shape = "(SH: 15,0 -10,5 -6,0 -10,-5)(EN: -6,0)(MG: 15,0)"
    assert {:ship, {0, _}, 5} = art = Art.ship_shape(shape, nil, 5)
    assert art in Atlas.arts(Atlas.fetch(Art.name()))
    assert {:ship, {1, _}, 5} = Art.ship_shape(shape, 5, 5)
  end
end

defmodule ExPilot.ShipshapeFileTest do
  use ExUnit.Case, async: false

  alias ExPilot.Shipshape

  setup do
    dir = Path.join(System.tmp_dir!(), "shipshape_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    previous = System.get_env("XDG_CONFIG_HOME")
    System.put_env("XDG_CONFIG_HOME", dir)

    on_exit(fn ->
      if previous,
        do: System.put_env("XDG_CONFIG_HOME", previous),
        else: System.delete_env("XDG_CONFIG_HOME")

      File.rm_rf!(dir)
    end)

    :ok
  end

  test "a player's shipshape file is kept under the config home, read trimmed, and removed by keeping nothing" do
    assert Shipshape.read_file("carol") == nil
    assert :ok = Shipshape.keep_file("carol", Shipshape.preset!("dart") <> "\n")
    assert Shipshape.read_file("carol") == Shipshape.preset!("dart")
    assert Shipshape.next_preset(Shipshape.preset!("dart"), 1) == Shipshape.preset!("wedge")
    assert Shipshape.next_preset(nil, 1) == Shipshape.preset!("dart")
    assert Shipshape.next_preset(nil, -1) == Shipshape.preset!("saucer")
    assert Shipshape.next_preset("(SH: 1,1 2,2 3,3)", 1) == Shipshape.preset!("classic")
    assert Shipshape.preset_name(Shipshape.preset!("wide")) == "wide"
    assert Shipshape.preset_name(nil) == "classic"
    assert Shipshape.preset_name("(SH: 1,1 2,2 3,3)") == nil
    assert :ok = Shipshape.keep_file("carol", nil)
    assert Shipshape.read_file("carol") == nil
  end
end
