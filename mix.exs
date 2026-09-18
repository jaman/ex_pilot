defmodule ExPilot.MixProject do
  use Mix.Project

  @version "0.1.1"
  @source_url "https://github.com/jaman/ex_pilot"
  @description "An XPilot for the terminal, over ssh, in the browser and on the desktop, on Cauldron."

  def project do
    [
      app: :ex_pilot,
      version: @version,
      elixir: "~> 1.18",
      description: @description,
      start_permanent: Mix.env() == :prod,
      elixirc_options: [warnings_as_errors: true],
      deps: deps(),
      name: "ExPilot",
      source_url: @source_url,
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :ssh, :inets, :ssl, :crypto, :wx],
      mod: {ExPilot.Application, []}
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      family(:cauldron_2d, "~> 0.1.3", "../cauldron/cauldron_2d", []),
      family(:cauldron_2d_drafter, "~> 0.1.3", "../cauldron/cauldron_2d_drafter", []),
      family(:cauldron_2d_net, "~> 0.1.3", "../cauldron/cauldron_2d_net", []),
      family(:cauldron_2d_wx, "~> 0.1.3", "../cauldron/cauldron_2d_wx", []),
      {:phoenix, "~> 1.8"},
      {:phoenix_live_view, "~> 1.2"},
      {:phoenix_html, "~> 4.2"},
      {:bandit, "~> 1.12"},
      {:jason, "~> 1.4"},
      {:lazy_html, ">= 0.1.0", only: :test},
      family(:drafter, "~> 0.4.0", "../drafter", []),
      family(:french_curve, "~> 0.1.4", "../french_curve", override: true),
      family(:linocut, "~> 0.1.3", "../cauldron/linocut", []),
      family(:tuning_fork, "~> 0.1.11", "../tuning_fork/tuning_fork", []),
      family(:tuning_fork_speaker, "~> 0.1.11", "../tuning_fork/tuning_fork_speaker", [])
    ]
  end

  defp family(app, requirement, path, opts) do
    if System.get_env("PLUMB_HEX") == nil and File.dir?(path),
      do: {app, [path: path] ++ opts},
      else: {app, requirement, Keyword.delete(opts, :override)}
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files:
        ~w(lib config priv/maps/dogfight.map.gz priv/scores priv/static mix.exs README.md TECHNICAL.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url_pattern: "#{@source_url}/blob/v#{@version}/%{path}#L%{line}",
      extras: ["README.md", "TECHNICAL.md"]
    ]
  end
end
