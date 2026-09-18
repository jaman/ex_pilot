defmodule ExPilot.Web.SheetController do
  @moduledoc "Serves the sprite sheet the browser draws the arena from."

  use Phoenix.Controller, formats: [:html]

  alias Cauldron2D.Net.Sheet

  import Plug.Conn

  def png(conn, _params) do
    sheet = Sheet.cached(ExPilot.Client.atlas())

    conn
    |> put_resp_content_type("image/png")
    |> put_resp_header("cache-control", "public, max-age=3600")
    |> send_resp(200, sheet.png)
  end
end
