defmodule ExPilot.WebTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest, except: [connect: 2]
  import Phoenix.ChannelTest
  import Phoenix.LiveViewTest
  import Plug.Conn, only: [get_session: 2, get_resp_header: 2]

  alias ExPilot.Arenas
  alias ExPilot.Web.Auth

  @endpoint ExPilot.Web.Endpoint
  @fixture Path.join(__DIR__, "../../fixtures/dogfight.map.gz")

  setup_all do
    {:ok, _} = ExPilot.Web.Endpoint.start_link()
    ExPilot.Art.install()
    :ok
  end

  setup do
    dir = Path.join(System.tmp_dir!(), "ex_pilot_web_#{System.os_time(:nanosecond)}")
    File.mkdir_p!(dir)
    System.put_env("XDG_CONFIG_HOME", Path.join(dir, "config"))
    System.put_env("XDG_STATE_HOME", Path.join(dir, "state"))
    {:ok, accounts} = Drafter.Accounts.start_link(path: Path.join(dir, "accounts.terms"), iterations: 1_000, name: ExPilot.Accounts)
    :ok = Drafter.Accounts.register(accounts, "alice", "alices password", %{settings: %{sfx: 0.5, music: 0.1}})
    :ok = Arenas.register(:webtest, @fixture, robots: 1)

    on_exit(fn ->
      Arenas.close(:webtest)
      if Process.alive?(accounts), do: GenServer.stop(accounts)
      File.rm_rf!(dir)
    end)

    {:ok, conn: build_conn()}
  end

  defp logged_in(conn), do: conn |> get("/session?token=" <> Auth.token("alice")) |> recycle()

  test "the login page takes a name and password, refuses a wrong one, and sends a right one into the lobby", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")
    assert html =~ "EXPILOT"

    assert render_submit(view, "login", %{"username" => "alice", "password" => "wrong"}) =~ "no such name and password"

    assert {:error, {:redirect, %{to: "/session?token=" <> token}}} = render_submit(view, "login", %{"username" => "alice", "password" => "alices password"})
    assert {:ok, "alice"} = Auth.verify(token)

    conn = get(conn, "/session?token=" <> token)
    assert redirected_to(conn) == "/lobby"
    assert get_session(conn, "username") == "alice"
  end

  test "registration makes an account and logs it in", %{conn: conn} do
    {:ok, view, _} = live(conn, "/")
    render_click(view, "toggle")
    assert render_submit(view, "register", %{"username" => "bob", "password" => "bobs password", "again" => "other"}) =~ "differ"
    assert {:error, {:redirect, %{to: "/session?token=" <> token}}} = render_submit(view, "register", %{"username" => "bob", "password" => "bobs password", "again" => "bobs password"})
    assert {:ok, "bob"} = Auth.verify(token)
    assert {:ok, _} = Auth.login("bob", "bobs password")
  end

  test "the lobby needs a login and lists the arenas with a way in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/lobby")

    {:ok, view, html} = live(logged_in(conn), "/lobby")
    assert html =~ "webtest"
    assert html =~ "nobody flying"
    :ok = Cauldron2D.Player.join(Arenas.world_name(:webtest), "bob", %{username: "bob"})
    assert render(view) =~ "1 pilot flying"
    Cauldron2D.Player.leave(Arenas.world_name(:webtest), "bob")
    assert render(view) =~ "nobody flying"
    assert html =~ "Dogfight... 6 bases"
    assert html =~ ~s(href="/arena/webtest")
    assert html =~ ~s(href="/arena/webtest?spectate=1")
    assert html =~ "dogfight"
    assert html =~ ~s(href="/guide")
  end

  test "the guide page shows every section with its sprites cut from the sheet", %{conn: conn} do
    {:ok, _view, html} = live(logged_in(conn), "/guide")
    assert html =~ "On the map"
    assert html =~ "Emergency shield"
    assert html =~ "background-position"
    assert length(Regex.scan(~r/class="sprite"/, html)) == ExPilot.Guide.sections() |> Enum.flat_map(&elem(&1, 1)) |> length()
  end

  test "the stylesheet is served", %{conn: conn} do
    conn = get(conn, "/expilot.css")
    assert conn.status == 200
    assert conn.resp_body =~ ".arena-card"
  end

  test "the arena page carries what the browser needs to mount the canvas", %{conn: conn} do
    {:ok, _view, html} = live(logged_in(conn), "/arena/webtest")
    assert html =~ ~s(phx-hook="Arena")
    assert html =~ ~s(data-arena="webtest")
    assert html =~ "data-token="
    assert html =~ "turn_left"
    assert html =~ "<canvas"
  end

  test "the sheet is served as a PNG", %{conn: conn} do
    conn = get(conn, "/atlas.png")
    assert conn.status == 200
    assert get_resp_header(conn, "content-type") |> hd() =~ "image/png"
    assert <<137, "PNG", _::binary>> = conn.resp_body
  end

  test "settings keep the levels in the account, beside whatever the ssh client saved", %{conn: conn} do
    {:ok, view, html} = live(logged_in(conn), "/settings")
    assert html =~ "50%"
    render_submit(view, "save", %{"sfx" => "70", "music" => "20"})
    assert Auth.levels("alice") == %{sfx: 0.7, music: 0.2}
  end

  test "a browser player joins the world through the channel, gets the sheet, the map and frames, and steers" do
    {:ok, socket} = connect(ExPilot.Web.UserSocket, %{"token" => Auth.token("alice")})
    assert socket.assigns.settings == %{sfx: 0.5, music: 0.1}

    {:ok, _reply, socket} = subscribe_and_join(socket, ExPilot.Web.ArenaChannel, "arena:webtest")
    assert_push "sheet", %{url: "/atlas.png", tile: 16}
    assert_push "map", %{width: 120, height: 120, wrap: true}, 2_000
    assert_push "frame", %{focus: [_, _], movers: movers, hud: hud}, 2_000
    assert Enum.any?(movers, fn [index, _, _] -> is_integer(index) end)
    assert Enum.any?(hud, fn row -> Enum.any?(row, fn [text, _] -> text =~ "alice" end) end)

    world = Arenas.world_name(:webtest)
    assert "alice" in Cauldron2D.World.players(world)

    push(socket, "input", %{"held" => ["thrust"], "aim" => nil})
    Process.sleep(200)
    %{ships: %{"alice" => ship}} = Cauldron2D.World.snapshot(world)
    refute ship.landed?

    Process.unlink(socket.channel_pid)
    leave(socket)
    Process.sleep(100)
    refute "alice" in Cauldron2D.World.players(world)
  end

  test "joining with spectate watches without a ship" do
    {:ok, socket} = connect(ExPilot.Web.UserSocket, %{"token" => Auth.token("alice")})
    {:ok, _reply, socket} = subscribe_and_join(socket, ExPilot.Web.ArenaChannel, "arena:webtest", %{"spectate" => "1"})
    assert_push "frame", %{hud: hud}, 2_000
    assert Enum.any?(hud, fn row -> Enum.any?(row, fn [text, _] -> text =~ "watching" end) end)
    %{ships: ships} = Cauldron2D.World.snapshot(Arenas.world_name(:webtest))
    refute Map.has_key?(ships, "alice")
    Process.unlink(socket.channel_pid)
    leave(socket)
  end

  test "a stranger's token opens no socket, and a topic with no arena is refused" do
    assert :error = connect(ExPilot.Web.UserSocket, %{"token" => "nonsense"})
    {:ok, socket} = connect(ExPilot.Web.UserSocket, %{"token" => Auth.token("alice")})
    assert {:error, %{reason: "no such arena"}} = subscribe_and_join(socket, ExPilot.Web.ArenaChannel, "arena:nowhere")
  end
end
