defmodule ExPilot.Web.ApiController do
  @moduledoc """
  ExPilot's own API beside `Cauldron2D.Net.Api` (which serves the token, the arenas,
  the stats and the leaders under `/api`): the duels (`GET /api/duels`; `POST
  /api/duel` with a `token`, `to`, `arena` and `first_to` to challenge someone; `POST
  /api/duel/cancel` with a `token` and the duel's `id` to decline or withdraw it).
  """

  use Phoenix.Controller, formats: [:json]

  import Plug.Conn

  alias ExPilot.{Arenas, Duels, Web.Auth}

  def duels(conn, _params),
    do:
      json(
        conn,
        Enum.map(Duels.list(), &Map.update!(&1, :at, fn at -> DateTime.to_iso8601(at) end))
      )

  def duel(conn, %{"token" => token, "to" => to, "arena" => arena} = params) do
    with {:ok, from} <- Auth.verify(token),
         {:ok, base} <- arena_id(arena),
         {:ok, duel} <- Duels.challenge(from, to, base, first_to: first_to(params)) do
      json(conn, Map.update!(duel, :at, &DateTime.to_iso8601/1))
    else
      :error -> conn |> put_status(401) |> json(%{error: "no such token"})
      {:error, reason} -> conn |> put_status(422) |> json(%{error: Atom.to_string(reason)})
    end
  end

  def duel(conn, _params),
    do: conn |> put_status(422) |> json(%{error: "token, to and arena are needed"})

  def cancel(conn, %{"token" => token, "id" => id}) do
    with {:ok, from} <- Auth.verify(token),
         {:ok, id} <- duel_id(id),
         :ok <- Duels.cancel(id, from) do
      json(conn, %{ok: true})
    else
      :error -> conn |> put_status(401) |> json(%{error: "no such token"})
      {:error, reason} -> conn |> put_status(422) |> json(%{error: Atom.to_string(reason)})
    end
  end

  def cancel(conn, _params),
    do: conn |> put_status(422) |> json(%{error: "token and id are needed"})

  defp duel_id(id) when is_integer(id), do: {:ok, id}

  defp duel_id(text) when is_binary(text),
    do:
      case(Integer.parse(text),
        do: (
          {id, ""} -> {:ok, id}
          _ -> {:error, :unknown}
        )
      )

  defp arena_id(name) do
    case Enum.find(Arenas.list(), &(&1.name == name)) do
      nil -> {:error, :unknown_arena}
      arena -> {:ok, arena.id}
    end
  end

  defp first_to(%{"first_to" => n}) when is_integer(n) and n > 0, do: n

  defp first_to(%{"first_to" => text}) when is_binary(text),
    do:
      case(Integer.parse(text),
        do: (
          {n, ""} when n > 0 -> n
          _ -> 5
        )
      )

  defp first_to(_params), do: 5
end
