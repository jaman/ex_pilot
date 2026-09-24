defmodule ExPilot.Web.SettingsLive do
  @moduledoc """
  The sound levels of this kind of client — the browser, or a phone or tablet
  (`:touch`, told by the page) — kept in the account under their own key, the alias
  the account is seen under on every client, the ship shape every client flies — a
  preset by a tap, or written in XPilot's notation, drawn as it is kept — the
  controller bindings every client uses (`ExPilot.Padmap`, an action a row, its
  controls as words; a control pressed on a pad while a row is focused writes itself
  in; `keep` saves them all, `reset` goes back to the default) and, on a phone or
  tablet, its controls: the hand the thumbstick is on and whether tilting the device
  steers. The touch controls are kept as they are changed; switching tilt on asks the
  browser for motion access where it wants asking (iOS), and the page says so when it
  is refused.
  """

  use Phoenix.LiveView

  import ExPilot.Web.Components

  alias ExPilot.{Alias, Padmap, Shipshape}
  alias ExPilot.Web.Auth

  @impl true
  def mount(_params, _session, socket) do
    kind = if connected?(socket), do: Auth.kind(get_connect_params(socket)["kind"]), else: :web
    levels = Auth.levels(socket.assigns.username, kind)
    controls = Auth.controls(socket.assigns.username, kind)

    {:ok,
     socket
     |> assign(kind: kind, sfx: levels.sfx, music: levels.music, saved: false, notice: nil)
     |> assign(side: controls.side, tilt: controls.tilt, invert: controls.invert, motion: nil)
     |> assign(shape_notice: nil, pad_notice: nil)
     |> shape()
     |> pad()
     |> seen()}
  end

  defp pad(socket) do
    bindings = Padmap.merge(Auth.padmap(socket.assigns.username))

    assign(socket,
      pad_rows:
        for(
          action <- Padmap.actions(),
          do: {action, Padmap.format_controls(Map.get(bindings, action, []))}
        ),
      pad_own?: Auth.padmap(socket.assigns.username) != %{},
      stick_thrust?: Padmap.pushes?(Map.get(bindings, :aim, []))
    )
  end

  defp shape(socket) do
    kept = Auth.shipshape(socket.assigns.username)
    assign(socket, shape: kept, shape_text: kept || "")
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
    <div class="page-head"><h1>Settings</h1><p class="dim">Kept in your account — every client follows, sound aside, which is per client.</p></div>
    <div class="settings-grid">
      <section class="card panel" id="you">
        <h2>You</h2>
        <form id="alias" phx-submit="alias" class="stack">
          <p>You are <strong>{@username}</strong>. Others see you as <strong>{@seen_as}</strong><span :if={not @chosen?}> — an anonymous name of your own, the same every visit</span>.</p>
          <div class="field-row">
            <label class="field"><span>seen as</span><input type="text" name="alias" value={if @chosen?, do: @seen_as, else: ""} placeholder={@anonymous} maxlength="32" /></label>
            <button type="submit" class="btn btn-sm">keep</button>
          </div>
          <p class="hint">Shown on every client and the boards; blank goes back to {@anonymous}. Only you and an admin see {@username}. <span :if={@notice}>{@notice}</span></p>
        </form>
      </section>

      <section class="card panel" id="sound">
        <h2>Sound on {kind_name(@kind)}</h2>
        <form id="levels" phx-change="change" phx-submit="save" class="stack">
          <div class="slider"><label>effects <b>{round(@sfx * 100)}%</b></label><input type="range" name="sfx" min="0" max="100" value={round(@sfx * 100)} /></div>
          <div class="slider"><label>music <b>{round(@music * 100)}%</b></label><input type="range" name="music" min="0" max="100" value={round(@music * 100)} /></div>
          <div class="actions"><button type="submit" class="btn btn-sm">save</button><span :if={@saved} class="hint">saved</span></div>
        </form>
      </section>

      <section class="card panel panel-wide" id="ship">
        <h2>Your ship</h2>
        <form id="shipshape" phx-submit="shipshape" class="stack">
          <div class="presets">
            <button :for={{name, text} <- Shipshape.presets()} type="button" class={["preset", (@shape || Shipshape.preset!("classic")) == text && "current"]} phx-click="preset" phx-value-name={name} title={text}>
              <.ship_svg shape={text} size={44} />
              <span>{name}</span>
            </button>
          </div>
          <div class="shape-row">
            <.ship_svg shape={@shape || Shipshape.preset!("classic")} size={64} />
            <input type="text" name="shape" value={@shape_text} placeholder={Shipshape.preset!("classic")} spellcheck="false" />
            <button type="submit" class="btn btn-sm">keep</button>
          </div>
          <p class="hint">A preset by a tap, or XPilot's notation: <code>(SH: x,y …)</code> the outline with the nose along +x, <code>(EN: x,y)</code> the engine, <code>(MG: x,y …)</code> the guns; blank goes back to the classic. <span :if={@shape_notice}>{@shape_notice}</span></p>
        </form>
      </section>

      <section class="card panel panel-wide" id="controller">
        <h2>Controller</h2>
        <form id="padmap" phx-submit="padmap" phx-hook="Pad" class="stack">
          <p class="pad-status" data-pad-status>looking for a controller — press a button on it with this page in front</p>
          <p class="hint" data-pad-help></p>
          <details class="hint" data-pad-mac hidden>
            <summary>Controller not seen on a Mac in Chrome or Firefox?</summary>

            <ol>
              <li>Press a button on it while this page is in front — browsers keep a controller hidden until then.</li>
              <li>Quit Steam entirely (its menu-bar icon too): it takes controllers over and hides them from browsers.</li>
              <li>Pair it over Bluetooth rather than USB: Chrome and Firefox on a Mac see only controllers that show up as plain HID devices, which most Xbox and PlayStation pads do over Bluetooth and many don't over USB. Third-party pads need their X-input mode.</li>
              <li>Or use Safari, which sees whatever macOS itself does — the same as the desktop and terminal clients.</li>
            </ol>
            <p>This page needs https or localhost for any browser to hand a controller over.</p>
          </details>

          <div class="bindings">
            <%= for {group, rows} <- grouped(@pad_rows) do %>
              <h3>{group}</h3>
              <label :for={{action, controls} <- rows}>
                <span>{action |> Atom.to_string() |> String.replace("_", " ")}</span>
                <input type="text" name={action} value={controls} spellcheck="false" autocomplete="off" />
              </label>
            <% end %>
          </div>
          <label class="check"><input type="checkbox" name="stick_thrust" value="on" checked={@stick_thrust?} /> the aim stick also thrusts when pushed past its ring, harder the further</label>
          <div class="actions">
            <button type="submit" class="btn btn-sm">keep</button>
            <button type="button" class="btn btn-ghost btn-sm" phx-click="padmap_reset">reset to the default</button>
            <span class="hint">{if @pad_own?, do: "your own bindings", else: "the default"}<span :if={@pad_notice}> — {@pad_notice}</span></span>
          </div>
          <p class="hint">Click a row and press the control on the pad, or write it: buttons by name (a, b, x, y, left_bumper, right_bumper, back, start, guide, left_stick, right_stick, dpad_up, dpad_down, dpad_left, dpad_right), an axis with its direction (left_x-, left_x+, left_y-, right_x+, right_trigger+, left_trigger+…), or for aim a whole stick (left_stick_xy, right_stick_xy) — the ship turns to the way it is pushed. Spaces between.</p>
        </form>
      </section>

      <section :if={@kind == :touch} class="card panel" id="phone">
        <h2>This phone or tablet</h2>
        <form id="controls" phx-change="controls" phx-hook="Tilt" class="stack">
          <div class="choice">
            <span>the stick under the</span>
            <label class="check"><input type="radio" name="side" value="left" checked={@side == :left} /> left</label>
            <label class="check"><input type="radio" name="side" value="right" checked={@side == :right} /> right</label>
            <span>hand, the buttons under the other</span>
          </div>
          <label class="check"><input type="checkbox" name="tilt" value="on" checked={@tilt} /> tilt to steer</label>
          <label class="check"><input type="checkbox" name="invert" value="on" checked={@invert} /> invert the tilt — the top tilted away aims down</label>
          <p class="hint">Kept as you change them. Tilting the device turns the ship; the stick then thrusts — a touch for a little, a push for more — and steers only when pushed far. <span :if={@motion}>{@motion}</span></p>
        </form>
      </section>

      <section class="card panel" id="keys">
        <h2>Keys in the browser</h2>
        <dl class="keys-list">
          <dt><kbd>A</kbd><kbd>D</kbd> or <kbd>←</kbd><kbd>→</kbd></dt><dd>turn — the pointer steers too</dd>
          <dt><kbd>W</kbd> <kbd>↑</kbd> or the right button</dt><dd>thrust</dd>
          <dt><kbd>space</kbd> or the left button</dt><dd>fire</dd>
          <dt><kbd>S</kbd> <kbd>shift</kbd></dt><dd>shield</dd>

          <dt><kbd>enter</kbd></dt><dd>next ship when watching</dd>
          <dt><kbd>+</kbd><kbd>−</kbd> <kbd>0</kbd></dt><dd>zoom, and back</dd>
        </dl>
        <p class="hint">Sound plays in the page.</p>
      </section>
    </div>
    </.shell>
    """
  end

  defp grouped(rows) do
    for {group, actions} <- Padmap.groups(),
        do: {group, Enum.filter(rows, fn {action, _} -> action in actions end)}
  end

  attr(:shape, :string, required: true)
  attr(:size, :integer, default: 48)

  defp ship_svg(assigns) do
    ~H"""
    <svg class="ship" viewBox="-16 -16 32 32" width={@size} height={@size} aria-hidden="true">
      <polygon points={polygon(@shape)} />
    </svg>
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

  def handle_event("preset", %{"name" => name}, socket) do
    case Shipshape.preset(name) do
      nil -> {:noreply, socket}
      text -> {:noreply, socket |> keep_shape(text) |> assign(shape_notice: "kept")}
    end
  end

  def handle_event("shipshape", %{"shape" => text}, socket) do
    case Auth.put_shipshape(socket.assigns.username, text) do
      :ok ->
        {:noreply, socket |> shape() |> assign(shape_notice: "kept")}

      {:error, :no_outline} ->
        {:noreply,
         assign(socket,
           shape_text: text,
           shape_notice: "no outline — an (SH: …) with three points or more is needed"
         )}

      {:error, reason} ->
        {:noreply, assign(socket, shape_text: text, shape_notice: inspect(reason))}
    end
  end

  def handle_event("padmap", fields, socket) do
    fields = aim_pushing(fields, Map.get(fields, "stick_thrust") == "on")

    case Auth.put_padmap(socket.assigns.username, fields) do
      :ok ->
        {:noreply, socket |> pad() |> assign(pad_notice: "kept")}

      {:error, {action, {:unknown, word}}} ->
        rows =
          for {name, _} <- socket.assigns.pad_rows,
              do: {name, Map.get(fields, Atom.to_string(name), "")}

        {:noreply,
         assign(socket,
           pad_rows: rows,
           pad_notice:
             "#{word} is no control (in #{String.replace(action, "_", " ")}); nothing kept"
         )}
    end
  end

  def handle_event("padmap_reset", _params, socket) do
    Auth.reset_padmap(socket.assigns.username)
    {:noreply, socket |> pad() |> assign(pad_notice: "back to the default")}
  end

  def handle_event("controls", params, socket) do
    controls = %{
      side: side(Map.get(params, "side")),
      tilt: Map.get(params, "tilt") == "on",
      invert: Map.get(params, "invert") == "on"
    }

    Auth.put_controls(socket.assigns.username, controls, socket.assigns.kind)

    {:noreply,
     assign(socket,
       side: controls.side,
       tilt: controls.tilt,
       invert: controls.invert,
       motion: nil
     )}
  end

  def handle_event("motion", %{"state" => "denied"}, socket),
    do:
      {:noreply,
       assign(socket,
         motion: "the browser refused motion access; tilt will not steer until it is allowed"
       )}

  def handle_event("motion", _state, socket), do: {:noreply, assign(socket, motion: nil)}

  def handle_event("alias", %{"alias" => alias}, socket),
    do:
      {:noreply,
       socket |> assign(notice: kept(Alias.put(socket.assigns.username, alias))) |> seen()}

  defp aim_pushing(%{"aim" => text} = fields, thrusts?) do
    case Padmap.parse_controls(text) do
      {:ok, controls} ->
        pushed = Padmap.with_push(controls, if(thrusts?, do: :thrust))
        Map.put(fields, "aim", Padmap.format_controls(pushed))

      {:error, _} ->
        fields
    end
  end

  defp aim_pushing(fields, _thrusts?), do: fields

  defp keep_shape(socket, text) do
    Auth.put_shipshape(socket.assigns.username, text)
    shape(socket)
  end

  defp polygon(text) do
    case Shipshape.parse(text) do
      {:ok, %{outline: outline}} -> Enum.map_join(outline, " ", fn {x, y} -> "#{x},#{-y}" end)
      {:error, _} -> ""
    end
  end

  defp side("right"), do: :right
  defp side(_left), do: :left

  defp kept(:ok), do: "kept"
  defp kept({:error, :taken}), do: "someone is already seen as that"
  defp kept({:error, :invalid}), do: "one to thirty-two letters, digits, spaces, _ or -"
  defp kept({:error, reason}), do: inspect(reason)
end
