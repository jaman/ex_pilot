defmodule ExPilot.Arenas.OnDemand do
  @moduledoc """
  The name registry behind `ExPilot.Arenas.world_name/1`: `{:via, ExPilot.Arenas.OnDemand, id}`
  resolves to arena `id`'s world, starting it — robots and all — when it is not running.

  Worlds register under `{:world, id}` in `ExPilot.Registry` directly; a lookup here that
  finds nothing there calls `ExPilot.Arenas.start/1`. An id no arena is registered for
  resolves to `:undefined`.
  """

  alias ExPilot.Arenas

  @doc false
  @spec register_name(Arenas.id(), pid()) :: :yes | :no
  def register_name(id, pid), do: Registry.register_name({ExPilot.Registry, {:world, id}}, pid)

  @doc false
  @spec unregister_name(Arenas.id()) :: :ok
  def unregister_name(id), do: Registry.unregister_name({ExPilot.Registry, {:world, id}})

  @doc false
  @spec whereis_name(Arenas.id()) :: pid() | :undefined
  def whereis_name(id) do
    case Arenas.running(id) do
      nil -> started(id)
      pid -> pid
    end
  end

  @doc false
  @spec send(Arenas.id(), term()) :: term()
  def send(id, message) do
    case whereis_name(id) do
      :undefined -> :erlang.error(:badarg, [id, message])
      pid -> Kernel.send(pid, message)
    end
  end

  defp started(id) do
    case Arenas.start(id) do
      {:ok, pid} -> pid
      {:error, _reason} -> :undefined
    end
  end
end
