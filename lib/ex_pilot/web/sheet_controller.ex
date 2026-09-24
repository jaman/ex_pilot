defmodule ExPilot.Web.SheetController do
  @moduledoc "Serves the sprite sheet the browser draws the arena from: cacheable for a year when asked for by version (`ExPilot.Web.Assets.sheet_path/0`), never otherwise."

  use Phoenix.Controller, formats: [:html]

  alias Cauldron2D.Net.Sheet

  import Plug.Conn

  def png(conn, params) do
    sheet = Sheet.cached(ExPilot.Client.atlas())

    conn
    |> put_resp_content_type("image/png")
    |> put_resp_header("cache-control", caching(params))
    |> send_resp(200, sheet.png)
  end

  defp caching(%{"vsn" => _version}), do: "public, max-age=31536000, immutable"
  defp caching(_unversioned), do: "no-cache"
end
