defmodule ExPilot.Application do
  @moduledoc false

  use Application

  alias ExPilot.Music.Instruments

  @impl true
  def start(_type, _args) do
    children = [
      ExPilot.Ledger,
      {Cauldron2D.Beacon.Listener, game: :ex_pilot},
      ExPilot.Duels,
      {Phoenix.PubSub, name: ExPilot.Web.PubSub}
    ]

    Instruments.register()
    Cauldron2D.Audio.Music.prefetch(ExPilot.Music.pieces())
    Supervisor.start_link(children, strategy: :one_for_one, name: ExPilot.Supervisor)
  end
end
