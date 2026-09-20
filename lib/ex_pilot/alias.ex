defmodule ExPilot.Alias do
  @moduledoc """
  The name other pilots see an account under.

  An account is seen under the alias it chose, or, while it has chosen none, under an
  anonymous name made from the username — two words and a number, the same on every
  visit and different for every account, and not to be worked back to the username.
  Only the player and an admin see the username itself.

      ExPilot.Alias.of("alice")
      #=> "amber-falcon-27"
      ExPilot.Alias.put("alice", "Ace")
      ExPilot.Alias.of("alice")
      #=> "Ace"
      ExPilot.Alias.label("alice")
      #=> "alice (Ace)"

  Aliases live in the account's props under `:alias` in `ExPilot.Accounts`. The anonymous
  names are derived with the web endpoint's `secret_key_base`, so they change if that
  does. Without an accounts server running — a client with no server behind it — a
  username is seen as itself.
  """

  alias Drafter.Accounts

  @type username :: String.t()

  @pattern ~r/\A[A-Za-z0-9 _-]{1,32}\z/
  @adjectives ~w(amber ashen azure bold brass brisk clear cobalt coral crimson dusky ember frost gilded hazel iron ivory jade keen lunar misty noble ochre onyx pale quiet rapid rust sable silver slate solar tawny umber vivid wild)
  @nouns ~w(falcon heron osprey kestrel condor raven swift gannet petrel skua tern wren finch lark magpie plover crane egret ibis kite owl hawk eagle stork gull auk loon rook jay dove martin swan)

  @doc "The name `username` is seen under: its chosen alias, else its anonymous name."
  @spec of(username()) :: String.t()
  def of(username) do
    cond do
      not accounts?() -> username
      chosen = chosen(username) -> chosen
      true -> anonymous(username)
    end
  end

  @doc "Whether `username` has chosen an alias."
  @spec chosen?(username()) :: boolean()
  def chosen?(username), do: chosen(username) != nil

  @doc "The player's own view of their name: the username, and after it in parentheses how others see them when that differs."
  @spec label(username()) :: String.t()
  def label(username) do
    case of(username) do
      ^username -> username
      seen_as -> "#{username} (#{seen_as})"
    end
  end

  @doc """
  Choose an alias for `username`; blank gives it up. `{:error, :invalid}` outside one to
  thirty-two letters, digits, spaces, underscores and dashes; `{:error, :taken}` when
  another account is seen under it or is named by it, in any case.
  """
  @spec put(username(), String.t()) :: :ok | {:error, :invalid | :taken | term()}
  def put(username, alias) do
    alias = String.trim(alias)

    cond do
      alias == "" -> Accounts.put_props(ExPilot.Accounts, username, %{alias: ""})
      not Regex.match?(@pattern, alias) -> {:error, :invalid}
      taken?(username, alias) -> {:error, :taken}
      true -> Accounts.put_props(ExPilot.Accounts, username, %{alias: alias})
    end
  end

  @doc "The account seen under `name` — an alias or an anonymous name, in any case — or `nil`; a username finds nothing."
  @spec resolve(String.t()) :: username() | nil
  def resolve(name) do
    wanted = String.downcase(String.trim(name))

    Enum.find_value(accounts(), fn %{username: username} ->
      if String.downcase(of(username)) == wanted, do: username
    end)
  end

  @doc "The anonymous name for `username`, whatever alias it has chosen."
  @spec anonymous(username()) :: String.t()
  def anonymous(username) do
    <<a, n, number::16, _::binary>> =
      :crypto.mac(:hmac, :sha256, salt(), String.downcase(username))

    Enum.at(@adjectives, rem(a, length(@adjectives))) <>
      "-" <> Enum.at(@nouns, rem(n, length(@nouns))) <> "-" <> two_digits(rem(number, 100))
  end

  defp two_digits(n), do: n |> Integer.to_string() |> String.pad_leading(2, "0")

  defp chosen(username) do
    case Accounts.fetch(ExPilot.Accounts, username) do
      {:ok, %{props: %{alias: alias}}} when is_binary(alias) and alias != "" -> alias
      {:ok, %{props: %{nickname: alias}}} when is_binary(alias) and alias != "" -> alias
      _ -> nil
    end
  end

  defp taken?(username, alias) do
    wanted = String.downcase(alias)
    mine = String.downcase(username)

    Enum.any?(accounts(), fn %{username: other} ->
      String.downcase(other) != mine and
        (String.downcase(other) == wanted or String.downcase(of(other)) == wanted or
           anonymous(other) == wanted)
    end)
  end

  defp accounts, do: Accounts.list(ExPilot.Accounts)

  defp accounts?, do: Process.whereis(ExPilot.Accounts) != nil

  defp salt do
    Application.get_env(:ex_pilot, ExPilot.Web.Endpoint, [])
    |> Keyword.get(:secret_key_base, "ex_pilot")
  end
end
