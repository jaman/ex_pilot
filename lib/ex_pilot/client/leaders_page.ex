defmodule ExPilot.Client.LeadersPage do
  @moduledoc """
  The terminal client's leaders page: today, this week and all time side by side, the
  top ten by kills with their kills a death and rounds won, from `ExPilot.Ledger`.

      ExPilot.Client.LeadersPage.page()
  """

  alias ExPilot.Ledger

  @top 10
  @periods [day: "today", week: "this week", all: "all time"]
  @dim {130, 130, 140}

  @doc "The page: key `l` on the title."
  @spec page() :: Cauldron2D.Client.Game.page()
  def page, do: %{key: :l, hint: "Leaders", title: "Leaders", render: &render/0}

  @doc "The page's lines: a column a period, a row a pilot."
  @spec lines() :: [String.t()]
  def lines do
    columns = for {period, title} <- @periods, do: column(title, Ledger.board(period, :kills))
    depth = columns |> Enum.map(&length/1) |> Enum.max()

    for row <- 0..(depth - 1) do
      Enum.map_join(columns, "   ", fn column ->
        String.pad_trailing(Enum.at(column, row, ""), 34)
      end)
    end
  end

  defp column(title, []), do: [String.pad_trailing(title, 34), "nobody yet"]

  defp column(title, board) do
    [
      String.pad_trailing(title, 34)
      | board |> Enum.take(@top) |> Enum.with_index(1) |> Enum.map(&entry/1)
    ]
  end

  defp entry({%{name: name, value: kills, values: values}, rank}) do
    "#{String.pad_leading(Integer.to_string(rank), 2)}. #{String.pad_trailing(String.slice(name, 0, 12), 12)} #{String.pad_leading(Ledger.value(kills, :kills), 4)} kills  #{Ledger.value(values[:ratio] || 0, :ratio)} k/d  #{Ledger.value(values[:wins] || 0, :wins)} won"
  end

  defp render do
    [
      [
        {"The boards by kills, with kills a death and rounds won. Every round counts; robots do not.",
         %{fg: @dim}}
      ],
      []
    ] ++
      for line <- lines(), do: [{line, %{}}]
  end
end
