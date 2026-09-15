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
    Voice.new(shape: :noise, cutoff: 0.18, envelope: Envelope.new(attack: 0.005, decay: 0.6, sustain: 0.0, release: 0.2), gain: 0.55)
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

  def voice(_other), do: nil

  defp run(freqs, decay, gain) do
    freqs
    |> Enum.with_index()
    |> Enum.map(fn {freq, index} ->
      {index * 60, Voice.new(shape: :sine, freq: freq, envelope: Envelope.hit(decay), gain: gain)}
    end)
  end
end
