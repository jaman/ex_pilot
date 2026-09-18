defmodule ExPilot.Web.ArenaChannel do
  @moduledoc "A browser player in an ExPilot arena, its sound at 44 100 Hz stereo unless the browser asks otherwise (a phone asks for 22 050 Hz mono); see `Cauldron2D.Net.Channel`."

  use Cauldron2D.Net.Channel, game: ExPilot.Client, topic: "arena"
end
