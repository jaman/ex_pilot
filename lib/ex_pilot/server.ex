defmodule ExPilot.Server do
  @moduledoc """
  Serve ExPilot over ssh.

      ExPilot.Server.start(port: 2222, accounts: "ex_pilot_accounts.bin", maps: ["priv/maps/dogfight.map.gz"])

  Every map becomes an arena named after its file. Players register on first
  connection as `new@host`; sound reaches them through an `ssh -R` tunnel to the port in
  their account props.

  ## Options

    * `:port` — the ssh port. Default `2222`
    * `:ip` — the interface to bind. Default `{0, 0, 0, 0}`
    * `:accounts` — the account file. Default `"ex_pilot_accounts.bin"`
    * `:maps` — map files to open. Default: every file under `priv/maps`
    * `:system_dir` — the ssh host key directory. Default: drafter's temporary keys
    * `:robots` — robots per arena. Default: each map's `maxrobots`
  """

  alias Cauldron2D.Drafter.Client
  alias ExPilot.Arenas

  @doc "Open the arenas and start the ssh daemon; returns the daemon and the accounts server."
  @spec start(keyword()) :: {:ok, %{daemon: pid(), accounts: pid(), arenas: [atom()]}} | {:error, term()}
  def start(opts \\ []) do
    :ok = Application.ensure_started(:ssh) |> normalise()
    Code.ensure_loaded!(Cauldron2D.Drafter.Surface)
    Drafter.Widget.Registry.register(Cauldron2D.Drafter.Surface)
    ExPilot.Art.install()

    {:ok, accounts} = Drafter.Accounts.start_link(path: Keyword.get(opts, :accounts, "ex_pilot_accounts.bin"), name: ExPilot.Accounts)
    arenas = open_arenas(Keyword.get_lazy(opts, :maps, &bundled_maps/0), Keyword.take(opts, [:robots]))

    daemon_opts =
      [
        port: Keyword.get(opts, :port, 2222),
        ip: Keyword.get(opts, :ip, {0, 0, 0, 0}),
        auth: {:accounts, accounts},
        register_as: "new",
        tunnel: true,
        mount_props: %{game: ExPilot.Client, accounts: accounts}
      ] ++ Keyword.take(opts, [:system_dir])

    with {:ok, daemon} <- Drafter.Server.start_ssh(Client, daemon_opts) do
      {:ok, %{daemon: daemon, accounts: accounts, arenas: arenas}}
    end
  end

  defp normalise(:ok), do: :ok
  defp normalise({:error, {:already_started, _}}), do: :ok

  @doc "The map files shipped with the package."
  @spec bundled_maps() :: [Path.t()]
  def bundled_maps do
    :ex_pilot |> :code.priv_dir() |> Path.join("maps/*.map*") |> Path.wildcard() |> Enum.sort()
  end

  defp open_arenas(paths, opts) do
    for path <- paths, id = arena_id(path), match?({:ok, _}, Arenas.open(id, path, opts)), do: id
  end

  defp arena_id(path) do
    path |> Path.basename() |> String.replace(~r/\.map(\.gz)?\z/, "") |> String.to_atom()
  end
end
