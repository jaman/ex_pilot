defmodule ExPilot.Music.Score do
  @moduledoc """
  Helpers for writing a piece's Strudel chains.

      ExPilot.Music.Score.cycles(["Em!4 C!4", "G!4 D!4"])
      ExPilot.Music.Score.roots("<Em C G D>")
  """

  @doc "The phrases as one `<…>` cycle list, one phrase per bar group in turn."
  @spec cycles([String.t()]) :: String.t()
  def cycles(phrases), do: "<" <> Enum.join(phrases, " ") <> ">"

  @doc "The chord names in a cycle list as root notes in `octave`, for a bass line."
  @spec roots(String.t(), String.t()) :: String.t()
  def roots(chords, octave \\ "2") do
    String.replace(chords, ~r/([A-G])(#|b)?(m7|m|M7|9|7)?/, fn full -> root_of(full) <> octave end)
  end

  @doc "A chord name's root as a Strudel note name: `\"C#m\"` is `\"cs\"`."
  @spec root_of(String.t()) :: String.t()
  def root_of(chord), do: chord |> String.replace(~r/(m7|m|M7|9|7)$/, "") |> String.replace("#", "s") |> String.replace("b", "f") |> String.downcase()
end
