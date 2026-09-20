defmodule ExPilot.WebTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest, except: [connect: 2]
  import Phoenix.ChannelTest
  import Phoenix.LiveViewTest
  import Plug.Conn, only: [get_session: 2, get_resp_header: 2]

  alias Cauldron2D.Net.Link.Local
  alias Cauldron2D.Net.Link.Socket
  alias ExPilot.Arenas
  alias ExPilot.Web.Auth
  alias ExPilot.Web.Endpoint

  @endpoint ExPilot.Web.Endpoint
  @fixture Path.join(__DIR__, "../../fixtures/dogfight.map.gz")

  setup_all do
    case Endpoint.start_link() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    ExPilot.Art.install()
    :ok
  end

  setup do
    dir = Path.join(System.tmp_dir!(), "ex_pilot_web_#{System.os_time(:nanosecond)}")
    File.mkdir_p!(dir)
    System.put_env("XDG_CONFIG_HOME", Path.join(dir, "config"))
    System.put_env("XDG_STATE_HOME", Path.join(dir, "state"))

    {:ok, accounts} =
      Drafter.Accounts.start_link(
        path: Path.join(dir, "accounts.terms"),
        iterations: 1_000,
        name: ExPilot.Accounts
      )

    :ok =
      Drafter.Accounts.register(accounts, "alice", "alices password", %{
        settings_web: %{sfx: 0.5, music: 0.1},
        settings: %{sfx: 0.9, music: 0.9}
      })

    :ok = Drafter.Accounts.register(accounts, "bob", "bobs password")
    :ok = Arenas.register(:webtest, @fixture, robots: 1)

    on_exit(fn ->
      Arenas.close(:webtest)
      if Process.alive?(accounts), do: GenServer.stop(accounts)
      File.rm_rf!(dir)
    end)

    {:ok, conn: build_conn()}
  end

  defp logged_in(conn), do: conn |> get("/session?token=" <> Auth.token("alice")) |> recycle()

  defp shows(view, text, tries \\ 50) do
    cond do
      render(view) =~ text -> true
      tries == 0 -> render(view)
      true -> Process.sleep(20) && shows(view, text, tries - 1)
    end
  end

  test "the login page takes a name and password, refuses a wrong one, and sends a right one into the lobby",
       %{conn: conn} do
    {:ok, view, html} = live(conn, "/")
    assert html =~ "EXPILOT"

    assert render_submit(view, "login", %{"username" => "alice", "password" => "wrong"}) =~
             "no such name and password"

    assert {:error, {:redirect, %{to: "/session?token=" <> token}}} =
             render_submit(view, "login", %{
               "username" => "alice",
               "password" => "alices password"
             })

    assert {:ok, "alice"} = Auth.verify(token)

    conn = get(conn, "/session?token=" <> token)
    assert redirected_to(conn) == "/lobby"
    assert get_session(conn, "username") == "alice"
  end

  test "registration makes an account and logs it in", %{conn: conn} do
    {:ok, view, _} = live(conn, "/")
    render_click(view, "toggle")

    assert render_submit(view, "register", %{
             "username" => "carol",
             "password" => "carols password",
             "again" => "other"
           }) =~ "differ"

    assert {:error, {:redirect, %{to: "/session?token=" <> token}}} =
             render_submit(view, "register", %{
               "username" => "carol",
               "password" => "carols password",
               "again" => "carols password"
             })

    assert {:ok, "carol"} = Auth.verify(token)
    assert {:ok, _} = Auth.login("carol", "carols password")
  end

  test "every page carries the pilots panel: a count in the bar, a scrollable list that slides open, one session per page",
       %{conn: conn} do
    {:ok, view, _html} = live(logged_in(conn), "/leaders")
    panel = find_live_child(view, "pilots")
    assert shows(view, ~r/1 pilot<\/span>/) == true
    assert Enum.count(ExPilot.Roster.online(), &(&1.id == "alice")) == 1
    refute render(panel) =~ ~s(class="pilots open")

    html = panel |> element("button.pilots-toggle") |> render_click()
    assert html =~ ~s(class="pilots open")
    assert html =~ ~r/<li[^>]*>.*#{ExPilot.Alias.of("alice")}.*in the lobby.*<\/li>/s

    world = Arenas.world_name(:webtest)
    :ok = Cauldron2D.Player.join(world, "bob", %{username: "bob"})
    on_exit(fn -> Cauldron2D.Player.leave(world, "bob") end)
    assert shows(panel, ~r/2 pilots<\/span>/) == true
    assert render(panel) =~ ~r/#{ExPilot.Alias.of("bob")}.*in webtest/s

    refute render_keydown(panel, "close", %{"key" => "Escape"}) =~ ~s(class="pilots open")
  end

  test "the lobby needs a login and lists the arenas with a way in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/lobby")

    {:ok, view, html} = live(logged_in(conn), "/lobby")
    assert html =~ "webtest"
    assert html =~ "nobody flying"
    :ok = Cauldron2D.Player.join(Arenas.world_name(:webtest), "bob", %{username: "bob"})
    assert shows(view, "1 pilot flying") == true
    assert render(view) =~ "in webtest"
    Cauldron2D.Player.leave(Arenas.world_name(:webtest), "bob")
    assert shows(view, "nobody flying") == true
    assert html =~ "Dogfight... 6 bases"
    assert html =~ ~s(href="/arena/webtest")
    assert html =~ ~s(href="/arena/webtest?spectate=1")
    assert html =~ "dogfight"
    assert html =~ ~s(href="/guide")
  end

  test "a desktop client logs in for a token and lists the arenas over plain HTTP", %{conn: conn} do
    conn = post(conn, "/api/token", %{"username" => "alice", "password" => "wrong"})
    assert conn.status == 401

    conn =
      post(build_conn(), "/api/token", %{"username" => "alice", "password" => "alices password"})

    assert %{"token" => token, "username" => "alice"} = Jason.decode!(conn.resp_body)
    assert {:ok, "alice"} = Auth.verify(token)

    conn =
      post(build_conn(), "/api/token", %{
        "username" => "carol",
        "password" => "carols password",
        "register" => true
      })

    assert %{"token" => _, "username" => "carol"} = Jason.decode!(conn.resp_body)

    conn = get(build_conn(), "/api/arenas")

    assert [
             %{
               "id" => "webtest",
               "name" => "webtest",
               "kind" => %{"text" => "dogfight", "colour" => "#ffb84d"},
               "players" => 0,
               "map" => "Dogfight... 6 bases",
               "teams" => []
             }
           ] = Jason.decode!(conn.resp_body)
  end

  test "the stats say how each running world and the node are keeping up" do
    conn = get(build_conn(), "/api/stats")

    assert %{
             "arenas" => [],
             "node" => %{
               "processes" => processes,
               "memory_mb" => _,
               "run_queue" => _,
               "schedulers" => _,
               "busy" => busy
             }
           } = Jason.decode!(conn.resp_body)

    assert processes > 0
    assert busy >= 0.0 and busy <= 1.0

    ExPilot.Arenas.world_name(:webtest) |> Cauldron2D.World.players()
    Process.sleep(60)
    conn = get(build_conn(), "/api/stats")

    assert %{
             "arenas" => [
               %{
                 "name" => "webtest",
                 "players" => _,
                 "hz" => 50,
                 "steps" => _,
                 "ticks" => _,
                 "tick_us" => %{"mean" => _, "p95" => _, "max" => _},
                 "behind" => _
               }
             ]
           } = Jason.decode!(conn.resp_body)
  end

  test "the guide page shows every section with its sprites cut from the sheet", %{conn: conn} do
    {:ok, _view, html} = live(logged_in(conn), "/guide")
    assert html =~ "On the map"
    assert html =~ "Emergency shield"
    assert html =~ "background-position"

    assert length(Regex.scan(~r/class="sprite"/, html)) ==
             ExPilot.Guide.sections() |> Enum.flat_map(&elem(&1, 1)) |> length()
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
    assert html =~ ~s(class="stick")

    for action <- ~w(thrust fire shield fire_missile next_watch),
        do: assert(html =~ ~s(data-action="#{action}"))

    assert html =~ ~s(href="/lobby")
    assert length(Regex.scan(~r/class="[^"]*music-toggle[^"]*"/, html)) == 2
  end

  test "a browser session's sound is 44.1 kHz stereo unless it asks for another format" do
    {:ok, socket} = connect(ExPilot.Web.UserSocket, %{"token" => Auth.token("alice")})

    {:ok, _reply, socket} =
      subscribe_and_join(socket, ExPilot.Web.ArenaChannel, "arena:webtest", %{})

    assert_push("audio", %{rate: 44_100, channels: 2})
    assert Cauldron2D.Audio.rate(socket.assigns.session.audio) == {44_100, 2}
    Process.unlink(socket.channel_pid)
    leave(socket)
    Process.sleep(100)

    {:ok, socket} = connect(ExPilot.Web.UserSocket, %{"token" => Auth.token("alice")})

    {:ok, _reply, socket} =
      subscribe_and_join(socket, ExPilot.Web.ArenaChannel, "arena:webtest", %{
        "audio" => %{"rate" => 22_050, "channels" => 1}
      })

    assert_push("audio", %{rate: 22_050, channels: 1})
    Process.unlink(socket.channel_pid)
    leave(socket)
  end

  test "the leaders page ranks the ledger by period and metric", %{conn: conn} do
    row = %{
      id: "alice",
      name: "alice",
      robot?: false,
      team: nil,
      won?: true,
      kills: 4,
      deaths: 1,
      score: 7,
      best_streak: 4,
      best_contact: 12.0,
      laps: 0,
      mode: :dogfight
    }

    :ok = Cauldron2D.Ledger.record(ExPilot.Ledger, "webtest", row)

    :ok =
      Cauldron2D.Ledger.record(ExPilot.Ledger, "webtest", %{
        row
        | id: "bob",
          name: "bob",
          kills: 1,
          deaths: 3,
          won?: false,
          best_streak: 1
      })

    {:ok, view, html} = live(logged_in(conn), "/leaders")
    assert html =~ "Leaders"
    assert html =~ ~r/alice.*bob/s
    html = render_click(view, "metric", %{"metric" => "ratio"})
    assert html =~ "4.00"
    html = render_change(view, "arena", %{"arena" => "nowhere"})
    assert html =~ "nobody yet"
  end

  test "the leaders API answers with the board", %{conn: _conn} do
    :ok =
      Cauldron2D.Ledger.record(ExPilot.Ledger, "webtest", %{
        id: "dan",
        name: "dan",
        robot?: false,
        team: nil,
        won?: false,
        kills: 2,
        deaths: 0,
        score: 4,
        best_streak: 2,
        best_contact: 3.0,
        laps: 0,
        mode: :dogfight
      })

    conn = get(build_conn(), "/api/leaders?period=all&metric=kills&arena=webtest")

    assert Enum.any?(
             Jason.decode!(conn.resp_body),
             &match?(%{"name" => "dan", "value" => 2, "rounds" => 1}, &1)
           )

    port = Application.get_env(:ex_pilot, ExPilot.Web.Endpoint)[:http][:port]

    assert {:ok, board} =
             Cauldron2D.Net.Remote.leaders("http://127.0.0.1:#{port}/api", :all, :kills)

    assert Enum.any?(board, &(&1.name == "dan"))
  end

  test "the lobby lists who is online under the names they are seen as, and tells the player how they are seen",
       %{conn: conn} do
    world = Arenas.world_name(:webtest)
    :ok = Cauldron2D.Player.join(world, "bob", %{username: "bob"})
    on_exit(fn -> Cauldron2D.Player.leave(world, "bob") end)
    Process.sleep(100)

    {:ok, _view, html} = live(logged_in(conn), "/lobby")
    assert html =~ "Pilots online"
    assert html =~ ExPilot.Alias.of("bob")
    assert html =~ "in webtest"
    refute html =~ ~r/<span class="mono">bob<\/span>/
    assert html =~ "<b>alice</b>"
    assert html =~ "seen as #{ExPilot.Alias.of("alice")}"
  end

  test "the admin page is for admins only, shows sessions, accounts and what happened, and acts on them",
       %{conn: conn} do
    assert {:error, {:redirect, %{to: "/lobby"}}} = live(logged_in(conn), "/admin")

    :ok = Auth.put_admin("alice", true)
    world = Arenas.world_name(:webtest)
    :ok = Cauldron2D.Player.join(world, "bob", %{username: "bob"})
    on_exit(fn -> Cauldron2D.Player.leave(world, "bob") end)
    Process.sleep(100)

    {:ok, view, html} = live(logged_in(conn), "/admin")
    assert html =~ "Admin"

    assert html =~
             ~r/<td class="mono">bob<\/td><td class="mono">#{ExPilot.Alias.of("bob")}<\/td><td>desktop<\/td><td>in webtest<\/td>/

    assert html =~
             ~r/<td class="mono">alice<\/td><td class="mono">#{ExPilot.Alias.of("alice")}<\/td><td>browser<\/td><td>lobby<\/td>/

    assert html =~ "logged in on a browser"

    assert html =~ "webtest"
    assert html =~ ~r/<td class="mono">alice<\/td>/
    assert html =~ "(anonymous)"
    assert html =~ "joined webtest"

    html = render_click(view, "admin", %{"username" => "bob", "to" => "yes"})
    assert Auth.admin?("bob")
    assert html =~ "bob is an admin"

    html = render_click(view, "kick", %{"id" => "bob", "arena" => "webtest"})
    assert html =~ "kicked #{ExPilot.Alias.of("bob")}"
    Process.sleep(100)
    refute "bob" in Cauldron2D.World.players(world)
  end

  test "the lobby challenges another pilot to a duel and lists it; only the two may fly it", %{
    conn: conn
  } do
    {:ok, view, html} = live(logged_in(conn), "/lobby")
    assert html =~ "Duels"

    html =
      render_submit(view, "challenge", %{
        "to" => ExPilot.Alias.of("bob"),
        "arena" => "webtest",
        "first_to" => "3"
      })

    assert html =~ "#{ExPilot.Alias.of("bob")} is challenged on webtest, first to 3"
    refute html =~ "bob is challenged"
    assert html =~ "#{ExPilot.Alias.of("alice")} vs #{ExPilot.Alias.of("bob")}"
    refute html =~ "alice vs"
    assert html =~ ~r/href="\/arena\/duel_\d+"/
    duel = Enum.find(ExPilot.Duels.list(), &(&1.challenged == "bob" and &1.ended == nil))
    assert duel.first_to == 3
    assert html =~ "withdraw"
    html = render_click(view, "cancel", %{"id" => Integer.to_string(duel.id)})
    assert html =~ "withdrawn"
    refute Enum.any?(ExPilot.Arenas.list(), &(&1.id == duel.arena))
  end

  test "the duel API challenges as the token's pilot and lists the duels", %{conn: _conn} do
    port = Application.get_env(:ex_pilot, ExPilot.Web.Endpoint)[:http][:port]

    assert {:ok, duel} =
             ExPilot.Duels.Remote.challenge(
               "http://127.0.0.1:#{port}/api",
               Auth.token("alice"),
               "dan",
               "webtest",
               2
             )

    assert {:error, "no such token"} =
             ExPilot.Duels.Remote.challenge(
               "http://127.0.0.1:#{port}/api",
               "nope",
               "dan",
               "webtest",
               2
             )

    assert %{challenger: "alice", challenged: "dan", first_to: 2} = duel
    conn = get(build_conn(), "/api/duels")

    assert Enum.any?(
             Jason.decode!(conn.resp_body),
             &match?(%{"challenger" => "alice", "challenged" => "dan"}, &1)
           )

    conn =
      post(build_conn(), "/api/duel", %{"token" => "nope", "to" => "dan", "arena" => "webtest"})

    assert conn.status == 401

    assert {:error, "not_yours"} =
             ExPilot.Duels.Remote.cancel(
               "http://127.0.0.1:#{port}/api",
               Auth.token("eve"),
               duel.id
             )

    assert :ok =
             ExPilot.Duels.Remote.cancel(
               "http://127.0.0.1:#{port}/api",
               Auth.token("alice"),
               duel.id
             )

    assert %{ended: :withdrawn} = Enum.find(ExPilot.Duels.list(), &(&1.id == duel.id))
  end

  test "the touch script is served", %{conn: conn} do
    conn = get(conn, "/expilot.js")
    assert conn.status == 200
    assert conn.resp_body =~ "pointer: coarse"
  end

  test "the sheet is served as a PNG", %{conn: conn} do
    conn = get(conn, "/atlas.png")
    assert conn.status == 200
    assert get_resp_header(conn, "content-type") |> hd() =~ "image/png"
    assert <<137, "PNG", _::binary>> = conn.resp_body
  end

  test "settings keep the browser's levels under their own key, beside the terminal's, and the alias every client shows",
       %{conn: conn} do
    {:ok, view, html} = live(logged_in(conn), "/settings")
    assert html =~ "50%"
    render_submit(view, "save", %{"sfx" => "70", "music" => "20"})
    assert Auth.levels("alice") == %{sfx: 0.7, music: 0.2}
    assert Auth.levels("alice", :terminal) == %{sfx: 0.9, music: 0.9}
    assert Auth.levels("alice", :touch) == %{sfx: 0.85, music: 0.35}

    anonymous = ExPilot.Alias.anonymous("alice")
    assert render(view) =~ "Others see you as <strong>#{anonymous}</strong>"

    assert %{username: ^anonymous} =
             ExPilot.Client.join_props(%{username: "alice", settings: %{}})

    render_submit(view, "alias", %{"alias" => "Ace"})
    assert ExPilot.Alias.of("alice") == "Ace"
    assert render(view) =~ "Others see you as <strong>Ace</strong>"
    assert %{username: "Ace"} = ExPilot.Client.join_props(%{username: "alice", settings: %{}})
    assert ExPilot.Client.player_label("alice") == "Ace"

    render_submit(view, "alias", %{"alias" => ""})
    assert ExPilot.Alias.of("alice") == anonymous
  end

  test "a browser player joins the world through the channel, gets the sheet, the map and frames, and steers" do
    {:ok, socket} = connect(ExPilot.Web.UserSocket, %{"token" => Auth.token("alice")})
    assert socket.assigns.settings == %{sfx: 0.5, music: 0.1}

    {:ok, _reply, socket} = subscribe_and_join(socket, ExPilot.Web.ArenaChannel, "arena:webtest")
    assert_push("sheet", %{url: "/atlas.png", tile: 16})
    assert_push("map", %{width: 120, height: 120, wrap: true}, 2_000)
    assert_push("frame", %{focus: [_, _], movers: movers, hud: hud}, 2_000)
    assert Enum.any?(movers, fn [index, _, _] -> is_integer(index) end)
    seen_as = ExPilot.Alias.of("alice")
    assert Enum.any?(hud, fn row -> Enum.any?(row, fn [text, _] -> text =~ seen_as end) end)
    refute Enum.any?(hud, fn row -> Enum.any?(row, fn [text, _] -> text =~ "alice" end) end)

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

  test "a desktop link over the WebSocket gets the sheet PNG, the map, frames and sound, steers, and leaves" do
    port = Application.get_env(:ex_pilot, ExPilot.Web.Endpoint)[:http][:port]

    {:ok, link} =
      Socket.start_link(
        url: "http://127.0.0.1:#{port}",
        token: Auth.token("alice"),
        topic: "arena:webtest",
        params: %{},
        owner: self()
      )

    assert_receive {:cauldron_link, :joined}, 2_000

    assert_receive {:cauldron_link, :sheet, %{tile: 16, frames: [_ | _]},
                    <<137, "PNG", _::binary>>},
                   3_000

    assert_receive {:cauldron_link, :map, %{width: 120, height: 120, wrap: true}}, 2_000

    assert_receive {:cauldron_link, :frame, %{focus: {_, _}, movers: [_ | _], hud: [_ | _]}},
                   2_000

    assert_receive {:cauldron_link, :pcm, chunk} when byte_size(chunk) > 0, 3_000

    world = Arenas.world_name(:webtest)
    Socket.input(link, %{held: ["thrust"], aim: nil})
    Process.sleep(200)
    %{ships: %{"alice" => ship}} = Cauldron2D.World.snapshot(world)
    refute ship.landed?

    Socket.leave(link)
    Process.sleep(200)
    refute "alice" in Cauldron2D.World.players(world)
  end

  test "the API serves the library's remote calls: login, register and the arenas with their kind" do
    port = Application.get_env(:ex_pilot, ExPilot.Web.Endpoint)[:http][:port]
    url = "http://127.0.0.1:#{port}/api"

    assert {:error, "no such name and password"} =
             Cauldron2D.Net.Remote.login(url, "alice", "wrong", false)

    assert {:ok, token} = Cauldron2D.Net.Remote.login(url, "alice", "alices password", false)
    assert {:ok, "alice"} = Auth.verify(token)
    assert {:ok, _} = Cauldron2D.Net.Remote.login(url, "dave", "daves password", true)
    assert {:error, "taken"} = Cauldron2D.Net.Remote.login(url, "dave", "daves password", true)

    assert {:ok,
            [
              %{
                id: "webtest",
                name: "webtest",
                kind: {"dogfight", {255, 184, 77}},
                teams: [],
                players: 0
              }
            ]} = Cauldron2D.Net.Remote.arenas(url)
  end

  test "the client's arenas from a URL or a node carry worlds reached through the library's remote" do
    port = Application.get_env(:ex_pilot, ExPilot.Web.Endpoint)[:http][:port]
    url = "http://127.0.0.1:#{port}"

    assert [
             %{
               id: "webtest",
               world:
                 {:via, Cauldron2D.Net.Remote.Worlds,
                  {:url, ^url, "t", "webtest", [topic: "arena"]}}
             }
           ] = ExPilot.Client.arenas(%{source: {:url, url, "t"}})

    assert [] = ExPilot.Client.arenas(%{source: {:url, "http://127.0.0.1:1", "t"}})

    assert [
             %{
               id: :webtest,
               name: "webtest",
               map: "Dogfight... 6 bases",
               world: {:via, Cauldron2D.Net.Remote.Worlds, {:node, _, :webtest}}
             }
           ] = ExPilot.Client.arenas(%{source: {:node, node()}})

    assert %ExPilot.Map{} = Arenas.map("Dogfight... 6 bases")
    assert [] = ExPilot.Client.arenas(%{source: {:node, :nobody@nowhere}})
  end

  test "the desktop's local link joins a world of this node through ExPilot.Client and gets the sheet, the map and frames" do
    world = Arenas.world_name(:webtest)

    {:ok, link} =
      Local.start_link(
        game: ExPilot.Client,
        world: world,
        name: "alice",
        props: %{username: "alice", sink: TuningFork.Sink.Silent},
        owner: self()
      )

    assert_receive {:cauldron_link, :sheet, %{tile: 16}, <<137, "PNG", _::binary>>}, 3_000
    assert_receive {:cauldron_link, :map, %{width: 120, height: 120}}, 2_000
    assert_receive {:cauldron_link, :frame, %{movers: [_ | _], hud: [_ | _]}}, 2_000
    assert "alice" in Cauldron2D.World.players(world)
    GenServer.stop(link)
    Process.sleep(100)
    refute "alice" in Cauldron2D.World.players(world)
  end

  test "a desktop link with a bad token is refused" do
    port = Application.get_env(:ex_pilot, ExPilot.Web.Endpoint)[:http][:port]

    {:ok, link} =
      Socket.start_link(
        url: "http://127.0.0.1:#{port}",
        token: "nope",
        topic: "arena:webtest",
        params: %{},
        owner: self()
      )

    assert_receive {:cauldron_link, :refused, _}, 2_000
    Process.sleep(100)
    refute Process.alive?(link)
  end

  test "joining with spectate watches without a ship" do
    {:ok, socket} = connect(ExPilot.Web.UserSocket, %{"token" => Auth.token("alice")})

    {:ok, _reply, socket} =
      subscribe_and_join(socket, ExPilot.Web.ArenaChannel, "arena:webtest", %{"spectate" => "1"})

    assert_push("frame", %{hud: hud}, 2_000)
    assert Enum.any?(hud, fn row -> Enum.any?(row, fn [text, _] -> text =~ "watching" end) end)
    %{ships: ships} = Cauldron2D.World.snapshot(Arenas.world_name(:webtest))
    refute Map.has_key?(ships, "alice")
    Process.unlink(socket.channel_pid)
    leave(socket)
  end

  test "a stranger's token opens no socket, and a topic with no arena is refused" do
    assert :error = connect(ExPilot.Web.UserSocket, %{"token" => "nonsense"})
    {:ok, socket} = connect(ExPilot.Web.UserSocket, %{"token" => Auth.token("alice")})

    assert {:error, %{reason: "no such world"}} =
             subscribe_and_join(socket, ExPilot.Web.ArenaChannel, "arena:nowhere")
  end
end
