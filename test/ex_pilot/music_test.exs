defmodule ExPilot.MusicTest do
  use ExUnit.Case, async: true

  alias ExPilot.Music

  @pieces [
    {"drift", [:drift]},
    {"orbit", [:cruise]},
    {"burn", [:combat]},
    {"banner", [:cruise]},
    {"raid", [:combat]},
    {"phalanx", [:cruise]},
    {"siege", [:combat]},
    {"circuit", [:cruise]},
    {"overtake", [:combat]},
    {"ember", [:low_fuel]},
    {"adrift", [:out]},
    {"laurels", [:victory]},
    {"ashes", [:defeat]},
    {"caprice", [:song]},
    {"rag", [:song]},
    {"mountain", [:song]},
    {"turk", [:song]},
    {"toreador", [:song]}
  ]

  test "every piece has every layer in every section, written in Strudel that reads" do
    pieces = Music.pieces()

    for {name, sections} <- @pieces, section <- sections do
      {_, piece} = List.keyfind(pieces, name, 0)
      assert piece.layers == [:drums, :bass, :pad, :lead]

      for layer <- piece.layers do
        assert is_binary(piece.sections[section][layer]), "#{name}/#{section}/#{layer}"
        {bars, js} = Music.source(name, section, layer)
        assert bars >= 24, "#{name}/#{section} is shorter than 24 bars"

        assert {:ok, _pattern} = TuningFork.Strudel.pattern(js),
               "#{name}/#{section}/#{layer} does not read"
      end
    end
  end

  test "every sound a piece asks for is one the kit knows, so nothing falls back to the bare synth" do
    for {name, sections} <- @pieces, section <- sections, layer <- [:drums, :bass, :pad, :lead] do
      {_bars, js} = Music.source(name, section, layer)

      for [_, names] <- Regex.scan(~r/s\("([^"]*)"\)/, js),
          sound <- Regex.scan(~r/[A-Za-z]\w*/, names) |> List.flatten() |> Enum.uniq() do
        assert TuningFork.Kit.known?(sound),
               "#{name}/#{section}/#{layer} plays unknown sound #{sound}"
      end
    end
  end

  test "polishing a chain that already has a hall or a swell leaves it alone" do
    assert Music.polish(:bass, ~s|note("c2")|) == ~s|note("c2")|
    assert Music.polish(:lead, ~s|note("c2").room(.9)|) == ~s|note("c2").room(.9)|
  end

  test "a section's chains stack into one live pattern with something in every layer" do
    {_, piece} = List.keyfind(Music.pieces(), "laurels", 0)
    chains = for {_layer, chain} <- piece.sections.victory, do: "(" <> chain <> ").gain(0.5)"

    assert {:ok, pattern} =
             TuningFork.Strudel.pattern("stack(" <> Enum.join(chains, ",\n") <> ")")

    assert length(TuningFork.Pattern.query(pattern, {0, 4})) >= 4 * 4
  end

  test "cues follow the screen and the fight, each mood to its own piece" do
    assert %{piece: "drift", section: :drift, layers: %{drums: +0.0}} = Music.cue(nil, :title)
    assert %{piece: "drift", section: :drift, layers: %{drums: 0.7}} = Music.cue(nil, :settings)
    me = %{id: :a, pos: {0.0, 0.0}, fuel: 900, alive?: true, lives: 3}
    assert %{piece: "orbit", section: :cruise} = Music.cue(%{me: me, ships: []}, :play)
    near = %{id: :b, pos: {3.0, 0.0}}
    assert %{piece: "burn", section: :combat} = Music.cue(%{me: me, ships: [near]}, :play)

    assert %{piece: "ember", section: :low_fuel} =
             Music.cue(%{me: %{me | fuel: 20}, ships: [near]}, :play)

    assert %{piece: "adrift", section: :out} =
             Music.cue(%{me: %{me | alive?: false, lives: 0}, ships: [near]}, :play)

    assert %{piece: "orbit"} = Music.cue(%{me: nil, ships: [near]}, :play)
  end

  test "a static stage gets one song a kind of arena, and a duel plays the dogfight's pieces when the music follows the play" do
    me = %{id: :a, pos: {0.0, 0.0}, fuel: 900, alive?: true, lives: 3}
    near = %{id: :b, pos: {3.0, 0.0}}

    assert %{piece: "caprice", section: :song} =
             Music.cue(%{me: me, ships: [near], mode: :dogfight}, {:static, :play})

    assert %{piece: "rag"} = Music.cue(%{me: me, ships: [], mode: :ctf}, {:static, :play})
    assert %{piece: "mountain"} = Music.cue(%{me: nil, ships: [], mode: :team}, {:static, :play})
    assert %{piece: "turk"} = Music.cue(%{mode: :race}, {:static, :play})
    assert %{piece: "toreador"} = Music.cue(%{mode: :duel}, {:static, :play})
    assert %{piece: "caprice"} = Music.cue(nil, {:static, :play})
    assert Music.cue(nil, {:static, :lobby}) == nil

    assert %{piece: "burn", section: :combat} =
             Music.cue(%{me: me, ships: [near], mode: :duel}, :play)

    for {name, piece} <- Music.pieces(), name in ~w(caprice rag mountain turk toreador) do
      assert piece.loop >= 32
      chains = for {_layer, chain} <- piece.sections.song, do: "(" <> chain <> ").gain(0.5)"

      assert {:ok, pattern} =
               TuningFork.Strudel.pattern("stack(" <> Enum.join(chains, ",\n") <> ")")

      assert length(TuningFork.Pattern.query(pattern, {0, piece.loop})) >= piece.loop * 8, name

      assert length(TuningFork.Pattern.query(pattern, {piece.loop - 1, piece.loop})) >= 6,
             "#{name}'s last bar is not empty"
    end
  end

  test "each kind of arena has its own cruise and combat pieces" do
    me = %{id: :a, pos: {0.0, 0.0}, fuel: 900, alive?: true, lives: 3}
    near = %{id: :b, pos: {3.0, 0.0}}

    assert %{piece: "banner", section: :cruise} =
             Music.cue(%{me: me, ships: [], mode: :ctf}, :play)

    assert %{piece: "raid", section: :combat} =
             Music.cue(%{me: me, ships: [near], mode: :ctf}, :play)

    assert %{piece: "phalanx"} = Music.cue(%{me: me, ships: [], mode: :team}, :play)
    assert %{piece: "siege"} = Music.cue(%{me: me, ships: [near], mode: :team}, :play)
    assert %{piece: "circuit"} = Music.cue(%{me: me, ships: [], mode: :race}, :play)
    assert %{piece: "overtake"} = Music.cue(%{me: me, ships: [near], mode: :race}, :play)
    assert %{piece: "banner"} = Music.cue(%{me: nil, ships: [near], mode: :ctf}, :play)
    assert %{piece: "orbit"} = Music.cue(nil, :play)
  end

  test "the summary cues laurels for a player still standing and ashes otherwise" do
    assert %{piece: "laurels", section: :victory} =
             Music.cue(%{me: %{alive?: true, lives: 2}}, :summary)

    assert %{piece: "ashes", section: :defeat} =
             Music.cue(%{me: %{alive?: false, lives: 0}}, :summary)

    assert %{piece: "ashes"} = Music.cue(nil, :summary)
  end

  test "the static songs are played from the scores of public pieces shipped with the game" do
    scores = Path.join(:code.priv_dir(:ex_pilot), "scores")

    assert Music.Score.part(Path.join(scores, "mozart_rondo_alla_turca.mid"),
             channel: 0,
             from: 0,
             bars: 1
           ) == "<[b4 a4 gs4 a4 c5@2 ~@2 d5 c5 b4 c5 e5@2 ~@2]>"

    assert Music.Score.part(Path.join(scores, "mozart_rondo_alla_turca.mid"),
             channel: 1,
             from: 0,
             bars: 1,
             voice: :lowest,
             on: :beats,
             transpose: -12
           ) == "<[~@4 a2@2 ~@2 c3@2 ~@2 a2@2 ~@2]>"
  end
end
