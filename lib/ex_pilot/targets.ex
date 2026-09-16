defmodule ExPilot.Targets do
  @moduledoc """
  Targets: the `!` tiles a team defends. Each belongs to the team of the nearest base,
  takes three hits from anything but its own team, and comes back a minute after it is
  destroyed. Destroying one scores for the shooter's team.

      ExPilot.Targets.new(arena)
      ExPilot.Targets.hit(targets, cell, team)
  """

  alias ExPilot.Map, as: Arena

  @type target :: %{pos: {integer(), integer()}, team: integer() | nil, hits: non_neg_integer(), respawn_in: float()}

  @hits 3
  @respawn 60.0
  @score 10

  @doc "A target for every `!` on `arena`, each with its team."
  @spec new(Arena.t()) :: [target()]
  def new(%Arena{} = arena) do
    bases = Arena.bases(arena)
    for pos <- Arena.targets(arena), do: %{pos: pos, team: team_near(bases, pos), hits: 0, respawn_in: 0.0}
  end

  defp team_near([], _pos), do: nil

  defp team_near(bases, {x, y}) do
    bases
    |> Enum.min_by(fn %{pos: {bx, by}} -> (bx - x) * (bx - x) + (by - y) * (by - y) end)
    |> Map.get(:team)
  end

  @doc "Whether the target at `cell` stands, so a shot stops there."
  @spec standing?([target()], {integer(), integer()}) :: boolean()
  def standing?(targets, cell), do: Enum.any?(targets, &(&1.pos == cell and &1.respawn_in <= 0.0))

  @doc """
  A shot from `team` hits the target at `cell`.

  Returns `{targets, outcome}`: `:hit`, `{:destroyed, team, points}` for the shooter's
  team, or `:none` when no standing target is there or it is the shooter's own.
  """
  @spec hit([target()], {integer(), integer()}, integer() | nil) :: {[target()], :none | :hit | {:destroyed, integer() | nil, pos_integer()}}
  def hit(targets, cell, team) do
    case Enum.find_index(targets, &(&1.pos == cell and &1.respawn_in <= 0.0)) do
      nil ->
        {targets, :none}

      index ->
        target = Enum.at(targets, index)

        cond do
          target.team != nil and target.team == team ->
            {targets, :none}

          target.hits + 1 >= @hits ->
            {List.replace_at(targets, index, %{target | hits: 0, respawn_in: @respawn}), {:destroyed, team, @score}}

          true ->
            {List.replace_at(targets, index, %{target | hits: target.hits + 1}), :hit}
        end
    end
  end

  @doc "Let `dt` seconds pass: destroyed targets come back when their time is up."
  @spec step([target()], float()) :: [target()]
  def step(targets, dt), do: Enum.map(targets, &%{&1 | respawn_in: max(0.0, &1.respawn_in - dt)})

  @doc "The cells of targets currently destroyed."
  @spec gone([target()]) :: MapSet.t()
  def gone(targets), do: for(%{pos: pos, respawn_in: left} <- targets, left > 0.0, into: MapSet.new(), do: pos)

  @doc "Whether `team` has a target standing."
  @spec standing_for?([target()], integer() | nil) :: boolean()
  def standing_for?(targets, team), do: Enum.any?(targets, &(&1.team == team and &1.respawn_in <= 0.0))
end
