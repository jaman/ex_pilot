defmodule Mix.Tasks.ExPilot.Serve do
  @shortdoc "Serve ExPilot over ssh"

  @moduledoc """
  Start the ExPilot ssh server and keep it running.

      mix ex_pilot.serve
      mix ex_pilot.serve --port 2222 --http 2280 --maps priv/maps
      PORT=8080 mix ex_pilot.serve

  ## Options

    * `--port` — the ssh port. Default `2222`
    * `--http N`, `-p N` — the port of the web pages, `0` for none. Default: `PORT` in
      the environment, else 2280
    * `--ip` — what to bind, comma-separated: addresses such as `192.168.1.5` or `fe80::1`,
      `0.0.0.0` for every IPv4 interface, `::` for every IPv6 one, `any` for both.
      Default `any`
    * `--accounts` — the account file, text you can read (`file:consult` terms, one
      account each). Default `$XDG_DATA_HOME/expilot/accounts.terms`
    * `--maps` — a directory of map files, or one file. Default: the bundled maps
    * `--robots` — robots per arena
    * `--beacon-port` — the UDP port the server calls on for the local network, `0` to
      keep quiet. Default: `beacon_port` in the config, else 2299
    * `--music` — the browsers' and desktops' music: `personal` (each session its own,
      following its own view, the default), `arena` (one stage a world, shared),
      `dynamic` (personal, at a rate the load sets), `static` (the first section each
      session is cued, rendered once and looped — a recording, not a performance) or
      `off`
    * `--sfx` — their effects: `personal` (default) or `off`
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, _} =
      OptionParser.parse!(args,
        strict: [
          port: :integer,
          ip: :string,
          http: :integer,
          accounts: :string,
          maps: :string,
          robots: :integer,
          beacon_port: :integer,
          music: :string,
          sfx: :string
        ],
        aliases: [p: :http]
      )

    opts =
      opts
      |> choice(:music, ~w(personal arena dynamic static off))
      |> choice(:sfx, ~w(personal off))

    opts =
      case Keyword.pop(opts, :beacon_port) do
        {nil, opts} -> opts
        {0, opts} -> Keyword.put(opts, :beacon, false)
        {port, opts} -> Keyword.put(opts, :beacon_port, port)
      end

    Mix.Task.run("app.start")

    server_opts =
      [port: Keyword.get(opts, :port, 2222)] ++
        ip_opt(Keyword.get(opts, :ip)) ++
        Keyword.take(opts, [:accounts, :http]) ++
        maps_opt(Keyword.get(opts, :maps)) ++ Keyword.take(opts, [:robots, :music, :sfx])

    case ExPilot.Server.start(server_opts) do
      {:ok, %{arenas: arenas, http: http}} ->
        Mix.shell().info(splash(server_opts[:port], arenas, http))
        Process.sleep(:infinity)

      {:error, reason} ->
        Mix.raise("could not start: #{inspect(reason)}")
    end
  end

  defp choice(opts, key, allowed) do
    case Keyword.fetch(opts, key) do
      :error ->
        opts

      {:ok, value} ->
        if value in allowed,
          do: Keyword.put(opts, key, String.to_atom(value)),
          else:
            Mix.raise("--#{key} takes one of #{Enum.join(allowed, ", ")}, not #{inspect(value)}")
    end
  end

  defp splash(port, arenas, http) do
    host = ExPilot.Server.hostname()

    """

    ExPilot is serving #{length(arenas)} arenas on port #{port}.

    #{web_line(host, http)}
      register:   ssh -p #{port} new@#{host}            (pick a name and password, then play)
      play:       ssh -p #{port} <name>@#{host}
      with sound: ssh -p #{port} -R <sound port>:127.0.0.1:4713 <name>@#{host}

    Every account gets its own sound port on this server (24713 for the first, 24714 for the
    next, …), shown in the game's settings. The tunnel carries the game's audio as raw PCM to
    your machine's port 4713; play it with ffmpeg on any OS:

      while :; do ffplay -nodisp -autoexit -fflags nobuffer -analyzeduration 0 -probesize 32 -f s16le -ar 44100 -ch_layout stereo -i "tcp://127.0.0.1:4713?listen"; done

    (ffplay ends with each connection; the loop puts a fresh listener up for the next one.)
    """
  end

  defp web_line(_host, nil), do: "  no web pages (--http 0)"

  defp web_line(host, http),
    do:
      "  in a browser:  http://#{host}:#{http}/            (log in or make an account, then play)"

  defp ip_opt(nil), do: []

  defp ip_opt(text) do
    binds = text |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.map(&bind/1)
    [ip: if(length(binds) == 1, do: hd(binds), else: binds)]
  end

  defp bind("any"), do: :any

  defp bind(text) do
    case :inet.parse_address(to_charlist(text)) do
      {:ok, address} -> address
      {:error, _} -> Mix.raise("--ip: #{text} is not an address, 0.0.0.0, :: or any")
    end
  end

  defp maps_opt(nil), do: []

  defp maps_opt(path) do
    if File.dir?(path), do: [maps: Path.wildcard(Path.join(path, "*.map*"))], else: [maps: [path]]
  end
end
