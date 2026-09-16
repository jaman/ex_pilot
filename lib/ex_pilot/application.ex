defmodule ExPilot.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: ExPilot.Registry},
      ExPilot.Arenas.Table,
      {DynamicSupervisor, name: ExPilot.ArenaSupervisor, strategy: :one_for_one},
      ExPilot.Arenas.Sweeper,
      {Phoenix.PubSub, name: ExPilot.Web.PubSub},
      {DynamicSupervisor, name: ExPilot.WebSupervisor, strategy: :one_for_one}
    ]

    Cauldron2D.Audio.Music.prefetch(ExPilot.Music.pieces())
    Supervisor.start_link(children, strategy: :one_for_one, name: ExPilot.Supervisor)
  end
end
