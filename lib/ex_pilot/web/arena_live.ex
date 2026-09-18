defmodule ExPilot.Web.ArenaLive do
  @moduledoc """
  The arena: the canvas the browser draws the world on, the hud beside it, and the
  round's end. On a coarse pointer (a phone or a tablet; `?touch=1` or `?touch=0`
  forces it, kept in the browser) the page is the game alone — no top bar, no key
  hints, nothing to scroll: the canvas fills the screen, a thumbstick steers and,
  pushed past the ring at half its travel, thrusts — the harder the push, the more
  thrust (`strength` in the input, from a third of full at the ring); buttons fire, shield, fire a missile
  and thrust (next ship when watching); the fuel, score and status ride over the
  world; `≡` opens the rest of the hud over it, `−`/`+` and a pinch zoom the view out
  to the whole arena and back, `⇄` swaps the stick and the buttons between hands (kept
  in the browser), `♪` switches the music off and on (kept in the browser, the effects
  stay), `⤢` goes full screen and `✕` leaves for the arenas. The sound comes
  as 22 050 Hz mono there, a quarter of the desktop's bytes. With a keyboard `+`, `−`
  and the wheel zoom and `0` puts the view back, and `♪` in the bar switches the music;
  watching, the arrows or a drag (the mouse, a finger) pan the view, the wheel and a
  pinch zoom about the pointer or the fingers, and `0` recentres it.
  """

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
            <span><kbd>+</kbd><kbd>−</kbd> or the wheel zoom, <kbd>0</kbd> back</span>
            <span :if={@spectate}>arrows or a drag pan, the wheel zooms at the pointer</span>
            <span><kbd>M</kbd> frames a second</span>
            <a href="/guide">guide</a>
          </span>
          <button type="button" class="music-toggle bar-toggle" title="music off and on">♪</button>
          <span id="meter" class="mono meter" hidden></span>
        </div>
        <div class="arena" id="arena" phx-hook="Arena" phx-update="ignore" data-arena={@arena} data-team={@team} data-spectate={@spectate} data-token={@token} data-keymap={@keymap} data-scale="32">
          <div class="stage"><canvas width="960" height="640" tabindex="0"></canvas></div>
          <div class="hud"></div>
          <div class="controls">
            <div class="stick"><div class="knob"></div></div>
            <div class="buttons">
              <div class="touch-btn" data-action="fire">fire</div>
              <div class="touch-btn" data-action="shield">shield</div>
              <div class="touch-btn" data-action="fire_missile">missile</div>
              <div class="touch-btn" data-action="thrust">thrust</div>
              <div class="touch-btn watching" data-action="next_watch">next</div>
            </div>
            <div class="chrome">
              <a class="chrome-btn" href="/lobby">✕</a>
              <div class="chrome-btn more">≡</div>
              <div class="chrome-btn zoom-out">−</div>
              <div class="chrome-btn zoom-in">+</div>
              <div class="chrome-btn swap">⇄</div>
              <div class="chrome-btn music-toggle">♪</div>
              <div class="chrome-btn full">⤢</div>
            </div>
          </div>
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

  def handle_event("refused", %{"reason" => reason}, socket),
    do: {:noreply, assign(socket, refused: reason)}
end
