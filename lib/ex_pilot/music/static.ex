defmodule ExPilot.Music.Static do
  @moduledoc """
  The songs a static stage loops, one a kind of arena, as `ExPilot.Music` lists them:
  `{name, bpm, %{song: {bars, layers}}}`. Each is a piece of the concert repertoire
  played from its score — a MIDI engraving under `priv/scores`, read at compile time
  through `ExPilot.Music.Score.part/2` — on the Salamander grand (`piano`, a recorded
  Yamaha C5, CC BY 3.0) with a recorded bass (`ExPilot.Music.Instruments`' `fingerbass`
  and `pickbass` from FreePats, `meatbass`, a plucked double bass, from Karoryfer Samples,
  all CC0), a drum kit and a doubling instrument arranged under it, in four layers,
  written to be heard round and round: the last bar leads back to the first and nothing
  changes with the fight.

  | piece      | kind     | bpm | bars | score                                                  |
  |------------|----------|-----|------|--------------------------------------------------------|
  | `caprice`  | dogfight | 176 | 80   | Paganini, Caprice No. 24: the theme and nine variations |
  | `rag`      | ctf      | 88  | 76   | Joplin, The Entertainer, whole                          |
  | `mountain` | team     | 140 | 72   | Grieg, In the Hall of the Mountain King, whole          |
  | `turk`     | race     | 132 | 64   | Mozart, Rondo alla Turca (K. 331), whole                |
  | `toreador` | duel     | 120 | 60   | Bizet, Carmen, Prelude: the march and the Toreador song |

  `caprice`: the violin part on the piano, doubled by an overdriven guitar on the
  faster variations, over a fingered bass on the root and its octave in eighths, palm-muted
  power chords, and a fast rock beat — kick and snare on every beat, hats in eighths, a
  snare-and-tom fill into every variation and a crash on each — that thins to a kick and
  a rim under the two lyrical variations.

  `rag`: both hands of the rag on the piano, a double bass on the left hand's beats an
  octave down, a shaker in eighths, and a two-beat kit — kick on one and three, rim or
  snare on two and four, hats through the B and D strains, a rim roll into every eighth
  bar and a crash at every strain.

  `mountain`: the tune on the piano from its lowest register to its highest, the
  pizzicato bass line on a double bass an octave up, a string ensemble doubling the tune
  from the second climb, and a kit that builds with it: a kick and a rim, then hats in
  eighths, then the full kit, then hats in sixteenths with a crash every four bars.

  `turk`: both hands on the piano, a picked bass on the left hand's beats an octave down,
  and a rock beat in eighths with an open hat on the A major passages, a fill into
  every eighth bar and a crash on it.

  `toreador`: both hands on the piano, a double bass on the left hand's beats, a string
  ensemble doubling the Toreador song, and a march — kick on one and three, snare
  eighths on two and a snare pick-up on four, hats in eighths, a snare roll into every
  fourth bar and a crash on it — that drops to a kick, a rim and a shaker for the song.

  The scores come from the Mutopia Project (mutopiaproject.org), engraved in LilyPond:
  Grieg's by Coyau, Joplin's by Chris Sawer and Mozart's by Rune Zedeler and Chris
  Sawer, all released to the public domain; Bizet's by Alex O'S under Creative Commons
  Attribution-ShareAlike 2.5, and Paganini's by Samuel Rummel under Creative Commons
  Attribution-ShareAlike 4.0 — those two ask that they be credited and that what is
  made from them be shared under the same terms.
  """

  alias ExPilot.Music.Score

  @scores Path.expand("../../../priv/scores", __DIR__)
  @grieg Path.join(@scores, "grieg_mountain_king.mid")
  @joplin Path.join(@scores, "joplin_entertainer.mid")
  @mozart Path.join(@scores, "mozart_rondo_alla_turca.mid")
  @bizet Path.join(@scores, "bizet_carmen_prelude.mid")
  @paganini Path.join(@scores, "paganini_caprice_24.mid")

  @external_resource @grieg
  @external_resource @joplin
  @external_resource @mozart
  @external_resource @bizet
  @external_resource @paganini

  @doc "The pieces, in the shape `ExPilot.Music.pieces/0` builds from."
  @spec scores() :: [
          {String.t(), pos_integer(), %{atom() => {pos_integer(), %{atom() => String.t()}}}}
        ]
  def scores do
    [
      {"caprice", 176, %{song: caprice()}},
      {"rag", 88, %{song: rag()}},
      {"mountain", 140, %{song: mountain()}},
      {"turk", 132, %{song: turk()}},
      {"toreador", 120, %{song: toreador()}}
    ]
  end

  @doc "The static piece for a kind of arena."
  @spec piece(atom()) :: String.t()
  def piece(:ctf), do: "rag"
  def piece(:team), do: "mountain"
  def piece(:race), do: "turk"
  def piece(:duel), do: "toreador"
  def piece(_dogfight), do: "caprice"

  defp stacked(parts), do: "stack(" <> Enum.join(parts, ", ") <> ")"

  defp kit(blocks) do
    blocks
    |> Enum.flat_map(fn {beat, fill, every, count} -> block_cycles(beat, fill, every, count) end)
    |> Score.cycles()
  end

  defp block_cycles(beat, fill, every, count) do
    for cycle <- 1..count, do: "[" <> if(rem(cycle, every) == 0, do: fill, else: beat) <> "]"
  end

  defp on(bars, ranges) do
    Score.cycles(
      Enum.map(0..(bars - 1), fn bar -> if within_any?(bar, ranges), do: "1", else: "0" end)
    )
  end

  defp within_any?(bar, ranges),
    do: Enum.any?(ranges, fn {from, to} -> bar >= from and bar < to end)

  defp every(bars, step),
    do:
      Score.cycles(
        Enum.map(0..(bars - 1), fn bar -> if rem(bar, step) == 0, do: "1", else: "0" end)
      )

  defp crashes(mask, gain),
    do: ~s|.superimpose(x => x.s("cr").struct("x ~ ~ ~").mask("#{mask}").gain(#{gain}))|

  defp piano(part, gain),
    do: ~s|note("#{part}").s("piano").attack(.005).release(.3).clip(.95).gain(#{gain})|

  @caprice_violin Score.part(@paganini, channel: 0, bars: 80)
  @caprice_roots ~w(a e a e a e a e a d g c f b e a)
  @caprice_fifths ~w(e b e b e b e b e a d g c f b e)

  defp caprice do
    bass =
      @caprice_roots
      |> Enum.map(fn root -> "[#{root}1 #{root}1 #{root}2 #{root}1]" end)
      |> Enum.chunk_every(2)
      |> Enum.map_join(" ", fn pair -> "[" <> Enum.join(pair, " ") <> "]" end)

    chugs =
      Enum.zip(@caprice_roots, @caprice_fifths)
      |> Enum.map(fn {root, fifth} -> "[#{root}2,#{fifth}3]*4" end)
      |> Enum.chunk_every(2)
      |> Enum.map_join(" ", fn pair -> "[" <> Enum.join(pair, " ") <> "]" end)

    drive = "[bd ~] [sd ~] [bd bd] [sd ~]"
    fill = "[bd ~] [sd ~] [sd sd sd sd] [ht ht mt lt]"
    thin = "bd ~ rim ~"

    drums =
      kit([{drive, fill, 8, 24}, {thin, fill, 8, 8}, {drive, fill, 8, 40}, {thin, fill, 8, 8}])

    hats = "<[hh*8]!24 ~!8 [hh*8]!40 ~!8>"
    guitar = on(80, [{8, 24}, {32, 56}, {64, 72}])

    {80,
     %{
       drums:
         stacked([~s|s("#{drums}").gain(.6)|, ~s|s("#{hats}").gain(.9)|]) <>
           crashes(every(80, 8), 0.3),
       bass: ~s|note("<#{bass}>").s("fingerbass").gain(.15).clip(.6)|,
       pad:
         ~s|note("<#{chugs}>").s("gm_electric_guitar_muted").attack(.005).release(.1).clip(.5).gain(.24).mask("#{on(80, [{0, 24}, {32, 72}])}")|,
       lead:
         stacked([
           piano(@caprice_violin, 0.85),
           ~s|note("#{@caprice_violin}").s("gm_overdriven_guitar").clip(.9).release(.15).gain(.26).mask("#{guitar}")|
         ])
     }}
  end

  @rag_right Score.part(@joplin, channel: 0, bars: 76)
  @rag_left Score.part(@joplin, channel: 1, bars: 76)
  @rag_bass Score.part(@joplin, channel: 1, bars: 76, voice: :lowest, on: :beats, transpose: -12)

  defp rag do
    stroll = "bd rim bd rim"
    stroll_fill = "bd rim [rim rim rim rim] [rim rim rim rim]"
    strut = "bd sd bd sd"
    strut_fill = "bd sd [sd sd sd sd] [lt mt ht sd]"

    drums =
      kit([
        {stroll, stroll, 8, 2},
        {stroll, stroll_fill, 8, 16},
        {strut, strut_fill, 8, 16},
        {stroll, stroll_fill, 8, 8},
        {strut, strut_fill, 8, 16},
        {stroll, stroll, 8, 2},
        {strut, strut_fill, 8, 16}
      ])

    hats = "<~!18 [hh*8]!16 ~!8 [hh*8]!16 ~!2 [hh*8]!16>"

    {76,
     %{
       drums:
         stacked([~s|s("#{drums}").gain(.5)|, ~s|s("#{hats}").gain(.8)|, ~s|s("sh*8").gain(.5)|]) <>
           crashes(on(76, [{2, 3}, {18, 19}, {34, 35}, {42, 43}, {60, 61}]), 0.25),
       bass: ~s|note("#{@rag_bass}").s("meatbass").gain(.4).clip(.8)|,
       pad: piano(@rag_left, 0.7),
       lead: piano(@rag_right, 0.9)
     }}
  end

  @mountain_tune Score.part(@grieg, channel: 0, from: 1, bars: 72)
  @mountain_bass Score.part(@grieg, channel: 1, from: 1, bars: 72, transpose: 12)

  defp mountain do
    soft = "bd ~ rim ~"
    soft_fill = "bd ~ rim [rim rim]"
    light = "bd rim bd rim"
    light_fill = "bd rim [bd bd] [rim rim rim rim]"
    full = "[bd ~] [sd ~] [bd bd] [sd ~]"
    full_fill = "[bd ~] [sd ~] [sd sd sd sd] [lt lt mt ht]"

    drums =
      kit([
        {soft, soft_fill, 8, 8},
        {light, light_fill, 8, 16},
        {full, full_fill, 8, 24},
        {full, full_fill, 8, 24}
      ])

    hats = "<~!8 [hh*8]!40 [hh*16]!24>"

    {72,
     %{
       drums:
         stacked([~s|s("#{drums}").gain(.55)|, ~s|s("#{hats}").gain(.85)|]) <>
           crashes(on(72, Enum.map(12..17, &{&1 * 4, &1 * 4 + 1})), 0.3),
       bass: ~s|note("#{@mountain_bass}").s("meatbass").gain(.4).clip(.9)|,
       pad:
         ~s|note("#{@mountain_tune}").s("gm_string_ensemble_1").attack(.05).release(.3).clip(1).gain(.22).mask("#{on(72, [{24, 72}])}")|,
       lead: piano(@mountain_tune, 0.9)
     }}
  end

  @turk_right Score.part(@mozart, channel: 0, bars: 64)
  @turk_left Score.part(@mozart, channel: 1, bars: 64)
  @turk_bass Score.part(@mozart, channel: 1, bars: 64, voice: :lowest, on: :beats, transpose: -12)

  defp turk do
    beat = "[bd ~] [sd ~] [bd bd] [sd ~]"
    fill = "[bd ~] [sd ~] [sd sd sd sd] [lt lt mt ht]"
    drums = kit([{beat, fill, 8, 64}])

    hats =
      "<[hh*8]!12 [[hh hh hh oh]*2]!4 [hh*8]!12 [[hh hh hh oh]*2]!4 [hh*8]!16 [[hh hh hh oh]*2]!16>"

    {64,
     %{
       drums:
         stacked([~s|s("#{drums}").gain(.45)|, ~s|s("#{hats}").gain(.75)|]) <>
           crashes(every(64, 8), 0.3),
       bass: ~s|note("#{@turk_bass}").s("pickbass").gain(.25).clip(.7)|,
       pad: piano(@turk_left, 0.7),
       lead: piano(@turk_right, 1.2)
     }}
  end

  @toreador_right Score.part(@bizet, channel: 0, bars: 60)
  @toreador_left Score.part(@bizet, channel: 1, bars: 60)
  @toreador_bass Score.part(@bizet, channel: 1, bars: 60, voice: :lowest, on: :beats)

  defp toreador do
    march = "[bd ~] [sd sd] [bd ~] [sd [sd sd]]"
    roll = "[bd ~] [sd sd] [sd sd sd sd] [sd sd sd sd]"
    song = "bd ~ rim ~"
    drums = kit([{march, roll, 4, 25}, {song, song, 4, 25}, {march, roll, 4, 10}])
    hats = "<[hh*8]!25 [sh*8]!25 [hh*8]!10>"

    {60,
     %{
       drums:
         stacked([~s|s("#{drums}").gain(.55)|, ~s|s("#{hats}").gain(.8)|]) <>
           crashes(on(60, Enum.map([0, 4, 8, 12, 16, 20, 50, 54, 58], &{&1, &1 + 1})), 0.3),
       bass: ~s|note("#{@toreador_bass}").s("meatbass").gain(.4).clip(.8)|,
       pad:
         stacked([
           piano(@toreador_left, 0.7),
           ~s|note("#{@toreador_right}").s("gm_string_ensemble_1").attack(.05).release(.3).clip(1).gain(.2).mask("#{on(60, [{25, 50}])}")|
         ]),
       lead: piano(@toreador_right, 0.9)
     }}
  end
end
