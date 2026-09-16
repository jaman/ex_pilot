defmodule ExPilot.Web.Router do
  @moduledoc false

  use Phoenix.Router

  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ExPilot.Web.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", ExPilot.Web do
    pipe_through :browser

    live "/", LoginLive
    get "/session", SessionController, :create
    get "/logout", SessionController, :delete
    get "/atlas.png", SheetController, :png

    live_session :player, on_mount: {ExPilot.Web.Auth, :require} do
      live "/lobby", LobbyLive
      live "/arena/:id", ArenaLive
      live "/settings", SettingsLive
      live "/guide", GuideLive
    end
  end
end
