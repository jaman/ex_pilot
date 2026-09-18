defmodule ExPilot.Music.Instruments do
  @moduledoc """
  The recorded instruments the pieces play beside the synthesised ones, registered with
  `TuningFork.Sfz` when the application starts: FreePats' fingered and picked electric
  bass and Karoryfer Samples' meatbass, all CC0, fetched from where they are published.
  """

  @instruments %{
    "fingerbass" => %{
      source: "github:freepats/electric-bass-YR/master/FingerBassYR 20190930.sfz",
      licence: "CC0 1.0",
      credit: "FreePats, Yamaha RBX bass",
      what: "an electric bass, fingered"
    },
    "pickbass" => %{
      source: "github:freepats/electric-bass-YR/master/PickedBassYR 20190930.sfz",
      licence: "CC0 1.0",
      credit: "FreePats, Yamaha RBX bass",
      what: "an electric bass, picked"
    },
    "meatbass" => %{
      source: "github:sfzinstruments/karoryfer.meatbass/master/Programs/pizz_basic_map.sfz",
      licence: "CC0 1.0",
      credit: "Karoryfer Samples, a 1958 Otto Rubner double bass",
      what: "a double bass, plucked"
    }
  }

  @doc "The instruments by name, as `TuningFork.Sfz.register/1` takes them."
  @spec instruments() :: %{String.t() => TuningFork.Sfz.instrument()}
  def instruments, do: @instruments

  @doc "Register every instrument with `TuningFork.Sfz`."
  @spec register() :: :ok
  def register, do: TuningFork.Sfz.register(@instruments)
end
