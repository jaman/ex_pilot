defmodule ExPilot.DuelsTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.Player
  alias ExPilot.{Arenas, Duels}

  @fixture Path.join(__DIR__, "../fixtures/dogfight.map.gz")

  setup do
    :ok = Arenas.register(:dueltest, @fixture, robots: 1)
    Phoenix.PubSub.subscribe(ExPilot.Web.PubSub, "duels")

    on_exit(fn ->
      for duel <- Duels.list(), do: Arenas.close(duel.arena)
      Arenas.close(:dueltest)
    end)

    :ok
  end

  test "a challenge makes a private arena only the two may fly in, the first to the kills wins it, and it closes after" do
    assert {:error, :yourself} = Duels.challenge("alice", "alice", :dueltest)
    assert {:error, :unknown_arena} = Duels.challenge("alice", "bob", :nowhere)
    assert {:ok, duel} = Duels.challenge("alice", "bob", :dueltest, first_to: 1)

    assert %{challenger: "alice", challenged: "bob", first_to: 1, winner: nil, base: :dueltest} =
             duel

    assert_receive {:duels, :changed}, 500

    assert Enum.any?(
             Arenas.list(),
             &(&1.id == duel.arena and &1.mode == :duel and &1.kind == ExPilot.Mode.kind(:duel) and
                 &1.note =~ "alice vs bob")
           )

    world = Arenas.world_name(duel.arena)
    assert {:error, :not_invited} = Player.join(world, "carol", %{username: "carol"})
    assert :ok = Player.join(world, "carol", %{username: "carol", spectate: true})
    Player.leave(world, "carol")
    assert Arenas.humans(duel.arena) == []
    refute Enum.any?(Cauldron2D.World.players(world), &match?({:robot, _}, &1))

    task =
      Task.async(fn ->
        :ok = Player.join(world, "alice", %{username: "alice"})
        :ok = Player.join(world, "bob", %{username: "bob"})

        receive do
          :done -> :ok
        end
      end)

    Process.sleep(100)
    assert %{mode: :duel} = ExPilot.Game.view(Cauldron2D.World.snapshot(world), "alice")
    ExPilot.Duels.result(Duels, duel.arena, %{won?: true, name: "alice", mode: :duel})
    assert_receive {:duels, :changed}, 500
    assert %{winner: "alice", ended: :won} = Enum.find(Duels.list(), &(&1.id == duel.id))
    send(task.pid, :done)
    Task.await(task)
  end

  test "the challenged declines and the challenger withdraws; nobody else can, and the arena goes with it" do
    assert {:ok, duel} = Duels.challenge("alice", "bob", :dueltest, first_to: 1)
    assert {:error, :not_yours} = Duels.cancel(duel.id, "carol")
    assert :ok = Duels.cancel(duel.id, "bob")
    assert_receive {:duels, :changed}, 500
    assert %{ended: :declined} = Enum.find(Duels.list(), &(&1.id == duel.id))
    refute Enum.any?(Arenas.list(), &(&1.id == duel.arena))
    assert {:error, :over} = Duels.cancel(duel.id, "alice")

    assert {:ok, again} = Duels.challenge("alice", "bob", :dueltest, first_to: 1)
    assert :ok = Duels.cancel(again.id, "alice")
    assert Enum.any?(Duels.list(), &(&1.id == again.id and &1.ended == :withdrawn))
  end

  test "a duel nobody has flown expires" do
    {:ok, duels} = Duels.start_link(name: nil, expire_after: 100)
    assert {:ok, duel} = Duels.challenge("alice", "bob", :dueltest, first_to: 1, duels: duels)
    assert Enum.any?(Arenas.list(), &(&1.id == duel.arena))
    Process.sleep(300)
    assert [%{ended: :expired}] = Duels.list(duels)
    refute Enum.any?(Arenas.list(), &(&1.id == duel.arena))
  end
end
