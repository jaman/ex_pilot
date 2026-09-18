defmodule Mix.Tasks.ExPilot.Desktop do
  @shortdoc "Play ExPilot in a window"

  @moduledoc """
  Open the desktop client: a wx window that joins a server by URL, a node, or the
  arenas this app serves itself from its Server page.

      mix ex_pilot.desktop
      mix ex_pilot.desktop --url http://arcade:2280 --name alice
      mix ex_pilot.desktop --node expilot@arcade --cookie secret

  ## Options

    * `--url` — the server's address for the Play page. Default `http://localhost:2280`
    * `--name` — the pilot's name. Default `pilot`
    * `--node`, `--cookie` — a node to connect to, and its cookie
    * `--maps` — a directory of map files, or one file, for the arenas this app serves.
      Default: the bundled maps
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [url: :string, name: :string, node: :string, cookie: :string, maps: :string]
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
      ExPilot.Arenas.register(id, path)
    end

    ExPilot.Wx.run(fields: Map.new(Keyword.take(opts, [:url, :name, :node, :cookie])))
  end
end
