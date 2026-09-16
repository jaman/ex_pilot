defmodule ExPilot.Arenas.Table do
  @moduledoc """
  The registered arenas, one small record each, in an ETS table this process owns.

      ExPilot.Arenas.Table.put(:dogfight, %{id: :dogfight, name: "Dogfight", opts: [], note: "", teams: []})
      ExPilot.Arenas.Table.all()
  """

  use GenServer

  @table __MODULE__

  @doc false
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Record arena `id`."
  @spec put(ExPilot.Arenas.id(), map()) :: :ok
  def put(id, record) do
    :ets.insert(@table, {id, record})
    :ok
  end

  @doc "The record of arena `id`, or `nil`."
  @spec get(ExPilot.Arenas.id()) :: map() | nil
  def get(id) do
    case :ets.lookup(@table, id) do
      [{_id, record}] -> record
      [] -> nil
    end
  end

  @doc "Every arena's record."
  @spec all() :: [map()]
  def all, do: for({_id, record} <- :ets.tab2list(@table), do: record)

  @doc "Forget arena `id`."
  @spec delete(ExPilot.Arenas.id()) :: :ok
  def delete(id) do
    :ets.delete(@table, id)
    :ok
  end

  @impl GenServer
  def init(_opts) do
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    {:ok, %{}}
  end
end
