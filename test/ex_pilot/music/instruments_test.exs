defmodule ExPilot.Music.InstrumentsTest do
  use ExUnit.Case, async: false

  alias ExPilot.Music.Instruments

  test "the recorded basses the pieces play are registered with the kit, with their licences" do
    Instruments.register()

    for name <- ["fingerbass", "pickbass", "meatbass"] do
      assert TuningFork.Sfz.instrument?(name)

      assert %{licence: "CC0 1.0", credit: credit, source: "github:" <> _} =
               TuningFork.Sfz.instruments()[name]

      assert credit =~ ~r/FreePats|Karoryfer/
    end
  end
end
