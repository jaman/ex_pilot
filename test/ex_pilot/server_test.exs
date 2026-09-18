defmodule ExPilot.ServerTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.Client.Hud
  alias Cauldron2D.Net.Audio
  alias Cauldron2D.World
  alias Drafter.Accounts
  alias ExPilot.Arenas

  @moduletag timeout: 60_000
  @fixture Path.join(__DIR__, "../fixtures/dogfight.map.gz")

  setup do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ex_pilot_server_#{System.os_time(:nanosecond)}_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    System.put_env("XDG_CONFIG_HOME", Path.join(dir, "config"))
    System.put_env("XDG_STATE_HOME", Path.join(dir, "state"))
    second = Path.join(dir, "dogfight2.map.gz")
    File.cp!(@fixture, second)
    port = 39_000 + :rand.uniform(900)

    {:ok, %{daemon: daemon, accounts: accounts} = server} =
      ExPilot.Server.start(
        port: port,
        http: false,
        accounts: Path.join(dir, "accounts.bin"),
        maps: [@fixture, second],
        robots: 1
      )

    :ok = Accounts.register(accounts, "alice", "alices password", %{pulse_port: 24_901})
    :ok = Accounts.register(accounts, "bob", "bobs password", %{pulse_port: 24_901})

    on_exit(fn ->
      if Process.alive?(daemon), do: :ssh.stop_daemon(daemon)
      for id <- [:dogfight, :dogfight2], do: Arenas.close(id)
      if Process.alive?(accounts), do: GenServer.stop(accounts)
      File.rm_rf!(dir)
    end)

    {:ok, port: port, server: server, dir: dir}
  end

  test "the accounts live under XDG data, and a file left in the working directory by an older server is carried over" do
    dir = Path.join(System.tmp_dir!(), "ex_pilot_accounts_#{System.os_time(:nanosecond)}")
    File.mkdir_p!(Path.join(dir, "old"))
    old = Path.join(dir, "old/ex_pilot_accounts.bin")
    record = %{username: "vet", props: %{}, hash: <<1>>, salt: <<2>>, iterations: 1_000}
    File.write!(old, :erlang.term_to_binary(%{"vet" => record}))

    previous = System.get_env("XDG_DATA_HOME")
    System.put_env("XDG_DATA_HOME", Path.join(dir, "data"))

    on_exit(fn ->
      if previous,
        do: System.put_env("XDG_DATA_HOME", previous),
        else: System.delete_env("XDG_DATA_HOME")

      File.rm_rf!(dir)
    end)

    path = ExPilot.Server.accounts_path(old)
    assert path == Path.join(dir, "data/expilot/accounts.terms")
    assert {:ok, [%{username: "vet"}]} = :file.consult(path)
    assert ExPilot.Server.accounts_path(old) == path
  end

  defp connect(port, user, password) do
    {:ok, conn} =
      :ssh.connect(
        ~c"127.0.0.1",
        port,
        [
          user: to_charlist(user),
          password: to_charlist(password),
          silently_accept_hosts: true,
          user_interaction: false,
          auth_methods: ~c"password"
        ],
        5_000
      )

    conn
  end

  defp open_shell(conn) do
    {:ok, channel} = :ssh_connection.session_channel(conn, 5_000)
    :ssh_connection.ptty_alloc(conn, channel, term: ~c"xterm", width: 100, height: 30)
    :ok = :ssh_connection.shell(conn, channel)
    {:ok, _} = collect_until(conn, channel, FrenchCurve.Capability.probe())
    :ssh_connection.send(conn, channel, "\e[?62;22c")
    channel
  end

  defp collect_until(conn, channel, marker, seen \\ "") do
    receive do
      {:ssh_cm, ^conn, {:data, ^channel, 0, data}} ->
        seen = seen <> data

        if String.contains?(seen, marker),
          do: {:ok, seen},
          else: collect_until(conn, channel, marker, seen)

      {:ssh_cm, ^conn, _other} ->
        collect_until(conn, channel, marker, seen)
    after
      8_000 -> {:timeout, seen}
    end
  end

  defp into_lobby(conn, channel) do
    assert {:ok, _} = collect_until(conn, channel, "over ssh")
    :ssh_connection.send(conn, channel, "\r")
    assert {:ok, _} = collect_until(conn, channel, "Arenas")
  end

  test "two players log in as themselves at once, each with a reverse tunnel on the same port, and share a world",
       %{port: port} do
    alice = connect(port, "alice", "alices password")
    bob = connect(port, "bob", "bobs password")

    assert {:ok, 24_901} =
             :ssh.tcpip_tunnel_from_server(alice, ~c"localhost", 24_901, ~c"localhost", 4_713)

    assert {:error, _} =
             :ssh.tcpip_tunnel_from_server(bob, ~c"localhost", 24_901, ~c"localhost", 4_713)

    assert {:ok, 24_902} =
             :ssh.tcpip_tunnel_from_server(bob, ~c"localhost", 24_902, ~c"localhost", 4_714)

    alice_channel = open_shell(alice)
    bob_channel = open_shell(bob)
    into_lobby(alice, alice_channel)
    into_lobby(bob, bob_channel)

    :ssh_connection.send(alice, alice_channel, "\r")
    :ssh_connection.send(bob, bob_channel, "\r")
    assert {:ok, _} = collect_until(alice, alice_channel, "fuel")
    assert {:ok, _} = collect_until(bob, bob_channel, "fuel")

    world = Arenas.world_name(:dogfight)
    assert Enum.sort(World.players(world) -- [{:robot, 1}]) == ["alice", "bob"]

    :ssh.close(alice)
    :ssh.close(bob)
  end

  test "a served session's sound goes to the account's port over TCP, the title offers the sound page, and a local session hears the speaker" do
    assert {TuningFork.Sink.Tcp, opts} =
             ExPilot.Client.sink(%{pulse_port: 24_901, served_by: %{host: "h", port: 1}})

    assert opts[:port] == 24_901 and opts[:warm_up_ms] == 300
    assert TuningFork.Sink.Silent == ExPilot.Client.sink(%{served_by: %{host: "h", port: 1}})
    assert ExPilot.Client.sink(%{}) in [TuningFork.Sink.Speaker, TuningFork.Sink.Silent]

    [%{key: :l}, page] =
      ExPilot.Client.pages(%{
        pulse_port: 24_901,
        served_by: %{host: "arcade", port: 2222},
        username: "alice"
      })

    assert page.key == :n and page.hint == "No sound?"

    lines =
      page.render.()
      |> Enum.map(fn row ->
        row |> Hud.runs() |> Enum.map_join(&elem(&1, 0))
      end)

    assert Enum.any?(lines, &(&1 =~ "ssh -p 2222 -R 24901:127.0.0.1:4713 alice@arcade"))
    assert Enum.any?(lines, &(&1 =~ ~r/^\s*while :; do ffplay .*; done$/))
    assert Enum.any?(lines, &(&1 =~ ~r/^\s*for \/L %i in \(1,0,2\) do ffplay /))
    assert Enum.any?(lines, &(&1 =~ "winget")) and Enum.any?(lines, &(&1 =~ "brew"))
    assert [%{key: :l}] = ExPilot.Client.pages(%{username: "alice"})

    assert ExPilot.Client.refusal_text(:full) == "no base is free"
    assert ExPilot.Client.player_label({:robot, 3}) == "Robot 3"
    assert Enum.all?(ExPilot.Client.arenas(%{}), &match?({_, {_, _, _}}, &1.kind))
  end

  test "a server stops whole — ssh, web and accounts — and can start again on the same ports", %{
    port: port,
    server: server,
    dir: dir
  } do
    assert :ok == ExPilot.Server.stop(server)
    refute Process.alive?(server.accounts)
    assert {:error, _} = :gen_tcp.connect(~c"127.0.0.1", port, [], 1_000)

    http = 40_000 + :rand.uniform(900)
    on_exit(fn -> Audio.set([]) end)

    {:ok, again} =
      ExPilot.Server.start(
        port: port,
        http: http,
        accounts: Path.join(dir, "accounts.bin"),
        maps: [@fixture],
        robots: 0,
        music: :arena,
        sfx: :off
      )

    assert %{music: :arena, sfx: :off} = Audio.policy()
    assert {:ok, socket} = :gen_tcp.connect(~c"127.0.0.1", http, [], 1_000)
    :gen_tcp.close(socket)
    assert :ok == ExPilot.Server.stop(again)
    assert {:error, _} = :gen_tcp.connect(~c"127.0.0.1", http, [], 1_000)
  end

  test "the arrow keys move the lobby's selection over ssh", %{port: port} do
    conn = connect(port, "alice", "alices password")
    channel = open_shell(conn)
    into_lobby(conn, channel)

    :ssh_connection.send(conn, channel, "\e[B")
    assert {:ok, seen} = collect_until(conn, channel, "dogfight2")
    assert seen =~ ~r/▶[^\n]{0,24}dogfight2/

    :ssh_connection.send(conn, channel, "\e[A")
    assert {:ok, seen} = collect_until(conn, channel, "dogfight ")
    assert seen =~ ~r/▶[^\n]{0,24}dogfight /

    :ssh.close(conn)
  end
end
