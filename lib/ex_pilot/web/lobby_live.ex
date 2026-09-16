defmodule ExPilot.Web.LobbyLive do
  @moduledoc "The arenas, who is in them, and the way in."

  use Phoenix.LiveView

  import ExPilot.Web.Components

  alias ExPilot.Arenas

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Cauldron2D.World.Presence.subscribe()
    {:ok, assign(socket, arenas: Arenas.list())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.shell username={@username} current="lobby">
      <div class="page-head">
        <h1>Arenas</h1>
        <p class="dim">{length(@arenas)} arenas · {Enum.sum(Enum.map(@arenas, & &1.players))} pilots flying · robots make room when you join a full one</p>
      </div>
      <div class="arenas">
        <article :for={arena <- @arenas} class="card arena-card">
          <header>
            <div>
              <h2>{arena.name}</h2>
              <div class="map">{arena.map}</div>
            </div>
            <.mode_badge mode={arena.mode} />
          </header>
          <div class="meta">
            <span class={["live", arena.players > 0 && "on"]}>{playing(arena.players)}</span>
            <span>{arena.note}</span>
          </div>
          <div class="actions">
            <a :if={arena.teams == []} class="btn btn-primary btn-sm" href={"/arena/#{arena.name}"}>join</a>
            <a :for={team <- arena.teams} class={"btn btn-sm btn-team-#{Integer.mod(team - 1, 4) + 1}"} href={"/arena/#{arena.name}?team=#{team}"}>team {team}</a>
            <a class="btn btn-ghost btn-sm" href={"/arena/#{arena.name}?spectate=1"}>watch</a>
          </div>
        </article>
      </div>
    </.shell>
    """
  end

  defp playing(0), do: "nobody flying"
  defp playing(1), do: "1 pilot flying"
  defp playing(n), do: "#{n} pilots flying"

  @impl true
  def handle_info({:cauldron_players, _world, _change, _id}, socket), do: {:noreply, assign(socket, arenas: Arenas.list())}
end
