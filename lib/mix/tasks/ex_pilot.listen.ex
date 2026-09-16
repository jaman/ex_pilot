defmodule Mix.Tasks.ExPilot.Listen do
  @shortdoc "Play a served game's sound on this machine"

  @moduledoc """
  Play the sound of an ExPilot session served elsewhere through this machine's speaker:
  run it here, then connect with `ssh -R <your port>:127.0.0.1:4713 …`.

      mix ex_pilot.listen
      mix ex_pilot.listen --port 4713

  Runs until stopped with Ctrl-C. The same as `mix tuning_fork.listen`.
  """

  use Mix.Task

  @impl Mix.Task
  def run(args), do: Mix.Task.run("tuning_fork.listen", args)
end
