defmodule ExPilot.Web.SettingsLive do
  @moduledoc """
  The sound levels of this kind of client — the browser, or a phone or tablet
  (`:touch`, told by the page) — kept in the account under their own key, and the alias
  the account is seen under on every client.
  """

  use Phoenix.LiveView

  import ExPilot.Web.Components

  alias ExPilot.Alias
  alias ExPilot.Web.Auth

  @impl true
  def mount(_params, _session, socket) do
    kind = if connected?(socket), do: Auth.kind(get_connect_params(socket)["kind"]), else: :web
    levels = Auth.levels(socket.assigns.username, kind)

    {:ok,
     socket
     |> assign(kind: kind, sfx: levels.sfx, music: levels.music, saved: false, notice: nil)
     |> seen()}
  end

  defp seen(socket) do
    username = socket.assigns.username

    assign(socket,
      seen_as: Alias.of(username),
      chosen?: Alias.chosen?(username),
      anonymous: Alias.anonymous(username)
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.shell socket={@socket} username={@username} admin?={@admin?} seen_as={@seen_as} current="settings">
    <h1>Settings</h1>
    <form id="alias" phx-submit="alias">
      <p class="dim">You are <strong>{@username}</strong>. Others see you as <strong>{@seen_as}</strong><span :if={not @chosen?}> — an anonymous name of your own, the same every visit</span>.</p>
      <p><label>be seen as <input type="text" name="alias" value={if @chosen?, do: @seen_as, else: ""} placeholder={@anonymous} maxlength="32" /></label> <button type="submit">keep</button> <span :if={@notice} class="dim">{@notice}</span></p>
      <p class="dim">The name every client and the boards show for you; blank goes back to {@anonymous}. Only you and an admin see {@username}.</p>
    </form>
    <form id="levels" phx-change="change" phx-submit="save">
      <p class="dim">Sound on {kind_name(@kind)}</p>
      <p><label>effects <input type="range" name="sfx" min="0" max="100" value={round(@sfx * 100)} /> {round(@sfx * 100)}%</label></p>
      <p><label>music <input type="range" name="music" min="0" max="100" value={round(@music * 100)} /> {round(@music * 100)}%</label></p>
      <p><button type="submit">save</button> <span :if={@saved} class="dim">saved</span></p>
    </form>
    <p class="dim">Keys in the browser: a/d or ←/→ turn, s/↑ or the right mouse button thrust, space or the left button fire, w/shift shield; the pointer steers. Sound plays in the page.</p>
    </.shell>
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

  def handle_event("alias", %{"alias" => alias}, socket),
    do:
      {:noreply,
       socket |> assign(notice: kept(Alias.put(socket.assigns.username, alias))) |> seen()}

  defp kept(:ok), do: "kept"
  defp kept({:error, :taken}), do: "someone is already seen as that"
  defp kept({:error, :invalid}), do: "one to thirty-two letters, digits, spaces, _ or -"
  defp kept({:error, reason}), do: inspect(reason)
end
