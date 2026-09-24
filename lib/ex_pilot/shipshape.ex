defmodule ExPilot.Shipshape do
  @moduledoc """
  XPilot ship shapes, as players wrote them.

      ExPilot.Shipshape.parse("(SH: 15,0 -8,8 -8,-8)(EN: -8,0)(MG: 15,0)")
      # => %{outline: [{15, 0}, {-8, 8}, {-8, -8}], engine: {-8, 0}, guns: [{15, 0}]}

  The outline's `x` points to the ship's nose and `y` is upward. Sections not present
  default to an engine at the rearmost point and one gun at the nose. `presets/0` are
  a few shapes by name for a player who would rather pick than write one.
  """

  @type point :: {integer(), integer()}
  @type t :: %{outline: [point()], engine: point(), guns: [point()]}

  @default "(SH: 15,0 -8,8 -8,-8)(EN: -8,0)(MG: 15,0)"

  @presets [
    {"classic", @default},
    {"dart", "(SH: 15,0 -10,5 -6,0 -10,-5)(EN: -6,0)(MG: 15,0)"},
    {"wedge", "(SH: 15,0 0,4 -8,9 -6,2 -6,-2 -8,-9 0,-4)(EN: -6,0)(MG: 15,0)"},
    {"wide", "(SH: 12,0 -6,10 -10,0 -6,-10)(EN: -10,0)(MG: 12,0)"},
    {"saucer", "(SH: 12,0 8,8 0,11 -8,8 -12,0 -8,-8 0,-11 8,-8)(EN: -12,0)(MG: 12,0)"}
  ]

  @doc "The classic default ship."
  @spec default() :: t()
  def default, do: parse!(@default)

  @doc "The shapes offered by name, `{name, text}`, the classic first."
  @spec presets() :: [{String.t(), String.t()}]
  def presets, do: @presets

  @doc "The text of the preset called `name`, or `nil`."
  @spec preset(String.t()) :: String.t() | nil
  def preset(name), do: @presets |> List.keyfind(name, 0, {name, nil}) |> elem(1)

  @doc "As `preset/1`, raising when there is no such preset."
  @spec preset!(String.t()) :: String.t()
  def preset!(name),
    do: preset(name) || raise(ArgumentError, "no shipshape preset #{inspect(name)}")

  @doc "The name of the preset `text` is, `\"classic\"` for `nil`, or `nil` for a shape of the player's own."
  @spec preset_name(String.t() | nil) :: String.t() | nil
  def preset_name(nil), do: "classic"

  def preset_name(text) do
    Enum.find_value(@presets, fn {name, preset} -> if preset == text, do: name end)
  end

  @doc "The preset `delta` (`1` or `-1`) steps from `text` in `presets/0`, wrapping; a shape that is no preset stands just before the classic, so a step forward lands on it."
  @spec next_preset(String.t() | nil, 1 | -1) :: String.t()
  def next_preset(text, delta) do
    names = Enum.map(@presets, &elem(&1, 0))
    at = Enum.find_index(names, &(&1 == preset_name(text))) || -1
    preset!(Enum.at(names, Integer.mod(at + delta, length(names))))
  end

  @doc "The path of `username`'s shipshape file, `$XDG_CONFIG_HOME/expilot/<username>.shipshape`."
  @spec file_path(String.t()) :: Path.t()
  def file_path(username) do
    base = System.get_env("XDG_CONFIG_HOME") || Path.join(System.user_home!(), ".config")
    Path.join([base, "expilot", username <> ".shipshape"])
  end

  @doc "The shape in `username`'s file, trimmed, or `nil` without one."
  @spec read_file(String.t()) :: String.t() | nil
  def read_file(username) do
    case File.read(file_path(username)) do
      {:ok, text} -> String.trim(text)
      {:error, _} -> nil
    end
  end

  @doc "Write `text` as `username`'s shipshape file, or remove the file for `nil`."
  @spec keep_file(String.t(), String.t() | nil) :: :ok | {:error, File.posix()}
  def keep_file(username, nil) do
    case File.rm(file_path(username)) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      error -> error
    end
  end

  def keep_file(username, text) do
    path = file_path(username)

    with :ok <- File.mkdir_p(Path.dirname(path)),
         do: File.write(path, String.trim(text) <> "\n")
  end

  @doc "Parse a shipshape string; `{:error, reason}` when it has no valid outline."
  @spec parse(String.t()) :: {:ok, t()} | {:error, term()}
  def parse(text) when is_binary(text) do
    sections =
      ~r/\(\s*([A-Z]{2})\s*:\s*([^)]*)\)/
      |> Regex.scan(text)
      |> Map.new(fn [_, name, body] -> {name, points(body)} end)

    case Map.get(sections, "SH", []) do
      outline when length(outline) >= 3 ->
        {:ok,
         %{
           outline: outline,
           engine: sections |> Map.get("EN", []) |> List.first() || rearmost(outline),
           guns: Map.get(sections, "MG", []) |> non_empty(fn -> [frontmost(outline)] end)
         }}

      _too_few ->
        {:error, :no_outline}
    end
  end

  @doc "As `parse/1`, raising on a bad shape."
  @spec parse!(String.t()) :: t()
  def parse!(text) do
    case parse(text) do
      {:ok, shape} ->
        shape

      {:error, reason} ->
        raise ArgumentError, "bad shipshape #{inspect(text)}: #{inspect(reason)}"
    end
  end

  defp points(body) do
    for pair <- String.split(body, ~r/\s+/, trim: true),
        [x, y] <- [String.split(pair, ",")],
        {xi, ""} <- [Integer.parse(x)],
        {yi, ""} <- [Integer.parse(y)],
        do: {xi, yi}
  end

  defp rearmost(outline), do: {outline |> Enum.map(&elem(&1, 0)) |> Enum.min(), 0}
  defp frontmost(outline), do: Enum.max_by(outline, &elem(&1, 0))

  defp non_empty([], default), do: default.()
  defp non_empty(list, _default), do: list
end
