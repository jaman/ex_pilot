defmodule ExPilot.Sound do
  @moduledoc """
  The sound each game event makes.

  `voice/1` maps an event name from `ExPilot.Game` to a `TuningFork.Voice`, a run of
  them, or `nil` for silence. `Cauldron2D.Audio` places each by the event's position.
  """

  alias TuningFork.{Envelope, Voice}

  @doc "The sound for an event name; `nil` for none."
  @spec voice(atom()) :: Cauldron2D.Audio.sound()
  def voice(:fire) do
    Voice.new(shape: :square, freq: 880.0, sweep: 0.35, envelope: Envelope.hit(0.07), gain: 0.22)
  end

  def voice(:cannon) do
    Voice.new(shape: :saw, freq: 320.0, sweep: 0.5, envelope: Envelope.hit(0.12), gain: 0.28)
  end

  def voice(:explosion) do
    Voice.new(
      shape: :noise,
      cutoff: 0.18,
      envelope: Envelope.new(attack: 0.005, decay: 0.6, sustain: 0.0, release: 0.2),
      gain: 0.55
    )
  end

  def voice(:kill), do: run([659.25, 523.25, 392.0], 0.12, 0.3)

  def voice(:bounce) do
    Voice.new(shape: :triangle, freq: 200.0, sweep: 0.7, envelope: Envelope.hit(0.08), gain: 0.35)
  end

  def voice(:shot_wall) do
    Voice.new(shape: :noise, cutoff: 0.45, envelope: Envelope.hit(0.04), gain: 0.16)
  end

  def voice(:refuel) do
    Voice.new(shape: :sine, freq: 1320.0, envelope: Envelope.hit(0.05), gain: 0.12)
  end

  def voice(:wormhole), do: run([392.0, 523.25, 659.25, 783.99], 0.14, 0.3)

  def voice(:respawn) do
    Voice.new(shape: :sine, freq: 440.0, sweep: 1.8, envelope: Envelope.hit(0.25), gain: 0.3)
  end

  def voice(:pick_up), do: run([523.25, 659.25, 783.99], 0.08, 0.25)

  def voice(:missile),
    do:
      Voice.new(
        shape: :saw,
        freq: 220.0,
        sweep: 0.5,
        cutoff: 0.4,
        envelope: Envelope.hit(0.3),
        gain: 0.25
      )

  def voice(:mine),
    do: Voice.new(shape: :square, freq: 110.0, envelope: Envelope.hit(0.15), gain: 0.2)

  def voice(:laser),
    do: Voice.new(shape: :saw, freq: 1760.0, sweep: 0.2, envelope: Envelope.hit(0.12), gain: 0.2)

  def voice(:cloak), do: run([880.0, 659.25, 440.0], 0.1, 0.2)

  def voice(:ecm),
    do: Voice.new(shape: :noise, highpass: 0.3, envelope: Envelope.hit(0.4), gain: 0.2)

  def voice(:transporter), do: run([440.0, 880.0, 1760.0], 0.08, 0.2)

  def voice(:hyperjump),
    do: Voice.new(shape: :sine, freq: 330.0, sweep: 3.0, envelope: Envelope.hit(0.25), gain: 0.25)

  def voice(:target_hit),
    do: Voice.new(shape: :square, freq: 330.0, envelope: Envelope.hit(0.06), gain: 0.18)

  def voice(:target_destroyed), do: run([392.0, 329.63, 261.63, 196.0], 0.15, 0.3)
  def voice(:goal), do: run([523.25, 659.25, 783.99, 1046.5], 0.14, 0.3)
  def voice(:checkpoint), do: run([783.99, 1046.5], 0.08, 0.2)
  def voice(:finish), do: run([523.25, 659.25, 783.99, 1046.5, 1318.5], 0.16, 0.3)
  def voice(_other), do: nil

  defp run(freqs, decay, gain) do
    freqs
    |> Enum.with_index()
    |> Enum.map(fn {freq, index} ->
      {index * 60, Voice.new(shape: :sine, freq: freq, envelope: Envelope.hit(decay), gain: gain)}
    end)
  end
end
