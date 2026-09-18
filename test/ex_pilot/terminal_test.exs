defmodule ExPilot.TerminalTest do
  use ExUnit.Case, async: false

  alias Drafter.Test, as: DT
  alias ExPilot.Arenas

  @fixture Path.join(__DIR__, "../fixtures/dogfight.map.gz")

  setup do
    Code.ensure_loaded!(Cauldron2D.Drafter.Surface)
    Drafter.Widget.Registry.register(Cauldron2D.Drafter.Surface)
    ExPilot.Art.install()
    dir = Path.join(System.tmp_dir!(), "ex_pilot_terminal_#{System.os_time(:nanosecond)}")
    File.mkdir_p!(dir)
    System.put_env("XDG_CONFIG_HOME", Path.join(dir, "config"))
    :ok = Arenas.register(:terminaltest, @fixture, robots: 1)

    ctx =
      DT.start_headless(ExPilot.Terminal, %{username: "alice", sink: TuningFork.Sink.Silent},
        size: {100, 30}
      )

    on_exit(fn ->
      DT.stop(ctx)
      Arenas.close(:terminaltest)
      File.rm_rf!(dir)
    end)

    {:ok, ctx: ctx}
  end

  test "the title is the program's own; Enter opens the client at its lobby and Esc comes back",
       %{ctx: ctx} do
    assert DT.screen_text(ctx) =~ "EXPILOT"
    assert DT.screen_text(ctx) =~ "host a server"
    DT.send_key(ctx, :enter)

    assert :ok ==
             DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "terminaltest" end, timeout: 3_000)

    assert DT.screen_text(ctx) =~ "Arenas"
    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "fuel" end, timeout: 8_000)
    assert Arenas.humans(:terminaltest) == ["alice"]
    DT.send_key(ctx, :escape)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "Arenas" end, timeout: 3_000)
    DT.send_key(ctx, :escape)

    assert :ok ==
             DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "host a server" end, timeout: 3_000)

    assert DT.get_state(ctx).client == nil
    assert :ok == DT.wait_for(ctx, fn _ -> Arenas.humans(:terminaltest) == [] end, timeout: 2_000)
  end

  test "the host, connect and leaders screens open from the title and close on escape", %{
    ctx: ctx
  } do
    DT.send_key(ctx, :h)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "start the server" end)
    DT.send_key(ctx, :escape)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "connect to a server" end)
    DT.send_key(ctx, :c)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "Where are the arenas" end)
    DT.send_key(ctx, :escape)
    DT.send_key(ctx, :l)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "Leaders" end)
    assert DT.screen_text(ctx) =~ "▶ today"
    DT.send_key(ctx, :right)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "▶ this week" end)
    DT.send_key(ctx, :escape)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "host a server" end)
  end
end
