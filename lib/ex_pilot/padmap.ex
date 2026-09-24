defmodule ExPilot.Padmap do
  @moduledoc """
  The ship on a game controller: the default layout, a player's own bindings over it,
  and the words they are written in.

      ExPilot.Padmap.parse_controls("b right_bumper")     # => {:ok, [:b, :right_bumper]}
      ExPilot.Padmap.parse_controls("left_x- right_trigger+")
      # => {:ok, [{:axis, :left_x, :neg}, {:axis, :right_trigger, :pos}]}
      ExPilot.Padmap.merge(%{fire: [:x]})                 # the default with `fire` on X

  Controls are `Cauldron2D.Input.Pad`'s, in the Xbox layout whatever the hardware: a
  button by its `Gamepad.Wire` name (`a`, `b`, `x`, `y`, `left_bumper`, `right_bumper`,
  `back`, `start`, `guide`, `left_stick`, `right_stick`, `dpad_up`, `dpad_down`,
  `dpad_left`, `dpad_right`), an axis (`left_x`, `left_y`, `right_x`, `right_y`,
  `left_trigger`, `right_trigger`) with `-` or `+` for its direction, up and left
  being `-`, or a whole stick as a direction, `left_stick_xy` or `right_stick_xy`,
  which only the `aim` row takes; `left_stick_xy+thrust` is that stick also holding
  thrust once pushed past `0.6` of its travel, harder the further (`with_push/2` sets
  or clears it, `pushes?/1` tells). Written out, the controls of an action are those
  words with spaces between.

  The default: the left stick aims — the ship turns to the way it is pushed — the
  d-pad turns left and right, the right trigger thrusts as far as it is pulled (d-pad
  up in full), `B` or the right bumper fires, `A` or the left trigger shields, `X`
  fires a missile, `Y` drops a mine, the left bumper fires the laser, the sticks
  pressed pick the next missile and cloak, d-pad down is the emergency shield and
  `Back` the emergency thrust; `A` or `Start` picks the next ship when watching.
  """

  alias Cauldron2D.Input.Pad
  alias ExPilot.Gear
  alias Gamepad.Wire

  @type action :: atom()
  @type overrides :: %{action() => [Pad.control()]}

  @push [beyond: 0.6, least: 0.3, gain: 1.4]

  @default %{
    aim: [{:stick, :left}],
    turn_left: [:dpad_left],
    turn_right: [:dpad_right],
    thrust: [{:axis, :right_trigger, :pos}, :dpad_up],
    fire: [:b, :right_bumper],
    shield: [:a, {:axis, :left_trigger, :pos}],
    next_watch: [:a, :start],
    fire_missile: [:x],
    drop_mine: [:y],
    fire_laser: [:left_bumper],
    next_missile: [:right_stick],
    cloak: [:left_stick],
    emergency_shield: [:dpad_down],
    emergency_thrust: [:back]
  }

  @doc "The default layout."
  @spec default() :: Pad.padmap()
  def default, do: @default

  @flying [:aim, :turn_left, :turn_right, :thrust, :fire, :shield, :next_watch]

  @doc "Every row of the layout: `aim` (a stick), the flying actions, then the gear's."
  @spec actions() :: [action()]
  def actions, do: @flying ++ Gear.actions()

  @doc "The rows in their two groups, `{title, actions}`: flying, then the gear."
  @spec groups() :: [{String.t(), [action()]}]
  def groups, do: [{"Flying", @flying}, {"Gear", Gear.actions()}]

  @doc "The default with `overrides` in place of its bindings, action by action; an action not among `actions/0` is ignored."
  @spec merge(overrides()) :: Pad.padmap()
  def merge(overrides) do
    Map.merge(@default, Map.take(overrides, actions()))
  end

  @doc "Of `bindings`, those that differ from the default's — what is worth keeping for a player."
  @spec overrides(overrides()) :: overrides()
  def overrides(bindings) do
    for {action, controls} <- bindings,
        controls != Map.get(@default, action),
        into: %{},
        do: {action, controls}
  end

  @doc "`controls` with every stick pushing `action` past its ring (`nil` clears the push); other controls are left alone."
  @spec with_push([Pad.control()], action() | nil) :: [Pad.control()]
  def with_push(controls, action) do
    Enum.map(controls, fn
      {:stick, side, _push} -> stick(side, action)
      {:stick, side} -> stick(side, action)
      other -> other
    end)
  end

  @doc "Whether any stick among `controls` pushes an action."
  @spec pushes?([Pad.control()]) :: boolean()
  def pushes?(controls), do: Enum.any?(controls, &match?({:stick, _, _}, &1))

  defp stick(side, nil), do: {:stick, side}
  defp stick(side, action), do: {:stick, side, push: [action: action] ++ @push}

  @doc "The controls a text names, `{:error, {:unknown, word}}` at the first word that is none."
  @spec parse_controls(String.t()) :: {:ok, [Pad.control()]} | {:error, {:unknown, String.t()}}
  def parse_controls(text) do
    text
    |> String.split(~r/[\s,]+/, trim: true)
    |> Enum.reduce_while({:ok, []}, fn word, {:ok, controls} ->
      case control(word) do
        nil -> {:halt, {:error, {:unknown, word}}}
        control -> {:cont, {:ok, controls ++ [control]}}
      end
    end)
  end

  @doc "The controls written out, one word each."
  @spec format_controls([Pad.control()]) :: String.t()
  def format_controls(controls), do: Enum.map_join(controls, " ", &word/1)

  @doc "A player's bindings as the account keeps them: action names to lists of control words."
  @spec to_props(overrides()) :: %{String.t() => [String.t()]}
  def to_props(overrides) do
    Map.new(overrides, fn {action, controls} ->
      {Atom.to_string(action), Enum.map(controls, &word/1)}
    end)
  end

  @doc "A player's bindings back from the account; a name that is no action, or a word that is no control, is dropped."
  @spec from_props(term()) :: overrides()
  def from_props(props) when is_map(props) do
    known = Map.new(actions(), &{Atom.to_string(&1), &1})

    for {name, words} <- props,
        is_list(words),
        action = Map.get(known, name),
        action != nil,
        into: %{},
        do: {action, words |> Enum.map(&control/1) |> Enum.reject(&is_nil/1)}
  end

  def from_props(_none), do: %{}

  defp control("left_stick_xy"), do: {:stick, :left}
  defp control("right_stick_xy"), do: {:stick, :right}
  defp control("left_stick_xy+" <> action), do: pushing_stick(:left, action)
  defp control("right_stick_xy+" <> action), do: pushing_stick(:right, action)

  defp control(word) when is_binary(word) do
    cond do
      button = named(word, Wire.buttons()) -> button
      axis = axis_word(word) -> axis
      true -> nil
    end
  end

  defp control(_other), do: nil

  defp pushing_stick(side, action) do
    case named(action, actions()) do
      nil -> nil
      pushed -> stick(side, pushed)
    end
  end

  defp axis_word(word) do
    with {name, direction} <- split_direction(word),
         axis when axis != nil <- named(name, Wire.axes()) do
      {:axis, axis, direction}
    else
      _ -> nil
    end
  end

  defp split_direction(word) do
    case String.split_at(word, -1) do
      {name, "-"} -> {name, :neg}
      {name, "+"} -> {name, :pos}
      _ -> nil
    end
  end

  defp named(word, names), do: Enum.find(names, &(Atom.to_string(&1) == word))

  defp word({:stick, side}), do: Atom.to_string(side) <> "_stick_xy"

  defp word({:stick, side, push: push}),
    do: word({:stick, side}) <> "+" <> Atom.to_string(Keyword.fetch!(push, :action))

  defp word({:axis, axis, :neg}), do: Atom.to_string(axis) <> "-"

  defp word({:axis, axis, :pos}), do: Atom.to_string(axis) <> "+"
  defp word(button), do: Atom.to_string(button)
end
