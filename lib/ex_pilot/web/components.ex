defmodule ExPilot.Web.Components do
  @moduledoc """
  The pieces ExPilot's pages share: the shell with its top bar (a tab bar along the
  bottom on a phone or a tablet, where the top bar is hidden), the badge naming an
  arena's kind, and a sprite cut from the sheet.
  """

  use Phoenix.Component

  alias Cauldron2D.Net.Sheet
  alias ExPilot.Art

  @sprite_scale 3

  attr(:username, :string, required: true)
  attr(:current, :string, required: true)
  attr(:wide, :boolean, default: false)
  slot(:inner_block, required: true)

  @doc "The top bar — wordmark, the pages, the pilot — over a page of content."
  def shell(assigns) do
    ~H"""
    <header class="topbar">
      <a class="wordmark" href="/lobby">EXPILOT</a>
      <nav>
        <a href="/lobby" class={@current == "lobby" && "current"}>arenas</a>
        <a href="/leaders" class={@current == "leaders" && "current"}>leaders</a>
        <a href="/guide" class={@current == "guide" && "current"}>guide</a>
        <a href="/settings" class={@current == "settings" && "current"}>settings</a>
      </nav>
      <div class="pilot"><span class="dot"></span> <b>{@username}</b> <a href="/logout" class="faint">log out</a></div>
    </header>
    <main class={["page", @wide && "page-wide"]}>{render_slot(@inner_block)}</main>
    <nav class="tabbar">
      <a href="/lobby" class={@current == "lobby" && "current"}><span class="glyph">▲</span>arenas</a>
      <a href="/leaders" class={@current == "leaders" && "current"}><span class="glyph">★</span>leaders</a>
      <a href="/guide" class={@current == "guide" && "current"}><span class="glyph">?</span>guide</a>
      <a href="/settings" class={@current == "settings" && "current"}><span class="glyph">⚙</span>settings</a>
      <a href="/logout"><span class="glyph">⏻</span>{@username}</a>
    </nav>
    """
  end

  attr(:mode, :atom, required: true)

  @doc "The kind of arena, as a badge."
  def mode_badge(assigns) do
    ~H"""
    <span class={"badge badge-#{@mode}"}>{mode_name(@mode)}</span>
    """
  end

  @doc "A kind of arena in words."
  @spec mode_name(atom()) :: String.t()
  def mode_name(mode), do: ExPilot.Mode.name(mode)

  attr(:art, :any, required: true)

  @doc "One art of the atlas, cut from the sheet and drawn three times its size."
  def sprite(assigns) do
    ~H"""
    <span class="sprite-box"><span class="sprite" style={sprite_style(@art)}></span></span>
    """
  end

  @doc "The inline style that shows `art` from `/atlas.png`."
  @spec sprite_style(term()) :: String.t()
  def sprite_style(art) do
    sheet = Sheet.cached(Art.name())
    index = Map.get(sheet.arts, art, 0)
    [x, y] = Enum.at(sheet.frames, index)
    {width, height} = Sheet.dimensions(sheet)
    scale = @sprite_scale

    "background-position: -#{x * scale}px -#{y * scale}px; background-size: #{width * scale}px #{height * scale}px; width: #{sheet.tile * scale}px; height: #{sheet.tile * scale}px"
  end
end
