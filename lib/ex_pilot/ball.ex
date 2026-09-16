defmodule ExPilot.Ball do
  @moduledoc """
  Treasures and the balls in them, for capture the flag.

  Every `*` on the map is a treasure belonging to the team of the nearest base, and a
  ball starts in each. A ball is a body of its own: gravity pulls it, it drifts with its
  velocity and bounces off walls (or goes home from them, with `ballswallbounce` off).
  A ship flying within reach of a loose ball picks it up; the ball then hangs on a string
  of `string/0` tiles, and when the string is taut it pulls the ball after the ship and
  the ship back toward the ball, the ship being the lighter of the two. Stretched past
  `break/0` times its length the string snaps and the ball is loose again; dropping it
  (`:connector`) or dying lets it go too. A team's own ball sitting at home is left alone
  by that team. Flying into one of your own treasures with another team's ball scores it,
  and the ball goes home. Without teams there is nothing to score, so a map without
  `teamplay` has no balls.

      ExPilot.Ball.new(arena)
      ExPilot.Ball.step(balls, ships, dt, %{grid: grid, fields: fields, size: size, wrap?: false, bounce?: true})
  """

  alias Cauldron2D.{Body, Collision}
  alias ExPilot.Map, as: Arena

  @type ball :: %{
          id: pos_integer(),
          home: {integer(), integer()},
          team: integer() | nil,
          pos: {float(), float()},
          vel: {float(), float()},
          carrier: term() | nil
        }
  @type env :: %{grid: Collision.grid(), fields: [Body.field()], size: {number(), number()}, wrap?: boolean(), bounce?: boolean()}

  @reach 0.9
  @string 2.5
  @break 1.3
  @spring 20.0
  @ship_pull 2.5
  @radius 0.3
  @loose_drag 0.5
  @carried_drag 0.3
  @restitution 0.6
  @score 5

  @doc "The length of the string, in tiles."
  @spec string() :: float()
  def string, do: @string

  @doc "How far the string stretches, as a factor of its length, before it snaps."
  @spec break() :: float()
  def break, do: @break

  @doc "A ball in every treasure of `arena`, each with its treasure's team."
  @spec new(Arena.t()) :: [ball()]
  def new(%Arena{} = arena) do
    bases = Arena.bases(arena)

    arena
    |> Arena.treasures()
    |> Enum.with_index(1)
    |> Enum.map(fn {{x, y} = home, id} ->
      %{id: id, home: home, team: team_near(bases, home), pos: {x + 0.5, y + 0.5}, vel: {0.0, 0.0}, carrier: nil}
    end)
  end

  defp team_near([], _pos), do: nil

  defp team_near(bases, {x, y}) do
    bases
    |> Enum.min_by(fn %{pos: {bx, by}} -> (bx - x) * (bx - x) + (by - y) * (by - y) end)
    |> Map.get(:team)
  end

  @doc """
  Move the balls for one tick: a loose ball is picked up by a ship in reach that carries
  none or drifts on; a carried ball hangs on its string, pulling its carrier when taut,
  and snaps free when overstretched. Balls fall in `fields`, bounce off `grid` or go home
  when `bounce?` is off, and wrap in `size` when `wrap?`.

  Returns `{balls, ships}`, the ships as pulled by their balls and freed of a snapped
  string.
  """
  @spec step([ball()], %{term() => map()}, float(), env()) :: {[ball()], %{term() => map()}}
  def step(balls, ships, dt, env) do
    Enum.map_reduce(balls, ships, fn ball, ships -> advance(ball, ships, dt, env) end)
  end

  defp advance(%{carrier: nil} = ball, ships, dt, env) do
    carrying = ships |> Map.values() |> Enum.map(& &1.ball) |> Enum.reject(&is_nil/1)

    taker =
      ships
      |> Map.values()
      |> Enum.find(fn ship -> ship.alive? and ship.ball == nil and ball.id not in carrying and not (at_home?(ball) and ship.team == ball.team) and within?(ship.body.pos, ball.pos, @reach) end)

    case taker do
      nil -> {ball |> accelerate(env.fields, @loose_drag, dt) |> travel(dt, env), ships}
      ship -> {%{ball | carrier: ship.id}, ships}
    end
  end

  defp advance(%{carrier: carrier} = ball, ships, dt, env) do
    case Map.get(ships, carrier) do
      %{alive?: true, ball: id} = ship when id == ball.id -> hang(ball, ship, ships, dt, env)
      _dropped_or_dead -> {%{ball | carrier: nil}, ships}
    end
  end

  defp hang(ball, ship, ships, dt, env) do
    {sx, sy} = ship.body.pos
    {bx, by} = ball.pos
    {dx, dy} = {bx - sx, by - sy}
    distance = :math.sqrt(dx * dx + dy * dy)

    cond do
      distance > @string * @break ->
        {%{ball | carrier: nil}, Map.put(ships, ship.id, %{ship | ball: nil})}

      distance > @string ->
        stretch = distance - @string
        {ux, uy} = {dx / distance, dy / distance}
        pulled = %{ball | vel: add(ball.vel, {-ux * @spring * stretch * dt, -uy * @spring * stretch * dt})}
        {vx, vy} = ship.body.vel
        tugged = %{ship | body: %{ship.body | vel: {vx + ux * @spring * @ship_pull * stretch * dt, vy + uy * @spring * @ship_pull * stretch * dt}}}
        {pulled |> accelerate(env.fields, @carried_drag, dt) |> travel(dt, env), Map.put(ships, ship.id, tugged)}

      true ->
        {ball |> accelerate(env.fields, @carried_drag, dt) |> travel(dt, env), ships}
    end
  end

  defp accelerate(ball, fields, drag, dt) do
    body = Body.new(pos: ball.pos, vel: ball.vel, radius: @radius) |> Body.gravitate(fields, dt) |> Body.drag(drag, dt)
    %{ball | vel: body.vel}
  end

  defp travel(ball, dt, env) do
    {x, y} = ball.pos
    {vx, vy} = ball.vel
    to = {x + vx * dt, y + vy * dt}

    case Collision.sweep(env.grid, ball.pos, to, @radius) do
      {:clear, at} -> %{ball | pos: wrapped(at, env)}
      {:blocked, at, normal, _cell} when env.bounce? -> %{ball | pos: wrapped(at, env), vel: Collision.bounce(ball.vel, normal, @restitution)}
      {:blocked, _at, _normal, _cell} -> home(ball)
    end
  end

  defp wrapped(pos, %{wrap?: true, size: size}), do: Body.wrap(%Body{pos: pos}, size).pos
  defp wrapped(pos, _env), do: pos

  defp home(%{home: {x, y}} = ball), do: %{ball | pos: {x + 0.5, y + 0.5}, vel: {0.0, 0.0}, carrier: nil}

  defp add({ax, ay}, {bx, by}), do: {ax + bx, ay + by}

  defp at_home?(%{home: {x, y}, pos: pos}), do: pos == {x + 0.5, y + 0.5}

  @doc """
  A carrier flying into a treasure of its own team with another team's ball scores it:
  the ball goes home and the carrier's team gains points.

  Returns `{balls, scored}`, each score `{carrier_id, team, points, team_scored_against}`.
  """
  @spec deliver([ball()], %{term() => map()}, Arena.t()) :: {[ball()], [{term(), integer(), pos_integer(), integer() | nil}]}
  def deliver(balls, ships, arena) do
    treasures = new(arena)

    Enum.map_reduce(balls, [], fn ball, scored ->
      with carrier when carrier != nil <- ball.carrier,
           %{team: team, body: %{pos: at}} when team != nil and team != ball.team <- Map.get(ships, carrier),
           true <- Enum.any?(treasures, fn t -> t.team == team and within?(at, t.pos, @reach) end) do
        {home(ball), [{carrier, team, @score, ball.team} | scored]}
      else
        _ -> {ball, scored}
      end
    end)
  end

  @doc "The ball a ship is carrying, or `nil`."
  @spec carried_by([ball()], term()) :: ball() | nil
  def carried_by(balls, ship_id), do: Enum.find(balls, &(&1.carrier == ship_id))

  defp within?({x1, y1}, {x2, y2}, reach), do: (x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1) < reach * reach
end
