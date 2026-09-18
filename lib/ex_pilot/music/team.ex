defmodule ExPilot.Music.Team do
  @moduledoc """
  The pieces for a team arena, as `ExPilot.Music` lists them: `{name, bpm, %{section => {bars, layers}}}`.

  `phalanx` (`:cruise`, 100 bpm, 56 bars) plays while no enemy is within reach: a drum
  tattoo on kick and snare rolls, a D Dorian theme in unison horns answered a fifth above,
  a passage of strings and bass alone, then the theme and its answer back together with a
  trumpet a fifth up and the tattoo at full weight, closing on a coda.

  `siege` (`:combat`, 136 bpm, 48 bars) plays while an enemy is within reach: a kick on
  every beat with the snare on two and four and a fill every eighth bar, a D minor bass
  ostinato on a pedal, a brass fanfare in dotted rhythms that climbs by step through the
  bridge, a half-time breakdown, then the assault again with the brass doubled an octave
  below.
  """

  alias ExPilot.Music.Score

  @doc "The pieces, in the shape `ExPilot.Music.pieces/0` builds from."
  @spec scores() :: [
          {String.t(), pos_integer(), %{atom() => {pos_integer(), %{atom() => String.t()}}}}
        ]
  def scores do
    [
      {"phalanx", 100, %{cruise: phalanx()}},
      {"siege", 136, %{combat: siege()}}
    ]
  end

  defp phalanx do
    theme_chords = "Dm G Dm Dm Dm C Am Dm"
    answer_chords = "Am Dm Am Am Am C Em Am"
    quiet_chords = "Dm!2 F!2 C!2 G!2"
    coda_chords = "Dm C Am Dm F Dm Dm Dm"

    chords =
      Score.cycles([
        "Dm!8",
        theme_chords,
        answer_chords,
        quiet_chords,
        theme_chords,
        answer_chords,
        coda_chords
      ])

    roots = Score.roots(chords)

    theme =
      "[d3@3 d3 f3@2 g3@2] [a3@6 g3@2] [f3@3 f3 e3@2 f3@2] [d3@8] [d3@3 d3 f3@2 a3@2] [c4@6 a3@2] [a3@3 g3 f3@2 e3@2] [d3@6 ~@2]"

    answer =
      "[a3@3 a3 c4@2 d4@2] [e4@6 d4@2] [c4@3 c4 b3@2 c4@2] [a3@8] [a3@3 a3 c4@2 e4@2] [g4@6 e4@2] [e4@3 d4 c4@2 b3@2] [a3@6 ~@2]"

    coda =
      "[d3@3 d3 f3@2 a3@2] [c4@6 a3@2] [a3@3 g3 f3@2 e3@2] [d3@8] [f3@3 f3 e3@2 c3@2] [d3@8] [d3@6 ~@2] [~@8]"

    tattoo_soft = "[bd ~ [~ sd] [sd sd sd sd]]"
    tattoo = "[bd [~ sd] bd [sd*4 sd*2]]"
    tattoo_full = "[bd [bd sd] bd [sd*4 sd*2]]"

    drums =
      Score.cycles([
        "#{tattoo_soft}!8",
        "#{tattoo}!16",
        "~!8",
        "#{tattoo_full}!16",
        "#{tattoo}!8"
      ])

    {56,
     %{
       drums:
         ~s|s("#{drums}").bank("RolandTR808").gain("<.4!8 .55!16 .2!8 .7!16 .55!8>").superimpose(x => x.s("cr").gain(.3).mask("<0!8 [1 0 0 0] 0!23 [1 0 0 0] 0!7 [1 0 0 0] 0!15>"))|,
       bass:
         ~s|note("#{roots}").s("gm_contrabass").struct("<[x ~ ~ ~]!8 [x ~ x ~]!16 [x ~ ~ x]!8 [x ~ x [~ x]]!16 [x ~ x ~]!8>").gain(.5).clip(.9).release(.2)|,
       pad:
         ~s|chord("#{chords}").voicing().s("gm_string_ensemble_1").attack(.6).release(1.2).lpf(1500).gain("<.12!8 .16!16 .2!8 .18!16 .16!8>")|,
       lead:
         ~s|note("#{Score.cycles(["~!8", theme, answer, "~!8", theme, answer, coda])}").s("gm_french_horn").clip(.95).gain("<0!8 .45!16 0!8 .5!16 .45!8>").superimpose(x => x.transpose(7).s("gm_trumpet").gain(.22).mask("<0!32 1!16 0!8>"))|
     }}
  end

  defp siege do
    assault_chords = "Dm Dm Bb Bb Dm Dm A A"
    climb_chords = "Dm F Gm Bb C A Dm Dm"
    break_chords = "Dm Dm Bb Bb Gm Gm A A"

    chords =
      Score.cycles([
        assault_chords,
        assault_chords,
        climb_chords,
        break_chords,
        assault_chords,
        climb_chords
      ])

    ostinato_d = "[d2 d2 d2 d2 f2 d2 e2 d2]"
    ostinato_a = "[a1 a1 a1 a1 cs2 a1 e2 a1]"
    assault_bass = "#{ostinato_d}!6 #{ostinato_a}!2"
    climb_bass = "[d2*8] [f2*8] [g2*8] [bf2*8] [c3*8] [a2*8] #{ostinato_d} #{ostinato_d}"

    break_bass =
      "[d2 ~ ~ d2 ~ ~ d2 ~]!2 [bf1 ~ ~ bf1 ~ ~ bf1 ~]!2 [g1 ~ ~ g1 ~ ~ g1 ~]!2 [a1 ~ ~ a1 ~ ~ a1 ~]!2"

    bass =
      Score.cycles([assault_bass, assault_bass, climb_bass, break_bass, assault_bass, climb_bass])

    fanfare =
      "[d4@3 d4 d4@2 f4@2] [a4@6 ~@2] [a4@3 a4 bf4@2 a4@2] [f4@4 d4@4] [d4@3 d4 d4@2 f4@2] [a4@3 a4 c5@2 a4@2] [g4@3 f4 e4@2 cs4@2] [a4@3 a4 a4@2 cs5@2]"

    fanfare_2 =
      "[d4@3 d4 d4@2 f4@2] [a4@3 a4 g4@2 f4@2] [a4@3 a4 bf4@2 c5@2] [d5@4 a4@4] [d4@3 d4 d4@2 f4@2] [a4@3 a4 c5@2 d5@2] [e5@3 d5 cs5@2 e5@2] [a4@3 a4 a4@2 cs5@2]"

    climb =
      "[d4@3 e4 f4@3 e4] [f4@3 g4 a4@3 g4] [g4@3 a4 bf4@3 a4] [bf4@3 c5 d5@3 c5] [c5@3 d5 e5@3 d5] [e5@3 f5 e5@2 cs5@2] [d5@6 a4@2] [f5@2 e5@2 d5@4]"

    breakdown = "[d4@8] [~@4 f4@2 e4@2] [d4@8] [~@8] [bf3@6 d4@2] [g4@8] [a4@6 e4@2] [a4@4 cs5@4]"

    assault = "[bd*4, ~ sd ~ sd, hh*8]"
    fill = "[bd*4, ~ sd [sd sd] [sd sd sd sd], hh*8]"
    assault_group = "#{assault}!7 #{fill}"
    half = "[bd hh ~ hh sd hh ~ [hh bd]]"
    half_fill = "[bd hh ~ hh sd sd [sd sd] [sd sd sd sd]]"

    drums =
      Score.cycles([
        assault_group,
        assault_group,
        assault_group,
        "#{half}!7 #{half_fill}",
        assault_group,
        assault_group
      ])

    {48,
     %{
       drums:
         ~s|s("#{drums}").bank("RolandTR909").gain("<.65!16 .7!8 .5!8 .7!16>").superimpose(x => x.s("cr").gain(.35).mask("<[1 0 0 0] 0!15 [1 0 0 0] 0!15 [1 0 0 0] 0!7 [1 0 0 0] 0!7>"))|,
       bass:
         ~s|note("#{bass}").s("gm_electric_bass_pick").gain("<.5!16 .55!8 .45!8 .5!8 .55!8>").clip(.6).lpf(800)|,
       pad:
         ~s|chord("#{chords}").voicing().s("gm_synth_strings_1").attack(.1).release(.5).gain("<.14!16 .16!8 .2!8 .16!16>")|,
       lead:
         ~s|note("#{Score.cycles([fanfare, fanfare_2, climb, breakdown, fanfare, climb])}").s("gm_brass_section").clip(.9).gain("<.4!8 .42!8 .45!8 .3!8 .45!8 .5!8>").superimpose(x => x.transpose(-12).gain(.2).mask("<0!32 1!16>"))|
     }}
  end
end
