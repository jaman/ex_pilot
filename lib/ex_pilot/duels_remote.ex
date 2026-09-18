defmodule ExPilot.Duels.Remote do
  @moduledoc """
  A challenge sent to another ExPilot server over its API (`POST <url>/duel`), and a
  duel there declined or withdrawn (`POST <url>/duel/cancel`).

      {:ok, duel} = ExPilot.Duels.Remote.challenge("http://arcade:2280/api", token, "bob", "dogfight", 5)
      :ok = ExPilot.Duels.Remote.cancel("http://arcade:2280/api", token, duel.id)

  `url` is the server's API, `token` one from `Cauldron2D.Net.Remote.login/4`, `arena`
  the name of the arena the duel borrows its map from. The duel comes back as
  `ExPilot.Duels` describes it with string keys turned to atoms and its arena a string;
  `{:error, text}` carries the server's reason.
  """

  @spec challenge(String.t(), String.t(), String.t(), String.t(), pos_integer()) ::
          {:ok, map()} | {:error, String.t()}
  def challenge(url, token, to, arena, first_to) do
    with {:ok, duel} <-
           post(url <> "/duel", %{token: token, to: to, arena: arena, first_to: first_to}) do
      {:ok, Map.new(duel, fn {key, value} -> {String.to_atom(key), value} end)}
    end
  end

  @doc "Decline or withdraw duel `id` on the server at `url`, as the token's pilot (`POST <url>/duel/cancel`)."
  @spec cancel(String.t(), String.t(), pos_integer()) :: :ok | {:error, String.t()}
  def cancel(url, token, id) do
    with {:ok, _} <- post(url <> "/duel/cancel", %{token: token, id: id}), do: :ok
  end

  defp post(url, body) do
    :inets.start()
    :ssl.start()
    request = {String.to_charlist(url), [], ~c"application/json", Jason.encode!(body)}

    case :httpc.request(:post, request, [ssl: [verify: :verify_none], timeout: 10_000],
           body_format: :binary
         ) do
      {:ok, {{_, 200, _}, _headers, response}} ->
        {:ok, Jason.decode!(response)}

      {:ok, {{_, _status, _}, _headers, response}} ->
        {:error, response |> Jason.decode!() |> Map.get("error", response)}

      {:error, reason} ->
        {:error, "no answer from #{url}: #{inspect(reason)}"}
    end
  end
end
