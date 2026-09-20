defmodule Mix.Tasks.ExPilot.Ledger do
  @shortdoc "Tend ExPilot's ledger: forget results by name"

  @moduledoc """
  Open the ledger at `$XDG_DATA_HOME/expilot/ledger.dets` and forget the results of every
  name matching a pattern, `*` standing for any run of characters. The load tool's
  accounts are `load_1`, `load_2` and so on.

      mix ex_pilot.ledger --forget "load_*"

  The ledger belongs to one process at a time: stop the server first, or the task says
  the file is held.

  ## Options

    * `--forget` — the pattern of names to forget. Required
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: [forget: :string])

    pattern =
      Keyword.get(opts, :forget) || Mix.raise("--forget PATTERN says which names to forget")

    Mix.Task.run("app.config")
    path = Application.get_env(:ex_pilot, :ledger, ExPilot.Ledger.path())

    with nil <- Cauldron2D.Ledger.holder(path),
         {:ok, _ledger} <-
           Cauldron2D.Ledger.start_link(
             name: ExPilot.Ledger,
             path: path,
             metrics: ExPilot.Ledger.metrics_spec()
           ),
         {:ok, gone} <- ExPilot.Ledger.forget(pattern) do
      Mix.shell().info(
        "forgot #{gone} results of #{pattern}; #{Cauldron2D.Ledger.count(ExPilot.Ledger)} remain"
      )
    else
      pid when is_integer(pid) ->
        Mix.raise("the ledger #{path} is held by process #{pid}; stop the server first")

      {:error, reason} ->
        Mix.raise("the ledger could not be tended: #{inspect(reason)}")
    end
  end
end
