defmodule Mix.Tasks.ExPilot.Maps do
  @shortdoc "Download the classic XPilot map collection"

  @moduledoc """
  Fetch the 131 classic XPilot maps from SourceForge into `priv/maps`.

      mix ex_pilot.maps
      mix ex_pilot.maps --into /var/lib/ex_pilot/maps

  The maps are community contributions with no stated licence, which is why they are
  fetched rather than shipped.
  """

  use Mix.Task

  @url ~c"https://sourceforge.net/projects/xpilotgame/files/maps/all-xpilot-maps-133/xpilot-all-133-maps.tar.gz/download"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [into: :string])
    into = Keyword.get(opts, :into, Path.join(:code.priv_dir(:ex_pilot), "maps"))
    Mix.Task.run("app.start")
    File.mkdir_p!(into)

    Mix.shell().info("fetching #{@url}")

    case :httpc.request(:get, {@url, []}, [ssl: [verify: :verify_none], autoredirect: true],
           body_format: :binary
         ) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        {:ok, entries} = :erl_tar.extract({:binary, body}, [:compressed, :memory])

        for {name, bytes} <- entries, String.ends_with?(to_string(name), ".map.gz") do
          File.write!(Path.join(into, Path.basename(to_string(name))), bytes)
        end

        Mix.shell().info("#{length(entries)} maps in #{into}")

      other ->
        Mix.raise("download failed: #{inspect(other)}")
    end
  end
end
