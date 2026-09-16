defmodule ExPilot.Server do
  @moduledoc """
  Serve ExPilot over ssh.

      ExPilot.Server.start(port: 2222, maps: ["priv/maps/dogfight.map.gz"])

  Every map becomes an arena named after its file, its world starting on the first join
  and stopping again after two minutes with nobody in it. The same worlds are served to
  browsers by `ExPilot.Web.Endpoint` on the `:http` port. Players register on first
  connection as `new@host`, or on the web's login page. Each account is given its own sound port on the server —
  24713 for the first account, 24714 for the next, and so on, kept in its props as
  `:pulse_port` and shown in the game's settings; the game's audio goes as raw PCM
  (`TuningFork.Sink.Tcp`) through the `ssh -R <port>:127.0.0.1:4713` tunnel to a player
  program on the player's machine, and never through this machine's speaker.

  ## Options

    * `:port` — the ssh port. Default `2222`
    * `:ip` — what to bind, as `Drafter.Server.start_ssh/2` takes it: an address, `{0, 0,
      0, 0}` for every IPv4 interface, `{0, 0, 0, 0, 0, 0, 0, 0}` for every IPv6 one,
      `:any` for both, or a list of these. Default `:any`
    * `:accounts` — the account file. Default `$XDG_DATA_HOME/expilot/accounts.terms`,
      taking over an `ex_pilot_accounts.bin` in the working directory left by an older
      server
    * `:maps` — map files to offer. Default: every file under `priv/maps`
    * `:system_dir` — the ssh host key directory. Default: drafter's temporary keys
    * `:robots` — robots per arena. Default: each map's `maxrobots`
    * `:http` — the port of the web pages, on every IPv4 interface; `false` or `0` for
      none. Default: `PORT` in the environment, else 2280
  """

  alias Cauldron2D.Drafter.Client
  alias ExPilot.Arenas

  @first_sound_port 24_713

  @doc "Register the arenas and start the ssh daemon and the web endpoint; returns the daemon, the accounts server, the arenas and the web port."
  @spec start(keyword()) :: {:ok, %{daemon: pid() | [pid()], accounts: pid(), arenas: [atom()], http: pos_integer() | nil}} | {:error, term()}
  def start(opts \\ []) do
    :ok = Application.ensure_started(:ssh) |> normalise()
    Code.ensure_loaded!(Cauldron2D.Drafter.Surface)
    Drafter.Widget.Registry.register(Cauldron2D.Drafter.Surface)
    ExPilot.Art.install()

    {:ok, accounts} =
      Drafter.Accounts.start_link(
        path: Keyword.get_lazy(opts, :accounts, &accounts_path/0),
        name: ExPilot.Accounts,
        default_props: fn number -> %{pulse_port: @first_sound_port + number} end
      )
    arenas = open_arenas(Keyword.get_lazy(opts, :maps, &bundled_maps/0), Keyword.take(opts, [:robots]))

    daemon_opts =
      [
        port: Keyword.get(opts, :port, 2222),
        ip: Keyword.get(opts, :ip, :any),
        auth: {:accounts, accounts},
        register_as: "new",
        tunnel: true,
        mount_props: %{game: ExPilot.Client, accounts: accounts, speaker: false, served_by: %{host: hostname(), port: Keyword.get(opts, :port, 2222)}}
      ] ++ Keyword.take(opts, [:system_dir])

    with {:ok, daemon} <- Drafter.Server.start_ssh(Client, daemon_opts),
         {:ok, http} <- start_web(Keyword.get_lazy(opts, :http, &default_http/0)) do
      {:ok, %{daemon: daemon, accounts: accounts, arenas: arenas, http: http}}
    end
  end

  @doc "The web port when none is given: `PORT` in the environment, else 2280."
  @spec default_http() :: pos_integer()
  def default_http do
    case System.get_env("PORT") do
      nil -> 2280
      port -> String.to_integer(port)
    end
  end

  defp start_web(false), do: {:ok, nil}
  defp start_web(0), do: {:ok, nil}

  defp start_web(port) do
    config = Application.get_env(:ex_pilot, ExPilot.Web.Endpoint, [])
    Application.put_env(:ex_pilot, ExPilot.Web.Endpoint, Keyword.merge(config, http: [ip: {0, 0, 0, 0}, port: port], url: [host: hostname(), port: port], server: true))

    case DynamicSupervisor.start_child(ExPilot.WebSupervisor, ExPilot.Web.Endpoint) do
      {:ok, _pid} -> {:ok, port}
      {:error, {:already_started, _pid}} -> {:ok, port}
      {:error, reason} -> {:error, {:web, reason}}
    end
  end

  @doc "This machine's name, as players are told to connect to it."
  @spec hostname() :: String.t()
  def hostname do
    case :inet.gethostname() do
      {:ok, name} -> to_string(name)
      _ -> "host"
    end
  end

  defp normalise(:ok), do: :ok
  defp normalise({:error, {:already_started, _}}), do: :ok

  @doc """
  The default account file, `$XDG_DATA_HOME/expilot/accounts.terms` (`~/.local/share`
  without the variable). When it does not exist and `legacy` does — an
  `ex_pilot_accounts.bin` in the working directory from an older server — its accounts
  are read and written there as text first.
  """
  @spec accounts_path(Path.t()) :: Path.t()
  def accounts_path(legacy \\ "ex_pilot_accounts.bin") do
    base = System.get_env("XDG_DATA_HOME") || Path.join(System.user_home!(), ".local/share")
    path = Path.join(base, "expilot/accounts.terms")

    if not File.exists?(path) and File.exists?(legacy) do
      File.mkdir_p!(Path.dirname(path))
      records = legacy |> File.read!() |> :erlang.binary_to_term() |> Map.values()
      File.write!(path, Enum.map(records, &:io_lib.format("~p.~n", [&1])))
    end

    path
  end

  @doc "The map files shipped with the package."
  @spec bundled_maps() :: [Path.t()]
  def bundled_maps do
    :ex_pilot |> :code.priv_dir() |> Path.join("maps/*.map*") |> Path.wildcard() |> Enum.sort()
  end

  defp open_arenas(paths, opts) do
    for path <- paths, id = arena_id(path), :ok == Arenas.register(id, path, opts), do: id
  end

  defp arena_id(path) do
    path |> Path.basename() |> String.replace(~r/\.map(\.gz)?\z/, "") |> String.to_atom()
  end
end
