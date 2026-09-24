defmodule ExPilot.RadarTest do
  use ExUnit.Case, async: true

  alias ExPilot.Radar

  test "the walls of a big map are scaled once, so a frame's radar costs the marks alone" do
    rows =
      for y <- 0..299,
          do: for(x <- 0..299, do: if(rem(x * y, 7) == 0, do: "x", else: " ")) |> Enum.join()

    {:ok, big} =
      ExPilot.Map.parse(
        "mapwidth: 300\nmapheight: 300\nmapname: big radar\nmapData: \\multiline: END\n" <>
          Enum.join(rows, "\n") <> "\nEND\n"
      )

    view = %{
      me: %{id: :a, team: nil},
      ships: [%{id: :a, pos: {5.0, 5.0}, alive?: true, team: nil}]
    }

    first = Radar.rows(big, view, {30, 12})
    {us, again} = :timer.tc(fn -> for _ <- 1..30, do: Radar.rows(big, view, {30, 12}) end)
    assert List.last(again) == first
    assert us < 150_000, "thirty radar frames took #{div(us, 1000)} ms"
  end
end
