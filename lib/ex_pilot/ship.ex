defmodule ExPilot.Ship do
  @moduledoc """
  One player's ship: its body, fuel, shield, lives and score, and what it is doing.

  Positions are tiles; the ship turns through 64 headings. A dead ship keeps its place
  in the game with `alive?` false and a `respawn_in` countdown among its `t:timers/0`.
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
          base: {integer(), integer()},
          launch_heading: non_neg_integer(),
          held: MapSet.t(atom()),
          strength: %{atom() => float()},
          aim: {number(), number()} | nil,
          thrusting?: boolean(),
          shielding?: boolean(),
          timers: timers(),
          tally: tally(),
          race: race(),
          lives: integer() | :unlimited,
          landed?: boolean(),
          items: %{atom() => pos_integer()},
          max_fuel: float(),
          armour: non_neg_integer(),
          cloaked?: boolean(),
          deflecting?: boolean(),
          autopilot?: boolean(),
          missile: :torpedo | :smart | :heat,
          ball: term(),
          shape: String.t() | nil,
          held_before: MapSet.t(atom()),
          watching: term() | nil
        }

  @typedoc """
  The ship's clocks, in the game's seconds: `cooldown` until it can fire, `respawn_in`
  while dead, the `*_until` times its immunity, phasing, emergency shield, emergency
  thrust and confusion end, and `empty_since`, when its tank ran dry, or `nil`.
  """
  @type timers :: %{
          cooldown: float(),
          respawn_in: float(),
          immune_until: float(),
          phasing_until: float(),
          emergency_shield_until: float(),
          emergency_thrust_until: float(),
          ecm_until: float(),
          empty_since: float() | nil
        }

  @typedoc """
  The ship's count: `score`, `kills` and `deaths` over the whole game, the round's
  `streak` of kills without dying and its `best_streak`, seconds of `contact` with an
  enemy and the round's `best_contact`, and what `result/2` last `recorded`.
  """
  @type tally :: %{
          score: integer(),
          kills: non_neg_integer(),
          deaths: non_neg_integer(),
          streak: non_neg_integer(),
          best_streak: non_neg_integer(),
          contact: float(),
          best_contact: float(),
          recorded: %{kills: non_neg_integer(), deaths: non_neg_integer(), score: integer()}
        }

  @typedoc "Where the ship is in a race: the next `checkpoint`, `laps` done, and whether it has `finished?`."
  @type race :: %{checkpoint: non_neg_integer(), laps: non_neg_integer(), finished?: boolean()}

  @timers %{
    cooldown: 0.0,
    respawn_in: 0.0,
    immune_until: 0.0,
    phasing_until: 0.0,
    emergency_shield_until: 0.0,
    emergency_thrust_until: 0.0,
    ecm_until: 0.0,
    empty_since: nil
  }

  defstruct id: nil,
            name: "",
            team: nil,
            robot?: false,
            body: %Body{},
            fuel: 1000.0,
            alive?: true,
            base: {0, 0},
            launch_heading: 16,
            held: MapSet.new(),
            strength: %{},
            aim: nil,
            thrusting?: false,
            shielding?: false,
            timers: @timers,
            tally: %{
              score: 0,
              kills: 0,
              deaths: 0,
              streak: 0,
              best_streak: 0,
              contact: 0.0,
              best_contact: 0.0,
              recorded: %{kills: 0, deaths: 0, score: 0}
            },
            race: %{checkpoint: 0, laps: 0, finished?: false},
            lives: :unlimited,
            landed?: true,
            items: %{},
            max_fuel: 1000.0,
            armour: 0,
            cloaked?: false,
            deflecting?: false,
            autopilot?: false,
            missile: :torpedo,
            ball: nil,
            shape: nil,
            held_before: MapSet.new(),
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
      body:
        Body.new(
          pos: {bx + 0.5, by + 0.5},
          headings: @headings,
          heading: heading,
          radius: @radius
        )
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
      | body:
          Body.new(
            pos: {bx + 0.5, by + 0.5},
            headings: @headings,
            heading: ship.launch_heading,
            radius: @radius
          ),
        fuel: @max_fuel,
        max_fuel: @max_fuel,
        alive?: true,
        timers: %{@timers | immune_until: ship.timers.immune_until},
        thrusting?: false,
        shielding?: false,
        landed?: true,
        items: %{},
        armour: 0,
        cloaked?: false,
        deflecting?: false,
        autopilot?: false,
        ball: nil
    }
  end

  @doc """
  Fit the ship out with a kit: `:fuel` in the tank (the tank grows to hold it) and
  `:items` as counts by kind, given as `ExPilot.Items.pick_up/2` gives them.
  """
  @spec equip(t(), %{fuel: float(), items: %{atom() => non_neg_integer()}}) :: t()
  def equip(%__MODULE__{} = ship, %{fuel: fuel, items: items}) do
    kitted =
      Enum.reduce(items, ship, fn {kind, count}, acc ->
        Enum.reduce(1..count//1, acc, fn _, s -> ExPilot.Items.pick_up(s, kind) end)
      end)

    %{kitted | fuel: fuel, max_fuel: max(kitted.max_fuel, fuel)}
  end

  @doc "Give the ship its lives back for a new round, keeping its score; the round's streak and contact start over."
  @spec new_round(t(), integer() | :unlimited) :: t()
  def new_round(%__MODULE__{} = ship, lives) do
    ship = respawn(ship)
    tally = %{ship.tally | streak: 0, best_streak: 0, contact: 0.0, best_contact: 0.0}
    %{ship | lives: lives, tally: tally}
  end

  @doc "The ship with one of its `t:timers/0` set."
  @spec timer(t(), atom(), float() | nil) :: t()
  def timer(%__MODULE__{timers: timers} = ship, name, value) when is_map_key(timers, name),
    do: %{ship | timers: Map.put(timers, name, value)}

  @doc "Another `dt` seconds alive with an enemy in contact: the current stretch, and the round's longest."
  @spec in_contact(t(), float()) :: t()
  def in_contact(%__MODULE__{} = ship, dt) do
    contact = ship.tally.contact + dt
    tally = %{ship.tally | contact: contact, best_contact: max(ship.tally.best_contact, contact)}
    %{ship | tally: tally}
  end

  @doc """
  The ship's result since the last one was taken — kills, deaths and score gained,
  the round's best streak of kills without dying and longest contact in seconds — and
  the ship with those taken as recorded.
  """
  @spec result(t(), boolean()) :: {map(), t()}
  def result(%__MODULE__{tally: tally} = ship, won?) do
    row = %{
      id: ship.id,
      name: ship.name,
      robot?: ship.robot?,
      team: ship.team,
      won?: won?,
      kills: tally.kills - tally.recorded.kills,
      deaths: tally.deaths - tally.recorded.deaths,
      score: tally.score - tally.recorded.score,
      best_streak: tally.best_streak,
      best_contact: Float.round(tally.best_contact, 1),
      laps: ship.race.laps
    }

    recorded = %{kills: tally.kills, deaths: tally.deaths, score: tally.score}
    {row, %{ship | tally: %{tally | recorded: recorded}}}
  end

  @doc "Mark the ship dead, counting the death and starting the respawn clock."
  @spec die(t(), float()) :: t()
  def die(%__MODULE__{} = ship, respawn_after) do
    tally = %{
      ship.tally
      | deaths: ship.tally.deaths + 1,
        score: ship.tally.score - 1,
        streak: 0,
        contact: 0.0
    }

    %{
      ship
      | alive?: false,
        timers: %{ship.timers | respawn_in: respawn_after},
        tally: tally,
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
  def credit_kill(%__MODULE__{} = ship) do
    tally = ship.tally
    streak = tally.streak + 1

    %{
      ship
      | tally: %{
          tally
          | kills: tally.kills + 1,
            score: tally.score + 2,
            streak: streak,
            best_streak: max(tally.best_streak, streak)
        }
    }
  end

  @doc "Whether `action` is held."
  @spec holding?(t(), atom()) :: boolean()
  def holding?(%__MODULE__{held: held}, action), do: MapSet.member?(held, action)

  @doc "How hard `action` is held, 0.0 to 1.0: what an analog control said, 1.0 for a key."
  @spec strength(t(), atom()) :: float()
  def strength(%__MODULE__{strength: strength}, action), do: Map.get(strength, action, 1.0)

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
      phasing?: ship.timers.phasing_until > 0.0,
      ball: ship.ball,
      shape: ship.shape,
      score: ship.tally.score
    }
  end
end
