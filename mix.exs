defmodule ExPilot.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :ex_pilot,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_options: [warnings_as_errors: true],
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger, :ssh, :inets, :ssl], mod: {ExPilot.Application, []}]
  end

  defp deps do
    [
      {:cauldron_2d, path: "../cauldron_2d"},
      {:cauldron_2d_drafter, path: "../cauldron_2d_drafter"},
      {:drafter, path: "../drafter"},
      {:french_curve, path: "../french_curve", override: true},
      {:linocut, path: "../linocut"},
      {:tuning_fork, path: "../tuning_fork/tuning_fork"},
      {:tuning_fork_speaker, path: "../tuning_fork/tuning_fork_speaker"}
    ]
  end
end
