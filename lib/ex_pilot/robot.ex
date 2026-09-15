defmodule ExPilot.Robot do
  @moduledoc """
  A robot player: a process that joins a world as `{:robot, n}` and flies by its view.

  Each frame it picks the nearest live enemy anywhere in the arena, turns toward it, thrusts
  while far and fires while lined up; it turns away from a wall ahead and raises its
  shield when a shot is close. With no enemy near it cruises, turning to keep clear of
  walls.

      ExPilot.Robot.start_link(world: world, number: 1, arena: :dogfight)
  """

  use GenServer

  alias Cauldron2D.{Collision, Player}
  alias ExPilot.{Arenas, Map, Ship}

  @reach 28.0
  @fire_cone 3
  @close 7.0
  @lookahead 2.0
  @shield_reach 2.5

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

    case Player.join(world, id, %{username: "Robot #{number}", robot?: true}) do
      :ok -> {:ok, %{world: world, id: id, grid: nil, held: MapSet.new(), tick: 0}}
      {:error, reason} -> {:stop, {:shutdown, reason}}
    end
  end

  @impl GenServer
  def handle_info({:cauldron_frame, %{view: view}}, state) do
    state = %{state | grid: state.grid || grid_for(view)}

    if rem(state.tick, 3) == 0 do
      held = decide(view, state.grid)
      if held != state.held, do: Player.input(state.world, state.id, %{held: held, aim: nil})
      {:noreply, %{state | held: held, tick: state.tick + 1}}
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

  @doc "The actions to hold for `view`, given the arena's collision grid."
  @spec decide(map(), Collision.grid()) :: MapSet.t(atom())
  def decide(%{me: nil}, _grid), do: MapSet.new()
  def decide(%{me: %{alive?: false}}, _grid), do: MapSet.new()

  def decide(%{me: me, ships: ships, shots: shots}, grid) do
    enemy = nearest_enemy(me, ships)
    wall_ahead? = wall_ahead?(me, grid)
    threatened? = Enum.any?(shots, &Collision.circles_overlap?(me.pos, @shield_reach, &1, 0.0))

    actions =
      cond do
        wall_ahead? -> [:turn_left]
        enemy == nil -> cruise(me)
        true -> hunt(me, enemy)
      end

    actions = if (threatened? or wall_ahead?) and me.fuel > 100, do: [:shield | actions], else: actions
    MapSet.new(actions)
  end

  defp nearest_enemy(me, ships) do
    ships
    |> Enum.filter(fn ship -> ship.id != me.id and ship.alive? and (me.team == nil or ship.team != me.team) end)
    |> Enum.min_by(&distance_sq(me.pos, &1.pos), fn -> nil end)
  end

  defp hunt(me, enemy) do
    wanted = heading_toward(me.pos, enemy.pos)
    delta = Integer.mod(wanted - me.heading + div(Ship.headings(), 2), Ship.headings()) - div(Ship.headings(), 2)
    far? = distance_sq(me.pos, enemy.pos) > @close * @close

    turning =
      cond do
        delta > 1 -> [:turn_left]
        delta < -1 -> [:turn_right]
        true -> []
      end

    in_reach? = Collision.circles_overlap?(me.pos, @reach, enemy.pos, 0.0)
    firing = if in_reach? and abs(delta) <= @fire_cone, do: [:fire], else: []
    thrusting = if far? and abs(delta) <= 8, do: [:thrust], else: []
    turning ++ firing ++ thrusting
  end

  defp cruise(me) do
    if rem(trunc(elem(me.pos, 0) + elem(me.pos, 1)), 7) == 0, do: [:turn_right], else: [:thrust]
  end

  defp wall_ahead?(me, grid) do
    {x, y} = me.pos
    {vx, vy} = Elixir.Map.get(me, :vel, {0.0, 0.0})
    theta = 2 * :math.pi() * me.heading / Ship.headings()
    facing = {x + :math.cos(theta) * @lookahead, y - :math.sin(theta) * @lookahead}
    coasting = {x + vx * 0.6, y + vy * 0.6}

    Enum.any?([facing, coasting], fn ahead ->
      match?({:blocked, _, _, _}, Collision.sweep(grid, me.pos, ahead, 0.0))
    end)
  end

  defp heading_toward({x1, y1}, {x2, y2}) do
    angle = :math.atan2(-(y2 - y1), x2 - x1)
    Integer.mod(round(angle / (2 * :math.pi()) * Ship.headings()), Ship.headings())
  end

  defp distance_sq({x1, y1}, {x2, y2}), do: (x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1)
end
