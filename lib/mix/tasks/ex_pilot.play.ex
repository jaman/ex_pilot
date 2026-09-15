defmodule Mix.Tasks.ExPilot.Play do
  @shortdoc "Play ExPilot in this terminal, no ssh"

  @moduledoc """
  Open the bundled arenas and run the client in this terminal, with sound through this
  machine's speaker.

      mix ex_pilot.play
      mix ex_pilot.play --maps priv/maps --name alice --robots 3
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [maps: :string, name: :string, robots: :integer])
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
      ExPilot.Arenas.open(id, path, Keyword.take(opts, [:robots]))
    end

    Drafter.run(Cauldron2D.Drafter.Client, props: %{game: ExPilot.Client, username: Keyword.get(opts, :name, "pilot")})
  end
end
