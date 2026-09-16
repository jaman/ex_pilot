defmodule ExPilot.Web.SessionController do
  @moduledoc "Turns a login token into the browser session cookie, and clears it on logout."

  use Phoenix.Controller, formats: [:html]

  import Plug.Conn

  alias ExPilot.Web.Auth

  def create(conn, %{"token" => token}) do
    case Auth.verify(token) do
      {:ok, username} -> conn |> put_session("username", username) |> redirect(to: "/lobby")
      :error -> redirect(conn, to: "/")
    end
  end

  def delete(conn, _params), do: conn |> configure_session(drop: true) |> redirect(to: "/")
end
