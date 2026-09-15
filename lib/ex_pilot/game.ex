defmodule ExPilot.Game do
  @moduledoc """
  The rules of ExPilot as one pure value, run by `Cauldron2D.World`.

  Ships turn, thrust, fire and shield on held actions; gravity from the map and its
  points pulls on them; walls crash an unshielded ship and bounce a shielded one; fuel
  stations refill a ship near them; wormholes move a ship elsewhere; cannons on the map
  fire at ships in front of them; a shot kills an unshielded ship it meets. A dead ship
  comes back on its base a few seconds later. Watchers join with `spectate: true` and
  see the arena without a ship.

  ## Actions

  `:turn_left`, `:turn_right`, `:thrust`, `:fire`, `:shield`. An `aim` in the input turns
  the ship toward that world point instead of the turn keys.

  ## Events

  Every event carries a position: `{:fire, pos}`, `{:explosion, pos}`, `{:bounce, pos}`,
  `{:shot_wall, pos}`, `{:refuel, pos}`, `{:wormhole, pos}`, `{:cannon, pos}`,
  `{:respawn, pos}`, `{:kill, pos}`, `{:round, pos}`.

  ## Rounds

  A ship on its base sits still until it thrusts. With limited lives, a ship whose lives are
  gone stays out until every ship is out; then a new round starts and everyone is back on
  their base with their lives, scores kept.
  """

  @behaviour Cauldron2D.Game

  alias Cauldron2D.{Body, Collision, Particles, Rng}
  alias Cauldron2D.Collision.Buckets
  alias ExPilot.Map, as: Arena
  alias ExPilot.Ship

  @type t :: %__MODULE__{}

  defstruct arena: nil,
            ships: %{},
            watchers: %{},
            shots: [],
            particles: nil,
            cannons: [],
            fields: [],
            rng: nil,
            events: [],
            time: 0.0,
            next_id: 1,
            settings: %{}

  @turn_rate 60.0
  @thrust 14.0
  @max_speed 18.0
  @drag 0.05
  @thrust_burn 60.0
  @shield_burn 80.0
  @shot_cost 5.0
  @refuel_rate 300.0
  @refuel_reach 2.0
  @fire_cooldown 0.18
  @respawn_after 3.0
  @cannon_range 12.0
  @cannon_cooldown 1.5
  @shot_radius 0.1
  @point_gravity 30.0
  @gravity_scale 0.25
  @particle_cap 300

  @doc """
  A new game on an arena.

  ## Options

    * `:arena` — an `ExPilot.Map`, or a path to a map file. Required
    * `:seed` — for the game's own randomness. Default: unique
    * `:lives` — lives per ship, or `:unlimited`. Default: the map's `limitedlives` and
      `worldlives`
  """
  @impl true
  def init(opts) do
    arena = load(Keyword.fetch!(opts, :arena))
    seed = Keyword.get(opts, :seed, :erlang.unique_integer([:positive]))

    %__MODULE__{
      arena: arena,
      particles: Particles.new(@particle_cap),
      cannons: Enum.map(Arena.cannons(arena), &Map.put(&1, :cooldown, 0.0)),
      fields: fields(arena),
      rng: Rng.new(seed),
      settings: %{
        wrap?: Arena.wrap?(arena),
        shot_speed: Arena.option(arena, :shotspeed) * 50 / 35,
        shot_life: Arena.option(arena, :shotlife) / 50,
        lives: Keyword.get(opts, :lives, lives_option(arena)),
        teamplay?: Arena.option(arena, :teamplay),
        max_shots: Arena.option(arena, :maxplayershots)
      }
    }
  end

  defp load(%Arena{} = arena), do: arena

  defp load(path) when is_binary(path) do
    {:ok, arena} = Arena.parse_file(path)
    arena
  end

  defp lives_option(arena) do
    if Arena.option(arena, :limitedlives), do: max(1, Arena.option(arena, :worldlives)), else: :unlimited
  end

  defp fields(arena) do
    uniform = %{strength: -Arena.option(arena, :gravity) * @gravity_scale, kind: {:uniform, {0.0, 1.0}}}

    points =
      for %{pos: {x, y}, kind: kind} <- Arena.gravity_points(arena) do
        point_field({x + 0.5, y + 0.5}, kind)
      end

    [uniform | points]
  end

  defp point_field(pos, kind) when kind in [:attract, :repel, :clockwise, :anticlockwise] do
    %{pos: pos, strength: @point_gravity, kind: kind}
  end

  defp point_field(_pos, :up), do: %{strength: @point_gravity / 10, kind: {:uniform, {0.0, -1.0}}}
  defp point_field(_pos, :down), do: %{strength: @point_gravity / 10, kind: {:uniform, {0.0, 1.0}}}
  defp point_field(_pos, :left), do: %{strength: @point_gravity / 10, kind: {:uniform, {-1.0, 0.0}}}
  defp point_field(_pos, :right), do: %{strength: @point_gravity / 10, kind: {:uniform, {1.0, 0.0}}}

  @impl true
  def join(%__MODULE__{} = game, id, props) do
    cond do
      Map.get(props, :spectate, false) ->
        {:ok, %{game | watchers: Map.put(game.watchers, id, %{focus: centre(game)})}}

      Map.has_key?(game.ships, id) ->
        {:error, :already_joined}

      true ->
        case free_base(game, Map.get(props, :team)) do
          nil ->
            {:error, :full}

          %{pos: base, team: team} ->
            ship =
              Ship.new(id, Map.get(props, :username, name_of(id)), base,
                team: team,
                robot?: Map.get(props, :robot?, false),
                lives: game.settings.lives
              )

            {:ok, %{game | ships: Map.put(game.ships, id, ship)}}
        end
    end
  end

  defp name_of(id) when is_binary(id), do: id
  defp name_of(id) when is_atom(id), do: Atom.to_string(id)
  defp name_of(id), do: inspect(id)

  defp centre(%__MODULE__{arena: arena}) do
    {w, h} = Arena.size(arena)
    {w / 2, h / 2}
  end

  defp free_base(game, wanted_team) do
    taken = game.ships |> Map.values() |> MapSet.new(& &1.base)

    game.arena
    |> Arena.bases()
    |> Enum.reject(&MapSet.member?(taken, &1.pos))
    |> Enum.filter(fn base -> wanted_team == nil or base.team == nil or base.team == wanted_team end)
    |> List.first()
  end

  @impl true
  def leave(%__MODULE__{} = game, id) do
    %{game | ships: Map.delete(game.ships, id), watchers: Map.delete(game.watchers, id)}
  end

  @impl true
  def handle_input(%__MODULE__{} = game, id, %{held: held} = input) do
    case Map.fetch(game.ships, id) do
      {:ok, ship} -> %{game | ships: Map.put(game.ships, id, %{ship | held: held, aim: Map.get(input, :aim)})}
      :error -> game
    end
  end

  @impl true
  def step(%__MODULE__{} = game, dt) do
    game
    |> Map.update!(:time, &(&1 + dt))
    |> fly_ships(dt)
    |> fly_shots(dt)
    |> fire_cannons(dt)
    |> Map.update!(:particles, &Particles.step(&1, dt, drag: 0.5))
    |> maybe_new_round()
  end

  defp maybe_new_round(%{ships: ships} = game) when map_size(ships) == 0, do: game

  defp maybe_new_round(game) do
    everyone_out? = Enum.all?(game.ships, fn {_, ship} -> not ship.alive? and not Ship.can_respawn?(ship) end)

    if everyone_out? do
      ships = Map.new(game.ships, fn {id, ship} -> {id, Ship.new_round(ship, game.settings.lives)} end)
      %{game | ships: ships} |> emit({:round, centre(game)})
    else
      game
    end
  end

  defp fly_ships(game, dt) do
    Enum.reduce(game.ships, game, fn {id, _}, acc -> fly_ship(acc, id, dt) end)
  end

  defp fly_ship(game, id, dt) do
    ship = Map.fetch!(game.ships, id)

    if ship.alive? do
      {ship, game} = ship |> steer(dt) |> propel(dt, game) |> fire(dt, game) |> move(dt, game)
      game = %{game | ships: Map.put(game.ships, id, ship)}
      game |> refuel(id, dt) |> warp(id)
    else
      countdown(game, id, dt)
    end
  end

  defp steer(%Ship{} = ship, dt) do
    steps = round(@turn_rate * dt)

    cond do
      Ship.holding?(ship, :turn_left) -> %{ship | body: Body.turn(ship.body, steps)}
      Ship.holding?(ship, :turn_right) -> %{ship | body: Body.turn(ship.body, -steps)}
      ship.aim != nil -> steer_toward(ship, ship.aim, steps)
      true -> ship
    end
  end

  defp steer_toward(ship, {ax, ay}, steps) do
    {x, y} = ship.body.pos
    wanted = heading_toward(ship.body, {ax - x, ay - y})
    delta = Integer.mod(wanted - ship.body.heading + div(Ship.headings(), 2), Ship.headings()) - div(Ship.headings(), 2)
    step = min(abs(delta), steps) * sign(delta)
    %{ship | body: Body.turn(ship.body, step)}
  end

  defp heading_toward(%Body{headings: headings}, {dx, dy}) do
    angle = :math.atan2(-dy, dx)
    Integer.mod(round(angle / (2 * :math.pi()) * headings), headings)
  end

  defp sign(n) when n > 0, do: 1
  defp sign(n) when n < 0, do: -1
  defp sign(_), do: 0

  defp propel(%Ship{landed?: true} = ship, dt, game) do
    if Ship.holding?(ship, :thrust) and ship.fuel > 0 do
      propel(%{ship | landed?: false}, dt, game)
    else
      shielding? = Ship.holding?(ship, :shield) and ship.fuel > 0
      burn = if shielding?, do: @shield_burn * dt, else: 0.0

      {%{ship | cooldown: max(0.0, ship.cooldown - dt), shielding?: shielding?, thrusting?: false, fuel: max(0.0, ship.fuel - burn)}, game}
    end
  end

  defp propel(%Ship{} = ship, dt, game) do
    thrusting? = Ship.holding?(ship, :thrust) and ship.fuel > 0
    shielding? = Ship.holding?(ship, :shield) and ship.fuel > 0

    body = if thrusting?, do: Body.thrust(ship.body, @thrust, dt), else: ship.body
    burn = (if thrusting?, do: @thrust_burn, else: 0.0) + if shielding?, do: @shield_burn, else: 0.0

    ship = %{
      ship
      | body: body |> Body.gravitate(game.fields, dt) |> Body.drag(@drag, dt) |> Body.cap_speed(@max_speed),
        fuel: max(0.0, ship.fuel - burn * dt),
        thrusting?: thrusting?,
        shielding?: shielding?,
        cooldown: max(0.0, ship.cooldown - dt)
    }

    if thrusting?, do: {ship, exhaust(game, ship)}, else: {ship, game}
  end

  defp exhaust(game, ship) do
    {dx, dy} = Body.direction(ship.body)
    {x, y} = ship.body.pos
    {vx, vy} = ship.body.vel
    {jitter, rng} = Rng.between(game.rng, -20, 20)
    spread = jitter / 100

    spark = %{
      art: :spark,
      pos: {x - dx * 0.5, y - dy * 0.5},
      vel: {vx - dx * 6 + dy * spread * 6, vy - dy * 6 - dx * spread * 6},
      ttl: 0.25
    }

    %{game | rng: rng, particles: Particles.spawn(game.particles, [spark])}
  end

  defp fire({ship, game}, _dt, _unused) do
    if Ship.holding?(ship, :fire) and ship.cooldown <= 0 and ship.fuel >= @shot_cost and shots_of(game, ship.id) < game.settings.max_shots do
      {dx, dy} = Body.direction(ship.body)
      {x, y} = ship.body.pos
      {vx, vy} = ship.body.vel
      speed = game.settings.shot_speed

      shot = %{
        id: game.next_id,
        owner: ship.id,
        body: Body.new(pos: {x + dx * 0.6, y + dy * 0.6}, vel: {vx + dx * speed, vy + dy * speed}, radius: @shot_radius),
        life: game.settings.shot_life
      }

      game = %{game | shots: [shot | game.shots], next_id: game.next_id + 1} |> emit({:fire, ship.body.pos})
      {%{ship | cooldown: @fire_cooldown, fuel: ship.fuel - @shot_cost}, game}
    else
      {ship, game}
    end
  end

  defp shots_of(game, owner), do: Enum.count(game.shots, &(&1.owner == owner))

  defp move({%Ship{landed?: true} = ship, game}, _dt, _unused), do: {ship, game}

  defp move({ship, game}, dt, _unused) do
    grid = Arena.grid(game.arena)
    from = ship.body.pos
    to = ship.body |> Body.integrate(dt) |> Map.fetch!(:pos)

    case Collision.sweep(grid, from, to, Ship.radius()) do
      {:clear, at} ->
        {%{ship | body: wrapped(%{ship.body | pos: at}, game)}, game}

      {:blocked, at, normal, _cell} when ship.shielding? ->
        body = %{ship.body | pos: at, vel: Collision.bounce(ship.body.vel, normal, 0.5)}
        {%{ship | body: wrapped(body, game)}, emit(game, {:bounce, at})}

      {:blocked, at, _normal, _cell} ->
        {ship, game} = explode({%{ship | body: %{ship.body | pos: at}}, game})
        {ship, game}
    end
  end

  defp wrapped(body, %{settings: %{wrap?: true}, arena: arena}), do: Body.wrap(body, Arena.size(arena))
  defp wrapped(body, _game), do: body

  defp explode({ship, game}) do
    pos = ship.body.pos
    {debris, rng} = debris(game.rng, pos, 24)
    game = %{game | rng: rng, particles: Particles.spawn(game.particles, debris)} |> emit({:explosion, pos})
    {Ship.die(ship, @respawn_after), game}
  end

  defp debris(rng, {x, y}, count) do
    Enum.map_reduce(1..count, rng, fn _, rng ->
      {angle, rng} = Rng.between(rng, 0, 359)
      {speed, rng} = Rng.between(rng, 3, 9)
      {life, rng} = Rng.between(rng, 30, 90)
      theta = angle * :math.pi() / 180
      {%{art: :debris, pos: {x, y}, vel: {:math.cos(theta) * speed, :math.sin(theta) * speed}, ttl: life / 100}, rng}
    end)
  end

  defp refuel(game, id, dt) do
    ship = Map.fetch!(game.ships, id)

    near? =
      Enum.any?(Arena.fuel(game.arena), fn {fx, fy} ->
        Collision.circles_overlap?(ship.body.pos, @refuel_reach, {fx + 0.5, fy + 0.5}, 0.0)
      end)

    if near? and ship.fuel < Ship.max_fuel() do
      filled = min(Ship.max_fuel(), ship.fuel + @refuel_rate * dt)
      %{game | ships: Map.put(game.ships, id, %{ship | fuel: filled})} |> emit_refuel(ship)
    else
      game
    end
  end

  defp emit_refuel(game, ship) do
    if rem(trunc(game.time * 10), 5) == 0, do: emit(game, {:refuel, ship.body.pos}), else: game
  end

  defp warp(game, id) do
    ship = Map.fetch!(game.ships, id)
    holes = Arena.wormholes(game.arena)
    here = Collision.cell_of(ship.body.pos)

    case Enum.find(holes, &(&1.pos == here and &1.kind in [:normal, :in])) do
      nil ->
        game

      _entrance ->
        exits = Enum.filter(holes, &(&1.pos != here and &1.kind in [:normal, :out]))

        case Rng.pick(game.rng, exits) do
          {nil, rng} ->
            %{game | rng: rng}

          {%{pos: {ex, ey}}, rng} ->
            moved = %{ship | body: %{ship.body | pos: {ex + 0.5, ey + 0.5}}}
            %{game | rng: rng, ships: Map.put(game.ships, id, moved)} |> emit({:wormhole, ship.body.pos})
        end
    end
  end

  defp countdown(game, id, dt) do
    ship = Map.fetch!(game.ships, id)
    remaining = ship.respawn_in - dt

    cond do
      remaining > 0 ->
        %{game | ships: Map.put(game.ships, id, %{ship | respawn_in: remaining})}

      Ship.can_respawn?(ship) ->
        revived = Ship.respawn(ship)
        %{game | ships: Map.put(game.ships, id, revived)} |> emit({:respawn, revived.body.pos})

      true ->
        %{game | ships: Map.put(game.ships, id, %{ship | respawn_in: 0.0})}
    end
  end

  defp fly_shots(game, dt) do
    grid = Arena.grid(game.arena)
    buckets = ship_buckets(game)

    {game, kept} =
      Enum.reduce(game.shots, {game, []}, fn shot, {acc, kept} ->
        advance_shot(acc, shot, dt, grid, buckets, kept)
      end)

    %{game | shots: Enum.reverse(kept)}
  end

  defp ship_buckets(game) do
    game.ships
    |> Map.values()
    |> Enum.filter(& &1.alive?)
    |> Enum.reduce(Buckets.new(4), fn ship, buckets -> Buckets.insert(buckets, ship.id, ship.body.pos, Ship.radius()) end)
  end

  defp advance_shot(game, shot, dt, grid, buckets, kept) do
    life = shot.life - dt
    from = shot.body.pos
    to = shot.body |> Body.gravitate(game.fields, dt) |> Body.integrate(dt)

    cond do
      life <= 0 ->
        {game, kept}

      true ->
        case Collision.sweep(grid, from, to.pos, @shot_radius) do
          {:blocked, at, _normal, _cell} ->
            {emit(game, {:shot_wall, at}), kept}

          {:clear, at} ->
            moved = %{shot | body: wrapped(%{to | pos: at}, game), life: life}

            case Enum.reject(Buckets.near(buckets, moved.body.pos, @shot_radius), &(&1 == shot.owner)) do
              [] -> {game, [moved | kept]}
              [victim | _] -> {strike(game, shot.owner, victim, moved.body.pos), kept}
            end
        end
    end
  end

  defp strike(game, owner, victim_id, pos) do
    victim = Map.fetch!(game.ships, victim_id)

    cond do
      victim.shielding? ->
        emit(game, {:bounce, pos})

      not victim.alive? ->
        game

      true ->
        {dead, game} = explode({victim, game})
        game = %{game | ships: Map.put(game.ships, victim_id, dead)} |> emit({:kill, pos})
        credit(game, owner)
    end
  end

  defp credit(game, {:cannon, _}), do: game

  defp credit(game, owner) do
    case Map.fetch(game.ships, owner) do
      {:ok, killer} -> %{game | ships: Map.put(game.ships, owner, Ship.credit_kill(killer))}
      :error -> game
    end
  end

  defp fire_cannons(game, dt) do
    {cannons, game} =
      Enum.map_reduce(game.cannons, game, fn cannon, acc ->
        cooled = %{cannon | cooldown: max(0.0, cannon.cooldown - dt)}

        case {cooled.cooldown, target_for(acc, cooled)} do
          {cd, target} when cd <= 0 and target != nil -> {%{cooled | cooldown: @cannon_cooldown}, cannon_fire(acc, cooled, target)}
          _ -> {cooled, acc}
        end
      end)

    %{game | cannons: cannons}
  end

  defp target_for(game, %{pos: {cx, cy}, facing: facing}) do
    muzzle = {cx + 0.5, cy + 0.5}

    game.ships
    |> Map.values()
    |> Enum.filter(& &1.alive?)
    |> Enum.filter(fn ship -> in_front?(facing, muzzle, ship.body.pos) end)
    |> Enum.filter(fn ship -> Collision.circles_overlap?(muzzle, @cannon_range, ship.body.pos, 0.0) end)
    |> Enum.min_by(fn ship -> distance_sq(muzzle, ship.body.pos) end, fn -> nil end)
  end

  defp in_front?(:up, {_, my}, {_, y}), do: y < my
  defp in_front?(:down, {_, my}, {_, y}), do: y > my
  defp in_front?(:left, {mx, _}, {x, _}), do: x < mx
  defp in_front?(:right, {mx, _}, {x, _}), do: x > mx

  defp distance_sq({x1, y1}, {x2, y2}), do: (x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1)

  defp cannon_fire(game, %{pos: {cx, cy}}, target) do
    muzzle = {cx + 0.5, cy + 0.5}
    {tx, ty} = target.body.pos
    {mx, my} = muzzle
    length = :math.sqrt(distance_sq(muzzle, target.body.pos))
    speed = game.settings.shot_speed * 0.8
    vel = {(tx - mx) / length * speed, (ty - my) / length * speed}

    shot = %{
      id: game.next_id,
      owner: {:cannon, {cx, cy}},
      body: Body.new(pos: {mx + (tx - mx) / length, my + (ty - my) / length}, vel: vel, radius: @shot_radius),
      life: game.settings.shot_life * 2
    }

    %{game | shots: [shot | game.shots], next_id: game.next_id + 1} |> emit({:cannon, muzzle})
  end

  @impl true
  def view(%__MODULE__{} = game, id) do
    me = Map.get(game.ships, id)
    watching = me && out?(me) && nearest_living(game, me)

    focus =
      cond do
        watching -> watching.body.pos
        me -> me.body.pos
        true -> Map.get(game.watchers, id, %{focus: centre(game)}).focus
      end

    %{
      me: me && summary_of(me),
      focus: focus,
      watching: watching && watching.name,
      others_out?: me != nil and Enum.all?(game.ships, fn {other, ship} -> other == id or out?(ship) end),
      enemies: Enum.count(game.ships, fn {other, ship} -> other != id and not out?(ship) end),
      ships: for({_, ship} <- game.ships, ship.alive?, do: Ship.summary(ship)),
      shots: Enum.map(game.shots, & &1.body.pos),
      particles: Particles.movers(game.particles, {-0.5, -0.5}),
      bounds: Arena.size(game.arena),
      wrap?: game.settings.wrap?,
      arena: Arena.name(game.arena),
      scores: scores(game),
      time: game.time
    }
  end

  defp out?(ship), do: not ship.alive? and not Ship.can_respawn?(ship)

  defp nearest_living(game, me) do
    {mx, my} = me.body.pos

    game.ships
    |> Map.values()
    |> Enum.filter(fn ship -> ship.id != me.id and ship.alive? end)
    |> Enum.min_by(fn %{body: %{pos: {x, y}}} -> (x - mx) * (x - mx) + (y - my) * (y - my) end, fn -> nil end)
  end

  @doc """
  Whether the round is over for the player a view belongs to.

  `nil` while it goes on: the player flies, or is out of lives but others still fly and
  the view follows the nearest. Once every other ship is out, `%{title: title, lines:
  lines, next: next}` with the standings as lines: `"Victory"` with `next: :next_arena`
  while the player still flies, `"Defeat"` with `next: :same_arena` when they are out too.
  A watcher's view, or one with unlimited lives, is never over.
  """
  @spec outcome(map()) :: nil | %{title: String.t(), lines: [String.t()]}
  def outcome(%{me: nil}), do: nil
  def outcome(%{others_out?: false}), do: nil
  def outcome(%{me: %{lives: :unlimited}}), do: nil

  def outcome(%{me: me, scores: scores}) do
    lines = Enum.map(scores, fn %{name: name, score: score} -> name <> "  " <> Integer.to_string(score) end)

    if me.alive? or me.lives > 0,
      do: %{title: "Victory", lines: lines, next: :next_arena},
      else: %{title: "Defeat", lines: lines, next: :same_arena}
  end

  defp summary_of(ship) do
    ship
    |> Ship.summary()
    |> Map.merge(%{fuel: ship.fuel, lives: ship.lives, respawn_in: ship.respawn_in, kills: ship.kills, deaths: ship.deaths})
  end

  defp scores(game) do
    game.ships
    |> Map.values()
    |> Enum.map(&%{name: &1.name, score: &1.score, team: &1.team})
    |> Enum.sort_by(& &1.score, :desc)
    |> Enum.take(8)
  end

  @impl true
  def drain_events(%__MODULE__{events: events} = game), do: {Enum.reverse(events), %{game | events: []}}

  defp emit(game, event), do: %{game | events: [event | game.events]}
end
