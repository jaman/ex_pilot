defmodule Mix.Tasks.ExPilot.Admin do
  @shortdoc "Make an account an admin of the server, or revoke it"
  @moduledoc """
  Give an account the admin page (`/admin` in the browser): the sessions and arenas
  running, every account with the name it is seen under, what happened lately, and the
  actions on them.

      mix ex_pilot.admin alice
      mix ex_pilot.admin alice --revoke

  The account file belongs to one process at a time: stop the server first, or the task
  says the file is held. A running server's admin page can grant and revoke as well.

  ## Options

    * `--revoke` — take the admin page away instead
    * `--accounts PATH` — the account file; default `ExPilot.Server.accounts_path/0`
  """

  use Mix.Task

  alias Drafter.Accounts
  alias ExPilot.Web.Auth

  @impl Mix.Task
  def run(args) do
    {opts, names} = OptionParser.parse!(args, strict: [revoke: :boolean, accounts: :string])
    username = List.first(names) || Mix.raise("which account? mix ex_pilot.admin NAME")
    Mix.Task.run("app.config")
    path = Keyword.get_lazy(opts, :accounts, &ExPilot.Server.accounts_path/0)
    admin? = not Keyword.get(opts, :revoke, false)

    case Accounts.start_link(path: path, name: ExPilot.Accounts) do
      {:ok, _accounts} ->
        granted(Auth.put_admin(username, admin?), username, admin?)

      {:error, reason} ->
        Mix.raise(
          "the account file could not be opened (is the server running?): #{inspect(reason)}"
        )
    end
  end

  defp granted(:ok, username, true), do: Mix.shell().info("#{username} is an admin")
  defp granted(:ok, username, false), do: Mix.shell().info("#{username} is no longer an admin")

  defp granted({:error, :unknown}, username, _admin?),
    do: Mix.raise("no account is called #{username}")
end
