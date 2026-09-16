defmodule ExPilot.Web.Endpoint do
  @moduledoc """
  The HTTP side of an ExPilot server: the pages, the player socket, the sprite sheet
  and the scripts, on the port `ExPilot.Server.start/1` is given as `:http`.
  """

  use Phoenix.Endpoint, otp_app: :ex_pilot

  @session_options [store: :cookie, key: "_ex_pilot", signing_salt: "ex_pilot_session", same_site: "Lax"]

  socket "/socket", ExPilot.Web.UserSocket, websocket: true, longpoll: false
  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]

  plug Plug.Static, at: "/", from: {:cauldron_2d_web, "priv/static"}, only: ~w(cauldron.js)
  plug Plug.Static, at: "/", from: :ex_pilot, only: ~w(expilot.css)
  plug Plug.Static, at: "/vendor", from: {:phoenix, "priv/static"}, only: ~w(phoenix.min.js)
  plug Plug.Static, at: "/vendor", from: {:phoenix_live_view, "priv/static"}, only: ~w(phoenix_live_view.min.js)

  plug Plug.Parsers, parsers: [:urlencoded, :multipart, :json], pass: ["*/*"], json_decoder: Jason
  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug ExPilot.Web.Router
end
