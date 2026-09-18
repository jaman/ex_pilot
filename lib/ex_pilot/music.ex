defmodule ExPilot.Music do
  @moduledoc """
  ExPilot's music: pieces written in Strudel, one per mood and kind of arena, each in
  four layers — `:drums`, `:bass`, `:pad`, `:lead` — for `Cauldron2D.Audio.Music`.

  | piece      | section     | when                                              |
  |------------|-------------|---------------------------------------------------|
  | `drift`    | `:drift`    | the title, the lobby and settings                 |
  | `orbit`    | `:cruise`   | a dogfight arena, flying with no one near         |
  | `burn`     | `:combat`   | a dogfight arena, an enemy within reach           |
  | `banner`   | `:cruise`   | a capture-the-flag arena, no one near             |
  | `raid`     | `:combat`   | a capture-the-flag arena, an enemy within reach   |
  | `phalanx`  | `:cruise`   | a team arena, no one near                         |
  | `siege`    | `:combat`   | a team arena, an enemy within reach               |
  | `circuit`  | `:cruise`   | a race, no one near                               |
  | `overtake` | `:combat`   | a race, a rival within reach                      |
  | `ember`    | `:low_fuel` | fuel below 150                                    |
  | `adrift`   | `:out`      | out of lives, watching the others                 |
  | `laurels`  | `:victory`  | the summary of a round won                        |
  | `ashes`    | `:defeat`   | the summary of a round lost                       |

  The kind of arena is the view's `mode` (`ExPilot.Game.mode/1`); the arena pieces for
  each kind live in `ExPilot.Music.Ctf`, `ExPilot.Music.Team` and `ExPilot.Music.Race`,
  a duel taking the dogfight's. A stage whose music is static asks
  `cue(view, {:static, :arena})` and gets a song written to loop, one a kind of arena,
  from `ExPilot.Music.Static`; the layered pieces above are for stages that follow the
  play.

  A bar is one Strudel cycle. Each layer is one Strudel chain, performed live on the
  player's stage by `Cauldron2D.Audio.Music`; the chains are written for the number of
  bars in the table and repeat from there. The title and lobby differ only in layer
  levels, so they share one section. Sound names are Strudel's: the drum machines and
  the General MIDI soundfonts, fetched on first use and synthesised until they arrive
  (`Cauldron2D.Audio.Music.prefetch/1` at the application's start fetches them all
  ahead). Every drum, pad and lead chain plays into a hall unless it sets its own
  `.room(` (`polish/2`).

  `cue/2` turns a player's view and screen into the cue for the piece and section that
  fit; the director changes piece at the next bar.

      ExPilot.Music.pieces()
      ExPilot.Music.cue(view, :arena)
      ExPilot.Music.source("burn", :combat, :drums)
  """

  alias ExPilot.Music.Ctf
  alias ExPilot.Music.Race
  alias ExPilot.Music.Score
  alias ExPilot.Music.Static
  alias ExPilot.Music.Team

  @layers [:drums, :bass, :pad, :lead]

  @doc "Every piece as `Cauldron2D.Audio.Music.piece/3` takes it, with its name."
  @spec pieces() :: [{String.t(), Cauldron2D.Audio.Music.spec()}]
  def pieces do
    for {name, bpm, sections} <- scores() do
      chains =
        Map.new(sections, fn {section, {_bars, layers}} ->
          {section, Map.new(layers, fn {layer, chain} -> {layer, polish(layer, chain)} end)}
        end)

      loop = sections |> Enum.map(fn {_section, {bars, _layers}} -> bars end) |> Enum.max()
      {name, %{bpm: bpm, beats_per_bar: 4, layers: @layers, sections: chains, loop: loop}}
    end
  end

  @doc "The Strudel chain a layer of a section is played as, and the bars it runs for."
  @spec source(String.t(), atom(), atom()) :: {pos_integer(), String.t()}
  def source(piece, section, layer) do
    {_name, _bpm, sections} = List.keyfind!(scores(), piece, 0)
    {bars, layers} = Map.fetch!(sections, section)
    {bars, polish(layer, Map.fetch!(layers, layer))}
  end

  @room %{drums: 0.12, pad: 0.3, lead: 0.3}

  @pad_swell ".attack(.8).release(1.2).clip(.8).lpf(1400)"

  @doc """
  The chain as the stage plays it: a chain with no `.room(` of its own is given the
  layer's hall — drums 0.12, pad 0.3, lead 0.3, bass dry — and a pad with no `.attack(`
  of its own swells in and out of every chord, a little short of the bar, under a
  low-pass, so no chord change is a blast and no chord a drone.
  """
  @spec polish(atom(), String.t()) :: String.t()
  def polish(layer, chain) do
    chain =
      if layer == :pad and not String.contains?(chain, ".attack("),
        do: chain <> @pad_swell,
        else: chain

    case Map.fetch(@room, layer) do
      {:ok, room} ->
        if String.contains?(chain, ".room("), do: chain, else: chain <> ".room(#{room})"

      :error ->
        chain
    end
  end

  @doc "Which piece, section and layer levels a player's view calls for on `screen`; `{:static, :arena}` names the song a static stage loops for the arena's kind."
  @spec cue(map() | nil, Cauldron2D.Client.Game.screen()) :: Cauldron2D.Audio.Music.cue()
  def cue(view, {:static, :arena}),
    do: %{piece: Static.piece(mode_of(view)), section: :song, layers: %{}}

  def cue(_view, {:static, _screen}), do: nil

  def cue(_view, :title),
    do: %{piece: "drift", section: :drift, layers: %{drums: 0.0, bass: 0.8, pad: 1.0, lead: 0.9}}

  def cue(_view, :lobby),
    do: %{piece: "drift", section: :drift, layers: %{drums: 0.7, bass: 0.9, pad: 1.0, lead: 0.7}}

  def cue(view, :settings), do: cue(view, :lobby)

  def cue(%{me: %{alive?: alive?, lives: lives}}, :summary)
      when alive? or lives == :unlimited or lives > 0,
      do: %{
        piece: "laurels",
        section: :victory,
        layers: %{drums: 1.0, bass: 1.0, pad: 1.0, lead: 1.0}
      }

  def cue(_view, :summary),
    do: %{piece: "ashes", section: :defeat, layers: %{drums: 0.8, bass: 1.0, pad: 1.0, lead: 0.9}}

  def cue(view, :arena) do
    case view do
      %{me: %{alive?: false, lives: 0}} ->
        %{piece: "adrift", section: :out, layers: %{drums: 0.0, bass: 0.9, pad: 1.0, lead: 0.8}}

      %{me: %{fuel: fuel}} when fuel < 150 ->
        %{
          piece: "ember",
          section: :low_fuel,
          layers: %{drums: 1.0, bass: 1.0, pad: 0.9, lead: 1.0}
        }

      %{me: %{id: _} = me, ships: ships} ->
        arena_cue(me, ships, mode_of(view))

      _watching ->
        cruise(mode_of(view), 0.6)
    end
  end

  @arena_pieces %{
    dogfight: {"orbit", "burn"},
    duel: {"orbit", "burn"},
    ctf: {"banner", "raid"},
    team: {"phalanx", "siege"},
    race: {"circuit", "overtake"}
  }

  defp mode_of(%{mode: mode}) when is_map_key(@arena_pieces, mode), do: mode
  defp mode_of(_view), do: :dogfight

  defp arena_cue(me, ships, mode) do
    nearby =
      Enum.count(ships, fn ship -> ship.id != me.id and within?(me.pos, ship.pos, 14.0) end)

    {_cruise, combat} = Map.fetch!(@arena_pieces, mode)

    cond do
      nearby >= 2 ->
        %{piece: combat, section: :combat, layers: %{drums: 1.0, bass: 1.0, pad: 0.6, lead: 1.0}}

      nearby == 1 ->
        %{piece: combat, section: :combat, layers: %{drums: 0.9, bass: 1.0, pad: 0.8, lead: 0.7}}

      true ->
        cruise(mode, 0.7)
    end
  end

  defp cruise(mode, drums) do
    {piece, _combat} = Map.fetch!(@arena_pieces, mode)
    %{piece: piece, section: :cruise, layers: %{drums: drums, bass: 0.9, pad: 1.0, lead: 0.8}}
  end

  defp within?({x1, y1}, {x2, y2}, reach),
    do: (x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1) < reach * reach

  defp scores do
    own() ++
      Ctf.scores() ++
      Team.scores() ++ Race.scores() ++ Static.scores()
  end

  defp own do
    [
      {"drift", 84, %{drift: drift()}},
      {"orbit", 112, %{cruise: orbit()}},
      {"burn", 140, %{combat: burn()}},
      {"ember", 100, %{low_fuel: ember()}},
      {"adrift", 72, %{out: adrift()}},
      {"laurels", 120, %{victory: laurels()}},
      {"ashes", 66, %{defeat: ashes()}}
    ]
  end

  defp drift do
    chords = cycles(["Em9!4 CM7!4 G!4 D!4", "Am7!4 Em!4 CM7!4 Bm7!4", "Em9!4 CM7!4 G!4 D!4"])
    roots = cycles(["e2!4 c2!4 g2!4 d2!4", "a2!4 e2!4 c2!4 b1!4", "e2!4 c2!4 g2!4 d2!4"])

    motif_a = "[e5@3 g5] [fs5@2 e5@2] [d5@3 e5] b4 ~ [c5@2 e5@2] [a5@3 g5] [fs5@2 e5@2] d5"
    motif_b = "[c5@2 e5@2] [a5@3 g5] [fs5@2 e5@2] [d5@3 ~] ~ [g5@2 a5@2] [b5@3 a5] [g5@2 e5@2]"
    motif_c = "[e4@3 g4] [fs4@2 e4@2] [d4@3 e4] b3 ~ [c4@2 e4@2] [a4@3 g4] [fs4@2 e4@2] d4"

    {48,
     %{
       drums:
         ~s|s("~ hh ~ hh").bank("RolandTR808").gain("<.25 .25 .35 .25>").mask("<1!48>").late(.02)|,
       bass: ~s|note("#{roots}").s("gm_acoustic_bass").gain(.5).clip(.5).release(.3)|,
       pad:
         ~s|chord("#{chords}").voicing().s("gm_pad_warm").attack(1.2).release(2).clip(.75).lpf(900).gain(.12)|,
       lead:
         ~s|note("#{cycles([motif_a, motif_b, motif_a, motif_b, motif_c, motif_c])}").s("gm_vibraphone").release(.6).gain("<.4!32 .45!16>").delay(.3).delaytime(.375).delayfeedback(.35).room(.45)|
     }}
  end

  defp orbit do
    intro = "Em!8"
    phrase_a = "Em Em C C G G D Bm"
    phrase_b = "Am Am F F Em Em Bm7 Bm7"
    break = "Em C Em C G D Em Em"
    chords = cycles([intro, phrase_a, phrase_a, phrase_b, phrase_b, break, phrase_a, phrase_a])
    roots = chords |> String.replace(~r/([A-G])(m7|m|M7)?/, fn full -> root_of(full) <> "2" end)

    motif =
      "[b4 e5 g5@2] [fs5@2 e5 b4] [d5@2 e5@2] [~@2 g5 a5] [b5@2 a5 g5] [fs5@3 ~] [e5@2 g5@2] [b4@3 ~]"

    answer =
      "[c5 e5 a5@2] [g5@2 e5@2] [~@2 f5 a5] [c6@2 b5@2] [g5@3 ~] [e5 g5 b5@2] [a5@2 g5@2] [e5@3 ~]"

    high =
      "[b5 e6 g6@2] [fs6@2 e6 b5] [d6@2 e6@2] [~@2 g6 a6] [b6@2 a6 g6] [fs6@3 ~] [e6@2 g6@2] [b5@3 ~]"

    {64,
     %{
       drums:
         ~s|s("<[~ hh]*4!8 [bd hh sd [hh bd]]!16 [bd hh sd [hh bd]]!16 [bd ~ hh ~]!8 [bd hh sd [hh bd]]!16>").bank("RolandTR909").gain("<.35!8 .6!16 .65!16 .35!8 .7!16>")|,
       bass:
         ~s|note("#{roots}").s("gm_electric_bass_finger").struct("<[x ~ x ~]!8 [x ~ x x]!48 [x ~ x ~]!8>").gain(.45).clip(.5).release(.15)|,
       pad:
         ~s|chord("#{chords}").voicing().s("gm_epiano2").attack(.05).release(1.5).clip(.9).lpf(2400).gain(.14)|,
       lead:
         ~s|note("#{cycles(["~!8", motif, motif, answer, answer, "~!8", high, high])}").s("gm_epiano1").gain(.28).release(.4).pan("<.3 -.3>").room(.35)|
     }}
  end

  defp burn do
    riff = "Em Em F F Em Em G Bm"
    bridge = "C D Em Em"
    chords = cycles([riff, riff, bridge, bridge, riff, riff, "Em!8"])
    roots = chords |> String.replace(~r/([A-G])(m7|m|M7)?/, fn full -> root_of(full) <> "2" end)

    {48,
     %{
       drums:
         ~s|s("<[bd hh hh bd sd hh hh bd bd hh hh bd sd hh hh bd]!16 [bd sd bd bd sd ~ bd sd]!8 [bd hh hh bd sd hh hh bd bd hh hh bd sd sd sd sd]!16 [bd ~ ~ ~]!4 [sd*4 bd*2 sd*2]!4>").bank("RolandTR909").gain(.7)|,
       bass:
         ~s|note("#{roots}").s("gm_electric_bass_pick").struct("x*8").gain(.55).clip(.5).lpf(900)|,
       pad:
         ~s|chord("#{chords}").voicing().s("gm_pad_poly").attack(.3).release(.8).clip(.8).lpf(1600).gain(.1)|,
       lead:
         ~s|n("<[0 4 7 4 0 4 12 4]!16 [7@2 4 0@3 7 4]!8 [12 4 0 4 14 4 0 12]!16 [0 ~@7]!4 [0 1 0 -2 0 1 3 7]!4>").scale("E4:minor").s("gm_overdriven_guitar").gain(.45).clip(.6)|
     }}
  end

  defp ember do
    chords = cycles(List.duplicate("Em F Em Em C F Em Bm", 4))
    roots = chords |> String.replace(~r/([A-G])(m7|m|M7)?/, fn full -> root_of(full) <> "2" end)

    {32,
     %{
       drums:
         ~s|s("[bd hh ~ hh ~ hh rim hh]").bank("RolandTR707").gain(.5).sometimesBy(.2, x => x.speed(1.5))|,
       bass:
         ~s|note("#{roots}").s("gm_electric_bass_pick").struct("<[x x x x]!3 [x x x [x f2]]>").gain(.55).lpf(600)|,
       pad:
         ~s|chord("#{chords}").voicing().s("gm_pad_bowed").attack(.8).release(1.2).clip(.8).lpf(1200).gain(.11)|,
       lead:
         ~s|note("<[e5@2 d5@2] [c5@2 b4@2] ~ [f5@2 e5@2] ~ ~ ~ ~>").s("gm_lead_8_bass_lead").gain(.35).lpf(1200)|
     }}
  end

  defp adrift do
    chords = cycles(["Am9!4 FM7!4 CM7!4 G!4", "Am9!4 FM7!4 CM7!4 G!4"])

    {32,
     %{
       drums: ~s|s("~").gain(0)|,
       bass:
         ~s|note("<a1!4 f1!4 c2!4 g1!4 a1!4 f1!4 c2!4 g1!4>").s("gm_contrabass").gain(.25).clip(4)|,
       pad:
         ~s|chord("#{chords}").voicing().s("gm_pad_choir").attack(1.5).release(2).clip(.85).lpf(1400).gain(.12)|,
       lead:
         ~s|note("<e5 ~ c5 ~ a4 ~ b4 ~ e5 ~ g5 ~ e5 ~ d5 ~>").s("gm_music_box").gain(.4).delay(.4).delaytime(.5).delayfeedback(.45).room(.7)|
     }}
  end

  defp laurels do
    chords = cycles(List.duplicate("E B C#m A E B A E", 3))
    roots = "<e2 b1 cs2 a1 e2 b1 a1 e2>"

    fanfare =
      "[e5 gs5 b5@2 e6@4] [ds6@2 b5@2 cs6@4] [~ a5 b5 cs6@2 b5@2 gs5@2] [e5@4 ~@4] [e5 fs5 gs5@2 b5@4] [e6@8] [~@6 b5@2] [e6@8]"

    {24,
     %{
       drums:
         ~s|s("[bd hh sd [hh bd]]").bank("RolandTR909").gain(.65).superimpose(x => x.s("cr").gain(.4).mask("<1 0!7>"))|,
       bass:
         ~s|note("#{roots}").s("gm_electric_bass_finger").struct("[x ~ x x] [x ~ x ~]").gain(.5)|,
       pad:
         ~s|chord("#{chords}").voicing().s("gm_string_ensemble_1").attack(.5).release(1.0).clip(.8).lpf(1800).gain(.13)|,
       lead:
         ~s|note("#{cycles([fanfare, fanfare, fanfare])}").s("gm_brass_section").gain(.45).room(.4)|
     }}
  end

  defp ashes do
    chords = cycles(List.duplicate("Em!2 D!2 CM7!2 Bm!2", 3))
    lament = "[b4@3 a4] [g4@4] [fs4@3 g4] [e4@4] [~@4] [d5@3 c5] [b4@4] [~@4]"

    {24,
     %{
       drums: ~s|s("bd ~ ~ ~").bank("RolandTR808").gain(.3).lpf(300)|,
       bass: ~s|note("<e2!2 d2!2 c2!2 b1!2>").s("gm_cello").gain(.4).clip(2)|,
       pad:
         ~s|chord("#{chords}").voicing().s("gm_string_ensemble_1").attack(.5).release(1.0).clip(.8).lpf(1800).gain(.13)|,
       lead:
         ~s|note("#{cycles([lament, lament, lament])}").s("gm_oboe").gain(.4).delay(.25).delaytime(.75).delayfeedback(.3).room(.6)|
     }}
  end

  defp cycles(phrases), do: Score.cycles(phrases)

  defp root_of(chord), do: Score.root_of(chord)
end
