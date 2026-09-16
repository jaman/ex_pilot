defmodule ExPilot.Client do
  @moduledoc """
  What `Cauldron2D.Drafter.Client` needs from ExPilot: the title, the keys, the arenas,
  how a view is drawn, and the sound and music.

  A player's own shipshape, in XPilot's notation, is read from
  `$XDG_CONFIG_HOME/expilot/<player>.shipshape` when they join an arena; every ship is
  drawn with its own shape, the default where a player has none.

      Drafter.run(Cauldron2D.Drafter.Client, props: %{game: ExPilot.Client})
  """

  @behaviour Cauldron2D.Drafter.Client.Game

  import Drafter.App

  alias ExPilot.{Arenas, Art, Game, Gear, Guide, Map, Music, Radar, Sound}

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
  def actions, do: [:turn_left, :turn_right, :thrust, :fire, :shield, :next_watch] ++ Gear.actions()

  @impl true
  def keymaps do
    %{
      wasd: Elixir.Map.merge(@item_keys, %{turn_left: [:a], turn_right: [:d], thrust: [:s, {:mouse, :right}], fire: [:" ", :f, {:mouse, :left}], shield: [:left_shift, :w]}),
      arrows: Elixir.Map.merge(@item_keys, %{turn_left: [:left], turn_right: [:right], thrust: [:up, {:mouse, :right}], fire: [:" ", :down, {:mouse, :left}], shield: [:left_shift, :s]}),
      vi: Elixir.Map.merge(@item_keys, %{turn_left: [:h], turn_right: [:l], thrust: [:k, {:mouse, :right}], fire: [:" ", :j, {:mouse, :left}], shield: [:left_shift, :i]})
    }
  end

  @impl true
  def toggles, do: []

  @impl true
  def holds, do: [thrust: 450, shield: 450]

  @impl true
  def steering, do: [:turn_left, :turn_right]

  @impl true
  def outcome(view), do: Game.outcome(view)

  @impl true
  def join_props(%{username: username}) do
    base = System.get_env("XDG_CONFIG_HOME") || Path.join(System.user_home!(), ".config")

    case File.read(Path.join([base, "expilot", username <> ".shipshape"])) do
      {:ok, shape} -> %{shape: String.trim(shape)}
      {:error, _} -> %{}
    end
  end

  @impl true
  def arenas, do: Arenas.list()

  @impl true
  def guide, do: Guide.sections()

  @impl true
  def scene(view) do
    arena = Arenas.map(view.arena)

    %{
      focus: view.focus,
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
          view.particles
    }
  end

  defp cell_fun(nil, _gone), do: fn _ -> {:space, [], nil} end

  defp cell_fun(arena, gone) do
    fn point ->
      case Map.art(arena, point) do
        nil -> {:space, [], nil}
        :target -> {:space, [if(MapSet.member?(gone, point), do: :target_gone, else: :target)], nil}
        art -> {:space, [art], nil}
      end
    end
  end

  defp item_movers(items), do: for({kind, {x, y}} <- items, do: {Art.item(kind), {x - 0.5, y - 0.5}})
  defp ball_movers(balls) do
    Enum.flat_map(balls, fn
      %{pos: {x, y}, string: nil} -> [{:ball, {x - 0.5, y - 0.5}}]
      %{pos: {x, y}, string: {sx, sy}} -> string_movers({sx, sy}, {x, y}) ++ [{:ball, {x - 0.5, y - 0.5}}]
    end)
  end

  defp string_movers({fx, fy}, {tx, ty}) do
    steps = max(1, round(:math.sqrt((tx - fx) * (tx - fx) + (ty - fy) * (ty - fy)) * 2))
    for i <- 1..(steps - 1)//1, do: {:string, {fx + (tx - fx) * i / steps - 0.5, fy + (ty - fy) * i / steps - 0.5}}
  end
  defp mine_movers(mines), do: for({x, y} <- mines, do: {:mine, {x - 0.5, y - 0.5}})
  defp missile_movers(missiles), do: for({kind, {x, y}, _vel} <- missiles, do: {kind, {x - 0.5, y - 0.5}})

  defp beam_movers(beams) do
    Enum.flat_map(beams, fn {{fx, fy}, {tx, ty}} ->
      steps = max(1, round(:math.sqrt((tx - fx) * (tx - fx) + (ty - fy) * (ty - fy)) * 2))
      for i <- 0..steps, do: {:beam, {fx + (tx - fx) * i / steps - 0.5, fy + (ty - fy) * i / steps - 0.5}}
    end)
  end

  defp ship_movers(ships) do
    Enum.flat_map(ships, fn
      %{pos: {x, y}, heading: heading, team: team, alive?: true, shielding?: true} = ship ->
        [{Art.ship_shape(ship.shape, team, heading), {x - 0.5, y - 0.5}}, {:shield, {x - 0.5, y - 0.5}}]

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
  def hud(%{me: nil} = view) do
    %{
      left: radar_lines(view) ++ [label("watching", style: %{bold: true}), label(view.arena), label(watching_text(view.watching), style: %{fg: :cyan}), label("") | scores_lines(view)],
      width: @column_width,
      bottom: message_rows(view)
    }
  end

  def hud(%{me: me} = view) do
    %{
      left: radar_lines(view) ++ pilot_lines(me, view) ++ [label("") | inventory_lines(me)] ++ [label("") | scores_lines(view)],
      width: @column_width,
      bottom: message_rows(view)
    }
  end

  defp radar_lines(view) do
    {columns, rows} = @radar_size
    arena = Arenas.map(view.arena)
    radar = if arena, do: Radar.rows(arena, view, {columns, rows}), else: List.duplicate([{String.duplicate(" ", columns), {0, 0, 0}}], rows)

    Enum.map(radar, fn runs -> label(Enum.map(runs, fn {text, {r, g, b}} -> {text, %{fg: {r, g, b}}} end)) end)
  end

  defp pilot_lines(me, view) do
    [
      label(me.name, style: %{bold: true}),
      label("fuel " <> fuel_bar(me.fuel, me.max_fuel), style: fuel_style(me.fuel)),
      label("score #{me.score}  kills #{me.kills}  deaths #{me.deaths}"),
      label(lives_text(me.lives) <> "  enemies " <> Integer.to_string(view.enemies)),
      label(race_text(view.race)),
      label(status_text(me, view.watching), style: %{fg: :cyan})
    ]
  end

  defp inventory_lines(me) do
    carried = me.items |> Enum.sort() |> Enum.map(fn {kind, count} -> label("#{kind} #{count}") end)
    armour = if me.armour > 0, do: [label("armour #{me.armour}")], else: []
    missile = if Elixir.Map.has_key?(me.items, :missile), do: [label("missile: #{me.missile}", style: %{fg: :yellow})], else: []
    none = if carried == [] and armour == [], do: [label("none", style: %{fg: :bright_black})], else: []
    [label("items", style: %{bold: true}) | armour ++ missile ++ carried ++ none]
  end

  defp message_rows(view) do
    view.messages |> Enum.take(-3) |> Enum.map(fn {_at, text} -> [label(text, style: %{fg: :bright_black})] end)
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

  defp status_text(%{alive?: false, lives: 0}, watching) when is_binary(watching), do: "out — watching " <> watching <> "  (Enter: next)"
  defp status_text(%{alive?: false, lives: 0}, _watching), do: "out"
  defp status_text(%{alive?: false, respawn_in: t}, _watching), do: "respawning in #{Float.round(t / 1, 1)}"
  defp status_text(%{landed?: true}, _watching), do: "on base — thrust to launch"
  defp status_text(%{shielding?: true}, _watching), do: "shield up"
  defp status_text(%{thrusting?: true}, _watching), do: "thrusting"
  defp status_text(_me, _watching), do: ""

  defp scores_lines(%{team_scores: teams} = view) when map_size(teams) > 0 do
    team_labels = teams |> Enum.sort() |> Enum.map(fn {team, score} -> label("team #{team}: #{score}", style: %{bold: true}) end)
    [label("scores", style: %{bold: true}) | team_labels ++ score_lines(view)]
  end

  defp scores_lines(view), do: [label("scores", style: %{bold: true}) | score_lines(view)]

  defp score_lines(view), do: Enum.map(view.scores, &label(String.pad_trailing(&1.name, 20) <> Integer.to_string(&1.score)))

  @impl true
  def listener(%{focus: focus}), do: focus

  @impl true
  def sounds, do: &Sound.voice/1

  @impl true
  def music, do: Music.pieces()

  @impl true
  def cue(view, screen), do: Music.cue(view, screen)
end
