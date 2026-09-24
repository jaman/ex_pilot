defmodule ExPilot.PadmapTest do
  use ExUnit.Case, async: true

  alias ExPilot.Padmap

  test "the default layout: the left stick aims the way it points, the d-pad turns, A shields, B and the right bumper fire, the right trigger thrusts" do
    default = Padmap.default()
    assert default.aim == [{:stick, :left}]
    assert default.turn_left == [:dpad_left]
    assert default.turn_right == [:dpad_right]
    assert :a in default.shield
    assert :b in default.fire
    assert :right_bumper in default.fire
    assert {:axis, :right_trigger, :pos} in default.thrust
    refute Enum.any?(default.thrust, &match?({:axis, :left_y, _}, &1))
    assert Enum.all?(Map.keys(default), &(&1 in Padmap.actions()))
    assert hd(Padmap.actions()) == :aim
  end

  test "controls are written as words: buttons by name, an axis with its direction as - or +" do
    assert Padmap.parse_controls("b right_bumper") == {:ok, [:b, :right_bumper]}

    assert Padmap.parse_controls("left_x-  right_trigger+") ==
             {:ok, [{:axis, :left_x, :neg}, {:axis, :right_trigger, :pos}]}

    assert Padmap.parse_controls("") == {:ok, []}
    assert Padmap.parse_controls("left_stick_xy") == {:ok, [{:stick, :left}]}
    assert Padmap.format_controls([{:stick, :right}]) == "right_stick_xy"

    assert Padmap.parse_controls("left_stick_xy+thrust") ==
             {:ok, [{:stick, :left, push: [action: :thrust, beyond: 0.6, least: 0.3, gain: 1.4]}]}

    assert Padmap.format_controls([{:stick, :left, push: [action: :thrust, beyond: 0.6]}]) ==
             "left_stick_xy+thrust"

    assert Padmap.parse_controls("left_stick_xy+zz") == {:error, {:unknown, "left_stick_xy+zz"}}

    assert Padmap.with_push([{:stick, :left}, :a], :thrust) == [
             {:stick, :left, push: [action: :thrust, beyond: 0.6, least: 0.3, gain: 1.4]},
             :a
           ]

    assert Padmap.with_push([{:stick, :left, push: [action: :thrust]}], nil) == [{:stick, :left}]
    assert Padmap.pushes?([{:stick, :left, push: [action: :thrust]}])
    refute Padmap.pushes?([{:stick, :left}])

    assert Padmap.from_props(%{"aim" => ["right_stick_xy"]}) == %{aim: [{:stick, :right}]}
    assert Padmap.parse_controls("a zz") == {:error, {:unknown, "zz"}}

    assert Padmap.parse_controls("left_x") == {:error, {:unknown, "left_x"}}

    assert Padmap.format_controls([:a, {:axis, :left_x, :neg}, {:axis, :right_trigger, :pos}]) ==
             "a left_x- right_trigger+"
  end

  test "a player's bindings replace the default's action by action, and survive the account's props as strings" do
    merged = Padmap.merge(%{fire: [:x], shield: []})
    assert merged.fire == [:x]
    assert merged.shield == []
    assert merged.thrust == Padmap.default().thrust
    assert Padmap.merge(%{}) == Padmap.default()
    assert Padmap.overrides(%{fire: [:x], thrust: Padmap.default().thrust}) == %{fire: [:x]}

    props = Padmap.to_props(%{fire: [:x, {:axis, :left_trigger, :pos}]})
    assert props == %{"fire" => ["x", "left_trigger+"]}
    assert Padmap.from_props(props) == %{fire: [:x, {:axis, :left_trigger, :pos}]}
    assert Padmap.from_props(%{"nonsense" => ["a"], "fire" => ["zz", "b"]}) == %{fire: [:b]}
    assert Padmap.from_props(nil) == %{}
  end
end
