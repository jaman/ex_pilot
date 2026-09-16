defmodule ExPilot.GuideTest do
  use ExUnit.Case, async: true

  alias ExPilot.{Art, Guide, Items}

  test "every entry's art is in the atlas and every item has an entry with its key" do
    Art.install()
    arts = Cauldron2D.Atlas.fetch(Art.name()).entries

    entries = for {_heading, section} <- Guide.sections(), entry <- section, do: entry
    assert length(Guide.sections()) >= 3

    for %{art: art, name: name, text: text} <- entries do
      assert Map.has_key?(arts, art), "#{name}'s art #{inspect(art)} is not in the atlas"
      assert String.length(text) > 10
    end

    for kind <- Items.kinds() do
      assert Enum.any?(entries, &(&1.art == Art.item(kind))), "no entry for #{kind}"
    end

    assert Enum.any?(entries, &(&1.text =~ "1 drops" or &1.text =~ "`1`"))
    assert ExPilot.Client.guide() == Guide.sections()
  end
end
