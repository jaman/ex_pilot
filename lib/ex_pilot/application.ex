defmodule ExPilot.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: ExPilot.Registry},
      {DynamicSupervisor, name: ExPilot.ArenaSupervisor, strategy: :one_for_one}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: ExPilot.Supervisor)
  end
end
