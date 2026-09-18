defmodule Mix.Tasks.ExPilot.Load do
  @shortdoc "Load a running ExPilot server with players and watchers"

  @moduledoc """
  Run `Cauldron2D.Net.Load` against an ExPilot server started elsewhere
  (`mix ex_pilot.serve` in another terminal, or another machine), with the players
  holding ExPilot's own actions: a report every few seconds, a summary at the end, and
  every report and the summary written as JSON lines to a file as the run goes.
  `Enter` ends the run early with the summary of what was measured; `Ctrl-C` kills
  the run, and the file has every report up to it.

      mix ex_pilot.load --url http://localhost:2280 --players 20 --watchers 50 --seconds 60
      mix ex_pilot.load --players 10 --ramp 10 --every 10 --seconds 300
      mix ex_pilot.load --players 10 --ramp 10 --audio off

  ## Options

    * `--url` — the server. Default `http://localhost:2280`
    * `--players`, `--watchers` — sessions to start with. Default 10 and 0
    * `--arenas` — arena ids, comma separated. Default every arena the server lists
    * `--seconds` — how long to run. Default 30
    * `--every` — seconds between reports and ramp steps. Default 5
    * `--ramp` — sessions to add at every report until the run is degraded
    * `--audio` — `personal` (default) for sessions that take the server's sound, `off`
      for sessions that ask for none, to load the worlds and the wire alone
    * `--out` — the JSON lines file. Default `$XDG_DATA_HOME/expilot/load/<time>.jsonl`
    * `--password` — the load accounts' password. Default `load test`
  """

  use Mix.Task

  alias Cauldron2D.Net.Load

  @held [:turn_left, :turn_right, :thrust, :fire]

  defp audio("personal"), do: :personal
  defp audio("off"), do: :off
  defp audio(other), do: Mix.raise("--audio takes personal or off, not #{inspect(other)}")

  @impl Mix.Task
  def run(args) do
    {opts, _} =
      OptionParser.parse!(args,
        strict: [
          url: :string,
          players: :integer,
          watchers: :integer,
          arenas: :string,
          seconds: :integer,
          every: :integer,
          ramp: :integer,
          audio: :string,
          out: :string,
          password: :string
        ]
      )

    Mix.Task.run("app.config")
    Application.ensure_all_started(:mint)
    Application.ensure_all_started(:jason)

    out =
      Keyword.get_lazy(opts, :out, fn ->
        Cauldron2D.Paths.data(
          :expilot,
          "load/#{DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(:basic)}.jsonl"
        )
      end)

    opts =
      opts
      |> Keyword.update(:url, "http://localhost:2280/api", &(&1 <> "/api"))
      |> Keyword.put(:actions, Enum.map(@held, &Atom.to_string/1))
      |> Keyword.put(:topic, "arena")
      |> Keyword.put(:out, out)
      |> Keyword.update(:audio, :personal, &audio/1)

    opts =
      case Keyword.pop(opts, :arenas) do
        {nil, opts} ->
          opts

        {names, opts} ->
          Keyword.put(opts, :arenas, names |> String.split(",") |> Enum.map(&String.trim/1))
      end

    spawn_link(fn ->
      IO.gets("")
      Load.stop()
    end)

    Mix.shell().info("writing #{out}  ·  Enter ends the run with the summary so far")
    summary = Load.run(opts)
    Mix.shell().info("")

    refusals =
      Enum.map_join(summary.refusals, ", ", fn {reason, count} ->
        "#{count} × #{inspect(reason)}"
      end)

    Mix.shell().info(
      "sessions #{summary.joined}/#{summary.sessions} joined, #{summary.refused} refused" <>
        if(refusals == "", do: "", else: " (#{refusals})")
    )

    Mix.shell().info(
      "frames a second #{Float.round(summary.fps.mean, 1)} mean, #{Float.round(summary.fps.min, 1)} least, of #{summary.server.hz} (the busiest world ran #{Float.round(summary.server.steps_per_second, 1)} steps a second at the end)"
    )

    Mix.shell().info(
      "longest gap between frames #{summary.gap_ms.max}ms; joins took #{summary.join_ms.mean}ms mean, #{summary.join_ms.max}ms most"
    )

    case summary.degraded do
      nil ->
        Mix.shell().info("never degraded")

      %{sessions: sessions, why: why} ->
        Mix.shell().info("degraded at #{sessions} sessions: " <> Enum.join(why, "; "))
    end

    if summary.capacity, do: Mix.shell().info("capacity: #{summary.capacity} sessions")
    if summary.stopped == :asked, do: Mix.shell().info("stopped early, as asked")
    Mix.shell().info("record: #{out}")
  end
end
