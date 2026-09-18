defmodule ExPilot.Server do
  @moduledoc """
  Serve ExPilot: its maps as arenas, over ssh and to browsers, through
  `Cauldron2D.Drafter.Server`.

      ExPilot.Server.start(port: 2222, maps: ["priv/maps/dogfight.map.gz"])

  Every map becomes an arena named after its file, its world starting on the first join
  and stopping again after a while with nobody in it. The same worlds are served to
  browsers by `ExPilot.Web.Endpoint` on the `:http` port. Players register on first
  connection as `new@host`, or on the web's login page; each account gets its own sound
  port, as `Cauldron2D.Drafter.Server` gives them. A started server names its VM and
  calls on the local network so other clients' connect screens list it.

  ## Options

    * `:port` — the ssh port. Default `2222`
    * `:ip` — what to bind, as `Drafter.Server.start_ssh/2` takes it. Default `:any`
    * `:accounts` — the account file. Default `$XDG_DATA_HOME/expilot/accounts.terms`,
      taking over an `ex_pilot_accounts.bin` in the working directory left by an older
      server
    * `:maps` — map files to offer. Default: every file under `priv/maps`
    * `:system_dir` — the ssh host key directory. Default: drafter's temporary keys
    * `:robots` — robots per arena. Default: each map's `maxrobots`
    * `:http` — the port of the web pages, on every IPv4 interface; `false` or `0` for
      none. Default: `PORT` in the environment, else 2280
    * `:beacon`, `:beacon_port` — as `Cauldron2D.Drafter.Server` takes them
    * `:music`, `:sfx` — the browsers' and desktops' sound, as `Cauldron2D.Net.Audio.set/1`
      takes them: music `:personal` (default), `:arena`, `:dynamic`, `:static` or `:off`; effects
      `:personal` (default) or `:off`. With `:static` the songs of `ExPilot.Music.Static` are
      rendered at 44 100 Hz stereo as the server starts, in the background, unless they
      are on disk from before, under `$XDG_CACHE_HOME/expilot/music`
  """

  alias Cauldron2D.Client.Game
  alias Cauldron2D.Drafter.Server
  alias Cauldron2D.Net.Audio
  alias ExPilot.Arenas
  alias ExPilot.Music.Static

  @type t :: %{
          required(:arenas) => [atom()],
          required(:daemon) => term(),
          required(:accounts) => pid(),
          required(:http) => pos_integer() | nil,
          optional(:node) => node() | nil,
          optional(:beacon) => pid() | nil,
          optional(:web) => module() | nil
        }

  @doc "Register the arenas and start serving; see the module documentation for the options."
  @spec start(keyword()) :: {:ok, t()} | {:error, term()}
  def start(opts \\ []) do
    ExPilot.Art.install()

    arenas =
      open_arenas(Keyword.get_lazy(opts, :maps, &bundled_maps/0), Keyword.take(opts, [:robots]))

    http = Keyword.get_lazy(opts, :http, &default_http/0)

    server_opts =
      [
        game: ExPilot.Client,
        accounts: Keyword.get_lazy(opts, :accounts, &accounts_path/0),
        accounts_name: ExPilot.Accounts,
        web: if(http in [false, 0], do: nil, else: {:ex_pilot, ExPilot.Web.Endpoint, http})
      ] ++ Keyword.take(opts, [:port, :ip, :system_dir, :beacon, :beacon_port])

    Audio.set(Keyword.take(opts, [:music, :sfx]))
    if Keyword.get(opts, :music) == :static, do: prerender_static()

    with {:ok, server} <- Server.start(server_opts) do
      {:ok, Map.put(server, :arenas, arenas)}
    end
  end

  defp prerender_static do
    pieces = ExPilot.Music.pieces()

    for {name, _bpm, sections} <- Static.scores(), section <- Map.keys(sections) do
      {_name, spec} = List.keyfind!(pieces, name, 0)

      Task.start(fn ->
        Cauldron2D.Audio.Music.render_static(name, spec, section, 44_100, 2,
          dir: Game.music_dir(ExPilot.Client)
        )
      end)
    end

    :ok
  end

  @doc "Stop what `start/1` started, and the arenas' worlds; the arenas stay registered for the next start."
  @spec stop(t()) :: :ok
  def stop(%{arenas: arenas} = server) do
    Server.stop(server)
    Enum.each(arenas, &Arenas.stop/1)
    :ok
  end

  @doc "The web port when none is given: `PORT` in the environment, else 2280."
  @spec default_http() :: pos_integer()
  def default_http do
    case System.get_env("PORT") do
      nil -> 2280
      port -> String.to_integer(port)
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

  @doc """
  The default account file, `$XDG_DATA_HOME/expilot/accounts.terms` (`~/.local/share`
  without the variable). When it does not exist and `legacy` does — an
  `ex_pilot_accounts.bin` in the working directory from an older server — its accounts
  are read and written there as text first.
  """
  @spec accounts_path(Path.t()) :: Path.t()
  def accounts_path(legacy \\ "ex_pilot_accounts.bin") do
    path = Cauldron2D.Paths.data(:expilot, "accounts.terms")

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
