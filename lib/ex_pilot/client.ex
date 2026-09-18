defmodule ExPilot.Client do
  @moduledoc """
  What every client — the terminal's, the browser's, the desktop's — needs from ExPilot,
  as `Cauldron2D.Client.Game` asks for it: the title, the keys, the arenas, how a view
  is drawn, and the sound and music.

  A player's own shipshape, in XPilot's notation, is read from
  `$XDG_CONFIG_HOME/expilot/<player>.shipshape` when they join an arena; every ship is
  drawn with its own shape, the default where a player has none.

      Drafter.run(Cauldron2D.Drafter.Client, props: %{game: ExPilot.Client})

  The arenas come from the prop `:source`: `:local` (the default), the arenas this VM
  runs; `{:node, node}`, a connected node's, joined across the connection; `{:url,
  url, token}`, a server's over its WebSocket through `Cauldron2D.Net.Link.World`, whose
  views are the wire's frames — drawn here from the local atlas, their hud as the
  server wrote it, with no music of their own. A browser's join params `team` and
  `spectate` become the join props.
  """

  @behaviour Cauldron2D.Client.Game

  alias Cauldron2D.Net.Link
  alias Cauldron2D.Net.Remote
  alias ExPilot.{Arenas, Art, Game, Gear, Guide, Map, Mode, Music, Radar, Sound}
  alias ExPilot.Client.{LeadersPage, SoundPage}

  @colours %{
    cyan: {80, 220, 240},
    yellow: {255, 255, 0},
    red: {255, 80, 80},
    green: {80, 220, 100},
    white: {240, 240, 240},
    dim: {130, 130, 140}
  }

  @impl true
  def title, do: %{name: "EXPILOT", tagline: "an XPilot for the terminal, over ssh", art: nil}

  @impl true
  def atlas, do: Art.install()

  @item_keys %{
    fire_missile: [:"2"],
    next_missile: [:n],
    drop_mine: [:"1"],
    fire_laser: [:"3"],
    cloak: [:c],
    ecm: [:e],
    transporter: [:r],
    tractor: [:g],
    pressor: [:b],
    deflector: [:x],
    phasing: [:p],
    hyperjump: [:u],
    emergency_shield: [:"["],
    emergency_thrust: [:"]"],
    autopilot: [:o],
    connector: [:v],
    next_watch: [:enter]
  }

  @impl true
  def actions,
    do: [:turn_left, :turn_right, :thrust, :fire, :shield, :next_watch] ++ Gear.actions()

  @impl true
  def keymaps do
    [
      wasd:
        Elixir.Map.merge(@item_keys, %{
          turn_left: [:a],
          turn_right: [:d],
          thrust: [:s, {:mouse, :right}],
          fire: [:" ", :f, {:mouse, :left}],
          shield: [:left_shift, :w]
        }),
      arrows:
        Elixir.Map.merge(@item_keys, %{
          turn_left: [:left],
          turn_right: [:right],
          thrust: [:up, {:mouse, :right}],
          fire: [:" ", :down, {:mouse, :left}],
          shield: [:left_shift, :s]
        }),
      vi:
        Elixir.Map.merge(@item_keys, %{
          turn_left: [:h],
          turn_right: [:l],
          thrust: [:k, {:mouse, :right}],
          fire: [:" ", :j, {:mouse, :left}],
          shield: [:left_shift, :i]
        })
    ]
  end

  @impl true
  def toggles, do: []

  @impl true
  def holds, do: [thrust: 450, shield: 450]

  @impl true
  def steering, do: [:turn_left, :turn_right]

  @impl true
  def outcome(%{wire: _} = view), do: Link.World.outcome(view)
  def outcome(view), do: Game.outcome(view)

  @impl true
  def join_props(%{username: username} = props) do
    base = System.get_env("XDG_CONFIG_HOME") || Path.join(System.user_home!(), ".config")

    shape =
      case File.read(Path.join([base, "expilot", username <> ".shipshape"])) do
        {:ok, shape} -> %{shape: String.trim(shape)}
        {:error, _} -> %{}
      end

    shape
    |> Elixir.Map.merge(nickname_prop(username))
    |> Elixir.Map.merge(param_props(Elixir.Map.get(props, :params, %{})))
  end

  defp param_props(params) do
    spectate =
      if Elixir.Map.get(params, "spectate") in [true, "1", "true"],
        do: %{spectate: true},
        else: %{}

    case Elixir.Map.get(params, "team") do
      nil -> spectate
      team -> Elixir.Map.put(spectate, :team, team)
    end
  end

  defp nickname_prop(username) do
    case Process.whereis(ExPilot.Accounts) && Drafter.Accounts.fetch(ExPilot.Accounts, username) do
      {:ok, %{props: %{nickname: nickname}}} when is_binary(nickname) and nickname != "" ->
        %{username: nickname}

      _ ->
        %{}
    end
  end

  @impl true
  def arenas(%{source: {:node, node}}) do
    case Remote.node_arenas(node) do
      {:ok, arenas} ->
        for %{map: name} <- arenas,
            arena = :rpc.call(node, Arenas, :map, [name]),
            match?(%Map{}, arena),
            do: Arenas.adopt(name, arena)

        for arena <- arenas, do: %{arena | world: {:via, Remote.Worlds, {:node, node, arena.id}}}

      {:error, _reason} ->
        []
    end
  end

  def arenas(%{source: {:url, url, token}}) do
    case Remote.arenas(url <> "/api") do
      {:ok, arenas} ->
        for arena <- arenas,
            do:
              remote_arena(
                arena,
                {:via, Remote.Worlds, {:url, url, token, arena.id, [topic: "arena"]}}
              )

      {:error, _reason} ->
        []
    end
  end

  def arenas(_local), do: Arenas.list()

  defp remote_arena(arena, world),
    do: Elixir.Map.merge(arena, %{world: world, kind: arena.kind || Mode.kind(:dogfight)})

  @impl true
  def map(view) do
    arena = Arenas.map(view.arena)
    {width, height} = Map.size(arena)
    %{width: width, height: height, wrap?: view.wrap?, cell: &Map.art(arena, &1)}
  end

  @impl true
  def sink(%{pulse_port: port}) when is_integer(port),
    do: {TuningFork.Sink.Tcp, host: "127.0.0.1", port: port, warm_up_ms: 300}

  def sink(%{served_by: %{}}), do: TuningFork.Sink.Silent

  def sink(_props),
    do:
      if(Code.ensure_loaded?(TuningFork.Sink.Speaker),
        do: TuningFork.Sink.Speaker,
        else: TuningFork.Sink.Silent
      )

  @impl true
  def pages(props), do: [LeadersPage.page() | SoundPage.pages(props)]

  @impl true
  def client_keys, do: %{fps: :m}

  @impl true
  def home, do: :expilot

  @impl true
  def refusal_text(:full), do: "no base is free"
  def refusal_text(:already_joined), do: "you are already in it"
  def refusal_text(:not_invited), do: "this duel is not yours — you can watch it"
  def refusal_text(reason), do: inspect(reason)

  @impl true
  def player_label({:robot, n}), do: "Robot #{n}"
  def player_label(id) when is_binary(id), do: id
  def player_label(id), do: inspect(id)

  @impl true
  def guide, do: Guide.sections()

  @impl true
  def scene(%{wire: _} = view), do: Link.World.scene(view, :ex_pilot)

  def scene(view) do
    arena = Arenas.map(view.arena)
    gone = for {x, y} <- view.targets_gone, do: {:target_gone, {x, y}}

    %{
      focus: view.focus,
      subject: view.watching || (view.me && view.me.id) || :free,
      bounds: if(view.wrap?, do: :unbounded, else: view.bounds),
      cell: cell_fun(arena, view.targets_gone),
      movers:
        item_movers(view.items) ++
          ball_movers(view.balls) ++
          mine_movers(view.mines) ++
          ship_movers(view.ships) ++
          shot_movers(view.shots) ++
          missile_movers(view.missiles) ++
          beam_movers(view.beams) ++
          view.particles ++ gone
    }
  end

  defp cell_fun(nil, _gone), do: fn _ -> {:space, [], nil} end

  defp cell_fun(arena, gone) do
    fn point ->
      case Map.art(arena, point) do
        nil ->
          {:space, [], nil}

        :target ->
          {:space, [if(MapSet.member?(gone, point), do: :target_gone, else: :target)], nil}

        art ->
          {:space, [art], nil}
      end
    end
  end

  defp item_movers(items),
    do: for({kind, {x, y}} <- items, do: {Art.item(kind), {x - 0.5, y - 0.5}})

  defp ball_movers(balls) do
    Enum.flat_map(balls, fn
      %{pos: {x, y}, string: nil} ->
        [{:ball, {x - 0.5, y - 0.5}}]

      %{pos: {x, y}, string: {sx, sy}} ->
        string_movers({sx, sy}, {x, y}) ++ [{:ball, {x - 0.5, y - 0.5}}]
    end)
  end

  defp string_movers({fx, fy}, {tx, ty}) do
    steps = max(1, round(:math.sqrt((tx - fx) * (tx - fx) + (ty - fy) * (ty - fy)) * 2))

    for i <- 1..(steps - 1)//1,
        do: {:string, {fx + (tx - fx) * i / steps - 0.5, fy + (ty - fy) * i / steps - 0.5}}
  end

  defp mine_movers(mines), do: for({x, y} <- mines, do: {:mine, {x - 0.5, y - 0.5}})

  defp missile_movers(missiles),
    do: for({kind, {x, y}, _vel} <- missiles, do: {kind, {x - 0.5, y - 0.5}})

  defp beam_movers(beams) do
    Enum.flat_map(beams, fn {{fx, fy}, {tx, ty}} ->
      steps = max(1, round(:math.sqrt((tx - fx) * (tx - fx) + (ty - fy) * (ty - fy)) * 2))

      for i <- 0..steps,
          do: {:beam, {fx + (tx - fx) * i / steps - 0.5, fy + (ty - fy) * i / steps - 0.5}}
    end)
  end

  defp ship_movers(ships) do
    Enum.flat_map(ships, fn
      %{pos: {x, y}, heading: heading, team: team, alive?: true, shielding?: true} = ship ->
        [
          {Art.ship_shape(ship.shape, team, heading), {x - 0.5, y - 0.5}},
          {:shield, {x - 0.5, y - 0.5}}
        ]

      %{pos: {x, y}, heading: heading, team: team, alive?: true} = ship ->
        [{Art.ship_shape(ship.shape, team, heading), {x - 0.5, y - 0.5}}]

      _dead ->
        []
    end)
  end

  defp shot_movers(shots), do: for({x, y} <- shots, do: {:shot, {x - 0.5, y - 0.5}})

  @radar_size {30, 12}
  @column_width 30

  @impl true
  def hud(%{wire: _} = view), do: %{left: Link.World.hud(view), width: @column_width, bottom: []}

  def hud(view) do
    parts = hud_parts(view)
    column = for {tag, lines} <- parts, tag != :messages, line <- lines, do: {tag, line}

    %{
      left: column,
      width: @column_width,
      bottom:
        Enum.flat_map(parts, fn
          {:messages, rows} -> rows
          _ -> []
        end)
    }
  end

  @doc """
  The hud's parts in order, each tagged: `:radar` (12 rows), then for a pilot `:name`,
  `:fuel`, `:score`, `:lives`, `:race`, `:status`, a blank, `:items` (a heading and a
  row an item), a blank and `:scores`; for a watcher `:watching` in place of the pilot
  rows; and last `:messages`, the latest three, each a row of elements.
  """
  @spec hud_parts(map()) :: [{atom(), [term()]}]
  def hud_parts(%{me: nil} = view) do
    [
      {:radar, radar_lines(view)},
      {:watching,
       [
         label("watching", style: %{bold: true}),
         label(view.arena),
         label(watching_text(view.watching), style: %{fg: :cyan})
       ]},
      {:blank, [label("")]},
      {:scores, scores_lines(view)},
      {:messages, message_rows(view)}
    ]
  end

  def hud_parts(%{me: me} = view) do
    [{:radar, radar_lines(view)}] ++
      pilot_lines(me, view) ++
      [
        {:blank, [label("")]},
        {:items, inventory_lines(me)},
        {:blank, [label("")]},
        {:scores, scores_lines(view)},
        {:messages, message_rows(view)}
      ]
  end

  defp radar_lines(view) do
    {columns, rows} = @radar_size
    arena = Arenas.map(view.arena)

    if arena,
      do: Radar.rows(arena, view, {columns, rows}),
      else: List.duplicate([{String.duplicate(" ", columns), {0, 0, 0}}], rows)
  end

  defp label(text, opts \\ []) do
    style = Keyword.get(opts, :style, %{})
    fg = Elixir.Map.get(style, :fg)

    style =
      if is_atom(fg) and fg != nil,
        do: %{style | fg: Elixir.Map.get(@colours, fg, @colours.white)},
        else: style

    [{text, style}]
  end

  defp pilot_lines(me, view) do
    [
      name: [label(me.name, style: %{bold: true})],
      fuel: [label("fuel " <> fuel_bar(me.fuel, me.max_fuel), style: fuel_style(me.fuel))],
      score: [label("score #{me.score}  kills #{me.kills}  deaths #{me.deaths}")],
      lives: [label(lives_text(me.lives) <> "  enemies " <> Integer.to_string(view.enemies))],
      race: [label(race_text(view.race))],
      status: [label(status_text(me, view.watching), style: %{fg: :cyan})]
    ]
  end

  defp inventory_lines(me) do
    carried =
      me.items |> Enum.sort() |> Enum.map(fn {kind, count} -> label("#{kind} #{count}") end)

    armour = if me.armour > 0, do: [label("armour #{me.armour}")], else: []

    missile =
      if Elixir.Map.has_key?(me.items, :missile),
        do: [label("missile: #{me.missile}", style: %{fg: :yellow})],
        else: []

    none = if carried == [] and armour == [], do: [label("none", style: %{fg: :dim})], else: []
    [label("items", style: %{bold: true}) | armour ++ missile ++ carried ++ none]
  end

  defp message_rows(view) do
    view.messages
    |> Enum.take(-3)
    |> Enum.map(fn {_at, text} -> label(text, style: %{fg: :dim}) end)
  end

  defp watching_text(nil), do: "Enter: follow a ship"
  defp watching_text(name), do: name <> "  (Enter: next)"

  defp race_text(nil), do: ""
  defp race_text(%{finished?: true}), do: "finished"
  defp race_text(%{lap: lap, laps: laps, next: next}), do: "lap #{lap}/#{laps} → #{<<?A + next>>}"

  defp fuel_bar(fuel, max_fuel) do
    filled = fuel |> Kernel./(max(max_fuel, 1.0)) |> Kernel.*(20) |> round() |> min(20) |> max(0)
    String.duplicate("█", filled) <> String.duplicate("░", 20 - filled)
  end

  defp fuel_style(fuel) when fuel < 150, do: %{fg: :red}
  defp fuel_style(_fuel), do: %{fg: :yellow}

  defp lives_text(:unlimited), do: "lives ∞"
  defp lives_text(lives), do: "lives #{lives}"

  defp status_text(%{alive?: false, lives: 0}, watching) when is_binary(watching),
    do: "out — watching " <> watching <> "  (Enter: next)"

  defp status_text(%{alive?: false, lives: 0}, _watching), do: "out"

  defp status_text(%{alive?: false, respawn_in: t}, _watching),
    do: "respawning in #{Float.round(t / 1, 1)}"

  defp status_text(%{landed?: true}, _watching), do: "on base — thrust to launch"
  defp status_text(%{shielding?: true}, _watching), do: "shield up"
  defp status_text(%{thrusting?: true}, _watching), do: "thrusting"
  defp status_text(_me, _watching), do: ""

  defp scores_lines(%{team_scores: teams} = view) when map_size(teams) > 0 do
    team_labels =
      teams
      |> Enum.sort()
      |> Enum.map(fn {team, score} -> label("team #{team}: #{score}", style: %{bold: true}) end)

    [label("scores", style: %{bold: true}) | team_labels ++ score_lines(view)]
  end

  defp scores_lines(view), do: [label("scores", style: %{bold: true}) | score_lines(view)]

  defp score_lines(view),
    do:
      Enum.map(
        view.scores,
        &label(String.pad_trailing(&1.name, 20) <> Integer.to_string(&1.score))
      )

  @impl true
  def listener(%{wire: _}), do: nil
  def listener(%{focus: focus}), do: focus

  @impl true
  def sounds, do: &Sound.voice/1

  @impl true
  def music, do: Music.pieces()

  @impl true
  def cue(%{wire: _}, _screen), do: nil
  def cue(view, screen), do: Music.cue(view, screen)
end
