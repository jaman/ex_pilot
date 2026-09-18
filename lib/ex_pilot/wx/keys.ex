defmodule ExPilot.Wx.Keys do
  @moduledoc """
  The desktop's keys: wx key codes and mouse buttons to ExPilot's actions, the same
  bindings the browser has.

      ExPilot.Wx.Keys.keymap()
  """

  alias Cauldron2D.Wx.Const

  @doc "Every binding, as `Cauldron2D.Wx.Input.new/2` takes them."
  @spec keymap() :: %{(integer() | {:mouse, atom()}) => atom()}
  def keymap do
    %{
      ?A => :turn_left,
      Const.key_left() => :turn_left,
      ?D => :turn_right,
      Const.key_right() => :turn_right,
      ?S => :thrust,
      Const.key_up() => :thrust,
      Const.key_space() => :fire,
      ?F => :fire,
      ?W => :shield,
      Const.key_shift() => :shield,
      Const.key_return() => :next_watch,
      ?1 => :drop_mine,
      ?2 => :fire_missile,
      ?3 => :fire_laser,
      ?N => :next_missile,
      ?C => :cloak,
      ?E => :ecm,
      ?R => :transporter,
      ?G => :tractor,
      ?B => :pressor,
      ?X => :deflector,
      ?P => :phasing,
      ?U => :hyperjump,
      ?[ => :emergency_shield,
      ?] => :emergency_thrust,
      ?O => :autopilot,
      ?V => :connector,
      {:mouse, :left} => :fire,
      {:mouse, :right} => :thrust
    }
  end

  @doc "The actions the pointer also drives."
  @spec steering() :: [atom()]
  def steering, do: [:turn_left, :turn_right]
end
