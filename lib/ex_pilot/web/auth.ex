defmodule ExPilot.Web.Auth do
  @moduledoc """
  Who a browser player is: login against the server's `Drafter.Accounts`, the signed
  token a page hands its socket, and the sound levels kept in the account. The name a
  player is seen under is `ExPilot.Alias`'s.

  The accounts server is `ExPilot.Accounts`, as `ExPilot.Server.start/1` names it.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Cauldron2D.Drafter.Client.Settings
  alias Cauldron2D.Sessions
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

  @doc "The account's sound levels for a kind of client (`:web` unless given), `%{sfx: level, music: level}`, with the defaults where unset."
  @spec levels(String.t(), atom()) :: %{sfx: float(), music: float()}
  def levels(username, kind \\ :web) do
    settings = settings(username, kind)
    %{sfx: Map.get(settings, :sfx, 0.85), music: Map.get(settings, :music, 0.35)}
  end

  @doc "Keep the account's sound levels for a kind of client, alongside whatever else that kind's settings hold."
  @spec put_levels(String.t(), number(), number(), atom()) :: :ok | {:error, term()}
  def put_levels(username, sfx, music, kind \\ :web) do
    key = Settings.prop_key(kind)

    Accounts.put_props(ExPilot.Accounts, username, %{
      key => Map.merge(settings(username, kind), %{sfx: sfx / 1, music: music / 1})
    })
  end

  @doc "What `Cauldron2D.Net.Socket` asks of the connect params: the token's pilot and their sound levels for the kind of client."
  @spec connect(map()) :: {:ok, %{username: String.t(), settings: map()}} | :error
  def connect(%{"token" => token} = params) do
    case verify(token) do
      {:ok, username} ->
        {:ok, %{username: username, settings: levels(username, kind(params["kind"]))}}

      :error ->
        :error
    end
  end

  def connect(_params), do: :error

  @doc "The kind of client a connect or join param names: `\"touch\"` is `:touch`, anything else `:web`."
  @spec kind(term()) :: :web | :touch
  def kind("touch"), do: :touch
  def kind(_other), do: :web

  defp track(socket, username) do
    kind = socket |> Phoenix.LiveView.get_connect_params() |> Map.get("kind") |> kind()
    Sessions.track(username, kind)
  end

  defp settings(username, kind) do
    key = Settings.prop_key(kind)

    case Accounts.fetch(ExPilot.Accounts, username) do
      {:ok, %{props: props}} -> Map.get(props, key, %{})
      _ -> %{}
    end
  end

  @doc "Whether the account is an admin: `admin: true` among its props, given with `put_admin/2` or `mix ex_pilot.admin`."
  @spec admin?(String.t()) :: boolean()
  def admin?(username) do
    match?({:ok, %{props: %{admin: true}}}, Accounts.fetch(ExPilot.Accounts, username))
  end

  @doc "Make the account an admin, or not."
  @spec put_admin(String.t(), boolean()) :: :ok | {:error, term()}
  def put_admin(username, admin?) when is_boolean(admin?),
    do: Accounts.put_props(ExPilot.Accounts, username, %{admin: admin?})

  @doc """
  The `on_mount` hooks of the pages: `:require` puts the session's username and whether
  they are an admin in the socket, lists the page in `Cauldron2D.Sessions` under the
  kind of client, or sends a stranger back to the login; `:admin` also turns away a
  player who is not an admin, to the lobby.
  """
  def on_mount(:require, _params, session, socket) do
    case session do
      %{"username" => username} when is_binary(username) ->
        if Phoenix.LiveView.connected?(socket), do: track(socket, username)
        {:cont, socket |> assign(:username, username) |> assign(:admin?, admin?(username))}

      _ ->
        {:halt, Phoenix.LiveView.redirect(socket, to: "/")}
    end
  end

  def on_mount(:admin, params, session, socket) do
    with {:cont, socket} <- on_mount(:require, params, session, socket) do
      if admin?(socket.assigns.username),
        do: {:cont, socket},
        else: {:halt, Phoenix.LiveView.redirect(socket, to: "/lobby")}
    end
  end
end
