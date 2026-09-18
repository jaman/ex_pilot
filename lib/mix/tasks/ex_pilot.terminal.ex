defmodule Mix.Tasks.ExPilot.Terminal do
  @shortdoc "ExPilot in this terminal: play here, connect elsewhere, host a server"

  @moduledoc """
  Run `ExPilot.Terminal`: the desktop's flow in a terminal — play the arenas this
  program carries, connect to a node or a server, host a server for others, see the
  leaders.

      mix ex_pilot.terminal
      mix ex_pilot.terminal --name alice --url http://arcade:2280
      mix ex_pilot.terminal --node expilot@arcade --cookie secret

  ## Options

    * `--name` — the pilot's name. Default `pilot`
    * `--url`, `--node`, `--cookie` — what the connect form starts with
    * `--maps` — a directory of map files, or one file, for the arenas this program
      carries. Default: the bundled maps
    * `--robots` — robots per arena
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          name: :string,
          url: :string,
          node: :string,
          cookie: :string,
          maps: :string,
          robots: :integer
        ]
      )

    Mix.Task.run("app.start")
    Code.ensure_loaded!(Cauldron2D.Drafter.Surface)
    Drafter.Widget.Registry.register(Cauldron2D.Drafter.Surface)
    ExPilot.Art.install()

    paths =
      case Keyword.get(opts, :maps) do
        nil -> ExPilot.Server.bundled_maps()
        dir -> if File.dir?(dir), do: Path.wildcard(Path.join(dir, "*.map*")), else: [dir]
      end

    for path <- paths do
      id = path |> Path.basename() |> String.replace(~r/\.map(\.gz)?\z/, "") |> String.to_atom()
      ExPilot.Arenas.register(id, path, Keyword.take(opts, [:robots]))
    end

    props =
      opts
      |> Keyword.take([:url, :node, :cookie])
      |> Map.new()
      |> Map.put(:username, Keyword.get(opts, :name, "pilot"))

    Drafter.run(ExPilot.Terminal, props: props)
  end
end
