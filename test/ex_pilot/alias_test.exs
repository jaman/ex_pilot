defmodule ExPilot.AliasTest do
  use ExUnit.Case, async: false

  alias ExPilot.Alias

  setup do
    dir = Path.join(System.tmp_dir!(), "ex_pilot_alias_#{System.os_time(:nanosecond)}")
    File.mkdir_p!(dir)

    {:ok, accounts} =
      Drafter.Accounts.start_link(
        path: Path.join(dir, "accounts.terms"),
        iterations: 1_000,
        name: ExPilot.Accounts
      )

    :ok = Drafter.Accounts.register(accounts, "alice", "alices password")
    :ok = Drafter.Accounts.register(accounts, "bob", "bobs password")

    on_exit(fn ->
      if Process.alive?(accounts), do: GenServer.stop(accounts)
      File.rm_rf!(dir)
    end)

    :ok
  end

  test "an account with no alias is seen under an anonymous one: two words and a number, the same every time, different per account" do
    seen = Alias.of("alice")
    assert seen =~ ~r/^[a-z]+-[a-z]+-\d\d$/
    assert Alias.of("alice") == seen
    assert Alias.of("bob") != seen
    refute Alias.chosen?("alice")
  end

  test "an alias the account chose is what it is seen under, and can be given up" do
    assert :ok = Alias.put("alice", "Ace")
    assert Alias.of("alice") == "Ace"
    assert Alias.chosen?("alice")
    assert :ok = Alias.put("alice", "")
    assert Alias.of("alice") =~ ~r/^[a-z]+-[a-z]+-\d\d$/
  end

  test "an alias cannot be another account's alias, another account's username, or an anonymous name" do
    assert :ok = Alias.put("alice", "Ace")
    assert {:error, :taken} = Alias.put("bob", "ace")
    assert {:error, :taken} = Alias.put("bob", "Alice")
    assert {:error, :taken} = Alias.put("bob", Alias.of("alice"))
    assert :ok = Alias.put("bob", "bob")
  end

  test "an alias is one to thirty-two letters, digits, spaces, underscores or dashes" do
    assert {:error, :invalid} = Alias.put("alice", String.duplicate("a", 33))
    assert {:error, :invalid} = Alias.put("alice", "no<script>")
    assert :ok = Alias.put("alice", "Red Baron_2")
  end

  test "resolve/1 finds the account behind an alias or an anonymous name, and nothing behind a username" do
    :ok = Alias.put("alice", "Ace")
    assert Alias.resolve("ace") == "alice"
    assert Alias.resolve(Alias.of("bob")) == "bob"
    assert Alias.resolve("alice") == nil
    assert Alias.resolve("nobody") == nil
  end

  test "label/1 tells the player their own name and how others see them" do
    assert Alias.label("alice") == "alice (#{Alias.of("alice")})"
    :ok = Alias.put("alice", "alice")
    assert Alias.label("alice") == "alice"
  end
end
