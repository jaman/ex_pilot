defmodule ExPilot.Web.LoginLive do
  @moduledoc "Log in, or make an account, against the server's accounts."

  use Phoenix.LiveView

  alias ExPilot.Web.Auth

  @impl true
  def mount(_params, %{"username" => username}, socket) when is_binary(username),
    do: {:ok, push_navigate(socket, to: "/lobby")}

  def mount(_params, _session, socket), do: {:ok, assign(socket, error: nil, registering: false)}

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
  def handle_event("toggle", _params, socket),
    do: {:noreply, assign(socket, registering: not socket.assigns.registering, error: nil)}

  def handle_event("login", %{"username" => username, "password" => password}, socket),
    do: logged_in(Auth.login(username, password), socket)

  def handle_event("register", %{"password" => password, "again" => again}, socket)
      when password != again,
      do: {:noreply, assign(socket, error: "the passwords differ")}

  def handle_event("register", %{"username" => username, "password" => password}, socket),
    do: registered(Auth.register(username, password), socket)

  defp logged_in({:ok, name}, socket), do: {:noreply, to_session(socket, name)}

  defp logged_in(:error, socket),
    do: {:noreply, assign(socket, error: "no such name and password")}

  defp registered({:ok, name}, socket), do: {:noreply, to_session(socket, name)}

  defp registered({:error, reason}, socket),
    do: {:noreply, assign(socket, error: refused(reason))}

  defp refused(:taken), do: "that name is taken"
  defp refused(:invalid_username), do: "a name is 1 to 32 letters, digits, _ or -"
  defp refused(:weak_password), do: "a password is at least 8 characters"

  defp to_session(socket, name), do: redirect(socket, to: "/session?token=" <> Auth.token(name))
end
