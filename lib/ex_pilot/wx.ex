defmodule ExPilot.Wx do
  @moduledoc """
  ExPilot in a window, played with the keys or the mouse: the title, the lobby, the
  arena, the summary, the settings, a connect screen and a serve screen, every one
  drawn on the same canvas (`ExPilot.Wx.Screens` on `Cauldron2D.Wx.Text`), the arena on
  `Cauldron2D.Wx.View`.

      ExPilot.Wx.run(fields: %{name: "alice"})

  `l` on the title or in the lobby shows the leaders: the boards of the place the lobby
  lists (this app's, a server's over `GET /api/leaders`, a node's), `←`/`→` the period,
  `Tab` the metric. `Enter` on the title plays here: the arenas this app carries, with their robots, no
  set-up. `c` connects elsewhere — a server by its URL (a token from `POST /api/token`,
  the arenas over its WebSocket) or a node this one connects to (its worlds joined
  across the connection, its maps adopted here) — and the lobby then lists that place's
  arenas. `s` is the settings: the effects and music levels and whether the pointer
  steers, the desktop's own (`Cauldron2D.Drafter.Client.Settings` with the kind
  `:desktop`, in `<name>.desktop.settings`) and applied to the arena as they change. `h`
  is the serve screen: `ExPilot.Server` with the ports, interfaces, accounts file and
  robots typed in, for players on other machines.

  ## Keys

  Title: `Enter` play here, `c` connect, `l` leaders, `s` settings, `h` host a server, `q` or `Esc`
  quit. Connect: `←`/`→` where, `↑`/`↓` or `Tab` field, typing fills the field in,
  `Enter` the chosen action (or the next field), `Esc` title. Lobby: `↑`/`↓`,
  `PgUp`/`PgDn`, `Home`/`End`, `Enter` join, `w` watch, `t` team, `s` settings, `r`
  refresh, `c` connect elsewhere, `Esc` title. Arena: the game's keys, `+`/`-` or the
  wheel zoom the view in and out — out as far as the whole arena — and `0` puts it
  back; watching, the arrows or a drag pan it, the wheel zooms about the pointer and
  `0` recentres it; `m` shows the frames and draws a second in the corner and hides them again, `Tab` the settings
  with the ship left where it is, `Esc` or `q` leaves for the lobby.
  Settings: `↑`/`↓` choose, `←`/`→` change a level or the switch, `Enter` the
  switch, `Esc` back where it was opened from. Summary: `Enter` again, `Esc` lobby, `q`
  title. Serve: `Enter` starts or stops (the first row), `↓` reaches the settings,
  typed as on connect, `Esc` title. Every item on a screen can be clicked instead.

  ## Options

    * `:fields` — values for fields by key (`:url`, `:name`, `:node`, `:cookie`…), over the defaults
    * `:size` — the window, default `{1320, 800}`
  """

  @behaviour :wx_object

  alias Cauldron2D.Beacon
  alias Cauldron2D.Drafter.Client.Settings
  alias Cauldron2D.Net.Remote
  alias Cauldron2D.World.Presence
  alias Cauldron2D.Wx.{Const, Text, View}
  alias ExPilot.{Arenas, Server}
  alias ExPilot.Wx.{Keys, Screens}

  require Record

  Record.defrecordp(:wx, Record.extract(:wx, from_lib: "wx/include/wx.hrl"))
  Record.defrecordp(:wxClose, Record.extract(:wxClose, from_lib: "wx/include/wx.hrl"))

  @wheres [
    {"a server", [url: "http://localhost:2280", name: "pilot", password: {:secret, ""}],
     [connect: "log in", register: "register"]},
    {"a node", [node: "expilot@localhost", cookie: "", name: "pilot"], [connect: "connect"]}
  ]
  @stars 140

  @enter 13
  @escape 27
  @tab 9
  @backspace 8
  @left 314
  @up 315
  @right 316
  @down 317
  @page_up 366
  @page_down 367
  @home 313
  @end_key 312
  @step 0.05

  defguardp in_arena?(state)
            when :erlang.map_get(:screen, state) == :arena or
                   (:erlang.map_get(:screen, state) == :settings and
                      :erlang.map_get(:from, state) == :arena)

  @doc """
  Open the window and block until it is closed.

  Closing leaves any match, stops a hosted server, and destroys the window before the
  process ends; then the wx environment is closed and the wx thread is made to finish
  that teardown before this returns, so a caller may exit the VM at once.
  """
  @spec run(keyword()) :: :ok
  def run(opts \\ []) do
    wx = :wx.new()
    client = :wx_object.start_link(__MODULE__, {wx, opts}, [])
    :wx_object.call(client, :wait, :infinity)
    :wx.destroy()
    drained()
  end

  defp drained do
    :wx.new()
    :wxSystemSettings.getScreenType()
    :wx.destroy()
    :ok
  end

  @impl :wx_object
  def init({wx, opts}) do
    frame =
      :wxFrame.new(wx, Const.id_any(), ~c"ExPilot", size: Keyword.get(opts, :size, {1320, 800}))

    sizer = :wxBoxSizer.new(Const.vertical())
    text = Text.new(frame, owner: self(), backdrop: &stars/3)
    me = self()

    arena =
      View.new(frame,
        keymap: Keys.keymap(),
        steering: Keys.steering(),
        size: {960, 640},
        scale: 2,
        hud: :right,
        hud_size: 300,
        zoom: true,
        on_over: fn over -> send(me, {:arena, :over, over}) end,
        on_closed: fn reason -> send(me, {:arena, :closed, reason}) end,
        on_refused: fn reason -> send(me, {:arena, :refused, reason}) end,
        on_key: fn code -> send(me, {:arena, :key, code}) end
      )

    :wxSizer.add(sizer, Text.window(text), proportion: 1, flag: Const.expand())
    :wxSizer.add(sizer, View.window(arena), proportion: 1, flag: Const.expand())
    :wxWindow.hide(View.window(arena))
    :wxFrame.setSizer(frame, sizer)
    :wxFrame.connect(frame, :close_window)
    :wxFrame.show(frame)
    Text.focus(text)
    Presence.subscribe()
    overrides = Keyword.get(opts, :fields, %{})
    name = Map.get(overrides, :name, "pilot")

    state = %{
      frame: frame,
      sizer: sizer,
      text: text,
      arena: arena,
      overrides: overrides,
      name: name,
      settings: Settings.load(ExPilot.Client, name, %{}, kind: :desktop),
      setting: 0,
      leaders: %{period: :day, metric: :kills, board: []},
      from: :title,
      screen: :title,
      title: %{
        name: "EXPILOT",
        tagline: "an XPilot for the desktop, the browser and the terminal, on the same worlds"
      },
      wheres: Enum.map(@wheres, fn {label, _fields, _actions} -> {label, []} end),
      where: 0,
      found: [],
      fields: [],
      field: 0,
      actions: [],
      arenas: [],
      selected: 0,
      team: nil,
      status: "",
      who: "",
      session: nil,
      chosen: nil,
      summary: nil,
      stats?: false,
      server: nil,
      serve_fields:
        fields(
          [
            ssh_port: "2222",
            web_port: Integer.to_string(Server.default_http()),
            interfaces: "any",
            accounts: Server.accounts_path(),
            robots: ""
          ],
          overrides
        ),
      serve_lines: [],
      waiting: []
    }

    {frame, state |> choose_where(0) |> draw()}
  end

  @doc "The starfield behind the screens: `Cauldron2D.Wx.Text`'s backdrop."
  @spec stars(term(), pos_integer(), pos_integer()) :: :ok
  def stars(dc, width, height) do
    :wxDC.setPen(dc, :wxPen.new({200, 210, 240}))

    for i <- 1..@stars,
        do:
          :wxDC.drawPoint(
            dc,
            {:erlang.phash2({i, :x}, max(width, 1)), :erlang.phash2({i, :y}, max(height, 1))}
          )

    :ok
  end

  defp fields(specs, overrides) do
    Enum.map(specs, fn
      {key, {:secret, default}} -> {key, Map.get(overrides, key, default), true}
      {key, default} -> {key, Map.get(overrides, key, default), false}
    end)
  end

  defp choose_where(state, index) do
    {_label, specs, actions} = Enum.at(@wheres, index)

    %{
      state
      | where: index,
        field: 0,
        actions: actions,
        fields: fields(specs, state.overrides),
        found: Beacon.Listener.found()
    }
  end

  defp use_found(state, index) do
    case Enum.at(state.found, index) do
      nil ->
        state

      server ->
        fields =
          Enum.map(state.fields, fn
            {:url, _, secret?} when server.http != nil ->
              {:url, server.http, secret?}

            {:node, _, secret?} when server.node != nil ->
              {:node, Atom.to_string(server.node), secret?}

            field ->
              field
          end)

        %{state | fields: fields, status: "Filled in from #{server.host}."}
    end
  end

  defp draw(state) do
    labelled = fn fields ->
      Enum.map(fields, fn {key, value, secret?} ->
        {key |> Atom.to_string() |> String.replace("_", " "), value, secret?}
      end)
    end

    Text.show(
      state.text,
      Screens.draw(
        %{state | fields: labelled.(state.fields), serve_fields: labelled.(state.serve_fields)},
        Text.size(state.text)
      )
    )

    state
  end

  @impl :wx_object
  def handle_call(:wait, from, state), do: {:noreply, %{state | waiting: [from | state.waiting]}}

  @impl :wx_object
  def handle_event(wx(event: wxClose()), state), do: {:stop, :normal, closing(state)}
  def handle_event(_event, state), do: {:noreply, state}

  @impl :wx_object
  def handle_info({:cauldron_wx_text, :key, code}, state), do: key(code, state)
  def handle_info({:cauldron_wx_text, :char, char}, state), do: {:noreply, typed(char, state)}
  def handle_info({:cauldron_wx_text, :action, action}, state), do: clicked(action, state)

  def handle_info({:arena, :over, over}, state) do
    title = Map.get(over, "title") || Map.get(over, :title) || "Over"
    lines = Map.get(over, "lines") || Map.get(over, :lines) || []

    {:noreply,
     state
     |> leave_arena()
     |> Map.merge(%{screen: :summary, summary: %{title: title, lines: lines}, status: ""})
     |> show_text()
     |> draw()}
  end

  def handle_info({:arena, :key, code}, %{screen: :arena} = state) do
    case code do
      c when c in [@escape, ?Q] -> {:noreply, to_lobby(state)}
      @tab -> {:noreply, to_settings(state, :arena)}
      ?M -> {:noreply, toggle_stats(state)}
      _ -> {:noreply, state}
    end
  end

  def handle_info({:arena, :closed, reason}, state) when in_arena?(state),
    do: {:noreply, to_lobby(%{state | status: "The connection ended: #{inspect(reason)}"})}

  def handle_info({:arena, :refused, reason}, state) when in_arena?(state),
    do: {:noreply, to_lobby(%{state | status: "Could not join: #{inspect(reason)}"})}

  def handle_info(
        {:cauldron_players, _world, _change, _id},
        %{screen: :lobby, session: %{where: :app}} = state
      ),
      do: {:noreply, refresh(state)}

  def handle_info(_message, state), do: {:noreply, state}

  defp play_here(state) do
    %{
      state
      | session: %{where: :app, name: state.name},
        who: state.name,
        status: "Flying here as #{state.name}."
    }
    |> to_lobby()
  end

  defp clicked({:key, code}, state), do: key(code, state)

  defp clicked({:row, index}, %{screen: :lobby, selected: index} = state),
    do: {:noreply, join(state, %{})}

  defp clicked({:row, index}, %{screen: :lobby} = state), do: {:noreply, select(state, index)}

  defp clicked({:where, index}, %{screen: :connect} = state),
    do: {:noreply, state |> choose_where(index) |> draw()}

  defp clicked({:found, index}, %{screen: :connect} = state),
    do: {:noreply, state |> use_found(index) |> draw()}

  defp clicked({:field, index}, %{screen: :connect} = state),
    do: {:noreply, %{state | field: index} |> draw()}

  defp clicked({:field, index}, %{screen: :serve} = state),
    do: {:noreply, %{state | field: index + 1} |> draw()}

  defp clicked({:choose, index}, %{screen: :connect} = state),
    do: {:noreply, connect(state, elem(Enum.at(state.actions, index), 0))}

  defp clicked({:setting, index}, %{screen: :settings} = state),
    do: {:noreply, %{state | setting: index} |> draw()}

  defp clicked({:period, index}, %{screen: :leaders} = state),
    do:
      {:noreply,
       state
       |> put_in([:leaders, :period], elem(Enum.at(Screens.periods(), index), 0))
       |> load_leaders()}

  defp clicked({:metric, index}, %{screen: :leaders} = state),
    do:
      {:noreply,
       state
       |> put_in([:leaders, :metric], elem(Enum.at(Screens.metrics(), index), 0))
       |> load_leaders()}

  defp clicked({:step, index, delta}, %{screen: :settings} = state),
    do: {:noreply, %{state | setting: index} |> change(delta)}

  defp clicked(:serve, %{screen: :serve} = state), do: {:noreply, toggle_serve(state)}
  defp clicked(_action, state), do: {:noreply, state}

  defp key(code, %{screen: :title} = state) do
    case code do
      @enter -> {:noreply, play_here(state)}
      ?C -> {:noreply, to_connect(state)}
      ?S -> {:noreply, to_settings(state, :title)}
      ?L -> {:noreply, to_leaders(state, :title)}
      ?H -> {:noreply, state |> Map.merge(%{screen: :serve, field: 0, status: ""}) |> draw()}
      c when c in [?Q, @escape] -> {:stop, :normal, closing(state)}
      _ -> {:noreply, state}
    end
  end

  defp key(code, %{screen: :connect} = state), do: {:noreply, connect_key(code, state)}
  defp key(code, %{screen: :lobby} = state), do: {:noreply, lobby_key(code, state)}

  defp key(code, %{screen: :settings} = state) do
    rows = length(Screens.settings_rows())

    case code do
      @escape ->
        {:noreply, back(state)}

      @up ->
        {:noreply, %{state | setting: Integer.mod(state.setting - 1, rows)} |> draw()}

      c when c in [@down, @tab] ->
        {:noreply, %{state | setting: Integer.mod(state.setting + 1, rows)} |> draw()}

      @left ->
        {:noreply, change(state, -1)}

      @right ->
        {:noreply, change(state, 1)}

      @enter ->
        {:noreply,
         if(Enum.at(Screens.settings_rows(), state.setting) == :pointer,
           do: change(state, 1),
           else: state
         )}

      _ ->
        {:noreply, state}
    end
  end

  defp key(code, %{screen: :leaders} = state) do
    case code do
      @escape ->
        {:noreply, back(state)}

      @left ->
        {:noreply,
         state
         |> put_in([:leaders, :period], step(Screens.periods(), state.leaders.period, -1))
         |> load_leaders()}

      @right ->
        {:noreply,
         state
         |> put_in([:leaders, :period], step(Screens.periods(), state.leaders.period, 1))
         |> load_leaders()}

      @tab ->
        {:noreply,
         state
         |> put_in([:leaders, :metric], step(Screens.metrics(), state.leaders.metric, 1))
         |> load_leaders()}

      _ ->
        {:noreply, state}
    end
  end

  defp key(code, %{screen: :summary} = state) do
    case code do
      @enter -> {:noreply, join_again(state)}
      @escape -> {:noreply, to_lobby(state)}
      ?Q -> {:noreply, to_title(state)}
      _ -> {:noreply, state}
    end
  end

  defp key(code, %{screen: :serve} = state) do
    total = length(state.serve_fields) + 1

    case code do
      @escape ->
        {:noreply, to_title(state)}

      @up ->
        {:noreply, %{state | field: Integer.mod(state.field - 1, total)} |> draw()}

      c when c in [@down, @tab] ->
        {:noreply, %{state | field: Integer.mod(state.field + 1, total)} |> draw()}

      @backspace ->
        {:noreply, state |> edit(&String.slice(&1, 0..-2//1)) |> draw()}

      @enter ->
        {:noreply,
         if(state.field == 0,
           do: toggle_serve(state),
           else: %{state | field: rem(state.field + 1, total)} |> draw()
         )}

      _ ->
        {:noreply, state}
    end
  end

  defp key(_code, state), do: {:noreply, state}

  defp connect_key(@escape, state), do: to_title(state)
  defp connect_key(?R, state), do: %{state | found: Beacon.Listener.found()} |> draw()

  defp connect_key(@left, state),
    do: state |> choose_where(Integer.mod(state.where - 1, length(@wheres))) |> draw()

  defp connect_key(@right, state),
    do: state |> choose_where(Integer.mod(state.where + 1, length(@wheres))) |> draw()

  defp connect_key(@up, state),
    do: %{state | field: Integer.mod(state.field - 1, connect_rows(state))} |> draw()

  defp connect_key(code, state) when code in [@down, @tab],
    do: %{state | field: Integer.mod(state.field + 1, connect_rows(state))} |> draw()

  defp connect_key(@backspace, state), do: state |> edit(&String.slice(&1, 0..-2//1)) |> draw()

  defp connect_key(@enter, state) do
    if state.field < length(state.fields),
      do: %{state | field: state.field + 1} |> draw(),
      else: connect(state, elem(Enum.at(state.actions, state.field - length(state.fields)), 0))
  end

  defp connect_key(_code, state), do: state

  defp connect_rows(state), do: length(state.fields) + length(state.actions)

  defp lobby_key(code, state) when code in [@escape, ?Q], do: to_title(state)
  defp lobby_key(?C, state), do: to_connect(state)

  defp lobby_key(@up, state),
    do: select(state, Integer.mod(state.selected - 1, arena_count(state)))

  defp lobby_key(@down, state),
    do: select(state, Integer.mod(state.selected + 1, arena_count(state)))

  defp lobby_key(@page_up, state), do: select(state, max(state.selected - Screens.window(), 0))

  defp lobby_key(@page_down, state),
    do: select(state, min(state.selected + Screens.window(), arena_count(state) - 1))

  defp lobby_key(@home, state), do: select(state, 0)
  defp lobby_key(@end_key, state), do: select(state, arena_count(state) - 1)
  defp lobby_key(?T, state), do: cycle_team(state)
  defp lobby_key(?S, state), do: to_settings(state, :lobby)
  defp lobby_key(?L, state), do: to_leaders(state, :lobby)
  defp lobby_key(?R, state), do: refresh(state)
  defp lobby_key(?W, state), do: join(state, %{spectate: true})
  defp lobby_key(@enter, state), do: join(state, %{})
  defp lobby_key(_code, state), do: state

  defp arena_count(state), do: max(length(state.arenas), 1)

  defp typed(char, %{screen: screen} = state)
       when screen in [:connect, :serve] and char >= 32 and char != 127 do
    state |> edit(&(&1 <> <<char::utf8>>)) |> draw()
  end

  defp typed(_char, state), do: state

  defp edit(%{screen: :connect} = state, fun),
    do: %{state | fields: edit_field(state.fields, state.field, fun)}

  defp edit(%{screen: :serve} = state, fun),
    do: %{state | serve_fields: edit_field(state.serve_fields, state.field - 1, fun)}

  defp edit_field(fields, index, fun) when index >= 0 and index < length(fields),
    do: List.update_at(fields, index, fn {key, value, secret?} -> {key, fun.(value), secret?} end)

  defp edit_field(fields, _index, _fun), do: fields

  defp values(fields), do: Map.new(fields, fn {key, value, _} -> {key, value} end)

  defp connect(state, action) do
    case session(state.where, action, values(state.fields)) do
      {:ok, session, message} ->
        %{state | session: session, who: session.name, status: message} |> to_lobby()

      {:error, message} ->
        %{state | status: message} |> draw()
    end
  end

  defp session(0, action, %{url: url, name: name, password: password}) do
    with {:ok, token} <- Remote.login(url <> "/api", name, password, action == :register) do
      {:ok, %{where: :url, url: url, token: token, name: name}, "Logged in as #{name}."}
    end
  end

  defp session(1, _action, %{node: node, cookie: cookie, name: name}) do
    node = String.to_atom(node)
    unless Node.alive?(), do: start_distribution()
    if cookie != "", do: Node.set_cookie(String.to_atom(cookie))

    if Node.connect(node),
      do: {:ok, %{where: :node, node: node, name: name}, "Connected to #{node}."},
      else: {:error, "Could not connect to #{node}: is it running with that name and cookie?"}
  end

  defp start_distribution do
    System.cmd("epmd", ["-daemon"])
    {:ok, host} = :inet.gethostname()
    Node.start(:"expilot_desktop_#{System.pid()}@#{host}", :shortnames)
  end

  defp refresh(%{session: nil} = state), do: %{state | status: "Connect first."} |> draw()

  defp refresh(state) do
    case arenas(state.session) do
      {:ok, arenas} ->
        %{state | arenas: arenas, selected: min(state.selected, max(length(arenas) - 1, 0))}
        |> draw()

      {:error, message} ->
        %{state | arenas: [], status: message} |> draw()
    end
  end

  defp arenas(%{where: :url, url: url}), do: Remote.arenas(url <> "/api")

  defp arenas(%{where: :node, node: node}),
    do: {:ok, ExPilot.Client.arenas(%{source: {:node, node}})}

  defp arenas(%{where: :app}), do: {:ok, Arenas.list()}

  defp select(state, index), do: %{state | selected: index, team: nil} |> draw()

  defp cycle_team(state) do
    teams = (Enum.at(state.arenas, state.selected) || %{teams: []}) |> Map.get(:teams, [])
    choices = [nil | teams]
    index = Enum.find_index(choices, &(&1 == state.team)) || 0
    %{state | team: Enum.at(choices, rem(index + 1, length(choices)))} |> draw()
  end

  defp join(state, extra) do
    case Enum.at(state.arenas, state.selected) do
      nil ->
        %{state | status: "No arena to join."} |> draw()

      arena ->
        props = if state.team, do: Map.put(extra, :team, state.team), else: extra
        fly(%{state | chosen: {arena, props}})
    end
  end

  defp join_again(%{chosen: nil} = state), do: to_lobby(state)
  defp join_again(state), do: fly(state)

  defp fly(%{chosen: {arena, props}} = state) do
    case link(state.session, arena, props) do
      {:ok, link} -> to_arena(state, link)
      {:error, message} -> to_lobby(%{state | status: message})
    end
  end

  defp link(%{where: :url, url: url, token: token}, arena, props) do
    {:ok,
     {:socket,
      url: url,
      token: token,
      topic: "arena:" <> arena.name,
      params: Map.new(props, fn {key, value} -> {Atom.to_string(key), value} end)}}
  end

  defp link(%{where: :node, node: node, name: name}, arena, props) do
    with {:ok, world} <- Remote.node_world(node, arena.id) do
      {:ok,
       {:local,
        game: ExPilot.Client, world: world, name: name, props: Map.put(props, :username, name)}}
    end
  end

  defp link(%{where: :app, name: name}, arena, props) do
    {:ok,
     {:local,
      game: ExPilot.Client,
      world: Arenas.world_name(String.to_atom(arena.name)),
      name: name,
      props: Map.put(props, :username, name)}}
  end

  defp change(state, delta) do
    settings =
      case Enum.at(Screens.settings_rows(), state.setting) do
        :pointer -> %{state.settings | pointer: not state.settings.pointer}
        level -> Settings.nudge(state.settings, level, delta * @step)
      end

    Settings.save(settings, ExPilot.Client, state.name, nil, kind: :desktop)
    %{state | settings: settings} |> apply_settings() |> draw()
  end

  defp apply_settings(%{settings: settings} = state) do
    View.levels(state.arena, settings.sfx, settings.music)
    View.pointer(state.arena, settings.pointer)
    state
  end

  defp toggle_stats(state) do
    View.show_stats(state.arena, not state.stats?)
    %{state | stats?: not state.stats?}
  end

  defp step(choices, current, delta) do
    keys = Keyword.keys(choices)
    index = Enum.find_index(keys, &(&1 == current)) || 0
    Enum.at(keys, Integer.mod(index + delta, length(keys)))
  end

  defp to_leaders(state, from) do
    state
    |> Map.merge(%{screen: :leaders, from: from, status: ""})
    |> show_text()
    |> load_leaders()
  end

  defp load_leaders(%{leaders: %{period: period, metric: metric}} = state) do
    case leaders(state.session, period, metric) do
      {:ok, board} ->
        state |> put_in([:leaders, :board], board) |> draw()

      {:error, message} ->
        state |> put_in([:leaders, :board], []) |> Map.put(:status, message) |> draw()
    end
  end

  defp leaders(%{where: :url, url: url}, period, metric),
    do: Remote.leaders(url <> "/api", period, metric)

  defp leaders(%{where: :node, node: node}, period, metric),
    do: Remote.node_leaders(node, ExPilot.Ledger, period, metric)

  defp leaders(_local, period, metric), do: {:ok, ExPilot.Ledger.board(period, metric)}

  defp to_settings(state, from) do
    state
    |> Map.merge(%{screen: :settings, from: from, setting: 0, status: ""})
    |> show_text()
    |> draw()
  end

  defp back(%{from: :arena} = state), do: show_arena(state)
  defp back(%{from: :lobby} = state), do: to_lobby(state)
  defp back(state), do: to_title(state)

  defp to_title(state),
    do:
      state |> leave_arena() |> Map.merge(%{screen: :title, status: ""}) |> show_text() |> draw()

  defp to_connect(state),
    do:
      state
      |> leave_arena()
      |> Map.merge(%{screen: :connect, field: 0, status: ""})
      |> show_text()
      |> draw()

  defp to_lobby(state),
    do: state |> leave_arena() |> Map.put(:screen, :lobby) |> show_text() |> refresh()

  defp to_arena(state, link) do
    :ok = View.join(state.arena, link)
    state |> apply_settings() |> show_arena()
  end

  defp show_arena(state) do
    :wxWindow.hide(Text.window(state.text))
    :wxWindow.show(View.window(state.arena))
    :wxSizer.layout(state.sizer)
    View.focus(state.arena)
    %{state | screen: :arena, status: ""}
  end

  defp leave_arena(state) when in_arena?(state) do
    View.leave(state.arena)
    state
  end

  defp leave_arena(state), do: state

  defp show_text(state) do
    :wxWindow.hide(View.window(state.arena))
    :wxWindow.show(Text.window(state.text))
    :wxSizer.layout(state.sizer)
    Text.focus(state.text)
    state
  end

  defp toggle_serve(%{server: nil} = state) do
    %{state | status: "Starting…"} |> draw()
    fields = values(state.serve_fields)

    opts = [
      port: integer(fields.ssh_port, 2222),
      http: integer(fields.web_port, Server.default_http()),
      ip: ip_option(fields.interfaces),
      accounts: fields.accounts
    ]

    opts =
      case integer(fields.robots, nil) do
        nil -> opts
        robots -> [{:robots, robots} | opts]
      end

    case Server.start(opts) do
      {:ok, server} ->
        %{state | server: server, serve_lines: splash(opts[:port], server), status: ""} |> draw()

      {:error, reason} ->
        %{state | status: "Could not start: #{inspect(reason)}"} |> draw()
    end
  end

  defp toggle_serve(state) do
    Server.stop(state.server)
    %{state | server: nil, serve_lines: [], status: "Stopped."} |> draw()
  end

  defp splash(port, %{arenas: arenas, http: http} = server) do
    host = Server.hostname()

    [
      "Serving #{length(arenas)} arenas.",
      "",
      "in a browser:  http://#{host}:#{http}/",
      "register:      ssh -p #{port} new@#{host}",
      "play:          ssh -p #{port} <name>@#{host}",
      "with sound:    ssh -p #{port} -R <sound port>:127.0.0.1:4713 <name>@#{host}",
      "here:          Esc, then Enter"
    ] ++ node_lines(Map.get(server, :node))
  end

  defp node_lines(nil), do: []

  defp node_lines(node),
    do: [
      "as a node:     #{node}   cookie #{Node.get_cookie()}",
      "calling on this network every two seconds"
    ]

  defp ip_option(text) do
    binds =
      text
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.map(fn
        "" ->
          :any

        "any" ->
          :any

        address ->
          address
          |> to_charlist()
          |> :inet.parse_address()
          |> then(fn
            {:ok, ip} -> ip
            _ -> :any
          end)
      end)

    if length(binds) == 1, do: hd(binds), else: binds
  end

  defp integer(text, default) do
    case Integer.parse(String.trim(text)) do
      {n, ""} -> n
      _ -> default
    end
  end

  defp closing(state) do
    state = leave_arena(state)
    if state.server, do: Server.stop(state.server)
    :wx_object.stop(state.text)
    :wx_object.stop(state.arena)
    :wxFrame.destroy(state.frame)
    for from <- state.waiting, do: :wx_object.reply(from, :ok)
    %{state | waiting: [], server: nil}
  end

  @impl :wx_object
  def terminate(_reason, state) do
    for from <- state.waiting, do: :wx_object.reply(from, :ok)
    :ok
  end
end
