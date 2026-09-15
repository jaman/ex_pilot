defmodule ExPilot.MusicTest do
  use ExUnit.Case, async: true

  alias ExPilot.Music

  @pieces [{"drift", [:drift]}, {"orbit", [:cruise]}, {"burn", [:combat]}, {"ember", [:low_fuel]}, {"adrift", [:out]}, {"laurels", [:victory]}, {"ashes", [:defeat]}]

  test "every piece has every layer in every section, written in Strudel that reads" do
    pieces = Music.pieces()

    for {name, sections} <- @pieces, section <- sections do
      {_, piece} = List.keyfind(pieces, name, 0)
      assert piece.layers == [:drums, :bass, :pad, :lead]

      for layer <- piece.layers do
        assert is_binary(piece.sections[section][layer]), "#{name}/#{section}/#{layer}"
        {bars, js} = Music.source(name, section, layer)
        assert bars >= 24, "#{name}/#{section} is shorter than 24 bars"
        assert {:ok, _pattern} = TuningFork.Strudel.pattern(js), "#{name}/#{section}/#{layer} does not read"
      end
    end
  end

  test "the sections run from under a minute to over two" do
    seconds =
      for {name, piece} <- Music.pieces(), {section, _} <- piece.sections do
        {bars, _} = Music.source(name, section, :drums)
        {"#{name}/#{section}", bars * 4 * 60 / piece.bpm}
      end

    assert Enum.all?(seconds, fn {_, s} -> s >= 45 and s <= 300 end), inspect(seconds)
    assert Enum.any?(seconds, fn {_, s} -> s > 120 end)
  end

  test "a section's chains stack into one live pattern with something in every layer" do
    {_, piece} = List.keyfind(Music.pieces(), "laurels", 0)
    chains = for {_layer, chain} <- piece.sections.victory, do: "(" <> chain <> ").gain(0.5)"
    assert {:ok, pattern} = TuningFork.Strudel.pattern("stack(" <> Enum.join(chains, ",\n") <> ")")
    assert length(TuningFork.Pattern.query(pattern, {0, 4})) >= 4 * 4
  end

  test "cues follow the screen and the fight, each mood to its own piece" do
    assert %{piece: "drift", section: :drift, layers: %{drums: 0.0}} = Music.cue(nil, :title)
    assert %{piece: "drift", section: :drift, layers: %{drums: 0.7}} = Music.cue(nil, :settings)
    me = %{id: :a, pos: {0.0, 0.0}, fuel: 900, alive?: true, lives: 3}
    assert %{piece: "orbit", section: :cruise} = Music.cue(%{me: me, ships: []}, :arena)
    near = %{id: :b, pos: {3.0, 0.0}}
    assert %{piece: "burn", section: :combat} = Music.cue(%{me: me, ships: [near]}, :arena)
    assert %{piece: "ember", section: :low_fuel} = Music.cue(%{me: %{me | fuel: 20}, ships: [near]}, :arena)
    assert %{piece: "adrift", section: :out} = Music.cue(%{me: %{me | alive?: false, lives: 0}, ships: [near]}, :arena)
    assert %{piece: "orbit"} = Music.cue(%{me: nil, ships: [near]}, :arena)
  end

  test "the summary cues laurels for a player still standing and ashes otherwise" do
    assert %{piece: "laurels", section: :victory} = Music.cue(%{me: %{alive?: true, lives: 2}}, :summary)
    assert %{piece: "ashes", section: :defeat} = Music.cue(%{me: %{alive?: false, lives: 0}}, :summary)
    assert %{piece: "ashes"} = Music.cue(nil, :summary)
  end
end
