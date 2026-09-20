defmodule ExPilot.Ledger do
  @moduledoc """
  ExPilot's results in `Cauldron2D.Ledger`, kept at
  `$XDG_DATA_HOME/expilot/ledger.dets` beside the accounts, with the metrics its boards
  rank by: kills, kills a death, rounds won, the best streak of kills without dying,
  the longest contact (seconds alive with an enemy within thirty tiles) and laps.

      ExPilot.Ledger.board(:week, :kills, arena: "Arena")
      ExPilot.Ledger.forget("load_*")

  The process is named `ExPilot.Ledger` and started with the application; every arena's
  recorder writes to it. The file belongs to one operating system process at a time:
  while another holds it, this one keeps nothing, `held/0` names the holder, and
  `ExPilot.Server.start/1` refuses to serve. `mix ex_pilot.ledger --forget load_*`
  forgets results from the command line, on a ledger no server holds.
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
  def child_spec(_opts), do: %{id: __MODULE__, start: {__MODULE__, :start_link, []}}

  @doc "Start the ledger named `ExPilot.Ledger` on the file configured as `:ex_pilot, :ledger`, else `path/0`; idle while another process holds it."
  @spec start_link() :: GenServer.on_start()
  def start_link do
    Ledger.start_link(
      name: __MODULE__,
      path: Application.get_env(:ex_pilot, :ledger, path()),
      metrics: @metrics,
      held: :idle
    )
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

  @doc "The operating system process holding the ledger file, `{:held, pid}`, or nil when this one does."
  @spec held() :: {:held, pos_integer()} | nil
  def held do
    case Ledger.access(__MODULE__) do
      :read_write -> nil
      held -> held
    end
  end

  @doc "Drop every result of a name matching `pattern` — `*` stands for any run of characters, as in `load_*` for the load tool's accounts — and say how many went."
  @spec forget(String.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def forget(pattern) do
    regex = ~r/^#{pattern |> String.split("*") |> Enum.map_join(".*", &Regex.escape/1)}$/
    Ledger.forget(__MODULE__, &Regex.match?(regex, &1.name))
  end

  @doc "Drop every result of the account `username`, whatever name it played under, and say how many went."
  @spec forget_account(String.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def forget_account(username), do: Ledger.forget(__MODULE__, &(&1.id == username))

  @doc "A board value as text: seconds for contact, two decimals for a ratio, whole numbers otherwise."
  @spec value(number(), Ledger.metric()) :: String.t()
  def value(seconds, :contact), do: "#{seconds} s"
  def value(ratio, :ratio), do: :erlang.float_to_binary(ratio / 1, decimals: 2)
  def value(count, _metric), do: Integer.to_string(round(count))
end
