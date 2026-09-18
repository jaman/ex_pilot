defmodule ExPilot.Mode do
  @moduledoc """
  The kinds of arena `ExPilot.Game.mode/1` tells apart, in words and in colour, for every
  client's lobby.

      ExPilot.Mode.name(:ctf)
      ExPilot.Mode.colour(:ctf)
      ExPilot.Mode.kind(:ctf)
  """

  @names %{
    dogfight: "dogfight",
    ctf: "capture the flag",
    team: "team battle",
    race: "race",
    duel: "duel"
  }
  @colours %{
    dogfight: {255, 184, 77},
    ctf: {111, 227, 154},
    team: {127, 214, 255},
    race: {217, 160, 255},
    duel: {255, 107, 107}
  }

  @doc "The kind in words."
  @spec name(atom() | String.t()) :: String.t()
  def name(mode), do: Map.get(@names, atom(mode), to_string(mode))

  @doc "The kind's colour."
  @spec colour(atom() | String.t()) :: {byte(), byte(), byte()}
  def colour(mode), do: Map.get(@colours, atom(mode), {200, 200, 210})

  @doc "The kind as a lobby lists it: `{name, colour}`."
  @spec kind(atom() | String.t()) :: {String.t(), {byte(), byte(), byte()}}
  def kind(mode), do: {name(mode), colour(mode)}

  @doc "The mode a lobby's kind stands for; `:dogfight` for a kind that is none of them."
  @spec of_kind({String.t(), tuple()} | nil) :: atom()
  def of_kind({name, _colour}),
    do: Enum.find_value(@names, :dogfight, fn {mode, text} -> if text == name, do: mode end)

  def of_kind(_none), do: :dogfight

  defp atom(mode) when is_atom(mode), do: mode

  defp atom(mode) when is_binary(mode),
    do: Enum.find(Map.keys(@names), &(Atom.to_string(&1) == mode))
end
