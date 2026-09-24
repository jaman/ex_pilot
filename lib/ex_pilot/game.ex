defmodule ExPilot.Game do
  @moduledoc """
  The rules of ExPilot as one pure value, run by `Cauldron2D.World`.

  Ships turn, thrust, fire and shield on held actions — thrust as hard as the input's
  `strength` says, its exhaust as long; gravity from the map and its
  points pulls on them; a wall bounces a ship, at a cost in fuel, unless the ship hits it
  unshielded faster than the map's `maxunshieldedwallbouncespeed`, which is a crash; fuel
  stations refill a ship near them; wormholes move a ship elsewhere; cannons on the map
  fire at ships in front of them, and die to any shot, missile or mine that reaches
  them — `cannonpoints` to the shooter whose score is under `cannonmaxscore`, the
  cannon back after `cannondeadtime` frames; a ship that touches a cannon kills it and
  is smashed unless it has both its shield and an emergency shield up, in which case it
  takes the points; a shot kills an unshielded ship it meets unless armour
  takes it; two ships that meet crash unless shielded, and shielded ships bounce apart.
  A ship whose tank has been empty for ten seconds, flying or sitting on its base, is
  lost as if it had crashed. A dead ship comes back on its base a few seconds later;
  its pilot's view says what killed it in `me.epitaph` (`"shot by alice"`, `"hit a
  wall"`, `"hit bob's mine"`, `"collided with carol"`, `"ran out of fuel"`…) from the
  death until two seconds after the respawn, `nil` otherwise.
  Watchers join with `spectate: true` and see the arena without a ship.

  ## Fuel

  The numbers are XPilot's, per frame at the map's `framespersecond` (`ExPilot.Map`).
  A ship thrusts with power 55 over its mass — the map's `shipmass` plus 0.005 a unit
  of fuel and a fourteenth of it per armour — and no faster than 65 pixels a frame.
  Thrust burns `power × 0.0008` a frame, a shield 0.2 a frame and a shot 0.2; a shot a
  shield takes costs 25, a laser 100, a missile or mine 120, and meeting another shielded
  ship 100 each; an unshielded bounce off a wall costs by speed and mass, scaled by
  `wallbouncefueldrainmult`. A shield needs fuel, and is down while the ship holds
  fire or its laser; nothing fires from behind an emergency shield, and firing ends the
  immunity a ship has just after it appears. A tank holds 2600. A fuel station holds 500, gives 5 a frame to a
  ship within reach, and refills 0.06 a frame for every ship in the arena.

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
  `timing`, ships pass the checkpoints in order (`ExPilot.Race`). What happens is told
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
  `{:hyperjump, pos}`, `{:target_hit, pos}`, `{:target_destroyed, pos}`,
  `{:cannon_destroyed, pos}`, `{:cannon_back, pos}`, `{:goal, pos}`,
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
  alias ExPilot.{Ball, Gear, Items, Race, Ship, Targets, Weapons}
  alias ExPilot.Map, as: Arena

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
            stations: %{},
            team_bonus: %{},
            round_over_in: nil,
            won_by: nil

  @turn_rate 60.0
  @power 55.0
  @speed_limit 65.0
  @thrust_fuel 0.0008
  @shield_fuel 0.2
  @shot_fuel 0.2
  @shot_hit_fuel 25.0
  @laser_hit_fuel 100.0
  @missile_hit_fuel 120.0
  @crash_fuel 100.0
  @fuel_mass 0.005
  @armour_mass_share 14
  @refuel_rate 5.0
  @station_fuel 500.0
  @station_regeneration 0.06
  @refuel_reach 2.0
  @round_pause 4.0
  @messages_kept 8
  @message_life 12.0
  @respawn_after 3.0
  @epitaph_lingers 2.0
  @spawn_immunity 3.0
  @starve_after 10.0
  @stun_time 3.0
  @cannon_range 12.0
  @cannon_cooldown 1.5
  @shot_radius 0.1
  @point_gravity 0.75
  @particle_cap 300

  @doc """
  A new game on an arena.

  ## Options

    * `:arena` — an `ExPilot.Map`, or a path to a map file. Required
    * `:seed` — for the game's own randomness. Default: unique
    * `:lives` — lives per ship, or `:unlimited`. Default: the map's `limitedlives` and
      `worldlives`
    * `:only` — the names allowed to fly; anyone else may only watch (`:not_invited`).
      Default: everyone
    * `:first_to` — a duel: the first ship to that many kills in the round wins it, the
      match is over for good, and `outcome/1` tells both sides. Default: none
  """
  @impl true
  def init(opts) do
    arena = load(Keyword.fetch!(opts, :arena))
    seed = Keyword.get(opts, :seed, :erlang.unique_integer([:positive]))

    %__MODULE__{
      arena: arena,
      particles: Particles.new(@particle_cap),
      cannons: Enum.map(Arena.cannons(arena), &Map.merge(&1, %{cooldown: 0.0, dead_until: nil})),
      fields: fields(arena),
      stations: Map.new(Arena.fuel(arena), &{&1, @station_fuel}),
      rng: Rng.new(seed),
      balls: if(Arena.option(arena, :teamplay), do: Ball.new(arena), else: []),
      targets: if(Arena.option(arena, :targets), do: Targets.new(arena), else: []),
      settings:
        Map.merge(item_options(arena), %{
          wrap?: Arena.wrap?(arena),
          shot_speed: Arena.speed(arena, Arena.option(arena, :shotspeed)),
          shot_life: Arena.seconds(arena, Arena.option(arena, :shotlife)),
          max_speed: Arena.speed(arena, @speed_limit),
          ship_mass: Arena.option(arena, :shipmass) / 1,
          thrust_burn: Arena.per_second(arena, @power * @thrust_fuel),
          shield_burn: Arena.per_second(arena, @shield_fuel),
          refuel_rate: Arena.per_second(arena, @refuel_rate),
          station_regeneration: Arena.per_second(arena, @station_regeneration),
          lives: Keyword.get(opts, :lives, lives_option(arena)),
          only: Keyword.get(opts, :only),
          first_to: Keyword.get(opts, :first_to),
          teamplay?: Arena.option(arena, :teamplay),
          team_immunity?: Arena.option(arena, :teamimmunity),
          max_shots: Arena.option(arena, :maxplayershots),
          crash_speed: Arena.speed(arena, Arena.option(arena, :maxunshieldedwallbouncespeed)),
          shielded_crash_speed:
            Arena.speed(arena, Arena.option(arena, :maxshieldedwallbouncespeed)),
          bounce_drain: Arena.option(arena, :wallbouncefueldrainmult) / 1,
          race?: Arena.option(arena, :timing),
          laps: Arena.option(arena, :racelaps),
          checkpoints: Arena.checkpoints(arena),
          checkpoint_reach: Arena.option(arena, :checkpointradius) / 1,
          cannon_dead_time: Arena.seconds(arena, Arena.option(arena, :cannondeadtime)),
          cannon_points: Arena.option(arena, :cannonpoints),
          cannon_max_score: Arena.option(arena, :cannonmaxscore),
          shields?: Arena.shields?(arena),
          kit: Items.kit(arena),
          shots_bounce?: Arena.option(arena, :shotswallbounce),
          shots_gravity?: Arena.option(arena, :shotsgravity),
          drag: Arena.drag(arena, Arena.option(arena, :friction)),
          killing?:
            Arena.option(arena, :allowplayerkilling) and Arena.option(arena, :playerkillings),
          crashes?: Arena.option(arena, :allowplayercrashes),
          ship_bounces?: Arena.option(arena, :allowplayerbounces),
          bounce_keep: Arena.option(arena, :playerwallbouncebrakefactor) / 1,
          target_kill_team?: Arena.option(arena, :targetkillteam),
          treasure_kill_team?: Arena.option(arena, :treasurekillteam),
          drop_prob: min(1.0, Arena.option(arena, :dropitemonkillprob) / 1),
          stun_laser?: Arena.option(arena, :laserisstungun),
          mine_fuse: Arena.seconds(arena, Arena.option(arena, :minefusetime)),
          fire_cooldown: Arena.seconds(arena, Arena.option(arena, :firerepeatrate)),
          shielded_pickup?: Arena.option(arena, :shieldeditempickup),
          shielded_mining?: Arena.option(arena, :shieldedmining),
          balls_bounce?: Arena.option(arena, :ballswallbounce),
          players_on_radar?: Arena.option(arena, :playersonradar),
          mode: if(is_integer(Keyword.get(opts, :first_to)), do: :duel, else: mode(arena))
        })
    }
  end

  @doc """
  What kind of arena a map makes: `:ctf` (teams and treasures), `:race`, `:team` (teams
  without treasures) or `:dogfight` (everyone for themselves); a game with `first_to`
  is a `:duel`.
  """
  @spec mode(Arena.t() | t()) :: :ctf | :race | :team | :dogfight | :duel
  def mode(%__MODULE__{settings: %{first_to: kills}}) when is_integer(kills), do: :duel
  def mode(%__MODULE__{arena: arena}), do: mode(arena)

  def mode(%Arena{} = arena) do
    cond do
      Arena.option(arena, :timing) -> :race
      Arena.option(arena, :teamplay) and Arena.treasures(arena) != [] -> :ctf
      Arena.option(arena, :teamplay) -> :team
      true -> :dogfight
    end
  end

  defp item_options(arena) do
    options =
      for kind <- Items.kinds(),
          option = Items.option(kind),
          into: %{},
          do: {option, Arena.option(arena, option)}

    Map.merge(options, %{
      itemprobmult: Arena.option(arena, :itemprobmult),
      maxitemdensity: Arena.option(arena, :maxitemdensity)
    })
  end

  defp load(%Arena{} = arena), do: arena

  defp load(path) when is_binary(path) do
    {:ok, arena} = Arena.parse_file(path)
    arena
  end

  defp lives_option(arena) do
    if Arena.option(arena, :limitedlives),
      do: max(1, Arena.option(arena, :worldlives)),
      else: :unlimited
  end

  defp fields(arena) do
    strength = Arena.acceleration(arena, -Arena.option(arena, :gravity))
    angle = Arena.option(arena, :gravityangle) * :math.pi() / 180

    uniform =
      if Arena.option(arena, :gravitypointsource),
        do: %{strength: strength, kind: {:toward, Arena.gravity_point(arena)}},
        else: %{
          strength: strength,
          kind: {:uniform, {exact(-:math.cos(angle)), exact(:math.sin(angle))}}
        }

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

  defp point_field(_pos, :down),
    do: %{strength: @point_gravity / 10, kind: {:uniform, {0.0, 1.0}}}

  defp point_field(_pos, :left),
    do: %{strength: @point_gravity / 10, kind: {:uniform, {-1.0, 0.0}}}

  defp point_field(_pos, :right),
    do: %{strength: @point_gravity / 10, kind: {:uniform, {1.0, 0.0}}}

  @impl true
  def join(%__MODULE__{} = game, id, props) do
    cond do
      Map.get(props, :spectate, false) ->
        {:ok,
         %{
           game
           | watchers:
               Map.put(game.watchers, id, %{
                 focus: centre(game),
                 held: MapSet.new(),
                 watching: nil
               })
         }}

      Map.has_key?(game.ships, id) ->
        {:error, :already_joined}

      game.settings.only != nil and
        Map.get(props, :username, name_of(id)) not in game.settings.only and
          not Map.get(props, :robot?, false) ->
        {:error, :not_invited}

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

    robots =
      game.ships |> Map.values() |> Enum.filter(& &1.robot?) |> Enum.sort_by(& &1.name, :desc)

    case Enum.find(robots, fn robot ->
           wanted == nil or robot.team == nil or robot.team == wanted
         end) do
      nil ->
        nil

      robot ->
        freed =
          %{game | ships: Map.delete(game.ships, robot.id)}
          |> tell("#{robot.name} made room for #{Map.get(props, :username, "a player")}")

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
    game =
      case Map.fetch(game.ships, id) do
        {:ok, ship} ->
          {row, _ship} = Ship.result(ship, false)
          emit(game, {:result, Map.put(row, :mode, mode(game))})

        :error ->
          game
      end

    %{game | ships: Map.delete(game.ships, id), watchers: Map.delete(game.watchers, id)}
  end

  @impl true
  def handle_input(%__MODULE__{} = game, id, %{held: held} = input) do
    case {Map.fetch(game.ships, id), Map.fetch(game.watchers, id)} do
      {{:ok, ship}, _} ->
        watching =
          if pressed?(held, ship.held, :next_watch),
            do: next_watch(game, id, watched(game, ship)),
            else: ship.watching

        %{
          game
          | ships:
              Map.put(game.ships, id, %{
                ship
                | held: held,
                  aim: Map.get(input, :aim),
                  strength: Map.get(input, :strength, %{}),
                  watching: watching
              })
        }

      {:error, {:ok, watcher}} ->
        watching =
          if pressed?(held, watcher.held, :next_watch),
            do: next_watch(game, id, chosen(game, watcher.watching)),
            else: watcher.watching

        %{
          game
          | watchers: Map.put(game.watchers, id, %{watcher | held: held, watching: watching})
        }

      _ ->
        game
    end
  end

  defp pressed?(held, before, action),
    do: MapSet.member?(held, action) and not MapSet.member?(before, action)

  defp next_watch(game, id, current) do
    flying =
      game.ships
      |> Map.values()
      |> Enum.filter(&(&1.id != id and &1.alive?))
      |> Enum.sort_by(& &1.name)

    case {flying, current} do
      {[], _} ->
        nil

      {_, nil} ->
        hd(flying).id

      {_, %{id: current_id}} ->
        Enum.at(
          flying,
          rem((Enum.find_index(flying, &(&1.id == current_id)) || -1) + 1, length(flying))
        ).id
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
    |> regenerate_stations(dt)
    |> fly_ships(dt)
    |> count_contact(dt)
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
    env = %{
      grid: Arena.grid(game.arena),
      fields: game.fields,
      size: Arena.size(game.arena),
      wrap?: game.settings.wrap?,
      bounce?: game.settings.balls_bounce?
    }

    {balls, ships} = Ball.step(game.balls, game.ships, dt, env)
    ships = Enum.reduce(balls, ships, fn ball, ships -> pair_ball(ships, ball) end)
    {balls, scored} = Ball.deliver(balls, ships, game.arena)

    Enum.reduce(scored, %{game | balls: balls, ships: ships}, fn {carrier, team, points, against},
                                                                 acc ->
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
    ships = Map.update!(game.ships, scorer, &put_in(&1.tally.score, &1.tally.score + points))

    bonus =
      if team,
        do: Map.update(game.team_bonus, team, points, &(&1 + points)),
        else: game.team_bonus

    %{game | ships: ships, team_bonus: bonus}
  end

  defp tell(game, text),
    do: %{game | messages: Enum.take([{game.time, text} | game.messages], @messages_kept)}

  defp collide_ships(%{settings: %{crashes?: false, ship_bounces?: false}} = game), do: game

  defp collide_ships(game) do
    flying =
      game.ships
      |> Map.values()
      |> Enum.filter(&(&1.alive? and not Gear.phasing?(&1, game.time)))
      |> Enum.sort_by(& &1.name)

    for {first, index} <- Enum.with_index(flying),
        second <- Enum.drop(flying, index + 1),
        reduce: game do
      acc -> collide_if_touching(acc, Map.get(acc.ships, first.id), Map.get(acc.ships, second.id))
    end
  end

  defp collide_if_touching(game, %{alive?: true} = one, %{alive?: true} = other) do
    if Collision.circles_overlap?(one.body.pos, Ship.radius(), other.body.pos, Ship.radius()),
      do: collide(game, one, other),
      else: game
  end

  defp collide_if_touching(game, _one, _other), do: game

  defp collide(game, one, other) do
    {one, other} = if game.settings.ship_bounces?, do: rebound(one, other), else: {one, other}
    game = %{game | ships: game.ships |> Map.put(one.id, one) |> Map.put(other.id, other)}

    guarded = fn ship ->
      Gear.shielded?(ship, game.time) or ship.deflecting? or immune?(ship, game.time)
    end

    dying = if game.settings.crashes?, do: Enum.reject([one, other], guarded), else: []

    case dying do
      [] ->
        game |> charge_shielded([one, other]) |> emit({:bounce, one.body.pos})

      lost ->
        Enum.reduce(lost, game, fn ship, acc ->
          struck = Enum.find([one, other], &(&1.id != ship.id))

          lose(
            acc,
            Map.fetch!(acc.ships, ship.id),
            "#{one.name} and #{other.name} collided",
            "collided with #{struck.name}"
          )
        end)
    end
  end

  defp charge_shielded(game, ships) do
    Enum.reduce(ships, game, fn ship, acc ->
      if Gear.shielded?(ship, acc.time),
        do: %{
          acc
          | ships: Map.update!(acc.ships, ship.id, &%{&1 | fuel: max(0.0, &1.fuel - @crash_fuel)})
        },
        else: acc
    end)
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
      %{
        one
        | body: %{
            one.body
            | vel: {avx + (along_b - along_a) * nx, avy + (along_b - along_a) * ny},
              pos: {ax - nx * gap, ay - ny * gap}
          }
      },
      %{
        other
        | body: %{
            other.body
            | vel: {bvx + (along_a - along_b) * nx, bvy + (along_a - along_b) * ny},
              pos: {bx + nx * gap, by + ny * gap}
          }
      }
    }
  end

  defp strike_lasered(%{lasered: []} = game), do: game

  defp strike_lasered(game) do
    Enum.reduce(Enum.reverse(game.lasered), game, fn {shooter, victim, at}, acc ->
      lasered(acc, Map.get(acc.ships, victim), shooter, at)
    end)
  end

  defp lasered(game, %{alive?: true} = ship, shooter, at) do
    cond do
      Items.has?(ship, :mirror) ->
        emit(game, {:bounce, at})

      game.settings.stun_laser? ->
        stunned = Ship.timer(ship, :ecm_until, game.time + @stun_time)
        %{game | ships: Map.put(game.ships, ship.id, stunned)} |> emit({:ecm, at})

      true ->
        strike(game, shooter, ship.id, at, :laser)
    end
  end

  defp lasered(game, _dead, _shooter, _at), do: game

  defp maybe_new_round(%{ships: ships} = game, _dt) when map_size(ships) == 0, do: game

  defp maybe_new_round(%{settings: %{first_to: kills}, round_over_in: nil} = game, _dt)
       when is_integer(kills) do
    case Enum.find(game.ships, fn {_, %{tally: tally}} ->
           tally.kills - tally.recorded.kills >= kills
         end) do
      {_, winner} ->
        %{game | round_over_in: @round_pause, won_by: winner.name}
        |> results(winner.name)
        |> tell(winner.name <> " won the duel")

      nil ->
        game
    end
  end

  defp maybe_new_round(%{won_by: winner} = game, _dt) when winner != nil, do: game
  defp maybe_new_round(%{settings: %{lives: :unlimited}} = game, _dt), do: game

  defp maybe_new_round(%{round_over_in: nil} = game, _dt) do
    case standing(game) do
      [] ->
        game |> results(nil) |> new_round()

      [winner] when map_size(game.ships) > 1 ->
        %{game | round_over_in: @round_pause}
        |> results(winner)
        |> tell(winner <> " won the round")

      _several ->
        game
    end
  end

  defp maybe_new_round(%{round_over_in: left} = game, dt) when left > dt,
    do: %{game | round_over_in: left - dt}

  defp maybe_new_round(game, _dt), do: new_round(game)

  defp results(game, winner) do
    Enum.reduce(game.ships, game, fn {id, ship}, acc ->
      {row, ship} =
        Ship.result(ship, winner != nil and winner in [ship.name, "team #{ship.team}"])

      %{acc | ships: Map.put(acc.ships, id, ship)}
      |> emit({:result, Map.put(row, :mode, mode(acc))})
    end)
  end

  @contact_range 30.0

  defp count_contact(game, dt) do
    alive = for {_, ship} <- game.ships, ship.alive?, do: ship

    ships =
      Map.new(game.ships, fn {id, ship} ->
        if ship.alive? and Enum.any?(alive, &enemy_near?(&1, ship)),
          do: {id, Ship.in_contact(ship, dt)},
          else: {id, ship}
      end)

    %{game | ships: ships}
  end

  defp enemy_near?(other, ship) do
    other.id != ship.id and (ship.team == nil or other.team != ship.team) and
      Collision.circles_overlap?(other.body.pos, @contact_range, ship.body.pos, 0.0)
  end

  defp new_round(game) do
    ships =
      Map.new(game.ships, fn {id, ship} ->
        {id, spawned(Ship.new_round(ship, game.settings.lives), game)}
      end)

    %{game | ships: ships, round_over_in: nil} |> emit({:round, centre(game)})
  end

  defp standing(%{settings: %{teamplay?: true}} = game) do
    game.ships
    |> Map.values()
    |> Enum.reject(&out?/1)
    |> Enum.uniq_by(& &1.team)
    |> Enum.map(&"team #{&1.team}")
  end

  defp standing(game),
    do: game.ships |> Map.values() |> Enum.reject(&out?/1) |> Enum.map(& &1.name)

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

      ship = Gear.wear(ship, dt, game.time, game.arena)
      game = %{game | ships: Map.put(game.ships, id, ship)}
      game |> refuel(id, dt) |> warp(id) |> pick_up(id) |> race(id) |> starve(id)
    else
      countdown(game, id, dt)
    end
  end

  defp starve(game, id) do
    ship = Map.fetch!(game.ships, id)

    cond do
      ship.fuel > 0 ->
        %{game | ships: Map.put(game.ships, id, Ship.timer(ship, :empty_since, nil))}

      ship.timers.empty_since == nil ->
        %{game | ships: Map.put(game.ships, id, Ship.timer(ship, :empty_since, game.time))}

      game.time - ship.timers.empty_since < @starve_after ->
        game

      true ->
        lose(game, ship, "#{ship.name} ran out of fuel", "ran out of fuel")
    end
  end

  defp lose(game, ship, message, cause) do
    {dead, game} = explode(ship, game, cause)
    %{game | ships: Map.put(game.ships, ship.id, dead)} |> tell(message)
  end

  defp pick_up(game, id) do
    ship = Map.fetch!(game.ships, id)

    case Items.take_at(game.items, ship.body.pos) do
      {nil, _} ->
        game

      {_item, _} when ship.shielding? and not game.settings.shielded_pickup? ->
        game

      {%{kind: kind}, rest} ->
        {picked, rng} = Items.pick_up(ship, kind, game.rng)

        %{game | items: rest, rng: rng, ships: Map.put(game.ships, id, picked)}
        |> emit({:pick_up, ship.body.pos})
    end
  end

  defp race(%{settings: %{race?: false}} = game, _id), do: game

  defp race(game, id) do
    ship = Map.fetch!(game.ships, id)

    passed =
      Race.pass(
        ship,
        game.settings.checkpoints,
        game.settings.laps,
        game.settings.checkpoint_reach
      )

    cond do
      passed.race.finished? and not ship.race.finished? ->
        %{game | ships: Map.put(game.ships, id, passed)}
        |> emit({:finish, ship.body.pos})
        |> tell("#{ship.name} finished")

      passed.race != ship.race ->
        %{game | ships: Map.put(game.ships, id, passed)} |> emit({:checkpoint, ship.body.pos})

      true ->
        game
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

    delta =
      Integer.mod(wanted - ship.body.heading + div(Ship.headings(), 2), Ship.headings()) -
        div(Ship.headings(), 2)

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
      burn = if shielding?, do: game.settings.shield_burn * dt, else: 0.0

      {%{
         ship
         | timers: %{ship.timers | cooldown: max(0.0, ship.timers.cooldown - dt)},
           shielding?: shielding?,
           thrusting?: false,
           fuel: max(0.0, ship.fuel - burn)
       }, game}
    end
  end

  defp propel(%Ship{} = ship, dt, game) do
    thrusting? =
      Ship.holding?(ship, :thrust) and
        (ship.fuel > 0 or ship.timers.emergency_thrust_until > game.time)

    shielding? = shielding?(ship, game)

    power = Ship.strength(ship, :thrust)

    body =
      if thrusting?,
        do: Body.thrust(ship.body, acceleration(ship, game) * power, dt),
        else: ship.body

    burn =
      if(thrusting?,
        do: game.settings.thrust_burn * power * Gear.thrust_fuel_factor(ship, game.time),
        else: 0.0
      ) + if shielding?, do: game.settings.shield_burn, else: 0.0

    ship = %{
      ship
      | body:
          body
          |> Body.gravitate(game.fields, dt)
          |> Body.drag(game.settings.drag, dt)
          |> Body.cap_speed(game.settings.max_speed),
        fuel: max(0.0, ship.fuel - burn * dt),
        thrusting?: thrusting?,
        shielding?: shielding?,
        timers: %{ship.timers | cooldown: max(0.0, ship.timers.cooldown - dt)}
    }

    if thrusting?, do: {ship, exhaust(game, ship)}, else: {ship, game}
  end

  defp shielding?(ship, game) do
    game.settings.shields? and Ship.holding?(ship, :shield) and ship.fuel > 0 and
      not Ship.holding?(ship, :fire) and not Ship.holding?(ship, :fire_laser)
  end

  defp acceleration(ship, game) do
    Arena.acceleration(game.arena, @power / mass(ship, game)) *
      Gear.thrust_factor(ship, game.time)
  end

  defp mass(ship, game) do
    empty = game.settings.ship_mass
    empty + @fuel_mass * ship.fuel + ship.armour * empty / @armour_mass_share
  end

  defp exhaust(game, ship) do
    {dx, dy} = Body.direction(ship.body)
    {x, y} = ship.body.pos
    {vx, vy} = ship.body.vel
    {jitter, rng} = Rng.between(game.rng, -20, 20)
    spread = jitter / 100
    power = Ship.strength(ship, :thrust)
    speed = 2 + 4 * power

    spark = %{
      art: :spark,
      pos: {x - dx * 0.5, y - dy * 0.5},
      vel: {vx - dx * speed + dy * spread * speed, vy - dy * speed - dx * spread * speed},
      ttl: 0.1 + 0.15 * power
    }

    %{game | rng: rng, particles: Particles.spawn(game.particles, [spark])}
  end

  defp fire({ship, game}, dt, unused) do
    if Ship.holding?(ship, :fire) and immune?(ship, game.time),
      do: fire({Ship.timer(ship, :immune_until, 0.0), game}, dt, unused),
      else: shoot({ship, game})
  end

  defp shoot({ship, game}) do
    if Ship.holding?(ship, :fire) and not Gear.confused?(ship, game.time) and
         ship.timers.emergency_shield_until <= game.time and
         ship.timers.cooldown <= 0 and
         ship.fuel >= @shot_fuel and
         shots_of(game, ship.id) < game.settings.max_shots do
      spread = if Items.has?(ship, :wideangle), do: [0, 3, -3], else: [0]
      directions = Enum.map(spread, &Body.direction(Body.turn(ship.body, &1)))

      directions =
        if Items.has?(ship, :rearshot),
          do: [{-elem(hd(directions), 0), -elem(hd(directions), 1)} | directions],
          else: directions

      {shots, next_id} =
        Enum.map_reduce(directions, game.next_id, fn {dx, dy}, id ->
          {x, y} = ship.body.pos
          {vx, vy} = ship.body.vel
          speed = game.settings.shot_speed

          {%{
             id: id,
             owner: ship.id,
             kind: :shot,
             body:
               Body.new(
                 pos: {x + dx * 0.6, y + dy * 0.6},
                 vel: {vx + dx * speed, vy + dy * speed},
                 radius: @shot_radius
               ),
             life: game.settings.shot_life
           }, id + 1}
        end)

      game =
        %{game | shots: shots ++ game.shots, next_id: next_id} |> emit({:fire, ship.body.pos})

      fired = %{ship | fuel: ship.fuel - @shot_fuel}
      {Ship.timer(fired, :cooldown, game.settings.fire_cooldown), game}
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
      swept(ship, game, Collision.sweep(grid, from, to, Ship.radius()))
    end
  end

  defp swept(ship, game, {:clear, at}) do
    moved = %{ship | body: wrapped(%{ship.body | pos: at}, game)}

    case cannon_touched(game, moved) do
      nil -> {moved, game}
      cannon -> rammed(moved, game, cannon)
    end
  end

  defp swept(ship, game, {:blocked, at, normal, _cell}) do
    shielded? = Gear.shielded?(ship, game.time)
    limit = if shielded?, do: game.settings.shielded_crash_speed, else: game.settings.crash_speed

    if Body.speed(ship.body) <= limit,
      do: bounce(ship, game, at, normal, shielded?),
      else: crash(ship, game, at)
  end

  defp cannon_touched(game, ship) do
    Enum.find(live_cannons(game), fn %{pos: {cx, cy}} ->
      Collision.circles_overlap?(ship.body.pos, Ship.radius(), {cx + 0.5, cy + 0.5}, 0.5)
    end)
  end

  defp rammed(ship, game, cannon) do
    doubled? = ship.shielding? and ship.timers.emergency_shield_until > game.time

    cond do
      doubled? ->
        game = cannon_dies(game, cannon, ship.id)
        {%{ship | tally: Map.fetch!(game.ships, ship.id).tally}, game}

      immune?(ship, game.time) ->
        {ship, cannon_dies(game, cannon, nil)}

      true ->
        {dead, game} = explode(ship, cannon_dies(game, cannon, nil), "smashed against a cannon")
        {dead, tell(game, "#{ship.name} smashed against a cannon")}
    end
  end

  defp crash(ship, game, at) do
    {dead, game} = explode(%{ship | body: %{ship.body | pos: at}}, game, "hit a wall")
    {dead, tell(game, "#{ship.name} hit a wall")}
  end

  defp bounce(ship, game, at, normal, shielded?) do
    body = %{
      ship.body
      | pos: at,
        vel: Collision.bounce(ship.body.vel, normal, game.settings.bounce_keep)
    }

    fuel = if shielded?, do: ship.fuel, else: max(0.0, ship.fuel - bounce_cost(ship, game))
    {%{ship | body: wrapped(body, game), fuel: fuel}, emit(game, {:bounce, at})}
  end

  defp bounce_cost(ship, game) do
    speed = Arena.pixels_per_frame(game.arena, Body.speed(ship.body))
    braking = 1.0 - 0.5 * game.settings.bounce_keep
    heft = max(0.0, mass(ship, game) - 0.75 * game.settings.ship_mass)
    0.9 * braking * heft * speed / 4 * game.settings.bounce_drain
  end

  defp wrapped(body, %{settings: %{wrap?: true}, arena: arena}),
    do: Body.wrap(body, Arena.size(arena))

  defp wrapped(body, _game), do: body

  defp explode(ship, game, cause) do
    pos = ship.body.pos
    {debris, rng} = debris(game.rng, pos, 24)
    {items, rng} = Items.drop(game.items, ship, game.settings.drop_prob, rng)

    game =
      %{game | rng: rng, items: items, particles: Particles.spawn(game.particles, debris)}
      |> emit({:explosion, pos})

    {%{Ship.die(ship, @respawn_after, of: cause, at: game.time) | ball: nil}, game}
  end

  defp debris(rng, {x, y}, count) do
    Enum.map_reduce(1..count, rng, fn _, rng ->
      {angle, rng} = Rng.between(rng, 0, 359)
      {speed, rng} = Rng.between(rng, 3, 9)
      {life, rng} = Rng.between(rng, 30, 90)
      theta = angle * :math.pi() / 180

      {%{
         art: :debris,
         pos: {x, y},
         vel: {:math.cos(theta) * speed, :math.sin(theta) * speed},
         ttl: life / 100
       }, rng}
    end)
  end

  defp refuel(game, id, dt) do
    ship = Map.fetch!(game.ships, id)

    station =
      Enum.find(game.stations, fn {{fx, fy}, fuel} ->
        fuel > 0 and
          Collision.circles_overlap?(ship.body.pos, @refuel_reach, {fx + 0.5, fy + 0.5}, 0.0)
      end)

    case station do
      {pos, fuel} when ship.fuel < ship.max_fuel ->
        given = Enum.min([game.settings.refuel_rate * dt, fuel, ship.max_fuel - ship.fuel])

        %{
          game
          | ships: Map.put(game.ships, id, %{ship | fuel: ship.fuel + given}),
            stations: Map.put(game.stations, pos, fuel - given)
        }
        |> emit_refuel(ship)

      _none ->
        game
    end
  end

  defp regenerate_stations(game, dt) do
    gain = game.settings.station_regeneration * map_size(game.ships) * dt

    %{
      game
      | stations:
          Map.new(game.stations, fn {pos, fuel} -> {pos, min(@station_fuel, fuel + gain)} end)
    }
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

            %{game | rng: rng, ships: Map.put(game.ships, id, moved)}
            |> emit({:wormhole, ship.body.pos})
        end
    end
  end

  defp countdown(game, id, dt) do
    ship = Map.fetch!(game.ships, id)
    remaining = ship.timers.respawn_in - dt

    cond do
      remaining > 0 ->
        %{game | ships: Map.put(game.ships, id, Ship.timer(ship, :respawn_in, remaining))}

      Ship.can_respawn?(ship) ->
        revived = spawned(Ship.respawn(ship), game)
        %{game | ships: Map.put(game.ships, id, revived)} |> emit({:respawn, revived.body.pos})

      true ->
        %{game | ships: Map.put(game.ships, id, Ship.timer(ship, :respawn_in, 0.0))}
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
    |> Enum.reduce(Buckets.new(4), fn ship, buckets ->
      Buckets.insert(buckets, ship.id, ship.body.pos, Ship.radius())
    end)
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
        case Enum.reject(
               Buckets.near(buckets, mine.body.pos, mine.body.radius),
               &(&1 == mine.owner)
             ) do
          [] ->
            {game, [mine | kept]}

          [victim | _] ->
            {game
             |> strike(mine.owner, victim, mine.body.pos, :mine)
             |> emit({:explosion, mine.body.pos}), kept}
        end
    end
  end

  defp advance_shot(game, shot, dt, grid, buckets, kept) do
    life = shot.life - dt
    from = shot.body.pos
    shot = Weapons.steer(shot, Map.values(game.ships), dt, game.settings.shot_speed)

    pulled =
      if game.settings.shots_gravity?,
        do: Body.gravitate(shot.body, game.fields, dt),
        else: shot.body

    to = Body.integrate(pulled, dt)

    if life <= 0 do
      {game, kept}
    else
      shot = %{shot | life: life}

      shot_swept(
        game,
        shot,
        to,
        Collision.sweep(grid, from, to.pos, shot.body.radius),
        buckets,
        kept
      )
    end
  end

  defp shot_swept(
         %{settings: %{shots_bounce?: true}} = game,
         shot,
         to,
         {:blocked, at, normal, _cell},
         _buckets,
         kept
       ) do
    body = wrapped(%{to | pos: at, vel: Collision.bounce(to.vel, normal, 0.9)}, game)
    {game, [%{shot | body: body} | kept]}
  end

  defp shot_swept(game, _shot, _to, {:blocked, at, _normal, _cell}, _buckets, kept),
    do: {emit(game, {:shot_wall, at}), kept}

  defp shot_swept(game, shot, to, {:clear, at}, buckets, kept) do
    moved = %{shot | body: wrapped(%{to | pos: at}, game)}

    with :miss <- target_hit(game, shot, moved.body.pos),
         :miss <- cannon_hit(game, shot, moved.body.pos) do
      shot_among_ships(game, moved, buckets, kept)
    else
      {:hit, game} -> {game, kept}
    end
  end

  defp cannon_hit(%{cannons: []}, _shot, _pos), do: :miss
  defp cannon_hit(_game, %{owner: {:cannon, _}}, _pos), do: :miss

  defp cannon_hit(game, shot, pos) do
    cell = Collision.cell_of(pos)

    case Enum.find(live_cannons(game), &(&1.pos == cell)) do
      nil -> :miss
      cannon -> {:hit, cannon_dies(game, cannon, shot.owner)}
    end
  end

  defp live_cannons(game), do: Enum.filter(game.cannons, &(&1.dead_until == nil))

  defp cannon_dies(game, %{pos: {cx, cy} = pos} = cannon, killer) do
    centre = {cx + 0.5, cy + 0.5}
    {debris, rng} = debris(game.rng, centre, 30)
    dead = %{cannon | dead_until: game.time + game.settings.cannon_dead_time}

    %{
      game
      | rng: rng,
        particles: Particles.spawn(game.particles, debris),
        cannons: Enum.map(game.cannons, &if(&1.pos == pos, do: dead, else: &1))
    }
    |> emit({:cannon_destroyed, centre})
    |> cannon_credited(killer)
  end

  defp cannon_credited(game, killer) do
    case Map.get(game.ships, killer) do
      %{tally: %{score: score}, team: team} when score <= game.settings.cannon_max_score ->
        game
        |> award(killer, team, game.settings.cannon_points)
        |> tell("#{name_of_ship(game, killer)} destroyed a cannon")

      _nobody ->
        game
    end
  end

  defp revive_cannons(game) do
    Enum.reduce(game.cannons, game, fn
      %{dead_until: until, pos: {cx, cy}} = cannon, acc when until != nil and until <= acc.time ->
        %{
          acc
          | cannons:
              Enum.map(
                acc.cannons,
                &if(&1.pos == cannon.pos, do: %{&1 | dead_until: nil}, else: &1)
              )
        }
        |> emit({:cannon_back, {cx + 0.5, cy + 0.5}})

      _cannon, acc ->
        acc
    end)
  end

  defp shot_among_ships(game, shot, buckets, kept) do
    victims =
      Enum.reject(
        Buckets.near(buckets, shot.body.pos, shot.body.radius),
        &(&1 == shot.owner or not hittable?(game, shot.owner, &1))
      )

    case victims do
      [] -> {game, [shot | kept]}
      [victim | _] -> {strike(game, shot.owner, victim, shot.body.pos, shot.kind), kept}
    end
  end

  defp target_hit(%{targets: []}, _shot, _pos), do: :miss

  defp target_hit(game, shot, pos) do
    cell = Collision.cell_of(pos)

    if Targets.standing?(game.targets, cell) do
      target_struck(
        game,
        shot,
        pos,
        cell,
        Targets.hit(game.targets, cell, team_of(game, shot.owner))
      )
    else
      :miss
    end
  end

  defp target_struck(_game, _shot, _pos, _cell, {_targets, :none}), do: :miss

  defp target_struck(game, _shot, pos, _cell, {targets, :hit}),
    do: {:hit, %{game | targets: targets} |> emit({:target_hit, pos})}

  defp target_struck(game, shot, pos, cell, {targets, {:destroyed, team, points}}) do
    game = %{game | targets: targets} |> emit({:target_destroyed, pos})
    {:hit, game |> target_credited(shot.owner, team, points) |> fall_of_targets(cell)}
  end

  defp target_credited(game, owner, team, points) do
    if is_map_key(game.ships, owner),
      do:
        game
        |> award(owner, team, points)
        |> tell("#{name_of_ship(game, owner)} destroyed a target"),
      else: game
  end

  defp fall_of_targets(%{settings: %{target_kill_team?: false}} = game, _cell), do: game

  defp fall_of_targets(game, cell) do
    case Enum.find(game.targets, &(&1.pos == cell)) do
      %{team: team} when team != nil ->
        if Targets.standing_for?(game.targets, team),
          do: game,
          else: kill_team(game, team, "team #{team} lost its last target")

      _ ->
        game
    end
  end

  defp kill_team(game, team, message) do
    game.ships
    |> Map.values()
    |> Enum.filter(&(&1.alive? and &1.team == team))
    |> Enum.reduce(tell(game, message), fn ship, acc ->
      lose(
        acc,
        Map.fetch!(acc.ships, ship.id),
        "#{ship.name} went down with the team",
        "went down with the team"
      )
    end)
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
      untouchable?(victim, game) -> game
      Gear.shielded?(victim, game.time) -> shield_struck(game, victim, pos, kind)
      deflects?(victim, game, owner) -> emit(game, {:bounce, pos})
      victim.armour > 0 -> armour_struck(game, victim, pos)
      true -> killed(game, owner, victim, pos, kind)
    end
  end

  defp shield_struck(game, victim, pos, kind) do
    drained = %{victim | fuel: max(0.0, victim.fuel - hit_cost(kind))}
    %{game | ships: Map.put(game.ships, victim.id, drained)} |> emit({:bounce, pos})
  end

  defp hit_cost(:shot), do: @shot_hit_fuel
  defp hit_cost(:laser), do: @laser_hit_fuel
  defp hit_cost(_missile_or_mine), do: @missile_hit_fuel

  defp untouchable?(victim, game), do: not victim.alive? or Gear.phasing?(victim, game.time)

  defp deflects?(victim, game, owner) do
    victim.deflecting? or immune?(victim, game.time) or
      (not game.settings.killing? and not match?({:cannon, _}, owner))
  end

  defp armour_struck(game, victim, pos) do
    %{game | ships: Map.put(game.ships, victim.id, %{victim | armour: victim.armour - 1})}
    |> emit({:bounce, pos})
  end

  defp killed(game, owner, victim, pos, kind) do
    killer = name_of_ship(game, owner)
    {dead, game} = explode(victim, game, epitaph(kind, killer))
    game = %{game | ships: Map.put(game.ships, victim.id, dead)} |> emit({:kill, pos})
    game |> credit(owner) |> tell(kill_message(kind, killer, victim))
  end

  defp kill_message(:shot, killer, victim), do: "#{killer} shot #{victim.name}"
  defp kill_message(:mine, killer, victim), do: "#{victim.name} hit #{killer}'s mine"
  defp kill_message(:laser, killer, victim), do: "#{killer} lasered #{victim.name}"
  defp kill_message(_missile, killer, victim), do: "#{killer}'s missile hit #{victim.name}"

  defp epitaph(:shot, killer), do: "shot by #{killer}"
  defp epitaph(:mine, killer), do: "hit #{killer}'s mine"
  defp epitaph(:laser, killer), do: "lasered by #{killer}"
  defp epitaph(_missile, killer), do: "hit by #{killer}'s missile"

  defp credit(game, {:cannon, _}), do: game

  defp credit(game, owner) do
    case Map.fetch(game.ships, owner) do
      {:ok, killer} -> %{game | ships: Map.put(game.ships, owner, Ship.credit_kill(killer))}
      :error -> game
    end
  end

  defp fire_cannons(game, dt) do
    game = revive_cannons(game)

    {cannons, game} =
      Enum.map_reduce(game.cannons, game, fn
        %{dead_until: until} = cannon, acc when until != nil ->
          {cannon, acc}

        cannon, acc ->
          cooled = %{cannon | cooldown: max(0.0, cannon.cooldown - dt)}

          case {cooled.cooldown, target_for(acc, cooled)} do
            {cd, target} when cd <= 0 and target != nil ->
              {%{cooled | cooldown: @cannon_cooldown}, cannon_fire(acc, cooled, target)}

            _ ->
              {cooled, acc}
          end
      end)

    %{game | cannons: cannons}
  end

  defp target_for(game, %{pos: {cx, cy}, facing: facing}) do
    muzzle = {cx + 0.5, cy + 0.5}

    game.ships
    |> Map.values()
    |> Enum.filter(fn ship ->
      ship.alive? and not ship.cloaked? and in_front?(facing, muzzle, ship.body.pos) and
        Collision.circles_overlap?(muzzle, @cannon_range, ship.body.pos, 0.0)
    end)
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
      body:
        Body.new(
          pos: {mx + (tx - mx) / length, my + (ty - my) / length},
          vel: vel,
          radius: @shot_radius
        ),
      life: game.settings.shot_life * 2
    }

    %{game | shots: [shot | game.shots], next_id: game.next_id + 1} |> emit({:cannon, muzzle})
  end

  @impl true
  def view(%__MODULE__{} = game, id) do
    me = Map.get(game.ships, id)
    watching = watched_by(game, id, me)

    %{
      me: me && summary_of(me, game.time),
      focus: focus_of(game, id, me, watching),
      watching: watching && watching.name,
      radar: %{players?: game.settings.players_on_radar?},
      rules: %{
        shields?: game.settings.shields?,
        crash_speed: game.settings.crash_speed,
        shot_speed: game.settings.shot_speed,
        shot_range: game.settings.shot_speed * game.settings.shot_life,
        unit_speed: Arena.speed(game.arena, 1.0)
      },
      mode: game.settings.mode,
      others_out?: others_out?(game, id, me),
      round_over?: game.round_over_in != nil,
      won_by: game.won_by,
      enemies: Enum.count(game.ships, fn {other, ship} -> other != id and not out?(ship) end),
      ships:
        for({_, ship} <- game.ships, ship.alive?, visible?(ship, me), do: seen(ship, game.time)),
      shots: for(%{kind: :shot, body: %{pos: pos}} <- game.shots, do: pos),
      missiles: missiles_view(game.shots),
      mines: for(%{kind: :mine, body: %{pos: pos}} <- game.shots, do: pos),
      items: Enum.map(game.items, &{&1.kind, &1.pos}),
      balls: Enum.map(game.balls, &ball_view(game, &1)),
      beams: game.beams,
      targets_gone: Targets.gone(game.targets),
      cannons_gone: for(%{dead_until: until, pos: pos} <- game.cannons, until != nil, do: pos),
      stations: game.stations,
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

  defp focus_of(_game, _id, _me, %{body: %{pos: pos}}), do: pos
  defp focus_of(_game, _id, %{body: %{pos: pos}}, nil), do: pos
  defp focus_of(game, id, nil, nil), do: Map.get(game.watchers, id, %{focus: centre(game)}).focus

  defp others_out?(_game, _id, nil), do: false

  defp others_out?(game, id, _me) do
    map_size(game.ships) > 1 and
      Enum.all?(game.ships, fn {other, ship} -> other == id or out?(ship) end)
  end

  defp missiles_view(shots) do
    for %{kind: kind, body: %{pos: pos, vel: vel}} <- shots,
        kind in [:torpedo, :smart, :heat],
        do: {kind, pos, vel}
  end

  defp ball_view(game, ball),
    do: %{pos: ball.pos, vel: ball.vel, string: ball.carrier && carrier_pos(game, ball.carrier)}

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

  defp spawned(ship, game),
    do:
      Ship.timer(Ship.equip(ship, game.settings.kit), :immune_until, game.time + @spawn_immunity)

  defp immune?(ship, now), do: ship.timers.immune_until > now

  defp visible?(ship, me) do
    not ship.cloaked? or (me != nil and (ship.id == me.id or Items.has?(me, :sensor)))
  end

  defp team_scores(%{settings: %{teamplay?: false}}), do: %{}

  defp team_scores(game) do
    game.ships
    |> Map.values()
    |> Enum.reject(&is_nil(&1.team))
    |> Enum.group_by(& &1.team, & &1.tally.score)
    |> Map.new(fn {team, scores} ->
      {team, Enum.sum(scores) + Map.get(game.team_bonus, team, 0)}
    end)
  end

  defp race_view(%{settings: %{race?: false}}, _me), do: nil
  defp race_view(_game, nil), do: nil

  defp race_view(game, me) do
    %{
      lap: me.race.laps + 1,
      laps: game.settings.laps,
      next: me.race.checkpoint,
      checkpoints: length(game.settings.checkpoints),
      finished?: me.race.finished?
    }
  end

  defp out?(ship), do: not ship.alive? and not Ship.can_respawn?(ship)

  defp nearest_living(game, me) do
    {mx, my} = me.body.pos

    game.ships
    |> Map.values()
    |> Enum.filter(fn ship -> ship.id != me.id and ship.alive? end)
    |> Enum.min_by(
      fn %{body: %{pos: {x, y}}} -> (x - mx) * (x - mx) + (y - my) * (y - my) end,
      fn -> nil end
    )
  end

  @doc """
  Whether the round is over for the player a view belongs to.

  `nil` while it goes on: the player flies, or is out of lives but others still fly and
  the view follows the nearest. Once every other ship is out, or the round has ended
  with one ship standing, `%{title: title, lines: lines, next: next}` with the standings
  as lines: `"Victory"` with `next: :next_world` while the player still flies, `"Defeat"`
  with `next: :same_world` when they are out. A watcher's view, or one with unlimited
  lives, is never over.
  """
  @spec outcome(map()) :: nil | %{title: String.t(), lines: [String.t()]}
  def outcome(%{me: nil}), do: nil

  def outcome(%{me: me, won_by: winner, scores: scores}) when winner != nil do
    lines =
      Enum.map(scores, fn %{name: name, score: score} ->
        name <> "  " <> Integer.to_string(score)
      end)

    if me.name == winner,
      do: %{title: "Victory", lines: lines, next: :lobby},
      else: %{title: "Defeat", lines: lines, next: :lobby}
  end

  def outcome(%{me: %{lives: :unlimited}}), do: nil
  def outcome(%{others_out?: false, round_over?: false}), do: nil

  def outcome(%{me: me, scores: scores}) do
    lines =
      Enum.map(scores, fn %{name: name, score: score} ->
        name <> "  " <> Integer.to_string(score)
      end)

    if me.alive? or me.lives > 0,
      do: %{title: "Victory", lines: lines, next: :next_world},
      else: %{title: "Defeat", lines: lines, next: :same_world}
  end

  defp summary_of(ship, time) do
    ship
    |> Ship.summary()
    |> Map.merge(%{
      fuel: ship.fuel,
      max_fuel: ship.max_fuel,
      lives: ship.lives,
      respawn_in: ship.timers.respawn_in,
      kills: ship.tally.kills,
      deaths: ship.tally.deaths,
      items: ship.items,
      armour: ship.armour,
      missile: ship.missile,
      epitaph: epitaph_of(ship, time)
    })
  end

  defp epitaph_of(%{died_of: cause, died_at: at}, time)
       when is_binary(cause) and is_number(at) and time - at < @respawn_after + @epitaph_lingers,
       do: cause

  defp epitaph_of(_ship, _time), do: nil

  defp scores(game) do
    game.ships
    |> Map.values()
    |> Enum.map(&%{name: &1.name, score: &1.tally.score, team: &1.team})
    |> Enum.sort_by(& &1.score, :desc)
    |> Enum.take(8)
  end

  @impl true
  def drain_events(%__MODULE__{events: events} = game),
    do: {Enum.reverse(events), %{game | events: []}}

  defp emit(game, event), do: %{game | events: [event | game.events]}
end
