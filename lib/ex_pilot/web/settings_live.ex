defmodule ExPilot.Web.SettingsLive do
  @moduledoc "The sound levels, kept in the account and shared with the ssh client."

  use Phoenix.LiveView

  alias ExPilot.Web.Auth

  @impl true
  def mount(_params, _session, socket) do
    levels = Auth.levels(socket.assigns.username)
    {:ok, assign(socket, sfx: levels.sfx, music: levels.music, saved: false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1>Settings</h1>
    <p><a href="/lobby">← lobby</a></p>
    <form phx-change="change" phx-submit="save">
      <p><label>effects <input type="range" name="sfx" min="0" max="100" value={round(@sfx * 100)} /> {round(@sfx * 100)}%</label></p>
      <p><label>music <input type="range" name="music" min="0" max="100" value={round(@music * 100)} /> {round(@music * 100)}%</label></p>
      <p><button type="submit">save</button> <span :if={@saved} class="dim">saved</span></p>
    </form>
    <p class="dim">Keys in the browser: a/d or ←/→ turn, s/↑ or the right mouse button thrust, space or the left button fire, w/shift shield; the pointer steers. Sound plays in the page.</p>
    """
  end

  @impl true
  def handle_event("change", %{"sfx" => sfx, "music" => music}, socket) do
    {:noreply, assign(socket, sfx: String.to_integer(sfx) / 100, music: String.to_integer(music) / 100, saved: false)}
  end

  def handle_event("save", %{"sfx" => sfx, "music" => music}, socket) do
    sfx = String.to_integer(sfx) / 100
    music = String.to_integer(music) / 100
    Auth.put_levels(socket.assigns.username, sfx, music)
    {:noreply, assign(socket, sfx: sfx, music: music, saved: true)}
  end
end
