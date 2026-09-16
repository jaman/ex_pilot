defmodule ExPilot.Web.ArenaChannel do
  @moduledoc "A browser player in an ExPilot arena; see `Cauldron2D.Web.Channel`."

  use Cauldron2D.Web.Channel, game: ExPilot.Web.Game
end
