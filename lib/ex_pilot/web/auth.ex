defmodule ExPilot.Web.Auth do
  @moduledoc """
  Who a browser player is: login against the server's `Drafter.Accounts`, the signed
  token a page hands its socket, and what the account keeps: sound levels and touch
  controls by kind of client, and the ship shape and the controller bindings every
  client uses. The name a player is seen under is `ExPilot.Alias`'s.

  The accounts server is `ExPilot.Accounts`, as `ExPilot.Server.start/1` names it.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Cauldron2D.Drafter.Client.Settings
  alias Cauldron2D.Sessions
  alias Drafter.Accounts
  alias ExPilot.{Padmap, Shipshape}
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

  @typedoc "How a phone or tablet is played: the hand the thumbstick is on, whether tilting the device steers, and whether the tilt's forward and back are inverted."
  @type controls :: %{side: :left | :right, tilt: boolean(), invert: boolean()}

  @doc "The account's touch controls for a kind of client (`:web` unless given): the stick on the `:left` unless moved, `tilt` and `invert` off unless switched on."
  @spec controls(String.t(), atom()) :: controls()
  def controls(username, kind \\ :web) do
    settings = settings(username, kind)

    %{
      side: side(Map.get(settings, :side)),
      tilt: Map.get(settings, :tilt) == true,
      invert: Map.get(settings, :invert) == true
    }
  end

  @doc "Keep the account's touch controls for a kind of client, alongside whatever else that kind's settings hold."
  @spec put_controls(String.t(), controls(), atom()) :: :ok | {:error, term()}
  def put_controls(username, %{side: side, tilt: tilt} = controls, kind \\ :web)
      when side in [:left, :right] and is_boolean(tilt) do
    key = Settings.prop_key(kind)
    invert = Map.get(controls, :invert, false) == true

    Accounts.put_props(ExPilot.Accounts, username, %{
      key => Map.merge(settings(username, kind), %{side: side, tilt: tilt, invert: invert})
    })
  end

  @doc "The account's ship shape in XPilot's notation, or `nil` for the classic; `nil` too without an accounts server."
  @spec shipshape(String.t()) :: String.t() | nil
  def shipshape(username) do
    with true <- Process.whereis(ExPilot.Accounts) != nil,
         {:ok, %{props: %{shipshape: shape}}} when is_binary(shape) and shape != "" <-
           Accounts.fetch(ExPilot.Accounts, username) do
      shape
    else
      _ -> nil
    end
  end

  @doc "Keep the account's ship shape; blank goes back to the classic, and a text with no outline is `{:error, :no_outline}`."
  @spec put_shipshape(String.t(), String.t()) :: :ok | {:error, term()}
  def put_shipshape(username, text) do
    case String.trim(text) do
      "" ->
        Accounts.put_props(ExPilot.Accounts, username, %{shipshape: nil})

      shape ->
        with {:ok, _parsed} <- Shipshape.parse(shape),
             do: Accounts.put_props(ExPilot.Accounts, username, %{shipshape: shape})
    end
  end

  @doc "The account's own controller bindings, action to controls, over `ExPilot.Padmap.default/0`; `%{}` where it keeps none, or without an accounts server."
  @spec padmap(String.t()) :: Padmap.overrides()
  def padmap(username) do
    with true <- Process.whereis(ExPilot.Accounts) != nil,
         {:ok, %{props: %{padmap: props}}} <- Accounts.fetch(ExPilot.Accounts, username) do
      Padmap.from_props(props)
    else
      _ -> %{}
    end
  end

  @doc "Keep the account's controller bindings — action names to their controls as `ExPilot.Padmap.parse_controls/1` reads them, only those that differ from the default; `{:error, {action, {:unknown, word}}}` at the first word that is no control, keeping nothing."
  @spec put_padmap(String.t(), %{String.t() => String.t()}) ::
          :ok | {:error, {String.t(), {:unknown, String.t()}}}
  def put_padmap(username, fields) do
    known = Map.new(Padmap.actions(), &{Atom.to_string(&1), &1})

    fields
    |> Enum.filter(fn {name, _text} -> Map.has_key?(known, name) end)
    |> Enum.reduce_while({:ok, %{}}, fn {name, text}, {:ok, acc} ->
      case Padmap.parse_controls(text) do
        {:ok, controls} -> {:cont, {:ok, Map.put(acc, Map.fetch!(known, name), controls)}}
        {:error, reason} -> {:halt, {:error, {name, reason}}}
      end
    end)
    |> case do
      {:ok, bindings} ->
        Accounts.put_props(ExPilot.Accounts, username, %{
          padmap: bindings |> Padmap.overrides() |> Padmap.to_props()
        })

      error ->
        error
    end
  end

  @doc "Forget the account's controller bindings, back to the default."
  @spec reset_padmap(String.t()) :: :ok | {:error, term()}
  def reset_padmap(username),
    do: Accounts.put_props(ExPilot.Accounts, username, %{padmap: nil})

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

  defp side(:right), do: :right
  defp side(_left), do: :left

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
