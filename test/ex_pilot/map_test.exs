defmodule ExPilot.MapTest do
  use ExUnit.Case, async: true

  alias ExPilot.Map, as: Arena

  @small """
  mapwidth: 8
  mapheight: 6
  edgewrap: no
  gravity: -1.5
  maxrobots: 2
  mapData: \\multiline: END
  qxxxxxxs
  x      x
  x _ #  x
  x @  + x
  xr    cx
  axxxxxxw
  END
  """

  setup_all do
    {:ok, arena} = Arena.parse(@small)
    {:ok, arena: arena}
  end

  test "walls, diagonals and empty space feed the collision grid", %{arena: arena} do
    grid = Arena.grid(arena)
    assert grid.({1, 0}) == :solid
    assert grid.({0, 0}) == {:diagonal, :se}
    assert grid.({7, 0}) == {:diagonal, :sw}
    assert grid.({0, 5}) == {:diagonal, :ne}
    assert grid.({7, 5}) == {:diagonal, :nw}
    assert grid.({2, 1}) == :open
    assert grid.({4, 2}) == :open, "fuel is not a wall"
  end

  test "outside a non-wrapping map is solid", %{arena: arena} do
    assert Arena.grid(arena).({-1, 3}) == :solid
    assert Arena.grid(arena).({3, 9}) == :solid
  end

  test "features are found with their tiles", %{arena: arena} do
    assert Arena.bases(arena) == [%{pos: {2, 2}, team: nil, dir: :up}]
    assert Arena.fuel(arena) == [{4, 2}]
    assert Arena.wormholes(arena) == [%{pos: {2, 3}, kind: :normal}]
    assert [%{pos: {5, 3}, kind: :attract}] = Arena.gravity_points(arena)
    assert Arena.cannons(arena) == [%{pos: {1, 4}, facing: :up}, %{pos: {6, 4}, facing: :right}]
  end

  test "options are read with XPilot's names and defaults", %{arena: arena} do
    assert Arena.option(arena, :gravity) == -1.5
    assert Arena.option(arena, :maxrobots) == 2
    assert Arena.option(arena, :edgewrap) == false
    assert Arena.option(arena, :shotspeed) == 21.0
    assert Arena.option(arena, :teamplay) == false
  end

  test "the classic corpus loads", _ do
    {:ok, dogfight} = Arena.parse_file(Path.join(__DIR__, "../fixtures/dogfight.map.gz"))
    assert dogfight.map.width == 120
    assert Arena.option(dogfight, :edgewrap) == true
    assert length(Arena.bases(dogfight)) == 6
    assert Arena.grid(dogfight).({-1, 0}) == Arena.grid(dogfight).({119, 0})

    for path <- Path.wildcard(Path.join(:code.priv_dir(:ex_pilot), "maps/*.map.gz")) do
      assert {:ok, arena} = Arena.parse_file(path), "#{Path.basename(path)} does not load"
      assert Arena.bases(arena) != [], "#{Path.basename(path)} has no base"
    end
  end

  test "the feature lists are read from the parsed map, not scanned from its tiles", _ do
    rows = for y <- 0..299, do: for(x <- 0..299, do: if(rem(x * y, 97) == 0, do: "x", else: " ")) |> Enum.join()
    text = "mapwidth: 300\nmapheight: 300\nmapData: \\multiline: END\n" <> Enum.join(rows, "\n") <> "\nEND\n"
    {:ok, big} = Arena.parse(text)

    {us, _} = :timer.tc(fn -> for _ <- 1..1_000, do: {Arena.fuel(big), Arena.wormholes(big), Arena.treasures(big), Arena.bases(big)} end)
    assert us < 200_000, "a thousand feature reads took #{div(us, 1000)} ms"
  end

  test "a base faces away from the wall it sits on: down under a ceiling, sideways off a wall, up by default", _ do
    {:ok, arena} = Arena.parse("mapwidth: 7\nmapheight: 3\nmapData: \\multiline: END\n _x   x\n_   _x_\n   x  x\nEND\n")
    assert Enum.map(Arena.bases(arena), &{&1.pos, &1.dir}) == [{{1, 0}, :down}, {{0, 1}, :right}, {{4, 1}, :left}, {{6, 1}, :up}]
    assert Arena.art(arena, {1, 0}) == :base_down
    assert Arena.art(arena, {0, 1}) == :base_right
    assert Arena.art(arena, {4, 1}) == :base_left
  end

  test "team bases carry their team", _ do
    {:ok, arena} = Arena.parse("mapwidth: 4\nmapheight: 2\nmapData: \\multiline: END\n1 2 \nxxxx\nEND\n")
    assert Arena.bases(arena) == [%{pos: {0, 0}, team: 1, dir: :up}, %{pos: {2, 0}, team: 2, dir: :up}]
  end

  test "art for a tile", %{arena: arena} do
    assert Arena.art(arena, {1, 0}) == :wall
    assert Arena.art(arena, {0, 0}) == :wall_se
    assert Arena.art(arena, {4, 2}) == :fuel
    assert Arena.art(arena, {2, 2}) == :base_up
    assert Arena.art(arena, {3, 1}) == nil
  end
end
