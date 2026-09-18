defmodule ExPilot.Web.SettingsLive do
  @moduledoc """
  The sound levels of this kind of client — the browser, or a phone or tablet
  (`:touch`, told by the page) — kept in the account under their own key, and the
  nickname every client plays under.
  """

  use Phoenix.LiveView

  alias ExPilot.Web.Auth

  @impl true
  def mount(_params, _session, socket) do
    kind = if connected?(socket), do: Auth.kind(get_connect_params(socket)["kind"]), else: :web
    levels = Auth.levels(socket.assigns.username, kind)

    {:ok,
     assign(socket,
       kind: kind,
       sfx: levels.sfx,
       music: levels.music,
       nickname: nickname_of(socket.assigns.username),
       saved: false,
       notice: nil
     )}
  end

  defp nickname_of(username) do
    case Auth.nickname(username) do
      ^username -> ""
      nickname -> nickname
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1>Settings</h1>
    <p><a href="/lobby">← lobby</a></p>
    <form id="levels" phx-change="change" phx-submit="save">
      <p class="dim">Sound on {kind_name(@kind)}</p>
      <p><label>effects <input type="range" name="sfx" min="0" max="100" value={round(@sfx * 100)} /> {round(@sfx * 100)}%</label></p>
      <p><label>music <input type="range" name="music" min="0" max="100" value={round(@music * 100)} /> {round(@music * 100)}%</label></p>
      <p><button type="submit">save</button> <span :if={@saved} class="dim">saved</span></p>
    </form>
    <form id="nickname" phx-submit="nickname">
      <p><label>fly as <input type="text" name="nickname" value={@nickname} placeholder={@username} maxlength="24" /></label> <button type="submit">keep</button> <span :if={@notice} class="dim">{@notice}</span></p>
      <p class="dim">The name others see and the boards count, on every client; blank means {@username}.</p>
    </form>
    <p class="dim">Keys in the browser: a/d or ←/→ turn, s/↑ or the right mouse button thrust, space or the left button fire, w/shift shield; the pointer steers. Sound plays in the page.</p>
    """
  end

  defp kind_name(:touch), do: "this phone or tablet"
  defp kind_name(_web), do: "this browser"

  @impl true
  def handle_event("change", %{"sfx" => sfx, "music" => music}, socket) do
    {:noreply,
     assign(socket,
       sfx: String.to_integer(sfx) / 100,
       music: String.to_integer(music) / 100,
       saved: false
     )}
  end

  def handle_event("save", %{"sfx" => sfx, "music" => music}, socket) do
    sfx = String.to_integer(sfx) / 100
    music = String.to_integer(music) / 100
    Auth.put_levels(socket.assigns.username, sfx, music, socket.assigns.kind)
    {:noreply, assign(socket, sfx: sfx, music: music, saved: true)}
  end

  def handle_event("nickname", %{"nickname" => nickname}, socket) do
    case Auth.put_nickname(socket.assigns.username, nickname) do
      :ok -> {:noreply, assign(socket, nickname: String.trim(nickname), notice: "kept")}
      {:error, reason} -> {:noreply, assign(socket, notice: inspect(reason))}
    end
  end
end
