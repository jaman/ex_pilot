defmodule ExPilot.Web.LobbyLive do
  @moduledoc "The arenas, who is in them, the way in, and the duels: a challenge to another pilot on an arena, first to a number of kills."

  use Phoenix.LiveView

  import ExPilot.Web.Components

  alias Cauldron2D.World.Presence
  alias ExPilot.{Arenas, Duels}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Presence.subscribe()
      Phoenix.PubSub.subscribe(ExPilot.Web.PubSub, "duels")
    end

    {:ok,
     socket
     |> assign(challenge: %{"to" => "", "arena" => "", "first_to" => "5"}, notice: nil)
     |> load()}
  end

  defp load(socket), do: assign(socket, arenas: Arenas.list(), duels: Duels.list())

  @impl true
  def handle_event("challenge", %{"to" => to, "arena" => arena, "first_to" => first_to}, socket) do
    notice = challenge_notice(socket, String.trim(to), arena, kills(first_to))

    {:noreply,
     socket
     |> assign(notice: notice, challenge: %{"to" => to, "arena" => arena, "first_to" => first_to})
     |> load()}
  end

  def handle_event("cancel", %{"id" => id}, socket) do
    notice =
      case Duels.cancel(String.to_integer(id), socket.assigns.username) do
        :ok -> nil
        {:error, :not_yours} -> "not your duel"
        {:error, :over} -> "that duel is over"
        {:error, :unknown} -> "no such duel"
      end

    {:noreply, socket |> assign(notice: notice) |> load()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.shell username={@username} current="lobby">
      <div class="page-head">
        <h1>Arenas</h1>
        <p class="dim">{length(@arenas)} arenas · {Enum.sum(Enum.map(@arenas, & &1.players))} pilots flying · robots make room when you join a full one</p>
      </div>
      <section class="duels card">
        <h2>Duels</h2>
        <form id="challenge" phx-submit="challenge" class="challenge">
          <label>challenge <input type="text" name="to" value={@challenge["to"]} placeholder="pilot" /></label>
          <label>on
            <select name="arena">
              <option value="">arena</option>
              <option :for={arena <- @arenas} :if={arena.mode != :duel} value={arena.name} selected={@challenge["arena"] == arena.name}>{arena.name}</option>
            </select>
          </label>
          <label>first to <input type="number" name="first_to" min="1" max="50" value={@challenge["first_to"]} /> kills</label>
          <button type="submit" class="btn btn-primary btn-sm">challenge</button>
          <span :if={@notice} class="dim">{@notice}</span>
        </form>
        <ul :if={@duels != []} class="duel-list">
          <li :for={duel <- @duels}>
            <span class="mono">{duel.challenger} vs {duel.challenged}</span> · {duel.base} · first to {duel.first_to}
            <b :if={duel.ended == :won}> — {duel.winner} won</b>
            <span :if={duel.ended in [:declined, :withdrawn, :expired]} class="dim"> — {duel.ended}</span>
            <a :if={duel.ended == nil and mine?(duel, @username)} class="btn btn-primary btn-sm" href={"/arena/#{duel.arena}"}>fly</a>
            <a :if={duel.ended == nil} class="btn btn-ghost btn-sm" href={"/arena/#{duel.arena}?spectate=1"}>watch</a>
            <button :if={duel.ended == nil and duel.challenged == @username} phx-click="cancel" phx-value-id={duel.id} class="btn btn-ghost btn-sm">decline</button>
            <button :if={duel.ended == nil and duel.challenger == @username} phx-click="cancel" phx-value-id={duel.id} class="btn btn-ghost btn-sm">withdraw</button>
          </li>
        </ul>
        <p :if={@duels == []} class="dim">No duel on. Challenge someone.</p>
      </section>
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
            <a :if={arena.teams == [] and (arena.mode != :duel or (duel_of(@duels, arena.id) && mine?(duel_of(@duels, arena.id), @username)))} class="btn btn-primary btn-sm" href={"/arena/#{arena.name}"}>join</a>
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
  def handle_info({:cauldron_players, _world, _change, _id}, socket), do: {:noreply, load(socket)}
  def handle_info({:duels, :changed}, socket), do: {:noreply, load(socket)}

  defp mine?(duel, username), do: username in [duel.challenger, duel.challenged]

  defp duel_of(duels, arena_id), do: Enum.find(duels, &(&1.arena == arena_id))

  defp kills(first_to) do
    case Integer.parse(first_to) do
      {n, ""} when n > 0 -> n
      _ -> 5
    end
  end

  defp challenge_notice(_socket, "", _arena, _kills), do: "whom?"

  defp challenge_notice(socket, to, arena, kills) do
    bases =
      for %{id: id, mode: mode} <- socket.assigns.arenas, mode != :duel, do: Atom.to_string(id)

    if arena in bases,
      do:
        challenged(
          Duels.challenge(socket.assigns.username, to, String.to_existing_atom(arena),
            first_to: kills
          )
        ),
      else: "pick an arena"
  end

  defp challenged({:ok, duel}),
    do: "#{duel.challenged} is challenged on #{duel.base}, first to #{duel.first_to}"

  defp challenged({:error, :yourself}), do: "not yourself"
  defp challenged({:error, reason}), do: inspect(reason)
end
