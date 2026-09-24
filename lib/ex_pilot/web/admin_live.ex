defmodule ExPilot.Web.AdminLive do
  @moduledoc """
  The admin page, for accounts with `admin: true` (`mix ex_pilot.admin NAME`): who is
  logged in, on what, and where, how each arena and the node are keeping up, every account with the
  name it is seen under and its record, what happened lately, and the actions — kick a
  session, stop an idle arena, forget a name's results, grant or revoke admin. Refreshes
  itself every few seconds.
  """

  use Phoenix.LiveView

  import ExPilot.Web.Components

  alias Cauldron2D.{Player, Stats}
  alias Drafter.Accounts
  alias ExPilot.{Alias, Arenas, Duels, Ledger, Roster}
  alias ExPilot.Web.Auth

  @every 3_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Process.send_after(self(), :refresh, @every)
    {:ok, socket |> assign(notice: nil) |> load()}
  end

  @impl true
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @every)
    {:noreply, load(socket)}
  end

  defp load(socket) do
    assign(socket,
      online: Enum.map(Roster.online(), &Map.put(&1, :seen_as, Alias.of(&1.id))),
      arenas: Stats.worlds(),
      node: Stats.node(),
      duels: Enum.reject(Duels.list(), &(&1.ended != nil)),
      accounts: accounts(),
      lately: Enum.map(Roster.lately(), &Map.put(&1, :seen_as, Alias.of(&1.id))),
      now: System.system_time(:second)
    )
  end

  defp accounts do
    records = Map.new(Ledger.board(:all, :kills, top: :all), &{&1.account, &1})

    for %{username: username, number: number, props: props} <- Accounts.list(ExPilot.Accounts) do
      record = Map.get(records, username, %{rounds: 0, values: %{}})

      %{
        username: username,
        number: number,
        seen_as: Alias.of(username),
        chosen?: Alias.chosen?(username),
        admin?: props[:admin] == true,
        rounds: record.rounds,
        kills: record.values[:kills] || 0,
        wins: record.values[:wins] || 0
      }
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.shell socket={@socket} username={@username} admin?={@admin?} seen_as={Alias.of(@username)} current="admin">
      <div class="page-head">
        <h1>Admin</h1>
        <p class="dim">{length(@online)} online · {length(@arenas)} arenas running · node {Float.round(@node.busy * 100, 0)}% busy, {@node.memory_mb} MB, {@node.processes} processes · <span :if={@notice}>{@notice}</span></p>
      </div>

      <section class="card">
        <h2>Online</h2>
        <table class="board">
          <thead><tr><th>account</th><th>seen as</th><th>client</th><th>where</th><th>for</th><th></th></tr></thead>
          <tbody>
            <tr :for={pilot <- @online}>
              <td class="mono">{pilot.id}</td><td class="mono">{pilot.seen_as}</td><td>{client_name(pilot.kind)}</td><td>{where(pilot.arena)}</td><td>{ago(@now - pilot.since)}</td>
              <td><button :if={pilot.arena} phx-click="kick" phx-value-id={pilot.id} phx-value-arena={pilot.arena} class="btn btn-ghost btn-sm">kick</button></td>
            </tr>
            <tr :if={@online == []}><td colspan="6" class="dim">nobody logged in</td></tr>
          </tbody>
        </table>
      </section>

      <section class="card">
        <h2>Arenas running</h2>
        <table class="board">
          <thead><tr><th>arena</th><th>players</th><th>hz</th><th>tick mean / p95 / max (µs)</th><th>behind</th><th></th></tr></thead>
          <tbody>
            <tr :for={arena <- @arenas}>
              <td class="mono">{arena.name}</td><td>{arena.players}</td><td>{arena.hz}</td>
              <td>{arena.tick_us.mean} / {arena.tick_us.p95} / {arena.tick_us.max}</td><td>{arena.behind}</td>
              <td><button :if={arena.players == 0} phx-click="stop" phx-value-arena={arena.name} class="btn btn-ghost btn-sm">stop</button></td>
            </tr>
            <tr :if={@arenas == []}><td colspan="6" class="dim">no world running</td></tr>
          </tbody>
        </table>
        <p :if={@duels != []} class="dim">Duels on: <span :for={duel <- @duels} class="mono">{duel.challenger} vs {duel.challenged} on {duel.base} · </span></p>
      </section>

      <section class="card">
        <h2>Accounts</h2>
        <table class="board">
          <thead><tr><th>#</th><th>account</th><th>seen as</th><th>rounds</th><th>kills</th><th>wins</th><th>admin</th><th></th></tr></thead>
          <tbody>
            <tr :for={account <- @accounts}>
              <td>{account.number}</td><td class="mono">{account.username}</td>
              <td class="mono">{account.seen_as}<span :if={not account.chosen?} class="dim"> (anonymous)</span></td>
              <td>{account.rounds}</td><td>{account.kills}</td><td>{account.wins}</td>
              <td>{if account.admin?, do: "yes", else: ""}</td>
              <td>
                <button :if={not account.admin?} phx-click="admin" phx-value-username={account.username} phx-value-to="yes" class="btn btn-ghost btn-sm">make admin</button>
                <button :if={account.admin? and account.username != @username} phx-click="admin" phx-value-username={account.username} phx-value-to="no" class="btn btn-ghost btn-sm">revoke</button>
                <button :if={account.rounds > 0} phx-click="forget" phx-value-username={account.username} class="btn btn-ghost btn-sm">forget results</button>
              </td>
            </tr>
          </tbody>
        </table>
      </section>

      <section class="card">
        <h2>Lately</h2>
        <ul class="online-list">
          <li :for={event <- @lately}><span class="dim">{ago(@now - event.at)} ago</span> <span class="mono">{event.id}</span> ({event.seen_as}) {happened(event)}</li>
          <li :if={@lately == []} class="dim">nothing yet</li>
        </ul>
      </section>
    </.shell>
    """
  end

  defp client_name(:web), do: "browser"
  defp client_name(:touch), do: "phone or tablet"
  defp client_name(:terminal), do: "terminal"
  defp client_name(nil), do: "desktop"
  defp client_name(kind), do: to_string(kind)

  defp where(nil), do: "lobby"
  defp where(arena), do: "in #{arena}"

  defp happened(%{what: :logged_in, kind: kind}), do: "logged in on a #{client_name(kind)}"
  defp happened(%{what: :logged_out, kind: kind}), do: "logged out of a #{client_name(kind)}"
  defp happened(%{what: :joined, arena: arena}), do: "joined #{arena}"
  defp happened(%{what: :left, arena: arena}), do: "left #{arena}"

  @doc "A span of seconds as a word: `12s`, `4m`, `2h`, `3d`."
  @spec ago(integer()) :: String.t()
  def ago(seconds) when seconds < 60, do: "#{max(seconds, 0)}s"
  def ago(seconds) when seconds < 3_600, do: "#{div(seconds, 60)}m"
  def ago(seconds) when seconds < 86_400, do: "#{div(seconds, 3_600)}h"
  def ago(seconds), do: "#{div(seconds, 86_400)}d"

  @impl true
  def handle_event("kick", %{"id" => id, "arena" => arena}, socket) do
    :ok = Player.leave(Arenas.world_name(String.to_existing_atom(arena)), id)
    {:noreply, socket |> assign(notice: "kicked #{Alias.of(id)}") |> load()}
  end

  def handle_event("stop", %{"arena" => arena}, socket) do
    :ok = Arenas.stop(String.to_existing_atom(arena))
    {:noreply, socket |> assign(notice: "stopped #{arena}") |> load()}
  end

  def handle_event("forget", %{"username" => username}, socket) do
    notice =
      case Ledger.forget_account(username) do
        {:ok, gone} -> "forgot #{gone} results of #{username}"
        {:error, reason} -> "the ledger could not forget #{username}: #{inspect(reason)}"
      end

    {:noreply, socket |> assign(notice: notice) |> load()}
  end

  def handle_event("admin", %{"username" => username, "to" => to}, socket) do
    :ok = Auth.put_admin(username, to == "yes")

    {:noreply,
     socket
     |> assign(
       notice: "#{username} #{if to == "yes", do: "is an admin", else: "is no longer an admin"}"
     )
     |> load()}
  end
end
