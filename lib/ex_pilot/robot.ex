defmodule ExPilot.Robot do
  @moduledoc """
  A robot's brain for `Cauldron2D.Robot`: a robot joins a world as `{:robot, n}` and
  flies by its view, deciding every few frames here.

  On its base it turns to face away from the wall the base sits on and thrusts off,
  burning straight until it is clear. In flight it picks the nearest live enemy it has
  a clear line to and steers for the clear heading nearest the enemy's — clear as far as
  it would travel in the time a turn takes — thrusting while far and below cruising
  speed (slower where the map allows no shields, under the speed a wall crash takes), and
  firing while lined up within reach; when drifting into a wall it turns to
  face away and thrusts to brake, and it raises its shield when a shot is close. With
  no enemy in sight it looks for a way to one of the three nearest on the arena's coarse
  map (`ExPilot.Robot.Route`) and flies for the furthest point of that way it can see,
  holding its fire; with none it holds its course the same way. Low on fuel, with a fuel station in sight, it
  makes for the station and hovers there until the tank is full. A robot whose ship is
  gone from the arena — a player took its base — leaves the world and stops.

  The coarse map is built once per map name and kept, so a map's name must be unique
  among the maps open at once, as the radar's must be.

  Every robot has a skill, drawn by `Cauldron2D.Robot` between 0.3 and 1.0 unless
  given: it sets how tightly it aims, how far it fires from, how often it holds its
  fire, how fast it reacts (the runner's cadence) and how late it raises its shield.

      Cauldron2D.Robot.start_link(brain: ExPilot.Robot, world: world, number: 1, brain_opts: [arena: :dogfight])
      ExPilot.Robot.decide(view, grid, 0, skill: 0.6, stations: stations, route: route, tick: tick)
  """

  @behaviour Cauldron2D.Robot

  alias Cauldron2D.Collision
  alias Cauldron2D.Grid.Coarse, as: Route
  alias ExPilot.{Arenas, Map, Ship}

  @reach 18.0
  @fire_cone 2
  @close 7.0
  @lookahead 3.0
  @coast 0.6
  @cruise 6.0
  @turn_time 0.6
  @shield_reach 2.5
  @align 8
  @launch_burn 12
  @refuel_below 350.0
  @station_sight 25.0
  @station_hover 1.5
  @sought 3

  @impl Cauldron2D.Robot
  def init(_opts), do: %{grid: nil, stations: nil, route: nil, burn: 0}

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

    {held, burn} =
      decide(view, memory.grid, memory.burn,
        skill: skill,
        stations: memory.stations,
        route: memory.route,
        tick: tick
      )

    {%{held: held, aim: nil}, %{memory | burn: burn}}
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

  @doc "The actions to hold for `view`, given the arena's collision grid, with no launch burn running."
  @spec decide(map(), Collision.grid()) :: MapSet.t(atom())
  def decide(view, grid), do: view |> decide(grid, 0) |> elem(0)

  @doc """
  The actions to hold for `view` and the launch burn left after them.

  `burn` is how many decisions of the burn remain: a landed robot turns to face up and
  thrusts off with a full burn, then holds thrust straight while the burn lasts and the
  way ahead is clear. With the burn spent it flies: toward the nearest clear heading to
  the nearest enemy in sight, braking when drifting into a wall, firing when lined up,
  shielding when a shot is close; with no enemy in sight, toward the way `:route` finds
  to the nearest one. With the tank below 350 and a station of `:stations` within 25
  tiles the robot flies there instead and hovers within reach of it.

  `opts`: `:stations`, the arena's fuel tiles (default none); `:route`, the arena's
  `ExPilot.Robot.Route` (default none: an enemy out of sight is left alone); `:skill`,
  0.3 to 1.0 (default 1.0); `:tick`, the frame count, which a robot with less than full
  skill uses to hold its fire part of the time (default 0).
  """
  @spec decide(map(), Collision.grid(), non_neg_integer(), keyword()) ::
          {MapSet.t(atom()), non_neg_integer()}
  def decide(view, grid, burn, opts \\ [])
  def decide(%{me: nil}, _grid, _burn, _opts), do: {MapSet.new(), 0}
  def decide(%{me: %{alive?: false}}, _grid, _burn, _opts), do: {MapSet.new(), 0}

  def decide(%{me: %{landed?: true} = me}, _grid, _burn, _opts),
    do: {MapSet.new(launch(me)), @launch_burn}

  def decide(%{me: me} = view, grid, burn, opts) do
    mind = %{
      skill: Keyword.get(opts, :skill, 1.0),
      tick: Keyword.get(opts, :tick, 0),
      route: Keyword.get(opts, :route)
    }

    cond do
      burn > 0 and clear?(me, me.heading, grid) ->
        {MapSet.new(if(slow?(me, view), do: [:thrust], else: [])), burn - 1}

      station = thirsty_for(me, Keyword.get(opts, :stations, [])) ->
        {refuel(view, grid, station, mind), 0}

      true ->
        {fly(view, grid, mind), 0}
    end
  end

  defp thirsty_for(%{fuel: fuel} = me, stations) when fuel < @refuel_below do
    stations
    |> Enum.map(fn {x, y} -> {x + 0.5, y + 0.5} end)
    |> Enum.filter(&Collision.circles_overlap?(me.pos, @station_sight, &1, 0.0))
    |> Enum.min_by(&distance_sq(me.pos, &1), fn -> nil end)
  end

  defp thirsty_for(_me, _stations), do: nil

  defp refuel(%{me: me, ships: ships} = view, grid, station, mind) do
    enemy = nearest_in_sight(me, ships, grid)
    there? = distance_sq(me.pos, station) < @station_hover * @station_hover
    braking? = blocked?(grid, me.pos, coasting(me, view)) or (there? and speed(me) > 0.5)
    wanted = if braking?, do: wanted(me, nil, true), else: heading_toward(me.pos, station)
    heading = clear_heading(me, wanted, grid)

    thrusting =
      thrust_if(aligned?(me, heading, grid) and (braking? or (not there? and slow?(me, view))))

    shielding = shield_if(threatened?(view, mind) and me.fuel > 100 and shields?(view))

    MapSet.new(
      turn_toward(me.heading, heading) ++ thrusting ++ firing(me, enemy, mind) ++ shielding
    )
  end

  defp aligned?(me, heading, grid),
    do: abs(turn_delta(me.heading, heading)) <= @align and clear?(me, me.heading, grid)

  defp threatened?(%{me: me, shots: shots}, mind),
    do: Enum.any?(shots, &Collision.circles_overlap?(me.pos, @shield_reach * mind.skill, &1, 0.0))

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

  defp fly(%{me: me, ships: ships} = view, grid, mind) do
    {enemy, goal} = target(me, ships, grid, mind.route)
    braking? = blocked?(grid, me.pos, coasting(me, view))
    heading = clear_heading(me, wanted(me, goal, braking?), grid)
    far? = enemy == nil or distance_sq(me.pos, enemy.pos) > @close * @close

    thrusting =
      thrust_if(aligned?(me, heading, grid) and (braking? or (far? and slow?(me, view))))

    shielding =
      shield_if((threatened?(view, mind) or braking?) and me.fuel > 100 and shields?(view))

    MapSet.new(
      turn_toward(me.heading, heading) ++ thrusting ++ firing(me, enemy, mind) ++ shielding
    )
  end

  defp shields?(view), do: Elixir.Map.get(view, :rules, %{shields?: true}).shields?

  defp cruise(view) do
    case Elixir.Map.get(view, :rules) do
      %{shields?: false, crash_speed: crash_speed} -> min(@cruise, crash_speed * 0.8)
      _shielded -> @cruise
    end
  end

  defp wanted(me, _enemy, true) do
    {vx, vy} = velocity(me)
    heading_toward({0.0, 0.0}, {-vx, -vy})
  end

  defp wanted(me, nil, false), do: me.heading
  defp wanted(me, goal, false), do: heading_toward(me.pos, goal)

  defp target(me, ships, grid, route) do
    case nearest_in_sight(me, ships, grid) do
      nil -> {nil, way_toward(me, enemies(me, ships), grid, route)}
      enemy -> {enemy, enemy.pos}
    end
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

  defp firing(_me, nil, _mind), do: []

  defp firing(me, enemy, %{skill: skill, tick: tick}) do
    reach = @reach * (0.45 + 0.55 * skill)
    cone = @fire_cone + round((1.0 - skill) * 5)
    hesitating? = rem(tick, 4) < round((1.0 - skill) * 4)
    in_reach? = Collision.circles_overlap?(me.pos, reach, enemy.pos, 0.0)
    lined_up? = abs(turn_delta(me.heading, heading_toward(me.pos, enemy.pos))) <= cone
    if in_reach? and lined_up? and not hesitating?, do: [:fire], else: []
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

  defp nearest_in_sight(me, ships, grid) do
    me
    |> enemies(ships)
    |> Enum.filter(&match?({:clear, _}, Collision.sweep(grid, me.pos, &1.pos, 0.0)))
    |> Enum.min_by(&distance_sq(me.pos, &1.pos), fn -> nil end)
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

  defp slow?(me, view), do: speed(me) < cruise(view)

  defp speed(me) do
    {vx, vy} = velocity(me)
    :math.sqrt(vx * vx + vy * vy)
  end

  defp coasting(%{pos: {x, y}} = me, view) do
    {vx, vy} = velocity(me)
    coast = if shields?(view), do: @coast, else: @coast * 2
    {x + vx * coast, y + vy * coast}
  end

  defp velocity(me), do: Elixir.Map.get(me, :vel, {0.0, 0.0})

  defp blocked?(grid, from, to),
    do: match?({:blocked, _, _, _}, Collision.sweep(grid, from, to, 0.0))

  defp heading_toward({x1, y1}, {x2, y2}) do
    angle = :math.atan2(-(y2 - y1), x2 - x1)
    Integer.mod(round(angle / (2 * :math.pi()) * Ship.headings()), Ship.headings())
  end

  defp distance_sq({x1, y1}, {x2, y2}), do: (x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1)
end
