defmodule ExPilot.ClientTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Input.Pad
  alias ExPilot.Client

  test "the padmap binds the ship to a controller in the Xbox layout, every control to an action of the game's" do
    padmap = Client.padmap(%{username: "nobody"})
    actions = Client.actions()

    for {action, controls} <- padmap, action != :aim do
      assert action in actions
      assert controls != []
    end

    assert padmap.aim == [{:stick, :left}]
    assert :dpad_left in padmap.turn_left
    assert :dpad_right in padmap.turn_right
    assert {:axis, :right_trigger, :pos} in padmap.thrust
    assert :b in padmap.fire
    assert :a in padmap.shield
    assert :a in padmap.next_watch

    pad = Pad.new(padmap)
    pad = Pad.handle(pad, %{type: :axis, device: 0, axis: :right_trigger, value: 0.6})
    assert MapSet.member?(Pad.held(pad), :thrust)
    assert_in_delta Pad.strength(pad).thrust, 0.6, 0.001

    pad = Pad.handle(pad, %{type: :axis, device: 0, axis: :left_x, value: -1.0})
    refute MapSet.member?(Pad.held(pad), :turn_left)
    assert {dx, +0.0} = Pad.aim(pad)
    assert_in_delta dx, -1.0, 0.001
  end

  test "the client's own controller actions leave the bumpers and Start to the game" do
    assert %{turn_left: nil, turn_right: nil, projection: nil} = Client.client_pad()
  end

  test "W thrusts and S shields on every client, shift shielding beside S" do
    wasd = Keyword.fetch!(Client.keymaps(), :wasd)
    assert wasd.thrust == [:w, {:mouse, :right}]
    assert wasd.shield == [:left_shift, :s]

    browser = ExPilot.Web.ArenaLive.keymap()
    assert browser["KeyW"] == "thrust"
    assert browser["KeyS"] == "shield"
    assert browser["ShiftLeft"] == "shield"
    assert browser["ArrowUp"] == "thrust"

    desktop = ExPilot.Wx.Keys.keymap()
    assert desktop[?W] == :thrust
    assert desktop[?S] == :shield
  end
end
