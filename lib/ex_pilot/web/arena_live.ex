defmodule ExPilot.Web.ArenaLive do
  @moduledoc "The arena: the canvas the browser draws the world on, the hud beside it, and the round's end."

  use Phoenix.LiveView

  import ExPilot.Web.Components

  alias ExPilot.Web.Auth

  @keymap %{
    "KeyA" => "turn_left",
    "ArrowLeft" => "turn_left",
    "KeyD" => "turn_right",
    "ArrowRight" => "turn_right",
    "KeyS" => "thrust",
    "ArrowUp" => "thrust",
    "Space" => "fire",
    "Enter" => "next_watch",
    "KeyW" => "shield",
    "ShiftLeft" => "shield",
    "Digit1" => "drop_mine",
    "Digit2" => "fire_missile",
    "Digit3" => "fire_laser",
    "KeyN" => "next_missile",
    "KeyC" => "cloak",
    "KeyE" => "ecm",
    "KeyR" => "transporter",
    "KeyG" => "tractor",
    "KeyB" => "pressor",
    "KeyX" => "deflector",
    "KeyP" => "phasing",
    "KeyU" => "hyperjump",
    "BracketLeft" => "emergency_shield",
    "BracketRight" => "emergency_thrust",
    "KeyO" => "autopilot",
    "KeyV" => "connector",
    "mouse" => %{"0" => "fire", "2" => "thrust"}
  }

  @doc "The browser's keys, by `KeyboardEvent.code`, and the mouse buttons, to the game's actions."
  @spec keymap() :: map()
  def keymap, do: @keymap

  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    {:ok,
     assign(socket,
       arena: id,
       team: Map.get(params, "team"),
       spectate: Map.get(params, "spectate"),
       token: Auth.token(socket.assigns.username),
       keymap: Jason.encode!(@keymap),
       over: nil,
       refused: nil
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.shell username={@username} current="arena" wide={true}>
      <div class="arena-page">
        <div class="arena-bar">
          <a href="/lobby">← arenas</a>
          <span class="mono">{@arena}</span>
          <span :if={@spectate} class="badge badge-team">watching</span>
          <span class="keys">
            <span><kbd>A</kbd><kbd>D</kbd> or <kbd>←</kbd><kbd>→</kbd> turn</span>
            <span><kbd>S</kbd> <kbd>↑</kbd> or right button thrust</span>
            <span><kbd>space</kbd> or left button fire</span>
            <span><kbd>W</kbd> <kbd>shift</kbd> shield</span>
            <span>the pointer steers</span>
            <span><kbd>enter</kbd> next ship when watching</span>
            <a href="/guide">guide</a>
          </span>
        </div>
        <div class="arena" id="arena" phx-hook="Arena" phx-update="ignore" data-arena={@arena} data-team={@team} data-spectate={@spectate} data-token={@token} data-keymap={@keymap} data-scale="32">
          <canvas width="960" height="640" tabindex="0"></canvas>
          <div class="hud"></div>
        </div>
        <p :if={@refused} class="error">could not join: {@refused}</p>
      </div>
      <div :if={@over} class="summary">
        <div class="card">
          <h2 class={String.downcase(@over["title"])}>{@over["title"]}</h2>
          <div class="lines">{Enum.join(@over["lines"], "\n")}</div>
          <div class="row" style="justify-content: center">
            <a class="btn btn-primary" href={"/arena/#{@arena}"}>fly again</a>
            <a class="btn" href="/lobby">arenas</a>
          </div>
        </div>
      </div>
    </.shell>
    """
  end

  @impl true
  def handle_event("over", over, socket), do: {:noreply, assign(socket, over: over)}
  def handle_event("refused", %{"reason" => reason}, socket), do: {:noreply, assign(socket, refused: reason)}
end
