defmodule ExPilot.Client do
  @moduledoc """
  What `Cauldron2D.Drafter.Client` needs from ExPilot: the title, the keys, the arenas,
  how a view is drawn, and the sound and music.

      Drafter.run(Cauldron2D.Drafter.Client, props: %{game: ExPilot.Client})
  """

  @behaviour Cauldron2D.Drafter.Client.Game

  import Drafter.App

  alias ExPilot.{Arenas, Art, Game, Map, Music, Ship, Sound}

  @impl true
  def title, do: %{name: "EXPILOT", tagline: "an XPilot for the terminal, over ssh", art: nil}

  @impl true
  def atlas, do: Art.install()

  @impl true
  def actions, do: [:turn_left, :turn_right, :thrust, :fire, :shield]

  @impl true
  def keymaps do
    %{
      wasd: %{turn_left: [:a], turn_right: [:d], thrust: [:s, {:mouse, :right}], fire: [:" ", :f, {:mouse, :left}], shield: [:left_shift, :w]},
      arrows: %{turn_left: [:left], turn_right: [:right], thrust: [:up, {:mouse, :right}], fire: [:" ", :down, {:mouse, :left}], shield: [:left_shift, :s]},
      vi: %{turn_left: [:h], turn_right: [:l], thrust: [:k, {:mouse, :right}], fire: [:" ", :j, {:mouse, :left}], shield: [:left_shift, :i]}
    }
  end

  @impl true
  def toggles, do: [:thrust, :shield]

  @impl true
  def steering, do: [:turn_left, :turn_right]

  @impl true
  def outcome(view), do: Game.outcome(view)

  @impl true
  def arenas, do: Arenas.list()

  @impl true
  def scene(view) do
    arena = Arenas.map(view.arena)

    %{
      focus: view.focus,
      bounds: if(view.wrap?, do: :unbounded, else: view.bounds),
      cell: cell_fun(arena),
      movers: ship_movers(view.ships) ++ shot_movers(view.shots) ++ view.particles
    }
  end

  defp cell_fun(nil), do: fn _ -> {:space, [], nil} end

  defp cell_fun(arena) do
    fn point ->
      case Map.art(arena, point) do
        nil -> {:space, [], nil}
        art -> {:space, [art], nil}
      end
    end
  end

  defp ship_movers(ships) do
    Enum.flat_map(ships, fn
      %{pos: {x, y}, heading: heading, team: team, alive?: true, shielding?: true} ->
        [{Art.ship(team, heading), {x - 0.5, y - 0.5}}, {:shield, {x - 0.5, y - 0.5}}]

      %{pos: {x, y}, heading: heading, team: team, alive?: true} ->
        [{Art.ship(team, heading), {x - 0.5, y - 0.5}}]

      _dead ->
        []
    end)
  end

  defp shot_movers(shots), do: for({x, y} <- shots, do: {:shot, {x - 0.5, y - 0.5}})

  @impl true
  def hud(%{me: nil} = view) do
    [[label("watching", style: %{bold: true}), label(view.arena)], scores_row(view)]
  end

  def hud(%{me: me} = view) do
    [
      [
        label(me.name, style: %{bold: true}),
        label("fuel " <> fuel_bar(me.fuel), style: fuel_style(me.fuel)),
        label("score #{me.score}"),
        label("kills #{me.kills}"),
        label("deaths #{me.deaths}"),
        label(lives_text(me.lives)),
        label("enemies " <> Integer.to_string(view.enemies)),
        label(status_text(me, view.watching), style: %{fg: :cyan})
      ],
      scores_row(view)
    ]
  end

  defp fuel_bar(fuel) do
    filled = round(fuel / Ship.max_fuel() * 20)
    String.duplicate("█", filled) <> String.duplicate("░", 20 - filled)
  end

  defp fuel_style(fuel) when fuel < 150, do: %{fg: :red}
  defp fuel_style(_fuel), do: %{fg: :yellow}

  defp lives_text(:unlimited), do: "lives ∞"
  defp lives_text(lives), do: "lives #{lives}"

  defp status_text(%{alive?: false, lives: 0}, watching) when is_binary(watching), do: "out — watching " <> watching
  defp status_text(%{alive?: false, lives: 0}, _watching), do: "out"
  defp status_text(%{alive?: false, respawn_in: t}, _watching), do: "respawning in #{Float.round(t / 1, 1)}"
  defp status_text(%{landed?: true}, _watching), do: "on base — thrust to launch"
  defp status_text(%{shielding?: true}, _watching), do: "shield up"
  defp status_text(%{thrusting?: true}, _watching), do: "thrusting"
  defp status_text(_me, _watching), do: ""

  defp scores_row(view) do
    [label("scores", style: %{bold: true}) | Enum.map(view.scores, &label("#{&1.name} #{&1.score}"))]
  end

  @impl true
  def listener(%{focus: focus}), do: focus

  @impl true
  def sounds, do: &Sound.voice/1

  @impl true
  def music, do: Music.pieces()

  @impl true
  def cue(view, screen), do: Music.cue(view, screen)
end
