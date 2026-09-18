defmodule ExPilot.Ledger do
  @moduledoc """
  ExPilot's results in `Cauldron2D.Ledger`, kept at
  `$XDG_DATA_HOME/expilot/ledger.dets` beside the accounts, with the metrics its boards
  rank by: kills, kills a death, rounds won, the best streak of kills without dying,
  the longest contact (seconds alive with an enemy within thirty tiles) and laps.

      ExPilot.Ledger.board(:week, :kills, arena: "Arena")
      ExPilot.Ledger.forget("load_*")

  The process is named `ExPilot.Ledger` and started with the application; every arena's
  recorder writes to it. `mix ex_pilot.ledger --forget load_*` forgets results from the
  command line, on a ledger no server holds.
  """

  alias Cauldron2D.{Ledger, Paths}

  @metrics [
    kills: {:sum, :kills},
    ratio: {:ratio, :kills, :deaths},
    wins: {:count, :won?},
    streak: {:max, :best_streak},
    contact: {:max, :best_contact},
    laps: {:sum, :laps}
  ]

  @doc false
  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start:
        {Ledger, :start_link,
         [
           [
             name: __MODULE__,
             path: Application.get_env(:ex_pilot, :ledger, path()),
             metrics: @metrics
           ]
         ]}
    }
  end

  @doc "The metrics as `Cauldron2D.Ledger` is started with them."
  @spec metrics_spec() :: keyword()
  def metrics_spec, do: @metrics

  @doc "The metrics, in the order the boards offer them, with their titles."
  @spec metrics() :: [{Ledger.metric(), String.t()}]
  def metrics,
    do: [
      kills: "kills",
      ratio: "kills a death",
      wins: "rounds won",
      streak: "best streak",
      contact: "longest contact",
      laps: "laps"
    ]

  @doc "Where the ledger lives: `$XDG_DATA_HOME/expilot/ledger.dets`."
  @spec path() :: Path.t()
  def path, do: Paths.data(:expilot, "ledger.dets")

  @doc "The board of `period` by `metric`; `arena:` narrows it to one arena."
  @spec board(Ledger.period(), Ledger.metric(), keyword()) :: [Ledger.entry()]
  def board(period, metric, opts \\ []), do: Ledger.board(__MODULE__, period, metric, opts)

  @doc "Drop every result of a name matching `pattern` — `*` stands for any run of characters, as in `load_*` for the load tool's accounts — and say how many went."
  @spec forget(String.t()) :: non_neg_integer()
  def forget(pattern) do
    regex = ~r/^#{pattern |> String.split("*") |> Enum.map_join(".*", &Regex.escape/1)}$/
    Ledger.forget(__MODULE__, &Regex.match?(regex, &1.name))
  end

  @doc "A board value as text: seconds for contact, two decimals for a ratio, whole numbers otherwise."
  @spec value(number(), Ledger.metric()) :: String.t()
  def value(seconds, :contact), do: "#{seconds} s"
  def value(ratio, :ratio), do: :erlang.float_to_binary(ratio / 1, decimals: 2)
  def value(count, _metric), do: Integer.to_string(round(count))
end
