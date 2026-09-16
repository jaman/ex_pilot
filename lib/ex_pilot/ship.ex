defmodule ExPilot.Ship do
  @moduledoc """
  One player's ship: its body, fuel, shield, lives and score, and what it is doing.

  Positions are tiles; the ship turns through 64 headings. A dead ship keeps its place
  in the game with `alive?` false and a `respawn_in` countdown.
  """

  alias Cauldron2D.Body

  @type t :: %__MODULE__{
          id: term(),
          name: String.t(),
          team: integer() | nil,
          robot?: boolean(),
          body: Body.t(),
          fuel: float(),
          alive?: boolean(),
          respawn_in: float(),
          base: {integer(), integer()},
          launch_heading: non_neg_integer(),
          immune_until: float(),
          held: MapSet.t(atom()),
          aim: {number(), number()} | nil,
          thrusting?: boolean(),
          shielding?: boolean(),
          cooldown: float(),
          score: integer(),
          kills: non_neg_integer(),
          deaths: non_neg_integer(),
          lives: integer() | :unlimited,
          landed?: boolean(),
          items: %{atom() => pos_integer()},
          max_fuel: float(),
          armour: non_neg_integer(),
          cloaked?: boolean(),
          deflecting?: boolean(),
          phasing_until: float(),
          emergency_shield_until: float(),
          emergency_thrust_until: float(),
          autopilot?: boolean(),
          missile: :torpedo | :smart | :heat,
          ball: term(),
          checkpoint: non_neg_integer(),
          laps: non_neg_integer(),
          finished?: boolean(),
          ecm_until: float(),
          shape: String.t() | nil,
          held_before: MapSet.t(atom()),
          empty_since: float() | nil,
          watching: term() | nil
        }

  defstruct id: nil,
            name: "",
            team: nil,
            robot?: false,
            body: %Body{},
            fuel: 1000.0,
            alive?: true,
            respawn_in: 0.0,
            base: {0, 0},
            launch_heading: 16,
            immune_until: 0.0,
            held: MapSet.new(),
            aim: nil,
            thrusting?: false,
            shielding?: false,
            cooldown: 0.0,
            score: 0,
            kills: 0,
            deaths: 0,
            lives: :unlimited,
            landed?: true,
            items: %{},
            max_fuel: 1000.0,
            armour: 0,
            cloaked?: false,
            deflecting?: false,
            phasing_until: 0.0,
            emergency_shield_until: 0.0,
            emergency_thrust_until: 0.0,
            autopilot?: false,
            missile: :torpedo,
            ball: nil,
            checkpoint: 0,
            laps: 0,
            finished?: false,
            ecm_until: 0.0,
            shape: nil,
            held_before: MapSet.new(),
            empty_since: nil,
            watching: nil

  @headings 64
  @radius 0.45
  @max_fuel 1000.0

  @doc "The number of headings a ship turns through."
  @spec headings() :: pos_integer()
  def headings, do: @headings

  @doc "A ship's radius in tiles."
  @spec radius() :: float()
  def radius, do: @radius

  @doc "A full tank."
  @spec max_fuel() :: float()
  def max_fuel, do: @max_fuel

  @doc "A new ship for `id` named `name`, resting on its base facing the way `:dir` says (`:up` by default)."
  @spec new(term(), String.t(), {integer(), integer()}, keyword()) :: t()
  def new(id, name, {bx, by} = base, opts \\ []) do
    heading = launch_heading(Keyword.get(opts, :dir, :up))

    %__MODULE__{
      id: id,
      name: name,
      team: Keyword.get(opts, :team),
      robot?: Keyword.get(opts, :robot?, false),
      lives: Keyword.get(opts, :lives, :unlimited),
      shape: Keyword.get(opts, :shape),
      base: base,
      launch_heading: heading,
      body: Body.new(pos: {bx + 0.5, by + 0.5}, headings: @headings, heading: heading, radius: @radius)
    }
  end

  @doc "The heading a ship faces on a base with `dir`."
  @spec launch_heading(:up | :down | :left | :right) :: non_neg_integer()
  def launch_heading(:up), do: div(@headings, 4)
  def launch_heading(:down), do: 3 * div(@headings, 4)
  def launch_heading(:left), do: div(@headings, 2)
  def launch_heading(:right), do: 0

  @doc "Put the ship back on its base with a full tank, alive."
  @spec respawn(t()) :: t()
  def respawn(%__MODULE__{base: {bx, by}} = ship) do
    %{
      ship
      | body: Body.new(pos: {bx + 0.5, by + 0.5}, headings: @headings, heading: ship.launch_heading, radius: @radius),
        fuel: @max_fuel,
        max_fuel: @max_fuel,
        alive?: true,
        respawn_in: 0.0,
        thrusting?: false,
        shielding?: false,
        cooldown: 0.0,
        landed?: true,
        items: %{},
        armour: 0,
        cloaked?: false,
        deflecting?: false,
        phasing_until: 0.0,
        emergency_shield_until: 0.0,
        emergency_thrust_until: 0.0,
        autopilot?: false,
        ball: nil,
        ecm_until: 0.0,
        empty_since: nil
    }
  end

  @doc """
  Fit the ship out with a kit: `:fuel` in the tank (the tank grows to hold it) and
  `:items` as counts by kind, given as `ExPilot.Items.pick_up/2` gives them.
  """
  @spec equip(t(), %{fuel: float(), items: %{atom() => non_neg_integer()}}) :: t()
  def equip(%__MODULE__{} = ship, %{fuel: fuel, items: items}) do
    kitted = Enum.reduce(items, ship, fn {kind, count}, acc -> Enum.reduce(1..count//1, acc, fn _, s -> ExPilot.Items.pick_up(s, kind) end) end)
    %{kitted | fuel: fuel, max_fuel: max(kitted.max_fuel, fuel)}
  end

  @doc "Give the ship its lives back for a new round, keeping its score."
  @spec new_round(t(), integer() | :unlimited) :: t()
  def new_round(%__MODULE__{} = ship, lives), do: %{respawn(ship) | lives: lives}

  @doc "Mark the ship dead, counting the death and starting the respawn clock."
  @spec die(t(), float()) :: t()
  def die(%__MODULE__{} = ship, respawn_after) do
    %{
      ship
      | alive?: false,
        respawn_in: respawn_after,
        deaths: ship.deaths + 1,
        score: ship.score - 1,
        thrusting?: false,
        shielding?: false,
        lives: spend_life(ship.lives)
    }
  end

  defp spend_life(:unlimited), do: :unlimited
  defp spend_life(lives), do: lives - 1

  @doc "Whether the ship has a life left to respawn with."
  @spec can_respawn?(t()) :: boolean()
  def can_respawn?(%__MODULE__{lives: :unlimited}), do: true
  def can_respawn?(%__MODULE__{lives: lives}), do: lives > 0

  @doc "Credit a kill."
  @spec credit_kill(t()) :: t()
  def credit_kill(%__MODULE__{} = ship), do: %{ship | kills: ship.kills + 1, score: ship.score + 2}

  @doc "Whether `action` is held."
  @spec holding?(t(), atom()) :: boolean()
  def holding?(%__MODULE__{held: held}, action), do: MapSet.member?(held, action)

  @doc "The ship's position."
  @spec pos(t()) :: Body.point()
  def pos(%__MODULE__{body: body}), do: body.pos

  @doc "What another player sees of this ship."
  @spec summary(t()) :: map()
  def summary(%__MODULE__{} = ship) do
    %{
      id: ship.id,
      name: ship.name,
      team: ship.team,
      pos: ship.body.pos,
      vel: ship.body.vel,
      heading: ship.body.heading,
      launch_heading: ship.launch_heading,
      alive?: ship.alive?,
      landed?: ship.landed?,
      shielding?: ship.shielding?,
      thrusting?: ship.thrusting?,
      cloaked?: ship.cloaked?,
      deflecting?: ship.deflecting?,
      phasing?: ship.phasing_until > 0.0,
      ball: ship.ball,
      shape: ship.shape,
      score: ship.score
    }
  end
end
