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
          held: MapSet.t(atom()),
          aim: {number(), number()} | nil,
          thrusting?: boolean(),
          shielding?: boolean(),
          cooldown: float(),
          score: integer(),
          kills: non_neg_integer(),
          deaths: non_neg_integer(),
          lives: integer() | :unlimited,
          landed?: boolean()
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
            held: MapSet.new(),
            aim: nil,
            thrusting?: false,
            shielding?: false,
            cooldown: 0.0,
            score: 0,
            kills: 0,
            deaths: 0,
            lives: :unlimited,
            landed?: true

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

  @doc "A new ship for `id` named `name`, resting on its base facing up."
  @spec new(term(), String.t(), {integer(), integer()}, keyword()) :: t()
  def new(id, name, {bx, by} = base, opts \\ []) do
    %__MODULE__{
      id: id,
      name: name,
      team: Keyword.get(opts, :team),
      robot?: Keyword.get(opts, :robot?, false),
      lives: Keyword.get(opts, :lives, :unlimited),
      base: base,
      body: Body.new(pos: {bx + 0.5, by + 0.5}, headings: @headings, heading: div(@headings, 4), radius: @radius)
    }
  end

  @doc "Put the ship back on its base with a full tank, alive."
  @spec respawn(t()) :: t()
  def respawn(%__MODULE__{base: {bx, by}} = ship) do
    %{
      ship
      | body: Body.new(pos: {bx + 0.5, by + 0.5}, headings: @headings, heading: div(@headings, 4), radius: @radius),
        fuel: @max_fuel,
        alive?: true,
        respawn_in: 0.0,
        thrusting?: false,
        shielding?: false,
        cooldown: 0.0,
        landed?: true
    }
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
      alive?: ship.alive?,
      landed?: ship.landed?,
      shielding?: ship.shielding?,
      thrusting?: ship.thrusting?,
      score: ship.score
    }
  end
end
