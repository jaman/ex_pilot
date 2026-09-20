defmodule ExPilot.Web.PilotsLive do
  @moduledoc """
  The pilots panel every page carries: a count of who is logged in, and a side panel
  that slides open on it with the scrollable list — each pilot by the name they are
  seen under, where they are, and the kind of client. It is rendered inside the shell
  with `live_render/3`, follows `ExPilot.Roster`, and opens on `toggle` or `open`
  pushed to `#pilots` from anywhere on the page; Escape or the backdrop closes it.
  """

  use Phoenix.LiveView

  alias ExPilot.{Alias, Roster}

  @impl true
  def mount(_params, %{"username" => username}, socket) do
    if connected?(socket), do: Roster.subscribe()
    {:ok, socket |> assign(username: username, open: false) |> load()}
  end

  defp load(socket) do
    me = socket.assigns.username

    pilots =
      for %{id: id, kind: kind, arena: arena} <- Roster.online(), is_binary(id) do
        %{name: Alias.of(id), where: where(arena), client: client(kind), me?: id == me}
      end

    assign(socket, pilots: Enum.sort_by(pilots, &String.downcase(&1.name)))
  end

  defp where(nil), do: "in the lobby"
  defp where(arena), do: "in #{arena}"

  defp client(:web), do: "browser"
  defp client(:touch), do: "phone"
  defp client(:terminal), do: "terminal"
  defp client(nil), do: "desktop"
  defp client(kind), do: to_string(kind)

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <button class="pilots-toggle" phx-click="toggle" title="who is logged in"><span class="dot"></span><span class="pilots-count">{count(@pilots)}</span></button>
      <div class={["pilots", @open && "open"]} phx-window-keydown="close" phx-key="Escape">
        <div class="pilots-backdrop" phx-click="close"></div>
        <aside class="pilots-panel">
          <header>
            <h2>Pilots online</h2>
            <span class="dim">{count(@pilots)}</span>
            <button class="pilots-close" phx-click="close" aria-label="close">×</button>
          </header>
          <ul class="pilots-list">
            <li :for={pilot <- @pilots} class={pilot.me? && "me"}>
              <span class="mono">{pilot.name}</span>
              <span class="dim">{pilot.where}</span>
              <span class="faint">{pilot.client}</span>
            </li>
            <li :if={@pilots == []} class="dim">nobody is logged in</li>
          </ul>
        </aside>
      </div>
    </div>
    """
  end

  defp count([_one]), do: "1 pilot"
  defp count(pilots), do: "#{length(pilots)} pilots"

  @impl true
  def handle_event("toggle", _params, socket), do: {:noreply, update(socket, :open, &(not &1))}
  def handle_event("open", _params, socket), do: {:noreply, assign(socket, :open, true)}
  def handle_event("close", _params, socket), do: {:noreply, assign(socket, :open, false)}

  @impl true
  def handle_info({:roster, :changed}, socket), do: {:noreply, load(socket)}
end
