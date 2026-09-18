defmodule ExPilot.Client.SoundPage do
  @moduledoc """
  The "No sound?" page of a served ssh session: the player's sound port on the server,
  the player program to run on their machine for each operating system, and the ssh
  line whose reverse tunnel carries the sound.

      ExPilot.Client.SoundPage.pages(%{pulse_port: 24713, served_by: %{host: "arcade", port: 2222}, username: "alice"})
  """

  @ffplay "ffplay -nodisp -autoexit -fflags nobuffer -analyzeduration 0 -probesize 32 -f s16le -ar 44100 -ch_layout stereo -i \"tcp://127.0.0.1:4713?listen\""

  @doc "The page, for mount props with a `:pulse_port` and a `:served_by`; none otherwise."
  @spec pages(map()) :: [Cauldron2D.Client.Game.page()]
  def pages(%{pulse_port: port, served_by: %{host: host, port: ssh_port}} = props)
      when is_integer(port) do
    username = Map.get(props, :username, "<name>")

    [
      %{
        key: :n,
        hint: "No sound?",
        title: "Sound",
        render: fn -> render(port, host, ssh_port, username) end
      }
    ]
  end

  def pages(_props), do: []

  @doc "The command line that plays the sound on the player's machine."
  @spec player_command() :: String.t()
  def player_command, do: @ffplay

  defp render(port, host, ssh_port, username) do
    dim = %{fg: {130, 130, 140}}

    [
      [
        "The game plays its sound on your machine: it sends audio to port #{port} on the server, and ssh carries"
      ],
      [
        "that to port 4713 on yours, where a player program turns it into sound. Two steps, in either order."
      ],
      [""],
      [
        {"1.  On your machine, in a terminal of its own, run the player for your system and leave it running:",
         %{bold: true}}
      ],
      [""],
      [{"    macOS / Linux  (ffmpeg:  brew install ffmpeg   or   apt install ffmpeg)", dim}],
      ["    while :; do #{@ffplay}; done"],
      [""],
      [{"    Windows, cmd  (ffmpeg:  winget install ffmpeg)", dim}],
      ["    for /L %i in (1,0,2) do #{@ffplay}"],
      [""],
      [{"    Windows, PowerShell", dim}],
      ["    while ($true) { #{@ffplay} }"],
      [""],
      [{"2.  Connect to the game with the tunnel that carries the sound:", %{bold: true}}],
      [""],
      ["    ssh -p #{ssh_port} -R #{port}:127.0.0.1:4713 #{username}@#{host}"],
      [""],
      [
        {"The player restarts itself for every connection, so it can stay running between games. If ssh says",
         dim}
      ],
      [
        {"remote port forwarding failed, another of your sessions still holds port #{port} on the server.",
         dim}
      ]
    ]
  end
end
