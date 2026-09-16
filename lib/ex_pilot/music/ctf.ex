defmodule ExPilot.Music.Ctf do
  @moduledoc """
  The pieces for a ctf arena, as `ExPilot.Music` lists them: `{name, bpm, %{section => {bars, layers}}}`.

  `banner` (`:cruise`, 108 bpm, 56 bars) plays while no enemy is within reach: a march in
  F major — eight bars of snare and a horn call, a horn theme over a marching tuba with a
  second horn moving against it, a trumpet answer, a quiet turn through A flat major, and
  the theme back in full brass to a cadence on F.

  `raid` (`:combat`, 140 bpm, 44 bars) plays while an enemy is within reach: the chase in
  G minor — a driving kick and snare over a bass in eighths, a sawtooth theme that returns
  a second time louder, a two-bar figure sequenced up through G minor, B flat, C minor and
  D, a breakdown of bare drums and bass ending in a snare roll, and the theme back at full
  force with a four-bar tail on D.
  """

  alias ExPilot.Music.Score

  @doc "The pieces, in the shape `ExPilot.Music.pieces/0` builds from."
  @spec scores() :: [{String.t(), pos_integer(), %{atom() => {pos_integer(), %{atom() => String.t()}}}}]
  def scores do
    [
      {"banner", 108, %{cruise: banner()}},
      {"raid", 140, %{combat: raid()}}
    ]
  end

  defp banner do
    intro = "F!4 Bb!2 C!2"
    theme = "F F Bb C F Dm Bb C"
    answer = "Dm Bb F C Dm Bb Gm C"
    turn = "Ab Db Ab Eb Fm Db Bb C"
    coda = "F Bb F C Dm Bb C F"
    chords = Score.cycles([intro, theme, theme, answer, turn, theme, coda])
    roots = Score.roots(chords)

    call = "~ ~ ~ ~ [~@6 c5 d5] [f5@4 ~@4] [~@6 c5 d5] [e5@2 f5@2 g5@2 ~@2]"

    horn_theme =
      "[c5@2 f5@2 a5@3 g5, a4@4 f4@2 e4@2] [f5@4 c5@2 d5@2, a4@2 bf4@2 a4@2 f4@2] " <>
        "[d5@2 f5@2 bf5@3 a5, bf4@4 d5@2 f5@2] [g5@6 ~@2, e5@2 d5@2 c5@2 bf4@2] " <>
        "[c5@2 f5@2 a5@3 g5, a4@4 f4@2 e4@2] [a5@3 g5 f5@2 d5@2, d5@2 e5@2 a4@2 f4@2] " <>
        "[bf4@2 d5@2 f5@2 g5@2, f4@4 bf4@2 c5@2] [g5@2 e5@2 c5@2 ~@2, c5@2 g4@2 e4@2 g4@2]"

    trumpet_answer =
      "[a5@3 f5 d5@2 e5@2, d5@4 a4@2 g4@2] [f5@4 d5@2 bf4@2, bf4@4 f4@2 d4@2] " <>
        "[c5@2 f5@2 a5@2 c6@2, a4@2 c5@2 f5@2 e5@2] [g5@6 ~@2, e5@2 d5@2 c5@2 bf4@2] " <>
        "[a5@3 f5 d5@2 e5@2, d5@4 a4@2 g4@2] [f5@4 g5@2 a5@2, bf4@4 d5@2 f5@2] " <>
        "[bf5@3 a5 g5@2 d5@2, d5@4 bf4@2 g4@2] [e5@2 g5@4 ~@2, c5@2 e5@2 d5@2 g4@2]"

    quiet_turn =
      "[c5@4 ef5@2 af5@2, af4@8] [f5@6 ef5@2, af4@4 f4@4] [c5@4 ef5@2 af5@2, af4@8] " <>
        "[bf5@4 g5@2 ef5@2, g4@4 bf4@4] [af5@3 g5 f5@2 c5@2, c5@4 af4@4] " <>
        "[df5@2 f5@2 af5@4, f4@4 af4@4] [bf5@4 f5@2 d5@2, f4@4 d5@4] [e5@2 g5@2 bf5@2 ~@2, c5@4 e5@2 g4@2]"

    brass_coda =
      "[c5@2 f5@2 a5@3 g5, a4@4 f4@2 e4@2] [f5@4 d5@2 bf4@2, bf4@4 f4@2 d4@2] " <>
        "[c5@2 f5@2 a5@2 c6@2, a4@2 c5@2 f5@2 e5@2] [g5@6 ~@2, e5@2 d5@2 c5@2 bf4@2] " <>
        "[a5@3 g5 f5@2 d5@2, d5@2 e5@2 a4@2 f4@2] [bf4@2 d5@2 f5@2 g5@2, f4@4 bf4@2 c5@2] " <>
        "[e5@2 g5@2 c6@2 bf5@2, c5@2 e5@2 g5@2 e5@2] [a5@6 ~@2, c5@6 ~@2]"

    lead = Score.cycles([call, horn_theme, horn_theme, trumpet_answer, quiet_turn, horn_theme, brass_coda])

    march = "[bd sd bd [sd sd sd sd], hh*8]"
    stride = "[bd [sd sd] bd sd, hh*8]"

    {56,
     %{
       drums:
         ~s|s("<[bd ~ sd ~]!8 #{march}!16 #{stride}!8 [bd ~ sd ~, hh*4]!8 [cr sd bd [sd sd sd sd], hh*8] #{march}!13 [bd sd [bd bd] [sd sd sd sd], hh*8] [bd ~ ~ ~, cr ~ ~ ~]>").bank("RolandTR707").gain("<.35!8 .5!16 .55!8 .4!8 .6!16>")|,
       bass:
         ~s|note("#{roots}").s("gm_tuba").struct("<[x ~ x ~]!8 [x ~ x [x x]]!16 [x ~ x x]!8 [x@3 ~]!8 [x ~ x [x x]]!16>").gain(.5).clip(.6).release(.2)|,
       pad:
         ~s|chord("#{chords}").voicing().s("gm_string_ensemble_1").attack(.5).release(1.5).gain("<.1!8 .16!16 .18!8 .14!8 .2!16>")|,
       lead:
         ~s|note("#{lead}").s("<gm_french_horn!24 gm_trumpet!8 gm_french_horn!8 gm_brass_section!16>").attack(.03).release(.3).clip(.95).gain("<.3!8 .45!16 .5!8 .35!8 .5!16>")|
     }}
  end

  defp raid do
    theme = "Gm Gm Eb F Gm Gm Cm D"
    sequence = "Gm Gm Bb Bb Cm Cm D D"
    breakdown = "Gm!8"
    tail = "Gm Eb F D"
    chords = Score.cycles([theme, theme, sequence, breakdown, theme, tail])

    breakdown_bass =
      "[g2 g2 g2 g2 g2 g2 bf2 g2]!3 [g2 g2 g2 g2 f2 f2 fs2 fs2] " <>
        "[g2 g2 g2 g2 g2 g2 bf2 g2]!3 [d2 d2 d2 d2 fs2 fs2 a2 a2]"

    bass =
      Score.cycles([
        Score.roots(theme),
        Score.roots(theme),
        Score.roots(sequence),
        breakdown_bass,
        Score.roots(theme),
        Score.roots(tail)
      ])

    riff =
      "[g4 ~ g4 bf4 d5@2 f5 d5] [ef5@3 d5 c5@2 bf4@2] [ef5 ~ ef5 g5 bf5@2 g5 ef5] [f5@3 ef5 d5@2 c5@2] " <>
        "[g4 ~ g4 bf4 d5@2 f5 g5] [a5@3 g5 f5@2 d5@2] [ef5@2 c5@2 g5@2 ef5@2] [d5 ~ fs5 a5 fs5@2 d5@2]"

    rising =
      "[d5 ~ d5 ef5 d5 bf4 g4@2] [bf4 c5 d5@2 ~ g4 a4 bf4] [f5 ~ f5 g5 f5 d5 bf4@2] [d5 ef5 f5@2 ~ bf4 c5 d5] " <>
        "[g5 ~ g5 af5 g5 ef5 c5@2] [ef5 f5 g5@2 ~ c5 d5 ef5] [a5 ~ a5 c6 a5 fs5 d5@2] [fs5 g5 a5@2 c6@2 a5 fs5]"

    tail_riff = "[g5@2 f5@2 d5@2 bf4@2] [ef5 ~ ef5 g5 bf5@2 g5 ef5] [f5@3 ef5 d5@2 c5@2] [d5 ~ fs5 a5 fs5@2 ~@2]"

    lead = Score.cycles([riff, riff, rising, "~!8", riff, tail_riff])

    drive = "[bd ~ sd [~ bd] bd ~ sd ~, hh*8]"
    push = "[bd ~ sd [~ bd] bd ~ sd [~ bd], hh*8]"
    open = "[bd ~ sd [~ bd] bd ~ sd ~, [hh hh hh oh]*2]"
    fill = "[bd sd [sd sd] bd [sd sd] [sd sd] [bd bd] [sd sd]]"
    bare = "[bd ~ ~ bd ~ ~ bd ~ ~ ~ bd ~ ~ bd ~ ~, ~ ~ ~ ~ rim ~ ~ ~ ~ ~ ~ ~ rim ~ ~ ~]"

    {44,
     %{
       drums:
         ~s|s("<#{drive}!8 #{push}!7 [bd ~ sd ~ [sd sd] [sd sd] [sd sd] [sd sd], hh*8] #{open}!7 #{fill} #{bare}!6 [bd ~ bd ~, sd*8] [bd ~ ~ ~, sd*16] [cr ~ sd [~ bd] bd ~ sd ~, hh*8] #{push}!7 #{drive}!3 [bd sd [sd sd] bd [sd sd] [sd sd] [bd bd] cr]>").bank("RolandTR909").gain("<.65!8 .65!8 .7!8 .55!6 .6 .65 .7!12>")|,
       bass: ~s|note("#{bass}").s("gm_electric_bass_pick").struct("x*8").gain("<.5!16 .55!8 .6!8 .55!12>").clip(.5).lpf(1000)|,
       pad: ~s|chord("#{chords}").voicing().s("gm_synth_strings_1").attack(.05).release(.3).gain("<.14!8 .16!8 .18!8 0!8 .18!12>")|,
       lead: ~s|note("#{lead}").s("gm_lead_2_sawtooth").clip(.7).lpf(2400).gain("<.5!8 .55!8 .6!8 0!8 .65!12>")|
     }}
  end
end
