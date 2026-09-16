defmodule ExPilot.Web.Auth do
  @moduledoc """
  Who a browser player is: login against the server's `Drafter.Accounts`, the signed
  token a page hands its socket, and the sound levels kept in the account.

  The accounts server is `ExPilot.Accounts`, as `ExPilot.Server.start/1` names it.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Drafter.Accounts
  alias ExPilot.Web.Endpoint

  @salt "ex_pilot_player"
  @day 86_400

  @doc "Check a name and password; `{:ok, username}` in the account's spelling."
  @spec login(String.t(), String.t()) :: {:ok, String.t()} | :error
  def login(username, password) do
    case Accounts.authenticate(ExPilot.Accounts, username, password) do
      {:ok, %{username: name}} -> {:ok, name}
      _ -> :error
    end
  end

  @doc "Create an account; `{:ok, username}` or `{:error, reason}` as `Drafter.Accounts.register/4` gives it."
  @spec register(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def register(username, password) do
    case Accounts.register(ExPilot.Accounts, username, password) do
      :ok -> {:ok, username}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "A token naming `username`, good for a day."
  @spec token(String.t()) :: String.t()
  def token(username), do: Phoenix.Token.sign(Endpoint, @salt, username)

  @doc "The username a token names."
  @spec verify(String.t()) :: {:ok, String.t()} | :error
  def verify(token) do
    case Phoenix.Token.verify(Endpoint, @salt, token, max_age: @day) do
      {:ok, username} -> {:ok, username}
      _ -> :error
    end
  end

  @doc "The account's sound levels, `%{sfx: level, music: level}`, with the defaults where unset."
  @spec levels(String.t()) :: %{sfx: float(), music: float()}
  def levels(username) do
    settings =
      case Accounts.fetch(ExPilot.Accounts, username) do
        {:ok, %{props: %{settings: %{} = settings}}} -> settings
        _ -> %{}
      end

    %{sfx: Map.get(settings, :sfx, 0.85), music: Map.get(settings, :music, 0.35)}
  end

  @doc "Keep the account's sound levels, alongside whatever else its settings hold."
  @spec put_levels(String.t(), number(), number()) :: :ok | {:error, term()}
  def put_levels(username, sfx, music) do
    settings =
      case Accounts.fetch(ExPilot.Accounts, username) do
        {:ok, %{props: %{settings: %{} = settings}}} -> settings
        _ -> %{}
      end

    Accounts.put_props(ExPilot.Accounts, username, %{settings: Map.merge(settings, %{sfx: sfx / 1, music: music / 1})})
  end

  @doc "The `on_mount` hook of the player's pages: the session's username, or back to the login."
  def on_mount(:require, _params, session, socket) do
    case session do
      %{"username" => username} when is_binary(username) -> {:cont, assign(socket, :username, username)}
      _ -> {:halt, Phoenix.LiveView.redirect(socket, to: "/")}
    end
  end
end
