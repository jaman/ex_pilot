defmodule ExPilot.Terminal do
  @moduledoc """
  ExPilot in a terminal, with the desktop's flow: a title of its own, play here, connect
  to a node or a server, host a server, the leaders — the arenas, settings and play
  themselves being `Cauldron2D.Drafter.Client` started at its lobby and driven from
  here.

      Drafter.run(ExPilot.Terminal, props: %{username: "alice"})

  ## Keys

  Title: `Enter` play here, `c` connect, `l` leaders, `h` host a server, `q` or `Esc`
  quit. Connect and host: `Tab` between the fields, `Enter` in a field or on the button
  does it, `Esc` title. Leaders: `←`/`→` period, `Tab` metric, `Esc` title. In the
  client, its own keys; `Esc` from its lobby comes back here.

  ## Mount props

    * `:username` — the pilot's name. Default `pilot`
    * `:url`, `:node`, `:cookie` — what the connect form starts with
  """

  use Drafter.App, key_release: true, cell_size: true, frame_pacing: :always

  alias Cauldron2D.Beacon
  alias Cauldron2D.Drafter.Client
  alias Cauldron2D.Net.Remote
  alias ExPilot.{Ledger, Server}
  alias ExPilot.Wx.Screens

  @dim %{fg: :bright_black}
  @cyan %{fg: :cyan}
  @amber %{fg: :yellow}

  @impl true
  def mount(props) do
    %{
      props: props,
      screen: :title,
      username: Map.get(props, :username, "pilot"),
      client: nil,
      source: :local,
      status: "",
      url: Map.get(props, :url, "http://localhost:#{Server.default_http()}"),
      password: "",
      node: Map.get(props, :node, "expilot@localhost"),
      cookie: Map.get(props, :cookie, ""),
      ssh_port: "2222",
      web_port: Integer.to_string(Server.default_http()),
      interfaces: "any",
      accounts: Server.accounts_path(),
      robots: "",
      server: nil,
      serve_lines: [],
      leaders: %{period: :day, metric: :kills, board: []}
    }
  end

  @impl true
  def refresh_rate, do: Client.refresh_rate()

  @impl true
  def unmount(%{client: client}) do
    if client, do: Client.unmount(client)
    :ok
  end

  @impl true
  def render(%{screen: :client, client: client}), do: Client.render(client)

  def render(%{screen: :title} = state) do
    vertical(
      [
        label(""),
        label("EXPILOT", style: %{fg: :cyan, bold: true}, align: :center),
        label("an XPilot for the terminal, the browser and the desktop, on the same worlds",
          style: @dim,
          align: :center
        ),
        label(""),
        label("Enter  play here", align: :center),
        label("c      connect to a server or a node", align: :center),
        label("l      leaders", align: :center),
        label("h      host a server", align: :center),
        label("q      quit", align: :center),
        label(""),
        label(where(state.source), style: @dim, align: :center),
        label(state.status, style: @amber, align: :center)
      ],
      gap: 0
    )
  end

  def render(%{screen: :connect} = state) do
    vertical(
      [
        label("Where are the arenas?", style: %{bold: true}),
        label(""),
        label("A server", style: @cyan),
        horizontal(
          [
            label(String.pad_trailing("url", 10)),
            text_input(id: :url, bind: :url, on_submit: :login, flex: 1)
          ],
          gap: 1
        ),
        horizontal(
          [
            label(String.pad_trailing("name", 10)),
            text_input(id: :username, bind: :username, on_submit: :login, flex: 1)
          ],
          gap: 1
        ),
        horizontal(
          [
            label(String.pad_trailing("password", 10)),
            text_input(id: :password, bind: :password, on_submit: :login, password: true, flex: 1)
          ],
          gap: 1
        ),
        horizontal(
          [
            button("log in", id: :login, on_click: :login),
            button("register", id: :register, on_click: :register)
          ],
          gap: 2
        ),
        label(""),
        label("A node", style: @cyan),
        horizontal(
          [
            label(String.pad_trailing("node", 10)),
            text_input(id: :node, bind: :node, on_submit: :connect_node, flex: 1)
          ],
          gap: 1
        ),
        horizontal(
          [
            label(String.pad_trailing("cookie", 10)),
            text_input(
              id: :cookie,
              bind: :cookie,
              on_submit: :connect_node,
              password: true,
              flex: 1
            )
          ],
          gap: 1
        ),
        button("connect", id: :connect_node, on_click: :connect_node),
        label("")
      ] ++
        found_items() ++
        [
          label("Tab  next field     Enter  do it     Esc  title", style: @dim),
          label(state.status, style: @amber)
        ],
      gap: 0
    )
  end

  def render(%{screen: :host} = state) do
    running? = state.server != nil

    vertical(
      [
        label(if(running?, do: "Serving", else: "Host a server"), style: %{bold: true}),
        label(""),
        button(if(running?, do: "stop the server", else: "start the server"),
          id: :serve,
          on_click: :serve
        ),
        label(""),
        horizontal(
          [
            label(String.pad_trailing("ssh port", 12)),
            text_input(id: :ssh_port, bind: :ssh_port, on_submit: :serve, flex: 1)
          ],
          gap: 1
        ),
        horizontal(
          [
            label(String.pad_trailing("web port", 12)),
            text_input(id: :web_port, bind: :web_port, on_submit: :serve, flex: 1)
          ],
          gap: 1
        ),
        horizontal(
          [
            label(String.pad_trailing("interfaces", 12)),
            text_input(id: :interfaces, bind: :interfaces, on_submit: :serve, flex: 1)
          ],
          gap: 1
        ),
        horizontal(
          [
            label(String.pad_trailing("accounts", 12)),
            text_input(id: :accounts, bind: :accounts, on_submit: :serve, flex: 1)
          ],
          gap: 1
        ),
        horizontal(
          [
            label(String.pad_trailing("robots", 12)),
            text_input(id: :robots, bind: :robots, on_submit: :serve, flex: 1)
          ],
          gap: 1
        ),
        label("")
      ] ++
        Enum.map(
          state.serve_lines,
          &label(&1, style: if(running?, do: %{fg: :green}, else: @dim))
        ) ++
        [
          label(""),
          label("Enter  start or stop     Tab  a setting     Esc  title", style: @dim),
          label(state.status, style: @amber)
        ],
      gap: 0
    )
  end

  def render(%{screen: :leaders, leaders: leaders} = state) do
    periods =
      Enum.map_join(Screens.periods(), "   ", fn {period, title} ->
        if(period == leaders.period, do: "▶ ", else: "  ") <> title
      end)

    metrics =
      Enum.map_join(Screens.metrics(), "   ", fn {metric, title} ->
        if(metric == leaders.metric, do: "▶ ", else: "  ") <> title
      end)

    rows =
      leaders.board
      |> Enum.with_index(1)
      |> Enum.map(fn {entry, rank} ->
        label(
          "#{String.pad_leading(Integer.to_string(rank), 2)}  #{String.pad_trailing(String.slice(entry.name, 0, 18), 18)} #{String.pad_leading(Ledger.value(entry.value, leaders.metric), 9)}   #{entry.rounds} rounds  #{Ledger.value(entry.values[:kills] || 0, :kills)} kills  #{Ledger.value(entry.values[:wins] || 0, :wins)} won",
          style: if(rank == 1, do: %{fg: :green}, else: %{})
        )
      end)

    vertical(
      [
        label("Leaders", style: %{bold: true}),
        label(periods, style: @cyan),
        label(metrics, style: @amber),
        label("")
      ] ++
        if(rows == [], do: [label("nobody yet — fly a round", style: @dim)], else: rows) ++
        [
          label(""),
          label("←→  period     Tab  metric     Esc  title", style: @dim),
          label(state.status, style: @amber)
        ],
      gap: 0
    )
  end

  defp found_items do
    case Beacon.Listener.found() do
      [] ->
        [label("No server is calling on this network.", style: @dim), label("")]

      found ->
        [label("Calling on this network", style: @cyan)] ++
          Enum.map(Enum.with_index(found), fn {server, i} ->
            horizontal(
              [
                button("use", id: :"use_#{i}", on_click: {:use, server}, compact: true, width: 7),
                label("#{server.host}   #{server.http || "no web"}   #{server.node || "no node"}")
              ],
              gap: 1
            )
          end) ++ [label("")]
    end
  end

  @impl true
  def handle_event(name, data, %{screen: :client, client: client} = state),
    do: name |> Client.handle_event(data, client) |> after_client(state)

  def handle_event(:login, _data, state), do: {:ok, login(state, false)}
  def handle_event(:register, _data, state), do: {:ok, login(state, true)}
  def handle_event(:connect_node, _data, state), do: {:ok, connect_node(state)}
  def handle_event(:serve, _data, state), do: {:ok, toggle_serve(state)}

  def handle_event({:use, server}, _data, state),
    do:
      {:ok,
       %{
         state
         | url: server.http || state.url,
           node: if(server.node, do: Atom.to_string(server.node), else: state.node),
           status: "Filled in from #{server.host}."
       }}

  def handle_event(_name, _data, state), do: {:noreply, state}

  @impl true
  def handle_event(event, %{screen: :client, client: client} = state),
    do: event |> Client.handle_event(client) |> after_client(state)

  def handle_event({:key, :q, [:ctrl]}, _state), do: {:stop, :normal}
  def handle_event({:key, :c, [:ctrl]}, _state), do: {:stop, :normal}

  def handle_event({:key, key}, %{screen: :title} = state) do
    case key do
      :enter -> {:ok, play(state)}
      :c -> {:ok, %{state | screen: :connect, status: ""}}
      :l -> {:ok, to_leaders(state)}
      :h -> {:ok, %{state | screen: :host, status: ""}}
      k when k in [:q, :escape] -> {:stop, :normal}
      _ -> {:noreply, state}
    end
  end

  def handle_event({:key, :escape}, %{screen: screen} = state)
      when screen in [:connect, :host, :leaders] do
    Enum.each(
      [
        :url,
        :username,
        :password,
        :node,
        :cookie,
        :ssh_port,
        :web_port,
        :interfaces,
        :accounts,
        :robots
      ],
      &Drafter.blur/1
    )

    {:ok, %{state | screen: :title}}
  end

  def handle_event({:key, :left}, %{screen: :leaders} = state),
    do:
      {:ok,
       state
       |> put_in([:leaders, :period], step(Screens.periods(), state.leaders.period, -1))
       |> load_leaders()}

  def handle_event({:key, :right}, %{screen: :leaders} = state),
    do:
      {:ok,
       state
       |> put_in([:leaders, :period], step(Screens.periods(), state.leaders.period, 1))
       |> load_leaders()}

  def handle_event({:key, :tab}, %{screen: :leaders} = state),
    do:
      {:ok,
       state
       |> put_in([:leaders, :metric], step(Screens.metrics(), state.leaders.metric, 1))
       |> load_leaders()}

  def handle_event(_event, state), do: {:noreply, state}

  @impl true
  def on_message(message, %{screen: :client, client: client} = state),
    do: %{state | client: Client.on_message(message, client)}

  def on_message(_message, state), do: state

  defp after_client({:stop, _reason}, state) do
    Client.unmount(state.client)
    {:ok, %{state | client: nil, screen: :title, status: ""}}
  end

  defp after_client({tag, client}, state) when tag in [:ok, :noreply],
    do: {tag, %{state | client: client}}

  defp play(state) do
    props =
      Map.merge(state.props, %{
        game: ExPilot.Client,
        username: state.username,
        start: :lobby,
        source: state.source
      })

    client = props |> Client.mount() |> Client.on_ready()
    %{state | screen: :client, client: client}
  end

  defp login(state, register?) do
    case Remote.login(state.url <> "/api", state.username, state.password, register?) do
      {:ok, token} ->
        play(%{
          state
          | source: {:url, state.url, token},
            status: "Logged in as #{state.username}."
        })

      {:error, message} ->
        %{state | status: message}
    end
  end

  defp connect_node(state) do
    node = String.to_atom(state.node)
    unless Node.alive?(), do: start_distribution()
    if state.cookie != "", do: Node.set_cookie(String.to_atom(state.cookie))

    if Node.connect(node),
      do: play(%{state | source: {:node, node}, status: "Connected to #{node}."}),
      else: %{
        state
        | status: "Could not connect to #{node}: is it running with that name and cookie?"
      }
  end

  defp start_distribution do
    System.cmd("epmd", ["-daemon"])
    {:ok, host} = :inet.gethostname()
    Node.start(:"expilot_terminal_#{System.pid()}@#{host}", :shortnames)
  end

  defp toggle_serve(%{server: nil} = state) do
    opts = [
      port: integer(state.ssh_port, 2222),
      http: integer(state.web_port, Server.default_http()),
      ip: ip_option(state.interfaces),
      accounts: state.accounts
    ]

    opts =
      case integer(state.robots, nil),
        do: (
          nil -> opts
          robots -> [{:robots, robots} | opts]
        )

    case Server.start(opts) do
      {:ok, server} ->
        %{state | server: server, serve_lines: splash(opts[:port], server), status: ""}

      {:error, reason} ->
        %{state | status: "Could not start: #{inspect(reason)}"}
    end
  end

  defp toggle_serve(state) do
    Server.stop(state.server)
    %{state | server: nil, serve_lines: [], status: "Stopped."}
  end

  defp splash(port, %{arenas: arenas, http: http} = server) do
    host = Server.hostname()

    [
      "Serving #{length(arenas)} arenas.",
      "in a browser:  http://#{host}:#{http}/",
      "register:      ssh -p #{port} new@#{host}",
      "play:          ssh -p #{port} <name>@#{host}"
    ] ++
      node_lines(Map.get(server, :node))
  end

  defp node_lines(nil), do: []

  defp node_lines(node),
    do: [
      "as a node:     #{node}   cookie #{Node.get_cookie()}",
      "calling on this network every two seconds"
    ]

  defp to_leaders(state), do: %{state | screen: :leaders, status: ""} |> load_leaders()

  defp load_leaders(%{leaders: %{period: period, metric: metric}} = state) do
    case leaders(state.source, period, metric) do
      {:ok, board} -> put_in(state, [:leaders, :board], board)
      {:error, message} -> state |> put_in([:leaders, :board], []) |> Map.put(:status, message)
    end
  end

  defp leaders({:url, url, _token}, period, metric),
    do: Remote.leaders(url <> "/api", period, metric)

  defp leaders({:node, node}, period, metric),
    do: Remote.node_leaders(node, Ledger, period, metric)

  defp leaders(:local, period, metric), do: {:ok, Ledger.board(period, metric)}

  defp step(choices, current, delta) do
    keys = Keyword.keys(choices)
    index = Enum.find_index(keys, &(&1 == current)) || 0
    Enum.at(keys, Integer.mod(index + delta, length(keys)))
  end

  defp where(:local), do: "playing here: the arenas this program carries"
  defp where({:url, url, _}), do: "connected to #{url}"
  defp where({:node, node}), do: "connected to #{node}"

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
end
