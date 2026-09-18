defmodule ExPilot.Gear do
  @moduledoc """
  What a ship's items do when their keys are pressed or held, and while their effects
  last.

  `use/4` reads the ship's held actions against what it held last tick — a toggle turns
  on the press, a one-shot spends an item on the press, a beam works while held — and
  returns the ship and game changed. `wear/3` runs the timed effects down.

  Keys: `:fire_missile` and `:next_missile`, `:drop_mine`, `:fire_laser`, `:cloak`,
  `:ecm`, `:transporter`, `:tractor` and `:pressor`, `:deflector`, `:phasing`,
  `:hyperjump`, `:emergency_shield`, `:emergency_thrust`, `:autopilot`, `:connector`.
  """

  alias Cauldron2D.{Body, Collision, Rng}
  alias ExPilot.{Items, Ship, Weapons}
  alias ExPilot.Map, as: Arena

  @cloak_burn 20.0
  @deflector_burn 20.0
  @beam_burn 40.0
  @laser_cost 30.0
  @laser_cooldown 0.5
  @ecm_reach 10.0
  @ecm_time 3.0
  @transporter_reach 8.0
  @beam_reach 10.0
  @beam_pull 9.0
  @phasing_time 4.0
  @emergency_time 4.0
  @autopilot_brake 3.0

  @doc "The actions items add to a ship's."
  @spec actions() :: [atom()]
  def actions do
    [
      :fire_missile,
      :next_missile,
      :drop_mine,
      :fire_laser,
      :cloak,
      :ecm,
      :transporter,
      :tractor,
      :pressor,
      :deflector,
      :phasing,
      :hyperjump,
      :emergency_shield,
      :emergency_thrust,
      :autopilot,
      :connector
    ]
  end

  @doc "Apply every item key `ship` pressed or holds this tick."
  @spec use({Ship.t(), map()}, float(), map()) :: {Ship.t(), map()}
  def use({ship, game}, dt, before) do
    pressed = MapSet.difference(ship.held, before)

    pressed
    |> Enum.reduce({ship, game}, fn action, {ship, game} = pair ->
      if ready?(action, ship, game), do: apply_item(action, pair), else: pair
    end)
    |> hold_laser(dt)
    |> beam(dt)
  end

  defp hold_laser({ship, game} = pair, _dt) do
    if Ship.holding?(ship, :fire_laser) and laser_ready?(ship, game),
      do: fire_laser(pair),
      else: pair
  end

  defp ready?(:next_missile, _ship, _game), do: true
  defp ready?(:fire_missile, ship, _game), do: Items.has?(ship, :missile)
  defp ready?(:drop_mine, ship, game), do: mine_ready?(ship, game)
  defp ready?(:cloak, ship, _game), do: Items.has?(ship, :cloak) or ship.cloaked?
  defp ready?(:deflector, ship, _game), do: Items.has?(ship, :deflector) or ship.deflecting?
  defp ready?(:autopilot, ship, _game), do: Items.has?(ship, :autopilot) or ship.autopilot?
  defp ready?(:connector, ship, _game), do: ship.ball != nil

  defp ready?(action, ship, _game)
       when action in [
              :ecm,
              :transporter,
              :phasing,
              :hyperjump,
              :emergency_shield,
              :emergency_thrust
            ],
       do: Items.has?(ship, action)

  defp ready?(_action, _ship, _game), do: false

  defp apply_item(:next_missile, pair), do: cycle_missile(pair)
  defp apply_item(:fire_missile, pair), do: fire_missile(pair)
  defp apply_item(:drop_mine, pair), do: drop_mine(pair)
  defp apply_item(:cloak, pair), do: toggle_cloak(pair)
  defp apply_item(:deflector, pair), do: toggle_deflector(pair)
  defp apply_item(:autopilot, pair), do: toggle_autopilot(pair)
  defp apply_item(:ecm, pair), do: ecm(pair)
  defp apply_item(:transporter, pair), do: transport(pair)
  defp apply_item(:phasing, pair), do: phase(pair)
  defp apply_item(:hyperjump, pair), do: hyperjump(pair)
  defp apply_item(:emergency_shield, pair), do: emergency_shield(pair)
  defp apply_item(:emergency_thrust, pair), do: emergency_thrust(pair)
  defp apply_item(:connector, {ship, game}), do: {%{ship | ball: nil}, game}

  defp mine_ready?(ship, game),
    do: Items.has?(ship, :mine) and (game.settings.shielded_mining? or not ship.shielding?)

  defp laser_ready?(ship, _game),
    do: Items.has?(ship, :laser) and ship.timers.cooldown <= 0 and ship.fuel >= @laser_cost

  defp cycle_missile({ship, game}) do
    next = %{torpedo: :smart, smart: :heat, heat: :torpedo}
    {%{ship | missile: Map.fetch!(next, ship.missile)}, game}
  end

  defp fire_missile({ship, game}) do
    missile = Weapons.missile(ship, ship.missile, game.next_id, game.settings)

    {Items.spend(ship, :missile),
     %{game | shots: [missile | game.shots], next_id: game.next_id + 1}
     |> emit({:missile, ship.body.pos})}
  end

  defp drop_mine({ship, game}) do
    mine = Weapons.mine(ship, game.next_id, game.settings.mine_fuse)

    {Items.spend(ship, :mine),
     %{game | shots: [mine | game.shots], next_id: game.next_id + 1}
     |> emit({:mine, ship.body.pos})}
  end

  defp fire_laser({ship, game}) do
    targets = game.ships |> Map.values() |> Enum.filter(&hittable?(game.settings, ship, &1))
    {from, to, hit} = Weapons.laser(ship, targets, Arena.grid(game.arena))
    game = %{game | beams: [{from, to} | game.beams]} |> emit({:laser, from})
    ship = Ship.timer(%{ship | fuel: ship.fuel - @laser_cost}, :cooldown, @laser_cooldown)

    case hit do
      nil -> {ship, game}
      victim -> {ship, %{game | lasered: [{ship.id, victim.id, to} | game.lasered]}}
    end
  end

  defp toggle_cloak({ship, game}) do
    if ship.cloaked?,
      do: {%{ship | cloaked?: false}, game},
      else: {%{Items.spend(ship, :cloak) | cloaked?: true}, emit(game, {:cloak, ship.body.pos})}
  end

  defp toggle_deflector({ship, game}) do
    if ship.deflecting?,
      do: {%{ship | deflecting?: false}, game},
      else: {%{Items.spend(ship, :deflector) | deflecting?: true}, game}
  end

  defp toggle_autopilot({ship, game}) do
    if ship.autopilot?,
      do: {%{ship | autopilot?: false}, game},
      else: {%{Items.spend(ship, :autopilot) | autopilot?: true}, game}
  end

  defp ecm({ship, game}) do
    until = game.time + @ecm_time

    ships =
      Map.new(game.ships, fn {id, other} ->
        if id != ship.id and enemy?(ship, other) and
             Collision.circles_overlap?(ship.body.pos, @ecm_reach, other.body.pos, 0.0),
           do: {id, Ship.timer(other, :ecm_until, until)},
           else: {id, other}
      end)

    {Items.spend(ship, :ecm), %{game | ships: ships} |> emit({:ecm, ship.body.pos})}
  end

  defp transport({ship, game}) do
    victim =
      game.ships
      |> Map.values()
      |> Enum.filter(fn other ->
        other.id != ship.id and other.alive? and enemy?(ship, other) and
          map_size(other.items) > 0 and
          Collision.circles_overlap?(ship.body.pos, @transporter_reach, other.body.pos, 0.0)
      end)
      |> Enum.min_by(fn other -> Collision.distance_sq(ship.body.pos, other.body.pos) end, fn ->
        nil
      end)

    case victim do
      nil ->
        {Items.spend(ship, :transporter), game}

      other ->
        {kind, rng} = Rng.pick(game.rng, Map.keys(other.items))
        robbed = Items.spend(other, kind)
        taken = ship |> Items.spend(:transporter) |> Items.pick_up(kind)

        {taken,
         %{game | rng: rng, ships: Map.put(game.ships, other.id, robbed)}
         |> emit({:transporter, ship.body.pos})}
    end
  end

  defp phase({ship, game}),
    do: {Ship.timer(Items.spend(ship, :phasing), :phasing_until, game.time + @phasing_time), game}

  defp hyperjump({ship, game}) do
    case open_tile(game.arena, game.rng, 30) do
      {nil, rng} ->
        {ship, %{game | rng: rng}}

      {pos, rng} ->
        {%{Items.spend(ship, :hyperjump) | body: %{ship.body | pos: pos}},
         %{game | rng: rng} |> emit({:hyperjump, ship.body.pos})}
    end
  end

  defp open_tile(_arena, rng, 0), do: {nil, rng}

  defp open_tile(arena, rng, tries) do
    {width, height} = Arena.size(arena)
    {x, rng} = Rng.between(rng, 1, width - 2)
    {y, rng} = Rng.between(rng, 1, height - 2)

    case Arena.tile(arena, {x, y}) do
      nil -> {{x + 0.5, y + 0.5}, rng}
      _other -> open_tile(arena, rng, tries - 1)
    end
  end

  defp emergency_shield({ship, game}) do
    spent = Items.spend(ship, :emergency_shield)
    {Ship.timer(spent, :emergency_shield_until, game.time + @emergency_time), game}
  end

  defp emergency_thrust({ship, game}) do
    spent = Items.spend(ship, :emergency_thrust)
    {Ship.timer(spent, :emergency_thrust_until, game.time + @emergency_time), game}
  end

  defp beam({ship, game}, dt) do
    direction =
      cond do
        Ship.holding?(ship, :tractor) and Items.has?(ship, :tractor_beam) -> 1
        Ship.holding?(ship, :pressor) and Items.has?(ship, :tractor_beam) -> -1
        true -> 0
      end

    with true <- direction != 0 and ship.fuel > 0,
         %{} = other <- nearest_enemy(ship, game, @beam_reach) do
      {sx, sy} = ship.body.pos
      {ox, oy} = other.body.pos
      {vx, vy} = other.body.vel
      length = max(0.1, :math.sqrt(Collision.distance_sq(ship.body.pos, other.body.pos)))
      pull = @beam_pull * dt * direction

      pulled = %{
        other
        | body: %{
            other.body
            | vel: {vx + (sx - ox) / length * pull, vy + (sy - oy) / length * pull}
          }
      }

      {%{ship | fuel: max(0.0, ship.fuel - @beam_burn * dt)},
       %{game | ships: Map.put(game.ships, other.id, pulled)}}
    else
      _ -> {ship, game}
    end
  end

  defp nearest_enemy(ship, game, reach) do
    game.ships
    |> Map.values()
    |> Enum.filter(fn other ->
      other.id != ship.id and other.alive? and enemy?(ship, other) and
        Collision.circles_overlap?(ship.body.pos, reach, other.body.pos, 0.0)
    end)
    |> Enum.min_by(fn other -> Collision.distance_sq(ship.body.pos, other.body.pos) end, fn ->
      nil
    end)
  end

  @doc "Whether `shooter` can hurt `victim` under `settings`: anyone but a teammate on a map with `teamimmunity`."
  @spec hittable?(map(), Ship.t(), Ship.t()) :: boolean()
  def hittable?(settings, shooter, victim) do
    not (settings.teamplay? and settings.team_immunity? and not enemy?(shooter, victim))
  end

  @doc "Whether two ships are on different sides."
  @spec enemy?(Ship.t(), Ship.t()) :: boolean()
  def enemy?(%Ship{team: nil}, _other), do: true
  def enemy?(_ship, %Ship{team: nil}), do: true
  def enemy?(%Ship{team: team}, %Ship{team: other}), do: team != other

  @doc "Run the timed effects down for `dt` and take their running costs from the tank."
  @spec wear(Ship.t(), float(), float()) :: Ship.t()
  def wear(%Ship{} = ship, dt, now) do
    burn =
      if(ship.cloaked?, do: @cloak_burn, else: 0.0) +
        if ship.deflecting?, do: @deflector_burn, else: 0.0

    fuel = max(0.0, ship.fuel - burn * dt)

    %{
      ship
      | fuel: fuel,
        cloaked?: ship.cloaked? and fuel > 0,
        deflecting?: ship.deflecting? and fuel > 0,
        timers: lapsed(ship.timers, now),
        body: if(ship.autopilot?, do: brake(ship.body, dt), else: ship.body)
    }
  end

  defp lapsed(timers, now) do
    Map.new(timers, fn
      {name, until}
      when name in [:phasing_until, :emergency_shield_until, :emergency_thrust_until] ->
        {name, if(until > now, do: until, else: 0.0)}

      other ->
        other
    end)
  end

  defp brake(%Body{vel: {vx, vy}} = body, dt) do
    keep = max(0.0, 1.0 - @autopilot_brake * dt)
    %{body | vel: {vx * keep, vy * keep}}
  end

  @doc "How much harder the ship thrusts: afterburners and emergency thrust multiply it."
  @spec thrust_factor(Ship.t(), float()) :: float()
  def thrust_factor(%Ship{} = ship, now) do
    burners = Map.get(ship.items, :afterburner, 0)
    emergency = if ship.timers.emergency_thrust_until > now, do: 2.0, else: 1.0
    (1.0 + 0.5 * burners) * emergency
  end

  @doc "Whether the ship is shielded this tick: by its own shield, or an emergency one."
  @spec shielded?(Ship.t(), float()) :: boolean()
  def shielded?(%Ship{} = ship, now),
    do: ship.shielding? or ship.timers.emergency_shield_until > now

  @doc "Whether the ship's phasing lets it through walls and shots this tick."
  @spec phasing?(Ship.t(), float()) :: boolean()
  def phasing?(%Ship{} = ship, now), do: ship.timers.phasing_until > now

  @doc "Whether an ECM has the ship confused this tick."
  @spec confused?(Ship.t(), float()) :: boolean()
  def confused?(%Ship{} = ship, now), do: ship.timers.ecm_until > now

  defp emit(game, event), do: %{game | events: [event | game.events]}
end
