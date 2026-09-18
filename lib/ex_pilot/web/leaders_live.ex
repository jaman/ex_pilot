defmodule ExPilot.Web.LeadersLive do
  @moduledoc """
  The boards: the pilots of today, this week and all time, by kills, kills a death, rounds
  won, longest streak, longest contact and laps, over every arena or one of them, from
  `ExPilot.Ledger`.
  """

  use Phoenix.LiveView

  import ExPilot.Web.Components

  alias ExPilot.{Arenas, Ledger}

  @periods [day: "today", week: "this week", all: "all time"]
  @metrics Ledger.metrics()

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       period: :day,
       metric: :kills,
       arena: nil,
       arenas: Enum.map(Arenas.list(), & &1.name)
     )
     |> load()}
  end

  @impl true
  def handle_event("period", %{"period" => period}, socket),
    do: {:noreply, socket |> assign(period: choice(period, @periods)) |> load()}

  def handle_event("metric", %{"metric" => metric}, socket),
    do: {:noreply, socket |> assign(metric: choice(metric, @metrics)) |> load()}

  def handle_event("arena", %{"arena" => ""}, socket),
    do: {:noreply, socket |> assign(arena: nil) |> load()}

  def handle_event("arena", %{"arena" => arena}, socket),
    do: {:noreply, socket |> assign(arena: arena) |> load()}

  defp choice(text, choices) do
    Enum.find_value(choices, elem(hd(choices), 0), fn {key, _} ->
      if Atom.to_string(key) == text, do: key
    end)
  end

  defp load(socket) do
    %{period: period, metric: metric, arena: arena} = socket.assigns

    assign(socket,
      board: Ledger.board(period, metric, arena: arena),
      periods: @periods,
      metrics: @metrics
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.shell username={@username} current="leaders">
      <div class="page-head">
        <h1>Leaders</h1>
        <p class="dim">Every round counts; robots do not.</p>
      </div>
      <div class="leaders">
        <div class="tabs">
          <button :for={{key, label} <- @periods} phx-click="period" phx-value-period={key} class={["tab", @period == key && "current"]}>{label}</button>
        </div>
        <div class="tabs">
          <button :for={{key, label} <- @metrics} phx-click="metric" phx-value-metric={key} class={["tab", @metric == key && "current"]}>{label}</button>
        </div>
        <form id="arena-pick" phx-change="arena" class="arena-pick">
          <label>arena
            <select name="arena">
              <option value="" selected={@arena == nil}>every arena</option>
              <option :for={name <- @arenas} value={name} selected={@arena == name}>{name}</option>
            </select>
          </label>
        </form>
        <table class="board">
          <thead><tr><th>#</th><th>pilot</th><th>{metric_name(@metric)}</th><th>rounds</th><th>kills</th><th>k/d</th><th>wins</th></tr></thead>
          <tbody>
            <tr :for={{entry, index} <- Enum.with_index(@board, 1)}>
              <td>{index}</td><td class="mono">{entry.name}</td><td class="value">{Ledger.value(entry.value, @metric)}</td><td>{entry.rounds}</td><td>{Ledger.value(entry.values[:kills] || 0, :kills)}</td><td>{Ledger.value(entry.values[:ratio] || 0, :ratio)}</td><td>{Ledger.value(entry.values[:wins] || 0, :wins)}</td>
            </tr>
            <tr :if={@board == []}><td colspan="7" class="dim">nobody yet — fly a round</td></tr>
          </tbody>
        </table>
      </div>
    </.shell>
    """
  end

  @doc "A metric's name for a heading."
  @spec metric_name(Cauldron2D.Ledger.metric()) :: String.t()
  def metric_name(metric), do: Keyword.fetch!(@metrics, metric)
end
