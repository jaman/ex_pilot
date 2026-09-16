defmodule ExPilot.RadarTest do
  use ExUnit.Case, async: true

  alias ExPilot.Radar

  @arena """
  mapwidth: 8
  mapheight: 8
  mapData: \\multiline: END
  xxxxxxxx
  x      x
  x _    x
  x      x
  x      x
  x      x
  x      x
  xxxxxxxx
  END
  """

  test "with playersonradar off only the player's own ship is marked" do
    {:ok, arena} = ExPilot.Map.parse(@arena)
    view = %{me: %{id: :a, team: nil}, radar: %{players?: false}, ships: [%{id: :a, pos: {2.5, 2.5}, alive?: true, team: nil}, %{id: :b, pos: {6.5, 6.5}, alive?: true, team: nil}]}
    colours = Radar.rows(arena, view, {4, 2}) |> List.flatten() |> Enum.map(&elem(&1, 1)) |> Enum.uniq()
    assert {255, 220, 40} in colours
    refute {255, 90, 90} in colours
  end

  test "draws the walls, the bases and every ship, the player brightest" do
    {:ok, arena} = ExPilot.Map.parse(@arena)
    view = %{me: %{id: :a, team: nil}, ships: [%{id: :a, pos: {2.5, 2.5}, alive?: true, team: nil}, %{id: :b, pos: {6.5, 6.5}, alive?: true, team: nil}]}
    rows = Radar.rows(arena, view, {4, 2})

    assert length(rows) == 2
    text = rows |> Enum.map(fn runs -> Enum.map_join(runs, &elem(&1, 0)) end)
    assert Enum.all?(text, &(String.length(&1) == 4))
    colours = rows |> List.flatten() |> Enum.map(&elem(&1, 1)) |> Enum.uniq()
    assert {255, 220, 40} in colours
    assert {255, 90, 90} in colours
    assert {70, 100, 230} in colours
  end

  test "the walls of a big map are scaled once, so a frame's radar costs the marks alone" do
    rows = for y <- 0..299, do: for(x <- 0..299, do: if(rem(x * y, 7) == 0, do: "x", else: " ")) |> Enum.join()
    {:ok, big} = ExPilot.Map.parse("mapwidth: 300\nmapheight: 300\nmapname: big radar\nmapData: \\multiline: END\n" <> Enum.join(rows, "\n") <> "\nEND\n")
    view = %{me: %{id: :a, team: nil}, ships: [%{id: :a, pos: {5.0, 5.0}, alive?: true, team: nil}]}

    first = Radar.rows(big, view, {30, 12})
    {us, again} = :timer.tc(fn -> for _ <- 1..30, do: Radar.rows(big, view, {30, 12}) end)
    assert List.last(again) == first
    assert us < 150_000, "thirty radar frames took #{div(us, 1000)} ms"
  end

  test "a ship is a two-by-two mark, a base a single dot, so ships stand out on a big map" do
    {:ok, arena} = ExPilot.Map.parse(@arena)
    view = %{me: %{id: :a, team: nil}, ships: [%{id: :b, pos: {4.0, 4.0}, alive?: true, team: nil}]}
    dots = fn {columns, rows} -> for row <- Radar.rows(arena, view, {columns, rows}), {text, colour} <- row, cell <- String.to_charlist(text), cell != 0x2800, do: {colour, cell} end

    lit = fn colour -> dots.({8, 4}) |> Enum.filter(&(elem(&1, 0) == colour)) |> Enum.map(fn {_, cell} -> (cell - 0x2800) |> Integer.digits(2) |> Enum.sum() end) |> Enum.sum() end
    assert lit.({255, 90, 90}) == 4
    assert lit.({150, 150, 165}) == 1
  end
end
