defmodule Mix.Tasks.ExPilot.Serve do
  @shortdoc "Serve ExPilot over ssh"

  @moduledoc """
  Start the ExPilot ssh server and keep it running.

      mix ex_pilot.serve
      mix ex_pilot.serve --port 2222 --accounts /var/lib/ex_pilot/accounts.bin --maps priv/maps

  ## Options

    * `--port` — the ssh port. Default `2222`
    * `--accounts` — the account file. Default `ex_pilot_accounts.bin`
    * `--maps` — a directory of map files, or one file. Default: the bundled maps
    * `--robots` — robots per arena
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [port: :integer, accounts: :string, maps: :string, robots: :integer])
    Mix.Task.run("app.start")

    server_opts =
      [port: Keyword.get(opts, :port, 2222), accounts: Keyword.get(opts, :accounts, "ex_pilot_accounts.bin")] ++
        maps_opt(Keyword.get(opts, :maps)) ++ Keyword.take(opts, [:robots])

    case ExPilot.Server.start(server_opts) do
      {:ok, %{arenas: arenas}} ->
        Mix.shell().info("ExPilot on port #{server_opts[:port]}, arenas: #{Enum.join(arenas, ", ")}")
        Mix.shell().info("connect with: ssh -p #{server_opts[:port]} -R 24713:localhost:4713 new@host")
        Process.sleep(:infinity)

      {:error, reason} ->
        Mix.raise("could not start: #{inspect(reason)}")
    end
  end

  defp maps_opt(nil), do: []

  defp maps_opt(path) do
    if File.dir?(path), do: [maps: Path.wildcard(Path.join(path, "*.map*"))], else: [maps: [path]]
  end
end
