defmodule ExPilot.Web.Layouts do
  @moduledoc false

  use Phoenix.Component

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover, user-scalable=no" />
        <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()} />
        <meta name="theme-color" content="#05060f" />
        <meta name="apple-mobile-web-app-capable" content="yes" />
        <meta name="mobile-web-app-capable" content="yes" />
        <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent" />
        <meta name="apple-mobile-web-app-title" content="ExPilot" />
        <link rel="manifest" href="/manifest.webmanifest" />
        <link rel="apple-touch-icon" href="/icon.png" />
        <title>ExPilot</title>
        <link rel="stylesheet" href="/expilot.css" />
        <script src="/vendor/phoenix.min.js"></script>
        <script src="/vendor/phoenix_live_view.min.js"></script>
        <script src="/cauldron.js"></script>
        <script src="/expilot.js"></script>
        <script>document.documentElement.classList.toggle("touch", ExPilot.touch());</script>
      </head>
      <body>
        {@inner_content}
        <script>
          window.addEventListener("DOMContentLoaded", function () {
            var csrf = document.querySelector("meta[name='csrf-token']").getAttribute("content");
            var hooks = {};
            hooks.Arena = {
              mounted: function () {
                var el = this.el;
                var hook = this;
                var touch = ExPilot.touch();
                document.documentElement.classList.toggle("touch", touch);
                if (touch) ExPilot.touchPage(el);
                var options = {
                  socketUrl: "/socket",
                  socketParams: { token: el.dataset.token, kind: touch ? "touch" : "web" },
                  topic: "arena:" + el.dataset.arena,
                  params: Object.assign({}, el.dataset.team ? { team: el.dataset.team } : {}, el.dataset.spectate ? { spectate: el.dataset.spectate } : {}),
                  hud: el.querySelector(".hud"),
                  scale: touch ? ExPilot.touchTile() : parseInt(el.dataset.scale || "32", 10),
                  keymap: JSON.parse(el.dataset.keymap),
                  steering: ["turn_left", "turn_right"],
                  zoom: { min: 2, max: 64 },
                  onOver: function (over) { hook.pushEvent("over", over); },
                  onError: function (reason) { hook.pushEvent("refused", { reason: reason }); },
                  onStats: function (stats) {
                    var meter = document.getElementById("meter");
                    if (meter) meter.textContent = stats.frames + " frames/s  " + stats.draws + " draws/s";
                  }
                };
                if (touch) {
                  options.fit = true;
                  options.touch = { zones: ExPilot.touchZones(el) };
                  options.audio = { rate: 22050, channels: 1 };
                }
                this.game = Cauldron.mount(el.querySelector("canvas"), options);
                if (touch) ExPilot.touchZoom(el, this.game);
                ExPilot.musicToggles(el.closest(".arena-page") || el, this.game);
                this.onMeterKey = function (event) {
                  var meter = document.getElementById("meter");
                  if (event.code === "KeyM" && meter && !event.repeat) meter.hidden = !meter.hidden;
                };
                window.addEventListener("keydown", this.onMeterKey);
              },
              destroyed: function () {
                window.removeEventListener("keydown", this.onMeterKey);
                ExPilot.leavePage();
                if (this.game) this.game.stop();
              }
            };
            var liveSocket = new LiveView.LiveSocket("/live", Phoenix.Socket, { hooks: hooks, params: { _csrf_token: csrf, kind: ExPilot.touch() ? "touch" : "web" } });
            liveSocket.connect();
            window.liveSocket = liveSocket;
          });
        </script>
      </body>
    </html>
    """
  end
end
