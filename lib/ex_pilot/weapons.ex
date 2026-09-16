defmodule ExPilot.Weapons do
  @moduledoc """
  What a ship can throw besides its cannon shot: torpedoes, smart and heat missiles,
  mines, and the laser.

  A missile is a shot with a `:kind` — `:torpedo` flies straight, `:smart` turns toward
  the nearest enemy, `:heat` toward the nearest ship that is thrusting — and a mine is a
  shot that never moves and explodes on any ship but its owner's, once armed. `steer/4` turns a
  missile each tick; `laser/3` finds the first ship along a ship's heading.

      ExPilot.Weapons.missile(ship, :smart, next_id, settings)
      ExPilot.Weapons.mine(ship, next_id)
      ExPilot.Weapons.laser(ship, ships, grid)
  """

  alias Cauldron2D.{Body, Collision}
  alias ExPilot.Ship

  @missile_speed 0.75
  @missile_life 4.0
  @missile_radius 0.2
  @missile_turn 3.0
  @mine_life 60.0
  @mine_radius 0.4
  @mine_arm 1.0
  @laser_range 12.0
  @laser_step 0.25

  @type kind :: :shot | :torpedo | :smart | :heat | :mine

  @doc "A missile of `kind` leaving `ship` along its heading."
  @spec missile(Ship.t(), :torpedo | :smart | :heat, pos_integer(), map()) :: map()
  def missile(%Ship{} = ship, kind, id, settings) do
    {dx, dy} = Body.direction(ship.body)
    {x, y} = ship.body.pos
    {vx, vy} = ship.body.vel
    speed = settings.shot_speed * @missile_speed

    %{
      id: id,
      owner: ship.id,
      kind: kind,
      body: Body.new(pos: {x + dx * 0.8, y + dy * 0.8}, vel: {vx + dx * speed, vy + dy * speed}, radius: @missile_radius),
      life: @missile_life
    }
  end

  @doc "A mine dropped where `ship` is, armed after `fuse` seconds (a second by default)."
  @spec mine(Ship.t(), pos_integer(), float()) :: map()
  def mine(%Ship{} = ship, id, fuse \\ @mine_arm) do
    %{id: id, owner: ship.id, kind: :mine, body: Body.new(pos: ship.body.pos, vel: {0.0, 0.0}, radius: @mine_radius), life: @mine_life, armed_in: fuse}
  end

  @doc "Whether `shot` is a mine that has had its second to arm."
  @spec armed?(map()) :: boolean()
  def armed?(%{kind: :mine, armed_in: left}), do: left <= 0
  def armed?(_shot), do: true

  @doc "Turn a homing missile toward its target for `dt` seconds; other shots are unchanged."
  @spec steer(map(), [Ship.t()], float(), float()) :: map()
  def steer(%{kind: kind} = missile, ships, dt, _speed) when kind in [:smart, :heat] do
    case target(missile, ships, kind) do
      nil -> missile
      %{body: %{pos: {tx, ty}}} -> turn_toward(missile, {tx, ty}, dt)
    end
  end

  def steer(shot, _ships, _dt, _speed), do: shot

  defp target(%{owner: owner, body: %{pos: pos}}, ships, kind) do
    ships
    |> Enum.filter(fn ship -> ship.id != owner and ship.alive? and not ship.cloaked? end)
    |> Enum.filter(fn ship -> kind == :smart or ship.thrusting? end)
    |> Enum.min_by(fn ship -> Collision.distance_sq(pos, ship.body.pos) end, fn -> nil end)
  end

  defp turn_toward(%{body: body} = missile, {tx, ty}, dt) do
    {x, y} = body.pos
    {vx, vy} = body.vel
    speed = :math.sqrt(vx * vx + vy * vy)
    wanted = :math.atan2(ty - y, tx - x)
    current = :math.atan2(vy, vx)
    delta = :math.atan2(:math.sin(wanted - current), :math.cos(wanted - current))
    step = max(-@missile_turn * dt, min(@missile_turn * dt, delta))
    angle = current + step
    %{missile | body: %{body | vel: {:math.cos(angle) * speed, :math.sin(angle) * speed}}}
  end

  @doc """
  The beam `ship` fires along its heading: `{from, to, hit}` where `hit` is the first
  living ship on the line within range, or `nil`, and `to` is where the beam stops — at
  that ship, at a wall, or at full range.
  """
  @spec laser(Ship.t(), [Ship.t()], Collision.grid()) :: {Body.point(), Body.point(), Ship.t() | nil}
  def laser(%Ship{} = ship, ships, grid) do
    {dx, dy} = Body.direction(ship.body)
    {x, y} = ship.body.pos
    from = {x + dx * 0.6, y + dy * 0.6}
    others = Enum.filter(ships, fn other -> other.id != ship.id and other.alive? end)
    trace(from, {dx, dy}, @laser_step, others, grid, from)
  end

  defp trace({fx, fy} = from, {dx, dy} = dir, travelled, ships, grid, at) when travelled <= @laser_range do
    next = {fx + dx * travelled, fy + dy * travelled}

    cond do
      Collision.inside?(grid, next) ->
        {from, at, nil}

      hit = Enum.find(ships, fn ship -> Collision.circles_overlap?(next, 0.05, ship.body.pos, Ship.radius()) end) ->
        {from, next, hit}

      true ->
        trace(from, dir, travelled + @laser_step, ships, grid, next)
    end
  end

  defp trace(from, _dir, _travelled, _ships, _grid, at), do: {from, at, nil}
end
