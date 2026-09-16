defmodule ExPilot.Robot do
  @moduledoc """
  A robot player: a process that joins a world as `{:robot, n}` and flies by its view.

  On its base it turns to face away from the wall the base sits on and thrusts off,
  burning straight until it is clear. In flight it picks the nearest live enemy anywhere
  in the arena and steers for the clear heading nearest the enemy's — clear as far as
  it would travel in the time a turn takes — thrusting while far and below cruising
  speed (slower where the map allows no shields, under the speed a wall crash takes), and
  firing while lined up within reach; when drifting into a wall it turns to
  face away and thrusts to brake, and it raises its shield when a shot is close. With no
  enemy it holds its course the same way. Low on fuel, with a fuel station in sight, it
  makes for the station and hovers there until the tank is full. A robot whose ship is
  gone from the arena — a player took its base — leaves the world and stops.

  Every robot has a skill, drawn at random between 0.3 and 1.0 when it is seated unless
  `:skill` is given: it sets how tightly it aims, how far it fires from, how often it
  holds its fire, how fast it reacts (`cadence/1`) and how late it raises its shield.

      ExPilot.Robot.start_link(world: world, number: 1, arena: :dogfight)
      ExPilot.Robot.decide(view, grid, 0, skill: 0.6, stations: stations, tick: tick)
  """

  use GenServer

  alias Cauldron2D.{Collision, Player}
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
  @least_skill 0.3
  @cadence 3
  @slowest_cadence 9

  @doc "Start a robot; options `:world`, `:number` and `:arena` are required."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    number = Keyword.fetch!(opts, :number)
    arena = Keyword.fetch!(opts, :arena)
    GenServer.start_link(__MODULE__, opts, name: {:via, Registry, {ExPilot.Registry, {:robot, arena, number}}})
  end

  @impl GenServer
  def init(opts) do
    world = Keyword.fetch!(opts, :world)
    number = Keyword.fetch!(opts, :number)
    id = {:robot, number}

    skill = Keyword.get_lazy(opts, :skill, &skill/0)

    case Player.join(world, id, %{username: "Robot #{number}", robot?: true}) do
      :ok -> {:ok, %{world: world, id: id, grid: nil, stations: nil, held: MapSet.new(), tick: 0, burn: 0, skill: skill}}
      {:error, reason} -> {:stop, {:shutdown, reason}}
    end
  end

  @impl GenServer
  def handle_info({:cauldron_frame, %{view: %{me: nil}}}, state) do
    Player.leave(state.world, state.id)
    {:stop, :normal, state}
  end

  def handle_info({:cauldron_frame, %{view: view}}, state) do
    state = %{state | grid: state.grid || grid_for(view), stations: state.stations || stations_for(view)}

    if rem(state.tick, cadence(state.skill)) == 0 do
      {held, burn} = decide(view, state.grid, state.burn, skill: state.skill, stations: state.stations, tick: state.tick)
      if held != state.held, do: Player.input(state.world, state.id, %{held: held, aim: nil})
      {:noreply, %{state | held: held, burn: burn, tick: state.tick + 1}}
    else
      {:noreply, %{state | tick: state.tick + 1}}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

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

  @doc "The actions to hold for `view`, given the arena's collision grid, with no launch burn running."
  @spec decide(map(), Collision.grid()) :: MapSet.t(atom())
  def decide(view, grid), do: view |> decide(grid, 0) |> elem(0)

  @doc """
  The actions to hold for `view` and the launch burn left after them.

  `burn` is how many decisions of the burn remain: a landed robot turns to face up and
  thrusts off with a full burn, then holds thrust straight while the burn lasts and the
  way ahead is clear. With the burn spent it flies: toward the nearest clear heading to
  the enemy, braking when drifting into a wall, firing when lined up, shielding when a
  shot is close. With the tank below 350 and a station of `:stations` within 25 tiles
  the robot flies there instead and hovers within reach of it.

  `opts`: `:stations`, the arena's fuel tiles (default none); `:skill`, 0.3 to 1.0
  (default 1.0); `:tick`, the frame count, which a robot with less than full skill uses
  to hold its fire part of the time (default 0).
  """
  @spec decide(map(), Collision.grid(), non_neg_integer(), keyword()) :: {MapSet.t(atom()), non_neg_integer()}
  def decide(view, grid, burn, opts \\ [])
  def decide(%{me: nil}, _grid, _burn, _opts), do: {MapSet.new(), 0}
  def decide(%{me: %{alive?: false}}, _grid, _burn, _opts), do: {MapSet.new(), 0}
  def decide(%{me: %{landed?: true} = me}, _grid, _burn, _opts), do: {MapSet.new(launch(me)), @launch_burn}

  def decide(%{me: me} = view, grid, burn, opts) do
    mind = %{skill: Keyword.get(opts, :skill, 1.0), tick: Keyword.get(opts, :tick, 0)}

    cond do
      burn > 0 and clear?(me, me.heading, grid) -> {MapSet.new(if(slow?(me, view), do: [:thrust], else: [])), burn - 1}
      station = thirsty_for(me, Keyword.get(opts, :stations, [])) -> {refuel(view, grid, station, mind), 0}
      true -> {fly(view, grid, mind), 0}
    end
  end

  @doc "A skill for a new robot: at random, from #{@least_skill} to 1.0."
  @spec skill() :: float()
  def skill, do: @least_skill + (1.0 - @least_skill) * :rand.uniform()

  @doc "Every how many frames a robot of `skill` decides: #{@cadence} at full skill, up to #{@slowest_cadence}."
  @spec cadence(float()) :: pos_integer()
  def cadence(skill), do: @cadence + round((1.0 - skill) / (1.0 - @least_skill) * (@slowest_cadence - @cadence))

  defp thirsty_for(%{fuel: fuel} = me, stations) when fuel < @refuel_below do
    stations
    |> Enum.map(fn {x, y} -> {x + 0.5, y + 0.5} end)
    |> Enum.filter(&Collision.circles_overlap?(me.pos, @station_sight, &1, 0.0))
    |> Enum.min_by(&distance_sq(me.pos, &1), fn -> nil end)
  end

  defp thirsty_for(_me, _stations), do: nil

  defp refuel(%{me: me, ships: ships, shots: shots} = view, grid, station, mind) do
    enemy = nearest_enemy(me, ships)
    there? = distance_sq(me.pos, station) < @station_hover * @station_hover
    braking? = blocked?(grid, me.pos, coasting(me, view)) or (there? and speed(me) > 0.5)
    heading = clear_heading(me, if(braking?, do: wanted(me, nil, true), else: heading_toward(me.pos, station)), grid)
    aligned? = abs(turn_delta(me.heading, heading)) <= @align and clear?(me, me.heading, grid)
    threatened? = Enum.any?(shots, &Collision.circles_overlap?(me.pos, @shield_reach * mind.skill, &1, 0.0))

    thrusting = if aligned? and (braking? or (not there? and slow?(me, view))), do: [:thrust], else: []
    shielding = if threatened? and me.fuel > 100 and shields?(view), do: [:shield], else: []
    MapSet.new(turn_toward(me.heading, heading) ++ thrusting ++ firing(me, enemy, mind) ++ shielding)
  end

  defp launch(me) do
    case turn_toward(me.heading, Elixir.Map.get(me, :launch_heading, div(Ship.headings(), 4))) do
      [] -> [:thrust]
      turning -> turning
    end
  end

  defp fly(%{me: me, ships: ships, shots: shots} = view, grid, mind) do
    enemy = nearest_enemy(me, ships)
    braking? = blocked?(grid, me.pos, coasting(me, view))
    heading = clear_heading(me, wanted(me, enemy, braking?), grid)
    aligned? = abs(turn_delta(me.heading, heading)) <= @align and clear?(me, me.heading, grid)
    far? = enemy == nil or distance_sq(me.pos, enemy.pos) > @close * @close
    threatened? = Enum.any?(shots, &Collision.circles_overlap?(me.pos, @shield_reach * mind.skill, &1, 0.0))

    thrusting = if aligned? and (braking? or (far? and slow?(me, view))), do: [:thrust], else: []
    shielding = if (threatened? or braking?) and me.fuel > 100 and shields?(view), do: [:shield], else: []
    MapSet.new(turn_toward(me.heading, heading) ++ thrusting ++ firing(me, enemy, mind) ++ shielding)
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
  defp wanted(me, enemy, false), do: heading_toward(me.pos, enemy.pos)

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

  defp nearest_enemy(me, ships) do
    ships
    |> Enum.filter(fn ship -> ship.id != me.id and ship.alive? and (me.team == nil or ship.team != me.team) end)
    |> Enum.min_by(&distance_sq(me.pos, &1.pos), fn -> nil end)
  end

  defp clear?(me, heading, grid), do: not blocked?(grid, me.pos, probe(me.pos, heading, reach(me)))

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

  defp blocked?(grid, from, to), do: match?({:blocked, _, _, _}, Collision.sweep(grid, from, to, 0.0))

  defp heading_toward({x1, y1}, {x2, y2}) do
    angle = :math.atan2(-(y2 - y1), x2 - x1)
    Integer.mod(round(angle / (2 * :math.pi()) * Ship.headings()), Ship.headings())
  end

  defp distance_sq({x1, y1}, {x2, y2}), do: (x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1)
end
