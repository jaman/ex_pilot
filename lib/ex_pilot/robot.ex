defmodule ExPilot.Robot do
  @moduledoc """
  A robot's brain for `Cauldron2D.Robot`: a robot joins a world as `{:robot, n}` and
  flies by its view, deciding every few frames here, the way XPilot's default robots do.

  On its base it turns to face away from the wall the base sits on and thrusts off,
  burning straight until it is clear. In flight it fights the enemy it has locked on
  to: it steers for the clear heading nearest the point the enemy will be at when a
  shot arrives — the enemy's position led by its velocity less the robot's own — and
  fires whenever the enemy is within a shot's reach with a clear line and somewhere in
  the half circle ahead, however far off the nose; the gun's own rate paces the shots (it does not fire on
  its way to a fuel station). It flies at a speed
  for the distance: slow up close, cruising in between, its attack speed when far, and
  brakes when drifting into a wall. It raises its shield, and holds its fire, when a
  shot is about to reach it, most of the time, or an enemy is right beside it, always; where the
  map allows no shields it thrusts away from an enemy within three tiles, or one it is
  closing on within a second, instead. Moving away from where it wants to go, it thrusts
  toward it to brake. With no
  lock it looks for a way to one of the three nearest enemies on the arena's coarse map
  (`ExPilot.Robot.Route`) and flies for the furthest point of that way it can see; with
  none it holds its course. Below 500 fuel, with a station in sight that has fuel, it
  makes for the station and hovers there until the tank is full.

  Every robot has a skill, drawn by `Cauldron2D.Robot` between 0.3 and 1.0 unless
  given. It is XPilot's `attack` (skill × 99) and `defense` (100 − attack): how often
  the robot takes a lock (`lock/4` acquires one on a third of its decisions, and only
  while `tick mod 100 < attack`), how fast it flies when attacking, and how often it
  bothers to shield (`85 + defense / 7 − attack / 50` per cent). A robot whose ship is
  gone from the arena — a player took its base — leaves the world and stops.

  The coarse map is built once per map name and kept, so a map's name must be unique
  among the maps open at once, as the radar's must be.

      Cauldron2D.Robot.start_link(brain: ExPilot.Robot, world: world, number: 1, brain_opts: [arena: :dogfight])
      ExPilot.Robot.decide(view, grid, 0, skill: 0.6, stations: stations, route: route, tick: tick, lock: :alice)
  """

  @behaviour Cauldron2D.Robot

  alias Cauldron2D.Collision
  alias Cauldron2D.Grid.Coarse, as: Route
  alias ExPilot.{Arenas, Map, Ship}

  @lookahead 3.0
  @coast 0.6
  @turn_time 0.6
  @shield_reach 1.7
  @beside 1.4
  @evade 2.7
  @evade_time 0.8
  @align 8
  @front 16
  @launch_burn 12
  @refuel_below 500.0
  @station_sight 25.0
  @station_hover 1.5
  @sought 3
  @default_shot_speed 7.2
  @default_shot_range 36.0
  @default_unit_speed 12 / 35

  @impl Cauldron2D.Robot
  def init(_opts), do: %{grid: nil, stations: nil, route: nil, burn: 0, lock: nil}

  @impl Cauldron2D.Robot
  def gone?(%{me: nil}), do: true
  def gone?(_view), do: false

  @impl Cauldron2D.Robot
  def decide(view, memory, %{tick: tick, skill: skill}) do
    memory = %{
      memory
      | grid: memory.grid || grid_for(view),
        stations: memory.stations || stations_for(view),
        route: memory.route || route_for(view)
    }

    lock = lock(view, memory.grid, memory.lock, skill: skill, tick: tick)

    {held, burn} =
      decide(view, memory.grid, memory.burn,
        skill: skill,
        stations: memory.stations,
        route: memory.route,
        tick: tick,
        lock: lock
      )

    {%{held: held, aim: nil}, %{memory | burn: burn, lock: lock}}
  end

  defp grid_for(%{arena: name}) do
    case Arenas.map(name) do
      nil -> fn _ -> :open end
      arena -> Map.grid(arena)
    end
  end

  defp stations_for(%{arena: name}) do
    case Arenas.map(name) do
      nil -> []
      arena -> Map.fuel(arena)
    end
  end

  defp route_for(%{arena: name}) do
    case {Arenas.map(name), :persistent_term.get({Route, name}, nil)} do
      {nil, _} ->
        nil

      {_arena, route} when route != nil ->
        route

      {arena, nil} ->
        route = Route.new(Map.grid(arena), Map.size(arena), wrap?: Map.wrap?(arena))
        :persistent_term.put({Route, name}, route)
        route
    end
  end

  @doc """
  The enemy the robot fights, given the one it fought last decision.

  A lock is kept while that enemy is alive and in sight; otherwise the nearest enemy in
  sight is taken on every third decision while `tick mod 100` is under the robot's
  attack, and nil until then. `opts`: `:skill` (default 1.0) and `:tick` (default 0).
  """
  @spec lock(map(), Collision.grid(), term(), keyword()) :: term()
  def lock(%{me: nil}, _grid, _lock, _opts), do: nil

  def lock(%{me: me, ships: ships} = _view, grid, lock, opts) do
    tick = Keyword.get(opts, :tick, 0)
    attack = attack(Keyword.get(opts, :skill, 1.0))
    kept = Enum.find(in_sight(me, ships, grid), &(&1.id == lock))

    cond do
      kept != nil -> lock
      rem(tick, 3) == 0 and rem(tick, 100) < attack -> nearest_id(me, in_sight(me, ships, grid))
      true -> nil
    end
  end

  @doc "The actions to hold for `view`, given the arena's collision grid, with no launch burn running and the nearest enemy in sight as the lock."
  @spec decide(map(), Collision.grid()) :: MapSet.t(atom())
  def decide(view, grid), do: view |> decide(grid, 0) |> elem(0)

  @doc """
  The actions to hold for `view` and the launch burn left after them.

  `burn` is how many decisions of the burn remain: a landed robot turns to face up and
  thrusts off with a full burn, then holds thrust straight while the burn lasts and the
  way ahead is clear. With the burn spent it flies as the module documentation says.

  `opts`: `:lock`, the id of the enemy to fight (default the nearest in sight; `nil`
  when there is a lock to respect but none held); `:stations`, the arena's fuel tiles
  (default none); `:route`, the arena's `ExPilot.Robot.Route` (default none: an enemy
  out of sight is left alone); `:skill`, 0.3 to 1.0 (default 1.0); `:tick`, the
  decision count (default 0). The view's `rules` may carry `shot_speed` and
  `shot_range` in tiles and `unit_speed`, tiles a second per pixel a frame; XPilot's
  defaults at 12 frames a second stand in.
  """
  @spec decide(map(), Collision.grid(), non_neg_integer(), keyword()) ::
          {MapSet.t(atom()), non_neg_integer()}
  def decide(view, grid, burn, opts \\ [])
  def decide(%{me: nil}, _grid, _burn, _opts), do: {MapSet.new(), 0}
  def decide(%{me: %{alive?: false}}, _grid, _burn, _opts), do: {MapSet.new(), 0}

  def decide(%{me: %{landed?: true} = me}, _grid, _burn, _opts),
    do: {MapSet.new(launch(me)), @launch_burn}

  def decide(%{me: me} = view, grid, burn, opts) do
    skill = Keyword.get(opts, :skill, 1.0)

    mind = %{
      attack: attack(skill),
      defense: 100 - attack(skill),
      tick: Keyword.get(opts, :tick, 0),
      route: Keyword.get(opts, :route),
      lock:
        Keyword.get_lazy(opts, :lock, fn -> nearest_id(me, in_sight(me, view.ships, grid)) end),
      shot_speed: rule(view, :shot_speed, @default_shot_speed),
      shot_range: rule(view, :shot_range, @default_shot_range),
      unit_speed: rule(view, :unit_speed, @default_unit_speed)
    }

    cond do
      burn > 0 and clear?(me, me.heading, grid) ->
        {MapSet.new(if(speed(me) < normal_speed(mind), do: [:thrust], else: [])), burn - 1}

      station = thirsty_for(me, view, Keyword.get(opts, :stations, [])) ->
        {refuel(view, grid, station, mind), 0}

      true ->
        {fly(view, grid, mind), 0}
    end
  end

  defp attack(skill), do: skill |> Kernel.*(99) |> round() |> max(1) |> min(99)

  defp rule(view, name, default),
    do: view |> Elixir.Map.get(:rules, %{}) |> Elixir.Map.get(name, default)

  defp thirsty_for(%{fuel: fuel} = me, view, stations) when fuel < @refuel_below do
    levels = Elixir.Map.get(view, :stations, %{})

    stations
    |> Enum.filter(fn pos -> Elixir.Map.get(levels, pos, 1.0) > 0 end)
    |> Enum.map(fn {x, y} -> {x + 0.5, y + 0.5} end)
    |> Enum.filter(&Collision.circles_overlap?(me.pos, @station_sight, &1, 0.0))
    |> Enum.min_by(&distance_sq(me.pos, &1), fn -> nil end)
  end

  defp thirsty_for(_me, _view, _stations), do: nil

  defp refuel(%{me: me} = view, grid, station, mind) do
    there? = distance_sq(me.pos, station) < @station_hover * @station_hover
    braking? = blocked?(grid, me.pos, coasting(me, view)) or (there? and speed(me) > 0.5)
    wanted = if braking?, do: reverse_heading(me), else: heading_toward(me.pos, station)
    heading = clear_heading(me, wanted, grid)

    thrusting =
      thrust_if(
        aligned?(me, heading, grid) and
          (braking? or (not there? and speed(me) < normal_speed(mind)))
      )

    shielding = shield_if(guarding?(view, grid, mind) and me.fuel > 100 and shields?(view))
    MapSet.new(turn_toward(me.heading, heading) ++ thrusting ++ shielding)
  end

  defp fly(%{me: me} = view, grid, mind) do
    enemy = locked_enemy(view, grid, mind)
    braking? = blocked?(grid, me.pos, coasting(me, view))
    evading = evading(me, view, grid)
    wanted = wanted_heading(me, view, grid, mind, enemy, braking?, evading)
    heading = clear_heading(me, wanted, grid)

    shielding =
      shield_if((guarding?(view, grid, mind) or braking?) and me.fuel > 100 and shields?(view))

    urgent? = braking? or evading != nil or shielding != [] or overshooting?(me, wanted)

    thrusting =
      thrust_if(
        aligned?(me, heading, grid) and
          (urgent? or speed(me) < wanted_speed(me, enemy, mind, view))
      )

    MapSet.new(
      turn_toward(me.heading, heading) ++
        thrusting ++ shielding ++ firing(view, grid, mind, shielding)
    )
  end

  defp wanted_heading(me, _view, _grid, _mind, _enemy, true, _evading), do: reverse_heading(me)

  defp wanted_heading(me, _view, _grid, _mind, _enemy, false, %{pos: pos}),
    do: heading_toward(pos, me.pos)

  defp wanted_heading(me, _view, _grid, mind, enemy, false, nil) when enemy != nil,
    do: heading_toward(me.pos, lead(me, enemy, mind))

  defp wanted_heading(me, view, grid, mind, nil, false, nil),
    do: goal_heading(me, way_toward(me, enemies(me, view.ships), grid, mind.route))

  defp evading(me, %{ships: ships} = view, grid) do
    if shields?(view),
      do: nil,
      else:
        me
        |> in_sight(ships, grid)
        |> Enum.filter(
          &(Collision.circles_overlap?(me.pos, @evade, &1.pos, 0.0) or closing?(me, &1))
        )
        |> Enum.min_by(&distance_sq(me.pos, &1.pos), fn -> nil end)
  end

  defp closing?(me, other) do
    {dx, dy} = {elem(other.pos, 0) - elem(me.pos, 0), elem(other.pos, 1) - elem(me.pos, 1)}
    {vx, vy} = velocity(me)
    {ox, oy} = velocity(other)
    distance = max(:math.sqrt(dx * dx + dy * dy), 0.001)
    closing = ((vx - ox) * dx + (vy - oy) * dy) / distance
    closing > 0 and distance / closing < @evade_time
  end

  defp overshooting?(me, wanted) do
    speed(me) > 1.0 and
      abs(turn_delta(heading_toward({0.0, 0.0}, velocity(me)), wanted)) >= @front
  end

  defp locked_enemy(%{me: me, ships: ships}, grid, %{lock: lock}) do
    Enum.find(in_sight(me, ships, grid), &(&1.id == lock))
  end

  defp lead(me, enemy, mind) do
    {x, y} = enemy.pos
    {ex, ey} = velocity(enemy)
    {mx, my} = velocity(me)
    flight = :math.sqrt(distance_sq(me.pos, enemy.pos)) / mind.shot_speed
    {x + (ex - mx) * flight, y + (ey - my) * flight}
  end

  defp goal_heading(me, nil), do: me.heading
  defp goal_heading(me, goal), do: heading_toward(me.pos, goal)

  defp wanted_speed(_me, nil, mind, view), do: cruise_cap(view, 3 * normal_speed(mind))

  defp wanted_speed(me, enemy, mind, view) do
    distance = :math.sqrt(distance_sq(me.pos, enemy.pos))

    cond do
      distance < 3.0 -> normal_speed(mind)
      distance < 8.0 -> cruise_cap(view, 3 * normal_speed(mind))
      true -> cruise_cap(view, attack_speed(mind))
    end
  end

  defp cruise_cap(view, wanted) do
    case Elixir.Map.get(view, :rules) do
      %{shields?: false, crash_speed: crash_speed} -> min(wanted, crash_speed * 0.8)
      _shielded -> wanted
    end
  end

  defp normal_speed(%{unit_speed: unit}), do: 6.0 * unit
  defp attack_speed(%{attack: attack, unit_speed: unit}), do: (15.0 + attack / 25) * unit

  defp firing(_view, _grid, _mind, [:shield]), do: []

  defp firing(%{me: me} = view, grid, mind, _unshielded) do
    case locked_enemy(view, grid, mind) do
      nil ->
        []

      enemy ->
        fire_if(
          distance_sq(me.pos, enemy.pos) <= mind.shot_range * mind.shot_range and
            abs(turn_delta(me.heading, heading_toward(me.pos, enemy.pos))) <= @front
        )
    end
  end

  defp fire_if(true), do: [:fire]
  defp fire_if(false), do: []

  defp guarding?(%{me: me, shots: shots, ships: ships}, grid, mind) do
    shot_near? = Enum.any?(shots, &Collision.circles_overlap?(me.pos, @shield_reach, &1, 0.0))

    enemy_beside? =
      Enum.any?(
        in_sight(me, ships, grid),
        &Collision.circles_overlap?(me.pos, @beside, &1.pos, 0.0)
      )

    enemy_beside? or (shot_near? and cares?(mind))
  end

  defp cares?(%{attack: attack, defense: defense, tick: tick}),
    do: rem(tick * 61 + 17, 100) < 85 + defense / 7 - attack / 50

  defp aligned?(me, heading, grid),
    do: abs(turn_delta(me.heading, heading)) <= @align and clear?(me, me.heading, grid)

  defp thrust_if(true), do: [:thrust]
  defp thrust_if(false), do: []

  defp shield_if(true), do: [:shield]
  defp shield_if(false), do: []

  defp launch(me) do
    case turn_toward(me.heading, Elixir.Map.get(me, :launch_heading, div(Ship.headings(), 4))) do
      [] -> [:thrust]
      turning -> turning
    end
  end

  defp shields?(view), do: Elixir.Map.get(view, :rules, %{shields?: true}).shields?

  defp reverse_heading(me) do
    {vx, vy} = velocity(me)
    heading_toward({0.0, 0.0}, {-vx, -vy})
  end

  defp way_toward(_me, _enemies, _grid, nil), do: nil

  defp way_toward(me, enemies, grid, route) do
    enemies
    |> Enum.sort_by(&distance_sq(me.pos, &1.pos))
    |> Enum.take(@sought)
    |> Enum.find_value(fn enemy ->
      case Route.find(route, me.pos, enemy.pos) do
        {:ok, path} -> Route.waypoint(grid, me.pos, path)
        :none -> nil
      end
    end)
  end

  defp clear_heading(me, wanted, grid) do
    half = div(Ship.headings(), 2)

    Enum.find_value(0..half, wanted, fn step ->
      [wanted + step, wanted - step]
      |> Enum.map(&Integer.mod(&1, Ship.headings()))
      |> Enum.sort_by(&abs(turn_delta(me.heading, &1)))
      |> Enum.find(&clear?(me, &1, grid))
    end)
  end

  defp turn_toward(heading, wanted) do
    case turn_delta(heading, wanted) do
      delta when delta > 1 -> [:turn_left]
      delta when delta < -1 -> [:turn_right]
      _aligned -> []
    end
  end

  defp turn_delta(heading, wanted) do
    half = div(Ship.headings(), 2)
    Integer.mod(wanted - heading + half, Ship.headings()) - half
  end

  defp in_sight(me, ships, grid) do
    me
    |> enemies(ships)
    |> Enum.filter(&match?({:clear, _}, Collision.sweep(grid, me.pos, &1.pos, 0.0)))
  end

  defp nearest_id(me, enemies) do
    case Enum.min_by(enemies, &distance_sq(me.pos, &1.pos), fn -> nil end) do
      nil -> nil
      enemy -> enemy.id
    end
  end

  defp enemies(me, ships) do
    Enum.filter(ships, fn ship ->
      ship.id != me.id and ship.alive? and (me.team == nil or ship.team != me.team)
    end)
  end

  defp clear?(me, heading, grid),
    do: not blocked?(grid, me.pos, probe(me.pos, heading, reach(me)))

  defp probe({x, y}, heading, reach) do
    theta = 2 * :math.pi() * heading / Ship.headings()
    {x + :math.cos(theta) * reach, y - :math.sin(theta) * reach}
  end

  defp reach(me), do: max(@lookahead, speed(me) * @turn_time)

  defp speed(me) do
    {vx, vy} = velocity(me)
    :math.sqrt(vx * vx + vy * vy)
  end

  defp coasting(%{pos: {x, y}} = me, view) do
    {vx, vy} = velocity(me)
    coast = if shields?(view), do: @coast, else: @coast * 2
    {x + vx * coast, y + vy * coast}
  end

  defp velocity(ship), do: Elixir.Map.get(ship, :vel, {0.0, 0.0})

  defp blocked?(grid, from, to),
    do: match?({:blocked, _, _, _}, Collision.sweep(grid, from, to, 0.0))

  defp heading_toward({x1, y1}, {x2, y2}) do
    angle = :math.atan2(-(y2 - y1), x2 - x1)
    Integer.mod(round(angle / (2 * :math.pi()) * Ship.headings()), Ship.headings())
  end

  defp distance_sq({x1, y1}, {x2, y2}), do: (x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1)
end
