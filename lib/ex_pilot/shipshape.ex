defmodule ExPilot.Shipshape do
  @moduledoc """
  XPilot ship shapes, as players wrote them.

      ExPilot.Shipshape.parse("(SH: 15,0 -8,8 -8,-8)(EN: -8,0)(MG: 15,0)")
      # => %{outline: [{15, 0}, {-8, 8}, {-8, -8}], engine: {-8, 0}, guns: [{15, 0}]}

  The outline's `x` points to the ship's nose and `y` is upward. Sections not present
  default to an engine at the rearmost point and one gun at the nose.
  """

  @type point :: {integer(), integer()}
  @type t :: %{outline: [point()], engine: point(), guns: [point()]}

  @default "(SH: 15,0 -8,8 -8,-8)(EN: -8,0)(MG: 15,0)"

  @doc "The classic default ship."
  @spec default() :: t()
  def default, do: parse!(@default)

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
      {:ok, shape} -> shape
      {:error, reason} -> raise ArgumentError, "bad shipshape #{inspect(text)}: #{inspect(reason)}"
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
