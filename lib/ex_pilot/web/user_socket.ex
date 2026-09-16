defmodule ExPilot.Web.UserSocket do
  @moduledoc """
  The player socket: a browser connects with the token its page was given at login,
  and its channels carry the player's name and sound levels.
  """

  use Phoenix.Socket

  alias ExPilot.Web.Auth

  channel "arena:*", ExPilot.Web.ArenaChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case Auth.verify(token) do
      {:ok, username} -> {:ok, socket |> assign(:username, username) |> assign(:settings, Auth.levels(username)) |> assign(:sheet_url, "/atlas.png")}
      :error -> :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "player:" <> socket.assigns.username
end
