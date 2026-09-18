defmodule ExPilot.Web.Router do
  @moduledoc false

  use Phoenix.Router

  alias ExPilot.Web.Auth

  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {ExPilot.Web.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/api", ExPilot.Web do
    pipe_through(:api)

    get("/duels", ApiController, :duels)
    post("/duel", ApiController, :duel)
    post("/duel/cancel", ApiController, :cancel)
  end

  forward("/api", Cauldron2D.Net.Api,
    login: &Auth.login/2,
    register: &Auth.register/2,
    token: &Auth.token/1,
    ledger: ExPilot.Ledger
  )

  scope "/", ExPilot.Web do
    pipe_through(:browser)

    live("/", LoginLive)
    get("/session", SessionController, :create)
    get("/logout", SessionController, :delete)
    get("/atlas.png", SheetController, :png)

    live_session :player, on_mount: {ExPilot.Web.Auth, :require} do
      live("/lobby", LobbyLive)
      live("/arena/:id", ArenaLive)
      live("/settings", SettingsLive)
      live("/guide", GuideLive)
      live("/leaders", LeadersLive)
    end
  end
end
