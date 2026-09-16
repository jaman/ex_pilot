defmodule ExPilot.Game do
  @moduledoc """
  The rules of ExPilot as one pure value, run by `Cauldron2D.World`.

  Ships turn, thrust, fire and shield on held actions; gravity from the map and its
  points pulls on them; a wall bounces a ship, at a cost in fuel, unless the ship hits it
  unshielded faster than `@wall_crash_speed`, which is a crash; fuel
  stations refill a ship near them; wormholes move a ship elsewhere; cannons on the map
  fire at ships in front of them; a shot kills an unshielded ship it meets unless armour
  takes it; two ships that meet crash unless shielded, and shielded ships bounce apart.
  A ship whose tank has been empty for ten seconds, flying or sitting on its base, is
  lost as if it had crashed. A dead ship comes back on its base a few seconds later.
  Watchers join with `spectate: true` and see the arena without a ship.

  A player without a base to join takes a robot's: the robot's ship is removed and the
  player seated there. A player joining without a team goes to the team with fewer ships.

  ## Map rules

  The map's header sets the rules `ExPilot.Map.option/2` reads: `allowshields`,
  `initialfuel` and the `initial…` kit every ship spawns with, `shotswallbounce`,
  `shotsgravity`, `friction`, `allowplayerkilling`, `allowplayercrashes` and
  `allowplayerbounces`, `playerwallbouncebrakefactor`, `targetkillteam` (a team whose
  last target falls is destroyed) and `treasurekillteam` (a team whose ball is scored
  against is destroyed), `dropitemonkillprob`, `laserisstungun`, `minefusetime`,
  `firerepeatrate`, `shieldeditempickup`, `shieldedmining`, `ballswallbounce`,
  `checkpointradius`, `playersonradar`, and gravity's `gravityangle` or, with
  `gravitypointsource`, a pull toward `gravitypoint`.

  Items appear on the map (`ExPilot.Items`) and are used with keys (`ExPilot.Gear`);
  missiles, mines and lasers are `ExPilot.Weapons`. With `teamplay`, teammates' shots
  pass through each other when the map has `teamimmunity`, team scores add up, targets
  (`ExPilot.Targets`) and balls in treasures (`ExPilot.Ball`) score for a team. With
  `racemode`, ships pass the checkpoints in order (`ExPilot.Race`). What happens is told
  in messages the view carries.

  ## Actions

  `:turn_left`, `:turn_right`, `:thrust`, `:fire`, `:shield`, then the item keys of
  `ExPilot.Gear.actions/0`. An `aim` in the input turns the ship toward that world point
  instead of the turn keys. `:next_watch`, pressed by a player who is out or by a
  watcher, moves the view to the next ship flying, by name; the view's `watching` names
  it.

  ## Events

  Every event carries a position: `{:fire, pos}`, `{:explosion, pos}`, `{:bounce, pos}`,
  `{:shot_wall, pos}`, `{:refuel, pos}`, `{:wormhole, pos}`, `{:cannon, pos}`,
  `{:respawn, pos}`, `{:kill, pos}`, `{:round, pos}`, `{:pick_up, pos}`, `{:missile, pos}`,
  `{:mine, pos}`, `{:laser, pos}`, `{:cloak, pos}`, `{:ecm, pos}`, `{:transporter, pos}`,
  `{:hyperjump, pos}`, `{:target_hit, pos}`, `{:target_destroyed, pos}`, `{:goal, pos}`,
  `{:checkpoint, pos}`, `{:finish, pos}`.

  ## Rounds

  A ship on its base sits still until it thrusts, and for three seconds after it appears
  there — on joining, on respawning and at a new round — nothing can hit it; it shows
  its shield meanwhile. With limited lives, a ship whose lives are
  gone stays out until the round ends: when one ship (one team, with `teamplay`) is left
  standing among two or more, it is told it won and `round_over_in` counts down four
  seconds; then, or at once when nobody is left, a new round starts and everyone is back
  on their base with their lives, scores kept.
  """

  @behaviour Cauldron2D.Game

  alias Cauldron2D.{Body, Collision, Particles, Rng}
  alias Cauldron2D.Collision.Buckets
  alias ExPilot.Map, as: Arena
  alias ExPilot.{Ball, Gear, Items, Race, Ship, Targets, Weapons}

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
            settings: %{},
            items: [],
            balls: [],
            targets: [],
            beams: [],
            lasered: [],
            messages: [],
            team_bonus: %{},
            round_over_in: nil

  @turn_rate 60.0
  @thrust 14.0
  @max_speed 18.0
  @drag 0.05
  @thrust_burn 25.0
  @shield_burn 25.0
  @shot_cost 0.5
  @refuel_rate 1200.0
  @refuel_reach 2.0
  @round_pause 4.0
  @wall_bounce_fuel 25.0
  @messages_kept 8
  @message_life 12.0
  @respawn_after 3.0
  @spawn_immunity 3.0
  @starve_after 10.0
  @stun_time 3.0
  @cannon_range 12.0
  @cannon_cooldown 1.5
  @shot_radius 0.1
  @point_gravity 0.75
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
      balls: if(Arena.option(arena, :teamplay), do: Ball.new(arena), else: []),
      targets: if(Arena.option(arena, :targets), do: Targets.new(arena), else: []),
      settings:
        Map.merge(item_options(arena), %{
          wrap?: Arena.wrap?(arena),
          shot_speed: Arena.option(arena, :shotspeed) * 50 / 35,
          shot_life: Arena.option(arena, :shotlife) / 50,
          lives: Keyword.get(opts, :lives, lives_option(arena)),
          teamplay?: Arena.option(arena, :teamplay),
          team_immunity?: Arena.option(arena, :teamimmunity),
          max_shots: Arena.option(arena, :maxplayershots),
          crash_speed: Arena.option(arena, :maxunshieldedwallbouncespeed) * 50 / 35,
          shielded_crash_speed: Arena.option(arena, :maxshieldedwallbouncespeed) * 50 / 35,
          bounce_fuel: @wall_bounce_fuel * Arena.option(arena, :wallbouncefueldrainmult),
          race?: Arena.option(arena, :racemode),
          laps: Arena.option(arena, :racelaps),
          checkpoints: Arena.checkpoints(arena),
          checkpoint_reach: Arena.option(arena, :checkpointradius) / 1,
          shields?: Arena.option(arena, :allowshields),
          kit: Items.kit(arena),
          shots_bounce?: Arena.option(arena, :shotswallbounce),
          shots_gravity?: Arena.option(arena, :shotsgravity),
          drag: @drag + friction_drag(Arena.option(arena, :friction)),
          killing?: Arena.option(arena, :allowplayerkilling) and Arena.option(arena, :playerkillings),
          crashes?: Arena.option(arena, :allowplayercrashes),
          ship_bounces?: Arena.option(arena, :allowplayerbounces),
          bounce_keep: Arena.option(arena, :playerwallbouncebrakefactor) / 1,
          target_kill_team?: Arena.option(arena, :targetkillteam),
          treasure_kill_team?: Arena.option(arena, :treasurekillteam),
          drop_prob: min(1.0, Arena.option(arena, :dropitemonkillprob) / 1),
          stun_laser?: Arena.option(arena, :laserisstungun),
          mine_fuse: Arena.option(arena, :minefusetime) / 50,
          fire_cooldown: Arena.option(arena, :firerepeatrate) / 50,
          shielded_pickup?: Arena.option(arena, :shieldeditempickup),
          shielded_mining?: Arena.option(arena, :shieldedmining),
          balls_bounce?: Arena.option(arena, :ballswallbounce),
          players_on_radar?: Arena.option(arena, :playersonradar),
          mode: mode(arena)
        })
    }
  end

  @doc """
  What kind of arena a map makes: `:ctf` (teams and treasures), `:race`, `:team` (teams
  without treasures) or `:dogfight` (everyone for themselves).
  """
  @spec mode(Arena.t()) :: :ctf | :race | :team | :dogfight
  def mode(%Arena{} = arena) do
    cond do
      Arena.option(arena, :racemode) -> :race
      Arena.option(arena, :teamplay) and Arena.treasures(arena) != [] -> :ctf
      Arena.option(arena, :teamplay) -> :team
      true -> :dogfight
    end
  end

  defp friction_drag(friction) when friction <= 0.0, do: 0.0
  defp friction_drag(friction) when friction >= 1.0, do: 1000.0
  defp friction_drag(friction), do: -:math.log(1.0 - friction) * 50

  defp item_options(arena) do
    options = for kind <- Items.kinds(), option = Items.option(kind), into: %{}, do: {option, Arena.option(arena, option)}
    Map.merge(options, %{itemprobmult: Arena.option(arena, :itemprobmult), maxitemdensity: Arena.option(arena, :maxitemdensity)})
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
    strength = -Arena.option(arena, :gravity) * @gravity_scale
    angle = Arena.option(arena, :gravityangle) * :math.pi() / 180

    uniform =
      if Arena.option(arena, :gravitypointsource),
        do: %{strength: strength, kind: {:toward, Arena.gravity_point(arena)}},
        else: %{strength: strength, kind: {:uniform, {exact(-:math.cos(angle)), exact(:math.sin(angle))}}}

    points =
      for %{pos: {x, y}, kind: kind} <- Arena.gravity_points(arena) do
        point_field({x + 0.5, y + 0.5}, kind)
      end

    [uniform | points]
  end

  defp exact(value) when abs(value) < 1.0e-9, do: 0.0
  defp exact(value), do: value

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
        {:ok, %{game | watchers: Map.put(game.watchers, id, %{focus: centre(game), held: MapSet.new(), watching: nil})}}

      Map.has_key?(game.ships, id) ->
        {:error, :already_joined}

      true ->
        case seat(game, props) do
          nil ->
            {:error, :full}

          {game, %{pos: base, team: team, dir: dir}} ->
            ship =
              Ship.new(id, Map.get(props, :username, name_of(id)), base,
                team: team,
                dir: dir,
                robot?: Map.get(props, :robot?, false),
                lives: game.settings.lives,
                shape: Map.get(props, :shape)
              )

            {:ok, %{game | ships: Map.put(game.ships, id, spawned(ship, game))}}
        end
    end
  end

  defp seat(game, props) do
    case free_base(game, wanted_team(props)) do
      nil -> evict_robot(game, props)
      base -> {game, base}
    end
  end

  defp name_of(id) when is_binary(id), do: id
  defp name_of(id) when is_atom(id), do: Atom.to_string(id)
  defp name_of(id), do: inspect(id)

  defp centre(%__MODULE__{arena: arena}) do
    {w, h} = Arena.size(arena)
    {w / 2, h / 2}
  end

  defp evict_robot(_game, %{robot?: true}), do: nil

  defp evict_robot(game, props) do
    wanted = wanted_team(props)
    robots = game.ships |> Map.values() |> Enum.filter(& &1.robot?) |> Enum.sort_by(& &1.name, :desc)

    case Enum.find(robots, fn robot -> wanted == nil or robot.team == nil or robot.team == wanted end) do
      nil ->
        nil

      robot ->
        freed = %{game | ships: Map.delete(game.ships, robot.id)} |> tell("#{robot.name} made room for #{Map.get(props, :username, "a player")}")
        {freed, Enum.find(Arena.bases(game.arena), &(&1.pos == robot.base))}
    end
  end

  defp wanted_team(%{team: team}) when is_binary(team) do
    case Integer.parse(team) do
      {number, ""} -> number
      _ -> nil
    end
  end

  defp wanted_team(props), do: Map.get(props, :team)

  defp free_base(game, nil) do
    crews = game.ships |> Map.values() |> Enum.frequencies_by(& &1.team)
    game |> free_bases() |> Enum.min_by(&Map.get(crews, &1.team, 0), fn -> nil end)
  end

  defp free_base(game, wanted_team) do
    game |> free_bases() |> Enum.find(fn base -> base.team == nil or base.team == wanted_team end)
  end

  defp free_bases(game) do
    taken = game.ships |> Map.values() |> MapSet.new(& &1.base)
    game.arena |> Arena.bases() |> Enum.reject(&MapSet.member?(taken, &1.pos))
  end

  @impl true
  def leave(%__MODULE__{} = game, id) do
    %{game | ships: Map.delete(game.ships, id), watchers: Map.delete(game.watchers, id)}
  end

  @impl true
  def handle_input(%__MODULE__{} = game, id, %{held: held} = input) do
    case {Map.fetch(game.ships, id), Map.fetch(game.watchers, id)} do
      {{:ok, ship}, _} ->
        watching = if pressed?(held, ship.held, :next_watch), do: next_watch(game, id, watched(game, ship)), else: ship.watching
        %{game | ships: Map.put(game.ships, id, %{ship | held: held, aim: Map.get(input, :aim), watching: watching})}

      {:error, {:ok, watcher}} ->
        watching = if pressed?(held, watcher.held, :next_watch), do: next_watch(game, id, chosen(game, watcher.watching)), else: watcher.watching
        %{game | watchers: Map.put(game.watchers, id, %{watcher | held: held, watching: watching})}

      _ ->
        game
    end
  end

  defp pressed?(held, before, action), do: MapSet.member?(held, action) and not MapSet.member?(before, action)

  defp next_watch(game, id, current) do
    flying = game.ships |> Map.values() |> Enum.filter(&(&1.id != id and &1.alive?)) |> Enum.sort_by(& &1.name)

    case {flying, current} do
      {[], _} -> nil
      {_, nil} -> hd(flying).id
      {_, %{id: current_id}} -> Enum.at(flying, rem((Enum.find_index(flying, &(&1.id == current_id)) || -1) + 1, length(flying))).id
    end
  end

  defp chosen(game, id) do
    case Map.get(game.ships, id) do
      %{alive?: true} = ship -> ship
      _ -> nil
    end
  end

  defp watched(game, me), do: chosen(game, me.watching) || nearest_living(game, me)

  @impl true
  def step(%__MODULE__{} = game, dt) do
    %{game | beams: [], lasered: []}
    |> Map.update!(:time, &(&1 + dt))
    |> fly_ships(dt)
    |> collide_ships()
    |> strike_lasered()
    |> fly_shots(dt)
    |> fire_cannons(dt)
    |> spawn_items(dt)
    |> roll_balls(dt)
    |> Map.update!(:targets, &Targets.step(&1, dt))
    |> Map.update!(:messages, &Enum.filter(&1, fn {at, _} -> at + @message_life > game.time end))
    |> Map.update!(:particles, &Particles.step(&1, dt, drag: 0.5))
    |> maybe_new_round(dt)
  end

  defp spawn_items(game, dt) do
    {items, rng} = Items.spawn(game.items, game.arena, game.rng, dt, game.settings)
    %{game | items: items, rng: rng}
  end

  defp roll_balls(%{balls: []} = game, _dt), do: game

  defp roll_balls(game, dt) do
    env = %{grid: Arena.grid(game.arena), fields: game.fields, size: Arena.size(game.arena), wrap?: game.settings.wrap?, bounce?: game.settings.balls_bounce?}
    {balls, ships} = Ball.step(game.balls, game.ships, dt, env)
    ships = Enum.reduce(balls, ships, fn ball, ships -> pair_ball(ships, ball) end)
    {balls, scored} = Ball.deliver(balls, ships, game.arena)

    Enum.reduce(scored, %{game | balls: balls, ships: ships}, fn {carrier, team, points, against}, acc ->
      acc
      |> award(carrier, team, points)
      |> Map.update!(:ships, &Map.update!(&1, carrier, fn ship -> %{ship | ball: nil} end))
      |> emit({:goal, Map.fetch!(acc.ships, carrier).body.pos})
      |> tell("#{Map.fetch!(acc.ships, carrier).name} scored for team #{team}")
      |> fall_of_treasure(against)
    end)
  end

  defp fall_of_treasure(%{settings: %{treasure_kill_team?: false}} = game, _team), do: game
  defp fall_of_treasure(game, nil), do: game
  defp fall_of_treasure(game, team), do: kill_team(game, team, "team #{team} lost its treasure")

  defp pair_ball(ships, %{carrier: nil}), do: ships

  defp pair_ball(ships, %{carrier: carrier, id: id}) do
    case Map.get(ships, carrier) do
      %{ball: nil} = ship -> Map.put(ships, carrier, %{ship | ball: id})
      _ -> ships
    end
  end

  defp award(game, scorer, team, points) do
    ships = Map.update!(game.ships, scorer, fn ship -> %{ship | score: ship.score + points} end)
    bonus = if team, do: Map.update(game.team_bonus, team, points, &(&1 + points)), else: game.team_bonus
    %{game | ships: ships, team_bonus: bonus}
  end

  defp tell(game, text), do: %{game | messages: Enum.take([{game.time, text} | game.messages], @messages_kept)}

  defp collide_ships(%{settings: %{crashes?: false, ship_bounces?: false}} = game), do: game

  defp collide_ships(game) do
    flying = game.ships |> Map.values() |> Enum.filter(&(&1.alive? and not Gear.phasing?(&1, game.time))) |> Enum.sort_by(& &1.name)

    for {first, index} <- Enum.with_index(flying), second <- Enum.drop(flying, index + 1), reduce: game do
      acc ->
        case {Map.get(acc.ships, first.id), Map.get(acc.ships, second.id)} do
          {%{alive?: true} = one, %{alive?: true} = other} ->
            if Collision.circles_overlap?(one.body.pos, Ship.radius(), other.body.pos, Ship.radius()), do: collide(acc, one, other), else: acc

          _ ->
            acc
        end
    end
  end

  defp collide(game, one, other) do
    {one, other} = if game.settings.ship_bounces?, do: rebound(one, other), else: {one, other}
    game = %{game | ships: game.ships |> Map.put(one.id, one) |> Map.put(other.id, other)}
    guarded = fn ship -> Gear.shielded?(ship, game.time) or ship.deflecting? or immune?(ship, game.time) end
    dying = if game.settings.crashes?, do: Enum.reject([one, other], guarded), else: []

    case dying do
      [] ->
        emit(game, {:bounce, one.body.pos})

      lost ->
        Enum.reduce(lost, game, fn ship, acc -> lose(acc, Map.fetch!(acc.ships, ship.id), "#{one.name} and #{other.name} collided") end)
    end
  end

  defp rebound(one, other) do
    {ax, ay} = one.body.pos
    {bx, by} = other.body.pos
    {dx, dy} = {bx - ax, by - ay}
    distance = max(:math.sqrt(dx * dx + dy * dy), 1.0e-6)
    {nx, ny} = {dx / distance, dy / distance}
    {avx, avy} = one.body.vel
    {bvx, bvy} = other.body.vel
    along_a = avx * nx + avy * ny
    along_b = bvx * nx + bvy * ny
    gap = (Ship.radius() * 2 - distance) / 2 + 0.01

    {
      %{one | body: %{one.body | vel: {avx + (along_b - along_a) * nx, avy + (along_b - along_a) * ny}, pos: {ax - nx * gap, ay - ny * gap}}},
      %{other | body: %{other.body | vel: {bvx + (along_a - along_b) * nx, bvy + (along_a - along_b) * ny}, pos: {bx + nx * gap, by + ny * gap}}}
    }
  end

  defp strike_lasered(%{lasered: []} = game), do: game

  defp strike_lasered(game) do
    Enum.reduce(Enum.reverse(game.lasered), game, fn {shooter, victim, at}, acc ->
      case Map.get(acc.ships, victim) do
        %{alive?: true} = ship ->
          cond do
            Items.has?(ship, :mirror) -> emit(acc, {:bounce, at})
            acc.settings.stun_laser? -> %{acc | ships: Map.put(acc.ships, victim, %{ship | ecm_until: acc.time + @stun_time})} |> emit({:ecm, at})
            true -> strike(acc, shooter, victim, at, :laser)
          end

        _ ->
          acc
      end
    end)
  end

  defp maybe_new_round(%{ships: ships} = game, _dt) when map_size(ships) == 0, do: game
  defp maybe_new_round(%{settings: %{lives: :unlimited}} = game, _dt), do: game

  defp maybe_new_round(%{round_over_in: nil} = game, _dt) do
    case standing(game) do
      [] -> new_round(game)
      [winner] when map_size(game.ships) > 1 -> %{game | round_over_in: @round_pause} |> tell(winner <> " won the round")
      _several -> game
    end
  end

  defp maybe_new_round(%{round_over_in: left} = game, dt) when left > dt, do: %{game | round_over_in: left - dt}
  defp maybe_new_round(game, _dt), do: new_round(game)

  defp new_round(game) do
    ships = Map.new(game.ships, fn {id, ship} -> {id, spawned(Ship.new_round(ship, game.settings.lives), game)} end)
    %{game | ships: ships, round_over_in: nil} |> emit({:round, centre(game)})
  end

  defp standing(%{settings: %{teamplay?: true}} = game) do
    game.ships |> Map.values() |> Enum.reject(&out?/1) |> Enum.uniq_by(& &1.team) |> Enum.map(&"team #{&1.team}")
  end

  defp standing(game), do: game.ships |> Map.values() |> Enum.reject(&out?/1) |> Enum.map(& &1.name)

  defp fly_ships(game, dt) do
    Enum.reduce(game.ships, game, fn {id, _}, acc -> fly_ship(acc, id, dt) end)
  end

  defp fly_ship(game, id, dt) do
    ship = Map.fetch!(game.ships, id)

    if ship.alive? do
      before = ship.held_before
      ship = %{ship | held_before: ship.held}

      {ship, game} =
        ship
        |> steer(dt, game.time)
        |> propel(dt, game)
        |> fire(dt, game)
        |> Gear.use(dt, before)
        |> move(dt, game)

      ship = Gear.wear(ship, dt, game.time)
      game = %{game | ships: Map.put(game.ships, id, ship)}
      game |> refuel(id, dt) |> warp(id) |> pick_up(id) |> race(id) |> starve(id)
    else
      countdown(game, id, dt)
    end
  end

  defp starve(game, id) do
    ship = Map.fetch!(game.ships, id)

    cond do
      ship.fuel > 0 -> %{game | ships: Map.put(game.ships, id, %{ship | empty_since: nil})}
      ship.empty_since == nil -> %{game | ships: Map.put(game.ships, id, %{ship | empty_since: game.time})}
      game.time - ship.empty_since < @starve_after -> game
      true -> lose(game, ship, "#{ship.name} ran out of fuel")
    end
  end

  defp lose(game, ship, message) do
    {dead, game} = explode({ship, game})
    %{game | ships: Map.put(game.ships, ship.id, dead)} |> tell(message)
  end

  defp pick_up(game, id) do
    ship = Map.fetch!(game.ships, id)

    case Items.take_at(game.items, ship.body.pos) do
      {nil, _} -> game
      {_item, _} when ship.shielding? and not game.settings.shielded_pickup? -> game
      {%{kind: kind}, rest} -> %{game | items: rest, ships: Map.put(game.ships, id, Items.pick_up(ship, kind))} |> emit({:pick_up, ship.body.pos})
    end
  end

  defp race(%{settings: %{race?: false}} = game, _id), do: game

  defp race(game, id) do
    ship = Map.fetch!(game.ships, id)
    passed = Race.pass(ship, game.settings.checkpoints, game.settings.laps, game.settings.checkpoint_reach)

    cond do
      passed.finished? and not ship.finished? -> %{game | ships: Map.put(game.ships, id, passed)} |> emit({:finish, ship.body.pos}) |> tell("#{ship.name} finished")
      passed.checkpoint != ship.checkpoint or passed.laps != ship.laps -> %{game | ships: Map.put(game.ships, id, passed)} |> emit({:checkpoint, ship.body.pos})
      true -> game
    end
  end

  defp steer(%Ship{} = ship, dt, now) do
    steps = round(@turn_rate * dt)

    cond do
      Gear.confused?(ship, now) -> ship
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
      shielding? = shielding?(ship, game)
      burn = if shielding?, do: @shield_burn * dt, else: 0.0

      {%{ship | cooldown: max(0.0, ship.cooldown - dt), shielding?: shielding?, thrusting?: false, fuel: max(0.0, ship.fuel - burn)}, game}
    end
  end

  defp propel(%Ship{} = ship, dt, game) do
    thrusting? = Ship.holding?(ship, :thrust) and (ship.fuel > 0 or ship.emergency_thrust_until > game.time)
    shielding? = shielding?(ship, game)

    body = if thrusting?, do: Body.thrust(ship.body, @thrust * Gear.thrust_factor(ship, game.time), dt), else: ship.body
    burn = (if thrusting? and ship.emergency_thrust_until <= game.time, do: @thrust_burn, else: 0.0) + if shielding?, do: @shield_burn, else: 0.0

    ship = %{
      ship
      | body: body |> Body.gravitate(game.fields, dt) |> Body.drag(game.settings.drag, dt) |> Body.cap_speed(@max_speed),
        fuel: max(0.0, ship.fuel - burn * dt),
        thrusting?: thrusting?,
        shielding?: shielding?,
        cooldown: max(0.0, ship.cooldown - dt)
    }

    if thrusting?, do: {ship, exhaust(game, ship)}, else: {ship, game}
  end

  defp shielding?(ship, game), do: game.settings.shields? and Ship.holding?(ship, :shield) and ship.fuel > 0

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
    if Ship.holding?(ship, :fire) and not Gear.confused?(ship, game.time) and ship.cooldown <= 0 and ship.fuel >= @shot_cost and
         shots_of(game, ship.id) < game.settings.max_shots do
      spread = if Items.has?(ship, :wideangle), do: [0, 3, -3], else: [0]
      directions = Enum.map(spread, &Body.direction(Body.turn(ship.body, &1)))
      directions = if Items.has?(ship, :rearshot), do: [{-elem(hd(directions), 0), -elem(hd(directions), 1)} | directions], else: directions

      {shots, next_id} =
        Enum.map_reduce(directions, game.next_id, fn {dx, dy}, id ->
          {x, y} = ship.body.pos
          {vx, vy} = ship.body.vel
          speed = game.settings.shot_speed
          {%{id: id, owner: ship.id, kind: :shot, body: Body.new(pos: {x + dx * 0.6, y + dy * 0.6}, vel: {vx + dx * speed, vy + dy * speed}, radius: @shot_radius), life: game.settings.shot_life}, id + 1}
        end)

      game = %{game | shots: shots ++ game.shots, next_id: next_id} |> emit({:fire, ship.body.pos})
      {%{ship | cooldown: game.settings.fire_cooldown, fuel: ship.fuel - @shot_cost}, game}
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

    if Gear.phasing?(ship, game.time) do
      {%{ship | body: wrapped(%{ship.body | pos: to}, game)}, game}
    else
      case Collision.sweep(grid, from, to, Ship.radius()) do
        {:clear, at} ->
          {%{ship | body: wrapped(%{ship.body | pos: at}, game)}, game}

        {:blocked, at, normal, _cell} ->
          shielded? = Gear.shielded?(ship, game.time)
          limit = if shielded?, do: game.settings.shielded_crash_speed, else: game.settings.crash_speed

          if Body.speed(ship.body) <= limit,
            do: bounce(ship, game, at, normal, shielded?),
            else: crash(ship, game, at)
      end
    end
  end

  defp crash(ship, game, at) do
    {dead, game} = explode({%{ship | body: %{ship.body | pos: at}}, game})
    {dead, tell(game, "#{ship.name} hit a wall")}
  end

  defp bounce(ship, game, at, normal, shielded?) do
    body = %{ship.body | pos: at, vel: Collision.bounce(ship.body.vel, normal, game.settings.bounce_keep)}
    fuel = if shielded?, do: ship.fuel, else: max(0.0, ship.fuel - game.settings.bounce_fuel)
    {%{ship | body: wrapped(body, game), fuel: fuel}, emit(game, {:bounce, at})}
  end

  defp wrapped(body, %{settings: %{wrap?: true}, arena: arena}), do: Body.wrap(body, Arena.size(arena))
  defp wrapped(body, _game), do: body

  defp explode({ship, game}) do
    pos = ship.body.pos
    {debris, rng} = debris(game.rng, pos, 24)
    {items, rng} = Items.drop(game.items, ship, game.settings.drop_prob, rng)
    game = %{game | rng: rng, items: items, particles: Particles.spawn(game.particles, debris)} |> emit({:explosion, pos})
    {%{Ship.die(ship, @respawn_after) | ball: nil}, game}
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

    if near? and ship.fuel < ship.max_fuel do
      filled = min(ship.max_fuel, ship.fuel + @refuel_rate * dt)
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
        revived = spawned(Ship.respawn(ship), game)
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

  defp advance_shot(game, %{kind: :mine} = mine, dt, _grid, buckets, kept) do
    life = mine.life - dt
    mine = %{mine | life: life, armed_in: mine.armed_in - dt}

    cond do
      life <= 0 ->
        {game, kept}

      not Weapons.armed?(mine) ->
        {game, [mine | kept]}

      true ->
        case Enum.reject(Buckets.near(buckets, mine.body.pos, mine.body.radius), &(&1 == mine.owner)) do
          [] -> {game, [mine | kept]}
          [victim | _] -> {game |> strike(mine.owner, victim, mine.body.pos, :mine) |> emit({:explosion, mine.body.pos}), kept}
        end
    end
  end

  defp advance_shot(game, shot, dt, grid, buckets, kept) do
    life = shot.life - dt
    from = shot.body.pos
    shot = Weapons.steer(shot, Map.values(game.ships), dt, game.settings.shot_speed)
    pulled = if game.settings.shots_gravity?, do: Body.gravitate(shot.body, game.fields, dt), else: shot.body
    to = Body.integrate(pulled, dt)

    cond do
      life <= 0 ->
        {game, kept}

      true ->
        case Collision.sweep(grid, from, to.pos, shot.body.radius) do
          {:blocked, at, normal, _cell} when game.settings.shots_bounce? ->
            {game, [%{shot | body: wrapped(%{to | pos: at, vel: Collision.bounce(to.vel, normal, 0.9)}, game), life: life} | kept]}

          {:blocked, at, _normal, _cell} ->
            {emit(game, {:shot_wall, at}), kept}

          {:clear, at} ->
            moved = %{shot | body: wrapped(%{to | pos: at}, game), life: life}

            case target_hit(game, shot, moved.body.pos) do
              {:hit, game} ->
                {game, kept}

              :miss ->
                case Enum.reject(Buckets.near(buckets, moved.body.pos, shot.body.radius), &(&1 == shot.owner or not hittable?(game, shot.owner, &1))) do
                  [] -> {game, [moved | kept]}
                  [victim | _] -> {strike(game, shot.owner, victim, moved.body.pos, shot.kind), kept}
                end
            end
        end
    end
  end

  defp target_hit(%{targets: []}, _shot, _pos), do: :miss

  defp target_hit(game, shot, pos) do
    cell = Collision.cell_of(pos)

    if Targets.standing?(game.targets, cell) do
      case Targets.hit(game.targets, cell, team_of(game, shot.owner)) do
        {_targets, :none} ->
          :miss

        {targets, :hit} ->
          {:hit, %{game | targets: targets} |> emit({:target_hit, pos})}

        {targets, {:destroyed, team, points}} ->
          game = %{game | targets: targets} |> emit({:target_destroyed, pos})
          game = if is_map_key(game.ships, shot.owner), do: game |> award(shot.owner, team, points) |> tell("#{name_of_ship(game, shot.owner)} destroyed a target"), else: game
          {:hit, fall_of_targets(game, cell)}
      end
    else
      :miss
    end
  end

  defp fall_of_targets(%{settings: %{target_kill_team?: false}} = game, _cell), do: game

  defp fall_of_targets(game, cell) do
    case Enum.find(game.targets, &(&1.pos == cell)) do
      %{team: team} when team != nil ->
        if Targets.standing_for?(game.targets, team), do: game, else: kill_team(game, team, "team #{team} lost its last target")

      _ ->
        game
    end
  end

  defp kill_team(game, team, message) do
    game.ships
    |> Map.values()
    |> Enum.filter(&(&1.alive? and &1.team == team))
    |> Enum.reduce(tell(game, message), fn ship, acc -> lose(acc, Map.fetch!(acc.ships, ship.id), "#{ship.name} went down with the team") end)
  end

  defp team_of(game, owner) do
    case Map.get(game.ships, owner) do
      %{team: team} -> team
      _ -> nil
    end
  end

  defp name_of_ship(game, id) do
    case Map.get(game.ships, id) do
      %{name: name} -> name
      _ -> "a cannon"
    end
  end

  defp hittable?(game, owner, victim_id) do
    case {Map.get(game.ships, owner), Map.get(game.ships, victim_id)} do
      {%{} = shooter, %{} = victim} -> Gear.hittable?(game.settings, shooter, victim)
      _ -> true
    end
  end

  defp strike(game, owner, victim_id, pos, kind) do
    victim = Map.fetch!(game.ships, victim_id)

    cond do
      not victim.alive? ->
        game

      Gear.phasing?(victim, game.time) ->
        game

      Gear.shielded?(victim, game.time) or victim.deflecting? or immune?(victim, game.time) ->
        emit(game, {:bounce, pos})

      not game.settings.killing? and not match?({:cannon, _}, owner) ->
        emit(game, {:bounce, pos})

      victim.armour > 0 ->
        %{game | ships: Map.put(game.ships, victim_id, %{victim | armour: victim.armour - 1})} |> emit({:bounce, pos})

      true ->
        {dead, game} = explode({victim, game})
        game = %{game | ships: Map.put(game.ships, victim_id, dead)} |> emit({:kill, pos})
        game |> credit(owner) |> tell(kill_message(game, owner, victim, kind))
    end
  end

  defp kill_message(game, owner, victim, kind) do
    killer = name_of_ship(game, owner)

    case kind do
      :shot -> "#{killer} shot #{victim.name}"
      :mine -> "#{victim.name} hit #{killer}'s mine"
      :laser -> "#{killer} lasered #{victim.name}"
      _missile -> "#{killer}'s missile hit #{victim.name}"
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
    |> Enum.filter(&(&1.alive? and not &1.cloaked?))
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
      kind: :shot,
      body: Body.new(pos: {mx + (tx - mx) / length, my + (ty - my) / length}, vel: vel, radius: @shot_radius),
      life: game.settings.shot_life * 2
    }

    %{game | shots: [shot | game.shots], next_id: game.next_id + 1} |> emit({:cannon, muzzle})
  end

  @impl true
  def view(%__MODULE__{} = game, id) do
    me = Map.get(game.ships, id)
    watching = watched_by(game, id, me)

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
      radar: %{players?: game.settings.players_on_radar?},
      rules: %{shields?: game.settings.shields?, crash_speed: game.settings.crash_speed},
      mode: game.settings.mode,
      others_out?: me != nil and map_size(game.ships) > 1 and Enum.all?(game.ships, fn {other, ship} -> other == id or out?(ship) end),
      round_over?: game.round_over_in != nil,
      enemies: Enum.count(game.ships, fn {other, ship} -> other != id and not out?(ship) end),
      ships: for({_, ship} <- game.ships, ship.alive?, visible?(ship, me), do: seen(ship, game.time)),
      shots: for(%{kind: :shot, body: %{pos: pos}} <- game.shots, do: pos),
      missiles: for(%{kind: kind, body: %{pos: pos, vel: vel}} <- game.shots, kind in [:torpedo, :smart, :heat], do: {kind, pos, vel}),
      mines: for(%{kind: :mine, body: %{pos: pos}} <- game.shots, do: pos),
      items: Enum.map(game.items, &{&1.kind, &1.pos}),
      balls: Enum.map(game.balls, &%{pos: &1.pos, vel: &1.vel, string: &1.carrier && carrier_pos(game, &1.carrier)}),
      beams: game.beams,
      targets_gone: Targets.gone(game.targets),
      particles: Particles.movers(game.particles, {-0.5, -0.5}),
      bounds: Arena.size(game.arena),
      wrap?: game.settings.wrap?,
      arena: Arena.name(game.arena),
      scores: scores(game),
      team_scores: team_scores(game),
      messages: Enum.reverse(game.messages),
      race: race_view(game, me),
      time: game.time
    }
  end

  defp watched_by(game, id, nil) do
    case Map.get(game.watchers, id) do
      %{watching: watching} -> chosen(game, watching)
      nil -> nil
    end
  end

  defp watched_by(game, _id, me), do: if(out?(me), do: watched(game, me), else: nil)

  defp carrier_pos(game, carrier) do
    case Map.get(game.ships, carrier) do
      %{body: %{pos: pos}} -> pos
      nil -> nil
    end
  end

  defp seen(ship, now) do
    summary = Ship.summary(ship)
    %{summary | shielding?: summary.shielding? or immune?(ship, now)}
  end

  defp spawned(ship, game), do: %{Ship.equip(ship, game.settings.kit) | immune_until: game.time + @spawn_immunity}

  defp immune?(ship, now), do: ship.immune_until > now

  defp visible?(ship, me) do
    not ship.cloaked? or (me != nil and (ship.id == me.id or Items.has?(me, :sensor)))
  end

  defp team_scores(%{settings: %{teamplay?: false}}), do: %{}

  defp team_scores(game) do
    game.ships
    |> Map.values()
    |> Enum.reject(&is_nil(&1.team))
    |> Enum.group_by(& &1.team, & &1.score)
    |> Map.new(fn {team, scores} -> {team, Enum.sum(scores) + Map.get(game.team_bonus, team, 0)} end)
  end

  defp race_view(%{settings: %{race?: false}}, _me), do: nil
  defp race_view(_game, nil), do: nil

  defp race_view(game, me) do
    %{lap: me.laps + 1, laps: game.settings.laps, next: me.checkpoint, checkpoints: length(game.settings.checkpoints), finished?: me.finished?}
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
  the view follows the nearest. Once every other ship is out, or the round has ended
  with one ship standing, `%{title: title, lines: lines, next: next}` with the standings
  as lines: `"Victory"` with `next: :next_arena` while the player still flies, `"Defeat"`
  with `next: :same_arena` when they are out. A watcher's view, or one with unlimited
  lives, is never over.
  """
  @spec outcome(map()) :: nil | %{title: String.t(), lines: [String.t()]}
  def outcome(%{me: nil}), do: nil
  def outcome(%{me: %{lives: :unlimited}}), do: nil
  def outcome(%{others_out?: false, round_over?: false}), do: nil

  def outcome(%{me: me, scores: scores}) do
    lines = Enum.map(scores, fn %{name: name, score: score} -> name <> "  " <> Integer.to_string(score) end)

    if me.alive? or me.lives > 0,
      do: %{title: "Victory", lines: lines, next: :next_arena},
      else: %{title: "Defeat", lines: lines, next: :same_arena}
  end

  defp summary_of(ship) do
    ship
    |> Ship.summary()
    |> Map.merge(%{
      fuel: ship.fuel,
      max_fuel: ship.max_fuel,
      lives: ship.lives,
      respawn_in: ship.respawn_in,
      kills: ship.kills,
      deaths: ship.deaths,
      items: ship.items,
      armour: ship.armour,
      missile: ship.missile
    })
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
