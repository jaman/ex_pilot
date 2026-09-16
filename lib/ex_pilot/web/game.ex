defmodule ExPilot.Web.Game do
  @moduledoc """
  ExPilot for `Cauldron2D.Web`: the arenas' worlds by id, the map, the movers and the
  hud as the browser draws them, over the same `ExPilot.Client` the ssh client uses.
  """

  @behaviour Cauldron2D.Web.Game

  alias ExPilot.{Arenas, Client}
  alias ExPilot.Map, as: Arena

  @colours %{
    cyan: {80, 220, 240},
    yellow: {255, 255, 0},
    red: {255, 80, 80},
    green: {80, 220, 100},
    white: {240, 240, 240},
    bright_black: {130, 130, 140}
  }

  @impl true
  def atlas, do: Client.atlas()

  @impl true
  def world(id) do
    case Enum.find(Arenas.list(), &(&1.name == id)) do
      nil -> nil
      arena -> arena.world
    end
  end

  @impl true
  def actions, do: Client.actions()

  @impl true
  def map(view) do
    arena = Arenas.map(view.arena)
    {width, height} = Arena.size(arena)
    %{width: width, height: height, wrap?: view.wrap?, cell: &Arena.art(arena, &1)}
  end

  @impl true
  def scene(view) do
    scene = Client.scene(view)
    gone = for {x, y} <- view.targets_gone, do: {:target_gone, {x, y}}
    %{focus: scene.focus, movers: scene.movers ++ gone}
  end

  @impl true
  def hud(view) do
    case Client.hud(view) do
      %{left: left, bottom: bottom} -> Enum.map(left, &row/1) ++ Enum.map(bottom, &row/1)
      rows -> Enum.map(rows, &row/1)
    end
  end

  @impl true
  def listener(view), do: Client.listener(view)

  @impl true
  def sounds, do: Client.sounds()

  @impl true
  def music, do: Client.music()

  @impl true
  def cue(view, screen), do: Client.cue(view, screen)

  @impl true
  def join_props(props), do: Client.join_props(props)

  @impl true
  def outcome(view), do: Client.outcome(view)

  defp row(elements) when is_list(elements), do: Enum.flat_map(elements, &runs/1)
  defp row(element), do: runs(element)

  defp runs({:label, runs, _opts}) when is_list(runs), do: for({text, style} <- runs, do: {text, colour(style)})
  defp runs({:label, text, opts}), do: [{text, colour(Keyword.get(opts, :style, %{}))}]
  defp runs({:layout, _, children, _}), do: Enum.flat_map(children, &runs/1)
  defp runs(_other), do: []

  defp colour(%{fg: {_, _, _} = rgb}), do: rgb
  defp colour(%{fg: name}) when is_atom(name), do: Map.get(@colours, name)
  defp colour(_style), do: nil
end
