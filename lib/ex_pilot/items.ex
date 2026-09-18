defmodule ExPilot.Items do
  @moduledoc """
  XPilot's items: what they are, where they appear, and what picking one up does.

  Items lie on open tiles and are picked up by flying over them. Each kind has a map
  option for how often it appears (`itemfuelpackprob` and the rest, scaled by
  `itemprobmult`), and the map's `maxitemdensity` caps how many lie about at once.

      ExPilot.Items.kinds()
      ExPilot.Items.pick_up(ship, :afterburner)
      ExPilot.Items.kit(arena)
      ExPilot.Items.spawn(items, arena, rng, dt, options)
  """

  alias Cauldron2D.Rng
  alias ExPilot.Map, as: Arena
  alias ExPilot.Ship

  @type kind ::
          :fuel
          | :tank
          | :ecm
          | :armor
          | :mine
          | :missile
          | :cloak
          | :sensor
          | :wideangle
          | :rearshot
          | :afterburner
          | :transporter
          | :mirror
          | :deflector
          | :hyperjump
          | :phasing
          | :laser
          | :emergency_thrust
          | :emergency_shield
          | :tractor_beam
          | :autopilot
  @type item :: %{pos: {number(), number()}, kind: kind(), ttl: float()}

  @kinds [
    fuel: :itemfuelpackprob,
    tank: :itemtankprob,
    ecm: :itemecmprob,
    armor: :itemarmorprob,
    mine: :itemmineprob,
    missile: :itemmissileprob,
    cloak: :itemcloakprob,
    sensor: :itemsensorprob,
    wideangle: :itemwideangleprob,
    rearshot: :itemrearshotprob,
    afterburner: :itemafterburnerprob,
    transporter: :itemtransporterprob,
    mirror: :itemmirrorprob,
    deflector: :itemdeflectorprob,
    hyperjump: :itemhyperjumpprob,
    phasing: :itemphasingprob,
    laser: :itemlaserprob,
    emergency_thrust: :itememergencythrustprob,
    emergency_shield: :itememergencyshieldprob,
    tractor_beam: :itemtractorbeamprob,
    autopilot: :itemautopilotprob
  ]

  @initial [
    tank: :initialtanks,
    ecm: :initialecms,
    armor: :initialarmor,
    mine: :initialmines,
    missile: :initialmissiles,
    cloak: :initialcloaks,
    sensor: :initialsensors,
    wideangle: :initialwideangles,
    rearshot: :initialrearshots,
    afterburner: :initialafterburners,
    transporter: :initialtransporters,
    mirror: :initialmirrors,
    deflector: :initialdeflectors,
    hyperjump: :initialhyperjumps,
    phasing: :initialphasings,
    laser: :initiallasers,
    emergency_thrust: :initialemergencythrusts,
    emergency_shield: :initialemergencyshields,
    tractor_beam: :initialtractorbeams,
    autopilot: :initialautopilots
  ]

  @fuel_pack 500.0
  @tank_fuel 500.0
  @lifetime 90.0
  @reach 0.7

  @doc "Every kind of item, in XPilot's order."
  @spec kinds() :: [kind()]
  def kinds, do: Keyword.keys(@kinds)

  @doc """
  What every ship starts and respawns with on `arena`: `initialfuel` and the
  `initial…` counts, in the shape `ExPilot.Ship.equip/2` takes.
  """
  @spec kit(Arena.t()) :: %{fuel: float(), items: %{kind() => non_neg_integer()}}
  def kit(%Arena{} = arena) do
    items =
      for {kind, option} <- @initial,
          count = Arena.option(arena, option),
          count > 0,
          into: %{},
          do: {kind, count}

    %{fuel: Arena.option(arena, :initialfuel) / 1, items: items}
  end

  @doc "The map option that sets how often `kind` appears."
  @spec option(kind()) :: atom()
  def option(kind), do: Keyword.fetch!(@kinds, kind)

  @doc """
  Give `ship` what `kind` does.

  A fuel pack fills the tank by 500; a tank adds 500 to the tank's capacity and fills it;
  armour adds a layer that absorbs one shot; every other kind adds one to the ship's
  count of it.
  """
  @spec pick_up(Ship.t(), kind()) :: Ship.t()
  def pick_up(%Ship{} = ship, :fuel),
    do: %{ship | fuel: min(ship.max_fuel, ship.fuel + @fuel_pack)}

  def pick_up(%Ship{} = ship, :tank),
    do: %{
      ship
      | max_fuel: ship.max_fuel + @tank_fuel,
        fuel: ship.fuel + @tank_fuel,
        items: count(ship.items, :tank)
    }

  def pick_up(%Ship{} = ship, :armor), do: %{ship | armour: ship.armour + 1}
  def pick_up(%Ship{} = ship, kind), do: %{ship | items: count(ship.items, kind)}

  defp count(items, kind), do: Map.update(items, kind, 1, &(&1 + 1))

  @doc "Whether `ship` has at least one of `kind`."
  @spec has?(Ship.t(), kind()) :: boolean()
  def has?(%Ship{items: items}, kind), do: Map.get(items, kind, 0) > 0

  @doc "Take one of `kind` from `ship`; unchanged when it has none."
  @spec spend(Ship.t(), kind()) :: Ship.t()
  def spend(%Ship{items: items} = ship, kind) do
    case Map.get(items, kind, 0) do
      0 -> ship
      1 -> %{ship | items: Map.delete(items, kind)}
      n -> %{ship | items: Map.put(items, kind, n - 1)}
    end
  end

  @doc """
  Let time pass for the items lying on `arena`: some expire, and with the map's
  probabilities a new one may appear on an open tile.

  Returns `{items, rng}`.
  """
  @spec spawn([item()], Arena.t(), Rng.t(), float(), map()) :: {[item()], Rng.t()}
  def spawn(items, arena, rng, dt, options) do
    kept = items |> Enum.map(&%{&1 | ttl: &1.ttl - dt}) |> Enum.filter(&(&1.ttl > 0))

    if length(kept) >= cap(arena, options) do
      {kept, rng}
    else
      appear(kept, arena, rng, dt, options)
    end
  end

  defp cap(arena, options) do
    {width, height} = Arena.size(arena)
    max(1, round(width * height * Map.fetch!(options, :maxitemdensity)))
  end

  defp appear(items, arena, rng, dt, options) do
    weights =
      for {kind, option} <- @kinds,
          do: {kind, Map.fetch!(options, option) * Map.fetch!(options, :itemprobmult)}

    total = weights |> Enum.map(&elem(&1, 1)) |> Enum.sum()
    {roll, rng} = Rng.between(rng, 0, 1_000_000)

    if roll / 1_000_000 < total * 50 * dt do
      {kind, rng} = choose(weights, total, rng)

      case open_tile(arena, rng, 20) do
        {nil, rng} -> {items, rng}
        {pos, rng} -> {[%{pos: pos, kind: kind, ttl: @lifetime} | items], rng}
      end
    else
      {items, rng}
    end
  end

  defp choose(weights, total, rng) do
    {roll, rng} = Rng.between(rng, 0, 1_000_000)
    target = roll / 1_000_000 * total

    {kind, _} =
      Enum.reduce_while(weights, {hd(weights) |> elem(0), 0.0}, fn {kind, weight}, {_, acc} ->
        if acc + weight >= target, do: {:halt, {kind, acc}}, else: {:cont, {kind, acc + weight}}
      end)

    {kind, rng}
  end

  defp open_tile(_arena, rng, 0), do: {nil, rng}

  defp open_tile(arena, rng, tries) do
    {width, height} = Arena.size(arena)
    {x, rng} = Rng.between(rng, 0, width - 1)
    {y, rng} = Rng.between(rng, 0, height - 1)

    case Arena.tile(arena, {x, y}) do
      nil -> {{x + 0.5, y + 0.5}, rng}
      _solid_or_feature -> open_tile(arena, rng, tries - 1)
    end
  end

  @doc """
  What a ship leaves on the floor where it died: each of its items and armour layers,
  with probability `prob`, as an item lying at `pos`.

  Returns `{items, rng}` with the dropped items added to `items`.
  """
  @spec drop([item()], Ship.t(), float(), Rng.t()) :: {[item()], Rng.t()}
  def drop(items, _ship, prob, rng) when prob <= 0.0, do: {items, rng}

  def drop(items, %Ship{} = ship, prob, rng) do
    carried =
      for {kind, count} <- Map.put(ship.items, :armor, ship.armour), _ <- 1..count//1, do: kind

    Enum.reduce(carried, {items, rng}, fn kind, {acc, rng} ->
      {dropped?, rng} = Rng.chance(rng, round(prob * 1000), 1000)

      if dropped?,
        do: {[%{pos: ship.body.pos, kind: kind, ttl: @lifetime} | acc], rng},
        else: {acc, rng}
    end)
  end

  @doc "The item at `pos` within reach of a ship there, and the rest."
  @spec take_at([item()], {number(), number()}) :: {item() | nil, [item()]}
  def take_at(items, {x, y}) do
    case Enum.split_with(items, fn %{pos: {ix, iy}} ->
           (ix - x) * (ix - x) + (iy - y) * (iy - y) < @reach * @reach
         end) do
      {[found | others], rest} -> {found, others ++ rest}
      {[], rest} -> {nil, rest}
    end
  end
end
