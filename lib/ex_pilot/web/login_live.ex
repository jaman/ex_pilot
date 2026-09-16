defmodule ExPilot.Web.LoginLive do
  @moduledoc "Log in, or make an account, against the server's accounts."

  use Phoenix.LiveView

  alias ExPilot.Web.Auth

  @impl true
  def mount(_params, session, socket) do
    case session do
      %{"username" => username} when is_binary(username) -> {:ok, push_navigate(socket, to: "/lobby")}
      _ -> {:ok, assign(socket, error: nil, registering: false)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="centre">
      <div class="card login">
        <h1 class="wordmark">EXPILOT<small>an XPilot for the browser and the terminal, on the same worlds</small></h1>
        <form phx-submit={if @registering, do: "register", else: "login"}>
          <label class="field"><span>pilot</span><input type="text" name="username" autocomplete="username" required autofocus /></label>
          <label class="field"><span>password</span><input type="password" name="password" autocomplete={if @registering, do: "new-password", else: "current-password"} required /></label>
          <label :if={@registering} class="field"><span>password again</span><input type="password" name="again" autocomplete="new-password" required /></label>
          <p :if={@error} class="error" style="margin: 0">{@error}</p>
          <div class="row" style="margin-top: 6px">
            <button type="submit" class="btn btn-primary">{if @registering, do: "create account", else: "launch"}</button>
            <button type="button" class="btn btn-ghost" phx-click="toggle">{if @registering, do: "I have an account", else: "new here?"}</button>
          </div>
        </form>
        <p class="foot dim">over ssh instead: <code>ssh -p 2222 new@host</code></p>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("toggle", _params, socket), do: {:noreply, assign(socket, registering: not socket.assigns.registering, error: nil)}

  def handle_event("login", %{"username" => username, "password" => password}, socket) do
    case Auth.login(username, password) do
      {:ok, name} -> {:noreply, redirect(socket, to: "/session?token=" <> Auth.token(name))}
      :error -> {:noreply, assign(socket, error: "no such name and password")}
    end
  end

  def handle_event("register", %{"username" => username, "password" => password, "again" => again}, socket) do
    cond do
      password != again ->
        {:noreply, assign(socket, error: "the passwords differ")}

      true ->
        case Auth.register(username, password) do
          {:ok, name} -> {:noreply, redirect(socket, to: "/session?token=" <> Auth.token(name))}
          {:error, :taken} -> {:noreply, assign(socket, error: "that name is taken")}
          {:error, :invalid_username} -> {:noreply, assign(socket, error: "a name is 1 to 32 letters, digits, _ or -")}
          {:error, :weak_password} -> {:noreply, assign(socket, error: "a password is at least 8 characters")}
        end
    end
  end
end
