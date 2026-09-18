defmodule ExPilot.LedgerTest do
  use ExUnit.Case, async: false

  alias ExPilot.Ledger

  test "the boards rank by ExPilot's metrics, every one of them valued in the entry" do
    row = %{
      id: "ledger_ann",
      name: "ann",
      robot?: false,
      team: nil,
      won?: true,
      kills: 6,
      deaths: 2,
      score: 9,
      best_streak: 4,
      best_contact: 12.5,
      laps: 3,
      mode: :race
    }

    :ok = Cauldron2D.Ledger.record(Ledger, "ledgertest", row)

    :ok =
      Cauldron2D.Ledger.record(Ledger, "ledgertest", %{
        row
        | id: "ledger_ben",
          name: "ben",
          kills: 2,
          deaths: 0,
          won?: false,
          best_streak: 2,
          best_contact: 30.0,
          laps: 1
      })

    assert [
             %{
               name: "ann",
               value: 6,
               values: %{ratio: 3.0, wins: 1, streak: 4, contact: 12.5, laps: 3}
             },
             %{name: "ben", value: 2}
           ] = Ledger.board(:all, :kills, arena: "ledgertest")

    assert [%{name: "ben"}, %{name: "ann"}] = Ledger.board(:all, :contact, arena: "ledgertest")
    assert [] = Ledger.board(:all, :kills, arena: "nowhere")
    assert Enum.map(Ledger.metrics(), &elem(&1, 0)) == Cauldron2D.Ledger.metrics(Ledger)
  end

  test "results of names matching a pattern are forgotten, the load tool's among them" do
    row = %{
      id: "load_7",
      name: "load_7",
      robot?: false,
      team: nil,
      won?: true,
      kills: 60,
      deaths: 0,
      score: 90,
      best_streak: 40,
      best_contact: 12.5,
      laps: 3,
      mode: :dogfight
    }

    :ok = Cauldron2D.Ledger.record(Ledger, "forgettest", row)
    :ok = Cauldron2D.Ledger.record(Ledger, "forgettest", %{row | id: "load_8", name: "load_8"})

    :ok =
      Cauldron2D.Ledger.record(Ledger, "forgettest", %{
        row
        | id: "ledger_cal",
          name: "cal",
          kills: 1
      })

    assert Ledger.forget("load_*") == 2
    assert [%{name: "cal"}] = Ledger.board(:all, :kills, arena: "forgettest")
    assert Ledger.forget("load_*") == 0
    assert Ledger.forget("cal") == 1
  end

  test "values read as the boards show them" do
    assert Ledger.value(12.5, :contact) == "12.5 s"
    assert Ledger.value(3, :ratio) == "3.00"
    assert Ledger.value(6, :kills) == "6"
  end
end
