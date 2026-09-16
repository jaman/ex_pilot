defmodule ExPilot.Music.Race do
  @moduledoc """
  The pieces for a race arena, as `ExPilot.Music` lists them: `{name, bpm, %{section => {bars, layers}}}`.

  | piece      | section   | bpm | bars | when                          |
  |------------|-----------|-----|------|-------------------------------|
  | `circuit`  | `:cruise` | 128 | 64   | lapping with no rival near    |
  | `overtake` | `:combat` | 156 | 48   | a rival within fourteen tiles |

  `circuit` is a D major drive: four-on-the-floor kick with open hats on the off-beats, a
  sixteenth-note arpeggiated electric bass, a pad changing chord every two bars through
  I–V–vi–IV, and a square-wave hook that enters after an eight-bar intro, answers itself,
  lifts through a middle eight, drops to hats and arpeggio, and returns.

  `overtake` is its B minor duel: a double-tresillo kick under a backbeat, a bass
  alternating octaves in eighths, a sawtooth lead in eighth-note cells that climb by
  sequence into a chromatic run, a suspended passage over `Asus` and `F#sus`, and the riff
  surging back; a two-bar fill closes every sixteen bars, and a crash opens every eight.
  """

  alias ExPilot.Music.Score

  @circuit_arpeggios %{
    "D" => {"d2", "a2", "d3", "fs3"},
    "A" => {"a1", "e2", "a2", "cs3"},
    "Bm" => {"b1", "fs2", "b2", "d3"},
    "G" => {"g1", "d2", "g2", "b2"},
    "F#m" => {"fs1", "cs2", "fs2", "a2"}
  }

  @circuit_hook ["D", "A", "Bm", "G"]
  @circuit_answer ["Bm", "G", "D", "A"]
  @circuit_lift ["G", "A", "F#m", "Bm"]

  @overtake_riff [{"Bm", "b1", "b2"}, {"G", "g1", "g2"}, {"Em", "e1", "e2"}, {"F#7", "fs1", "fs2"}]
  @overtake_climb [{"G", "g1", "g2"}, {"A", "a1", "a2"}, {"Bm", "b1", "b2"}, {"D", "d2", "d3"}]
  @overtake_suspense [{"Asus", "a1", "a2"}, {"Asus", "a1", "a2"}, {"F#sus", "fs1", "fs2"}, {"F#7", "fs1", "fs2"}]

  @doc "The pieces, in the shape `ExPilot.Music.pieces/0` builds from."
  @spec scores() :: [{String.t(), pos_integer(), %{atom() => {pos_integer(), %{atom() => String.t()}}}}]
  def scores do
    [
      {"circuit", 128, %{cruise: circuit()}},
      {"overtake", 156, %{combat: overtake()}}
    ]
  end

  defp circuit do
    progression = [
      @circuit_hook,
      @circuit_hook,
      @circuit_hook,
      @circuit_answer,
      @circuit_lift,
      @circuit_hook,
      @circuit_hook,
      @circuit_answer
    ]

    chords = Score.cycles(Enum.map(progression, &two_bar_chords/1))
    bass = Score.cycles(Enum.map(progression, &two_bar_arpeggios/1))

    hook =
      "[d5@3 d5@3 fs5@3 a5@3 fs5@4] [a5@3 fs5@3 d5@2 ~@2 e5@2 fs5@4] " <>
        "[cs5@3 cs5@3 e5@3 a5@3 e5@4] [a5@3 e5@3 cs5@2 ~@2 d5@2 e5@4] " <>
        "[b4@3 b4@3 d5@3 fs5@3 d5@4] [fs5@3 d5@3 b4@2 ~@2 cs5@2 d5@4] " <>
        "[g5@3 fs5@3 d5@3 b4@3 d5@4] [e5@3 fs5@3 g5@2 ~@2 a5@2 ~@4]"

    answer =
      "[fs5@3 fs5@3 a5@3 b5@3 a5@4] [fs5@3 d5@3 b4@2 ~@2 cs5@2 d5@4] " <>
        "[g5@3 g5@3 b5@3 a5@3 g5@4] [fs5@3 g5@3 a5@2 ~@2 b5@2 a5@4] " <>
        "[a5@3 fs5@3 d5@3 fs5@3 a5@4] [b5@3 a5@3 fs5@2 ~@2 e5@2 d5@4] " <>
        "[e5@3 cs5@3 a4@3 cs5@3 e5@4] [e5@6 ~@2 cs5@2 d5@2 e5@4]"

    lift =
      "[g5@4 ~@2 a5@2 b5@8] [a5@4 g5@4 fs5@8] " <>
        "[e5@4 ~@2 fs5@2 a5@8] [b5@4 a5@4 e5@8] " <>
        "[fs5@4 ~@2 a5@2 b5@8] [a5@4 fs5@4 cs5@8] " <>
        "[d5@4 ~@2 fs5@2 b5@8] [a5@4 fs5@4 e5@4 ~@4]"

    hats = "[hh oh]*4"
    kick = "[bd oh]*4"
    drive = "[bd*4, ~ cp ~ cp, [~ oh]*4]"
    turn = "[bd*4, ~ cp ~ [cp cp], [~ oh]*4]"
    surge = "[bd*4, ~ ~ cp*2 cp*4, [~ oh]*4]"
    phrase = "#{drive}!7 #{turn}"

    drums =
      Score.cycles([
        "#{hats}!4 #{kick}!4",
        phrase,
        phrase,
        phrase,
        "#{drive}!7 #{surge}",
        "#{hats}!6 #{kick} #{surge}",
        phrase,
        phrase
      ])

    crashes = Score.cycles(["0!8", "1 0!7", "1 0!7", "1 0!7", "1 0!7", "0!8", "1 0!7", "1 0!7"])

    {64,
     %{
       drums:
         ~s|s("#{drums}").bank("RolandTR909").gain("<.4!8 .6!24 .65!8 .35!8 .65!16>").superimpose(x => x.s("cr").struct("x ~ ~ ~").mask("#{crashes}").gain(.35))|,
       bass: ~s|note("#{bass}").s("gm_electric_bass_finger").gain("<.35!8 .5!32 .45!8 .5!16>").clip(.5)|,
       pad: ~s|chord("#{chords}").voicing().s("gm_pad_poly").attack(.4).release(1.5).gain("<.12!8 .16!24 .2!8 .08!8 .18!16>")|,
       lead:
         ~s|note("#{Score.cycles(["~!8", hook, hook, answer, lift, "~!8", hook, answer])}").s("gm_lead_1_square").clip(.8).release(.15).gain("<0!8 .4!24 .45!8 0!8 .45!16>")|
     }}
  end

  defp overtake do
    progression = [
      @overtake_riff,
      @overtake_riff,
      @overtake_climb,
      @overtake_suspense,
      @overtake_riff,
      @overtake_riff
    ]

    chords = Score.cycles(Enum.map(progression, &two_bar_named_chords/1))

    bass =
      Score.cycles([
        octave_bars(@overtake_riff, &driving_octaves/2),
        octave_bars(@overtake_riff, &driving_octaves/2),
        octave_bars(@overtake_climb, &driving_octaves/2),
        octave_bars(@overtake_suspense, &held_octaves/2),
        octave_bars(@overtake_riff, &driving_octaves/2),
        octave_bars(@overtake_riff, &driving_octaves/2)
      ])

    riff_head =
      "[b4 d5 fs5 d5 b4 d5 fs5 a5] [b5 a5 fs5 d5 e5 fs5 d5 ~] " <>
        "[g4 b4 d5 b4 g4 b4 d5 g5] [fs5 g5 a5 g5 fs5 d5 b4 ~] " <>
        "[e5 g5 b5 g5 e5 g5 b5 g5] [a5 g5 fs5 e5 d5 e5 fs5 ~] " <>
        "[fs5 e5 cs5 as4 fs5 e5 cs5 as4]"

    riff = "#{riff_head} [cs5 e5 fs5 as5 fs5 e5 cs5 ~]"
    riff_run = "#{riff_head} [e5 fs5 g5 as5 b5 ~ ~ ~]"

    climb =
      "[g4 a4 b4 d5 g4 a4 b4 d5] [b4 d5 e5 g5 b4 d5 e5 g5] " <>
        "[a4 b4 cs5 e5 a4 b4 cs5 e5] [cs5 e5 fs5 a5 cs5 e5 fs5 a5] " <>
        "[b4 cs5 d5 fs5 b4 cs5 d5 fs5] [d5 fs5 g5 b5 d5 fs5 g5 b5] " <>
        "[d5 e5 fs5 a5 d5 e5 fs5 a5] [fs5 g5 gs5 a5 as5 b5 ~ ~]"

    suspense =
      "[e5@6 d5@2] [e5@8] [d5@4 e5@4] [a5@8] " <>
        "[b4@4 cs5@4] [b4@8] [as4@4 cs5@4] [as4 cs5 e5 fs5 as5 b5 ~ ~]"

    main = "[bd@3 bd@3 bd@2 bd@3 bd@3 bd@2, ~ sd ~ sd, hh*8]"
    lead_in = "[bd@3 bd@3 bd@2 bd@3 bd@3 bd@2, ~ sd ~ [sd sd], hh*8]"
    fill = "[bd*4, [~ sd] [sd ~ sd sd] sd*4 sd*8]"
    thin = "[bd ~ ~ ~, hh*8]"
    build = "[bd*4, sd*4, hh*8]"

    drums =
      Score.cycles([
        "#{main}!8",
        "#{main}!6 #{lead_in} #{fill}",
        "#{main}!8",
        "#{thin}!6 #{build} #{fill}",
        "#{main}!8",
        "#{main}!6 #{lead_in} #{fill}"
      ])

    {48,
     %{
       drums:
         ~s|s("#{drums}").bank("RolandTR909").gain("<.65!16 .7!8 .45!6 .6 .7 .7!16>").superimpose(x => x.s("cr").struct("x ~ ~ ~").mask("<1 0!7>").gain(.35))|,
       bass: ~s|note("#{bass}").s("gm_electric_bass_pick").gain(.5).clip(.6).lpf(1000)|,
       pad: ~s|chord("#{chords}").voicing().s("gm_synth_strings_1").attack(.1).release(.5).gain("<.14!16 .16!8 .2!8 .15!16>")|,
       lead:
         ~s|note("#{Score.cycles([riff, riff_run, climb, suspense, riff, riff_run])}").s("gm_lead_2_sawtooth").clip(.6).gain("<.65!16 .7!8 .55!8 .7!16>")|
     }}
  end

  defp two_bar_chords(names), do: Enum.map_join(names, " ", &"#{&1}!2")

  defp two_bar_arpeggios(names), do: Enum.map_join(names, " ", &"#{arpeggio(&1)}!2")

  defp arpeggio(name) do
    {root, fifth, octave, third} = Map.fetch!(@circuit_arpeggios, name)
    "[#{root} #{octave} #{fifth} #{octave} #{root} #{octave} #{third} #{octave} #{root} #{octave} #{fifth} #{octave} #{root} #{octave} #{fifth} #{third}]"
  end

  defp two_bar_named_chords(steps), do: Enum.map_join(steps, " ", fn {name, _low, _high} -> "#{name}!2" end)

  defp octave_bars(steps, bar), do: Enum.map_join(steps, " ", fn {_name, low, high} -> "#{bar.(low, high)}!2" end)

  defp driving_octaves(low, high), do: "[#{low} #{high} #{low} #{high} #{low} #{high} #{low} #{high}]"

  defp held_octaves(low, high), do: "[#{low}@3 #{high}@3 #{low}@2 #{high}@3 #{low}@3 #{high}@2]"
end
