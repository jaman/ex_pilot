defmodule ExPilot.Guide do
  @moduledoc """
  What everything in the arena is: the things on the map, the weapons, and every item
  with the key that uses it, in sections of entries with the art the atlas draws them
  with. The terminal shows it from the title and the lobby, the browser on its guide page.

      ExPilot.Guide.sections()
  """

  alias ExPilot.Art

  @type entry :: %{art: term(), name: String.t(), text: String.t()}

  @doc "The guide's sections, each a heading and its entries."
  @spec sections() :: [{String.t(), [entry()]}]
  def sections do
    [
      {"On the map",
       [
         %{
           art: Art.ship(nil, 16),
           name: "Your ship",
           text:
             "Turn, thrust and fire; the pointer steers it. It sits on its base until it thrusts."
         },
         %{
           art: :base_up,
           name: "Base",
           text:
             "Where a ship starts and comes back after it is lost. Numbered bases belong to a team."
         },
         %{
           art: :wall,
           name: "Wall",
           text:
             "Touch one slowly or with the shield up and you bounce; hit it fast and you crash."
         },
         %{
           art: :fuel,
           name: "Fuel station",
           text:
             "Hover within two tiles to fill the tank. Ten seconds on an empty tank loses the ship."
         },
         %{
           art: :wormhole,
           name: "Wormhole",
           text: "Fly in and come out of another one somewhere else on the map."
         },
         %{
           art: :cannon_up,
           name: "Cannon",
           text:
             "Fires at any ship in front of it within twelve tiles. Shielded ships shrug the shots off."
         },
         %{
           art: :gravity,
           name: "Gravity point",
           text: "Pulls, pushes or swirls ships and shots that pass near it."
         },
         %{
           art: :target,
           name: "Target",
           text:
             "Belongs to the nearest team; three hits from another team destroy it for a while and score."
         },
         %{
           art: :treasure,
           name: "Treasure",
           text: "A team's home for the ball. Carry another team's ball into yours to score."
         },
         %{
           art: :ball,
           name: "Ball",
           text:
             "Picked up by flying over it and carried on a string that snaps if you pull too hard; v drops it."
         },
         %{
           art: :checkpoint,
           name: "Checkpoint",
           text: "On a race map, pass them in order A, B, C… to complete a lap."
         }
       ]},
      {"Weapons",
       [
         %{
           art: :shot,
           name: "Shot",
           text:
             "Space or the left button. Costs a little fuel; kills an unshielded ship it meets."
         },
         %{
           art: :shield,
           name: "Shield",
           text:
             "w or shift. Bounces shots and wall hits while it burns fuel; ships that meet shielded bounce apart."
         },
         %{
           art: :mine,
           name: "Mine",
           text:
             "1 drops one where you are. It arms after a moment and blows up the next ship over it."
         },
         %{
           art: :torpedo,
           name: "Torpedo",
           text: "2 fires the missile n has chosen. A torpedo flies straight and fast."
         },
         %{
           art: :smart,
           name: "Smart missile",
           text: "Turns toward the nearest enemy as it flies."
         },
         %{
           art: :heat,
           name: "Heat seeker",
           text: "Chases the hottest exhaust it can find: a ship that is thrusting."
         },
         %{
           art: :beam,
           name: "Laser",
           text:
             "3 fires a beam that hits the first ship in line at once. On some maps it only stuns."
         }
       ]},
      {"Items — fly over one to pick it up",
       [
         item(:fuel, "Fuel pack", "Adds 300 to the tank on the spot."),
         item(:tank, "Tank", "A bigger tank: 500 more capacity, and it comes full."),
         item(:armor, "Armour", "A layer that takes one hit that would have killed you."),
         item(
           :ecm,
           "ECM",
           "e jams every enemy within reach: their controls go haywire for a few seconds."
         ),
         item(:mine, "Mines", "One mine each; 1 drops one."),
         item(:missile, "Missiles", "One missile each; 2 fires, n picks torpedo, smart or heat."),
         item(
           :cloak,
           "Cloak",
           "c hides your ship from everyone without a sensor, until you press c again."
         ),
         item(:sensor, "Sensor", "Shows cloaked ships to you."),
         item(:wideangle, "Wide angle", "Every shot becomes three, fanned out ahead."),
         item(:rearshot, "Rear shot", "Every shot also fires one straight back."),
         item(:afterburner, "Afterburner", "Thrust is stronger for as long as you hold it."),
         item(
           :transporter,
           "Transporter",
           "r steals an item from the nearest enemy within reach."
         ),
         item(:mirror, "Mirror", "Lasers that hit you bounce off instead."),
         item(
           :deflector,
           "Deflector",
           "x turns a field on that pushes shots away, for a fuel cost."
         ),
         item(:hyperjump, "Hyperjump", "u jumps the ship to a random open place on the map."),
         item(:phasing, "Phasing", "p lets you pass through walls for a few seconds."),
         item(:laser, "Laser", "3 fires it; each item is one charge of beam."),
         item(
           :emergency_thrust,
           "Emergency thrust",
           "] gives a burst of thrust that costs no fuel."
         ),
         item(
           :emergency_shield,
           "Emergency shield",
           "[ raises a shield that holds without fuel for a while."
         ),
         item(
           :tractor_beam,
           "Tractor beam",
           "g pulls the nearest ship toward you, b pushes it away."
         ),
         item(:autopilot, "Autopilot", "o holds the ship still against drift and gravity.")
       ]}
    ]
  end

  defp item(kind, name, text), do: %{art: Art.item(kind), name: name, text: text}
end
