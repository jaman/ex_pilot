defmodule ExPilot.RosterTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.Player
  alias ExPilot.{Arenas, Roster}

  @fixture Path.join(__DIR__, "../fixtures/dogfight.map.gz")

  setup do
    :ok = Arenas.register(:rostered, @fixture, robots: 1)
    on_exit(fn -> Arenas.close(:rostered) end)
    Roster.clear()
    :ok
  end

  test "who is in which arena since when, and what happened lately" do
    assert Roster.online() == []
    world = Arenas.world_name(:rostered)

    :ok = Player.join(world, "alice", %{username: "alice"})
    assert :ok == wait(fn -> match?([%{id: "alice", arena: :rostered}], Roster.online()) end)
    [%{since: since}] = Roster.online()
    assert is_integer(since) and since <= System.system_time(:second)

    :ok = Player.leave(world, "alice")
    assert :ok == wait(fn -> Roster.online() == [] end)

    assert [
             %{what: :left, id: "alice", arena: :rostered},
             %{what: :joined, id: "alice", arena: :rostered}
           ] =
             Roster.lately() |> Enum.map(&Map.take(&1, [:what, :id, :arena]))
  end

  test "a logged-in session is on the roster before it is in an arena, and after it leaves one" do
    world = Arenas.world_name(:rostered)
    parent = self()

    session =
      spawn(fn ->
        :ok = Cauldron2D.Sessions.track("cal", :web)
        send(parent, :tracked)

        receive do
          :stop -> :ok
        end
      end)

    assert_receive :tracked
    assert :ok == wait(fn -> match?([%{id: "cal", kind: :web, arena: nil}], Roster.online()) end)

    :ok = Player.join(world, "cal", %{username: "cal"})

    assert :ok ==
             wait(fn -> match?([%{id: "cal", kind: :web, arena: :rostered}], Roster.online()) end)

    send(session, :stop)

    assert :ok ==
             wait(fn -> match?([%{id: "cal", kind: nil, arena: :rostered}], Roster.online()) end)

    :ok = Player.leave(world, "cal")
    assert :ok == wait(fn -> Roster.online() == [] end)

    assert [:left, :logged_out, :joined, :logged_in] = Enum.map(Roster.lately(), & &1.what)
    assert [%{what: :logged_in, id: "cal", kind: :web} | _] = Enum.reverse(Roster.lately())
  end

  test "keeping the roster starts no arena" do
    :ok = Arenas.register(:idle_one, @fixture, robots: 0)
    on_exit(fn -> Arenas.close(:idle_one) end)
    world = Arenas.world_name(:rostered)
    :ok = Player.join(world, "eve", %{username: "eve"})
    assert :ok == wait(fn -> match?([%{id: "eve", arena: :rostered}], Roster.online()) end)
    :ok = Player.leave(world, "eve")
    assert :ok == wait(fn -> Roster.online() == [] end)
    refute Arenas.running?(:idle_one)
  end

  test "a world that stops takes its pilots off the roster" do
    world = Arenas.world_name(:rostered)
    :ok = Player.join(world, "dee", %{username: "dee"})
    assert :ok == wait(fn -> match?([%{id: "dee", arena: :rostered}], Roster.online()) end)
    :ok = Arenas.stop(:rostered)
    assert :ok == wait(fn -> Roster.online() == [] end)
    assert [%{what: :left, id: "dee", arena: :rostered} | _] = Roster.lately()
  end

  test "robots are not on the roster" do
    world = Arenas.world_name(:rostered)
    :ok = Player.join(world, "bob", %{username: "bob"})
    assert :ok == wait(fn -> Enum.any?(Roster.online(), &(&1.id == "bob")) end)
    refute Enum.any?(Roster.online(), &match?({:robot, _}, &1.id))
    :ok = Player.leave(world, "bob")
  end

  defp wait(check, tries \\ 50) do
    cond do
      check.() -> :ok
      tries == 0 -> :timeout
      true -> Process.sleep(20) && wait(check, tries - 1)
    end
  end
end
