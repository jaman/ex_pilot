defmodule ExPilot.Web.UserSocket do
  @moduledoc """
  The player socket: a browser connects with the token its page was given at login and
  the kind of client it is (`web` or `touch`), and its channels carry the player's name
  and that kind's sound levels.
  """

  use Cauldron2D.Net.Socket,
    channel: ExPilot.Web.ArenaChannel,
    verify: {ExPilot.Web.Auth, :connect},
    topic: "arena"
end
