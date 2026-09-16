defmodule ExPilot.Web.Layouts do
  @moduledoc false

  use Phoenix.Component

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()} />
        <title>ExPilot</title>
        <link rel="stylesheet" href="/expilot.css" />
        <script src="/vendor/phoenix.min.js"></script>
        <script src="/vendor/phoenix_live_view.min.js"></script>
        <script src="/cauldron.js"></script>
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
                this.game = Cauldron.mount(el.querySelector("canvas"), {
                  socketUrl: "/socket",
                  socketParams: { token: el.dataset.token },
                  topic: "arena:" + el.dataset.arena,
                  params: Object.assign({}, el.dataset.team ? { team: el.dataset.team } : {}, el.dataset.spectate ? { spectate: el.dataset.spectate } : {}),
                  hud: el.querySelector(".hud"),
                  scale: parseInt(el.dataset.scale || "32", 10),
                  keymap: JSON.parse(el.dataset.keymap),
                  steering: ["turn_left", "turn_right"],
                  onOver: function (over) { hook.pushEvent("over", over); },
                  onError: function (reason) { hook.pushEvent("refused", { reason: reason }); }
                });
              },
              destroyed: function () { if (this.game) this.game.stop(); }
            };
            var liveSocket = new LiveView.LiveSocket("/live", Phoenix.Socket, { hooks: hooks, params: { _csrf_token: csrf } });
            liveSocket.connect();
            window.liveSocket = liveSocket;
          });
        </script>
      </body>
    </html>
    """
  end
end
