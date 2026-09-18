defmodule ExPilot.Wx.ScreensTest do
  use ExUnit.Case, async: true

  alias ExPilot.Wx.Screens

  @size {1280, 800}

  defp texts(items), do: Enum.map(items, &elem(&1, 2))

  test "the title centres the name, the tagline and the menu, and the menu items carry the keys a click stands for" do
    items =
      Screens.draw(
        %{screen: :title, title: %{name: "DOTS", tagline: "little dots"}, status: ""},
        @size
      )

    assert Enum.all?(items, &match?({{:centre, 640}, _, _, _, _, _}, &1))

    assert texts(items) |> Enum.take(8) == [
             "DOTS",
             "little dots",
             "Enter  play",
             "c  connect to a server or a node",
             "l  leaders",
             "s  settings",
             "h  host a server",
             "q  quit"
           ]

    assert Enum.map(items, &elem(&1, 5)) |> Enum.take(8) == [
             nil,
             nil,
             {:key, 13},
             {:key, ?C},
             {:key, ?L},
             {:key, ?S},
             {:key, ?H},
             {:key, ?Q}
           ]
  end

  test "the leaders screen shows the periods, the metrics and the ranked rows" do
    board = [
      %{
        name: "alice",
        account: "alice",
        value: 2.5,
        rounds: 4,
        values: %{kills: 10, ratio: 2.5, wins: 2}
      },
      %{
        name: "bob",
        account: "bob",
        value: 1.0,
        rounds: 1,
        values: %{kills: 1, ratio: 1.0, wins: 0}
      }
    ]

    items =
      Screens.draw(
        %{
          screen: :leaders,
          leaders: %{period: :week, metric: :ratio, board: board},
          from: :lobby,
          status: ""
        },
        @size
      )

    text = texts(items)
    assert "▶ this week" in text and "  today" in text
    assert "▶ kills a death" in text
    assert Enum.any?(text, &(&1 =~ ~r/^ 1  alice\s+2\.50\s+4 rounds  10 kills  2 won$/))
    assert Enum.any?(items, &match?({_, _, _, _, _, {:period, 2}}, &1))
    assert Enum.any?(items, &match?({_, _, _, _, _, {:metric, 5}}, &1))

    empty =
      Screens.draw(
        %{
          screen: :leaders,
          leaders: %{period: :day, metric: :kills, board: []},
          from: :title,
          status: ""
        },
        @size
      )
      |> texts()

    assert Enum.any?(empty, &(&1 =~ "nobody yet"))
  end

  test "the settings screen shows the levels as bars with the chosen one marked, the pointer switch, and clickable steps" do
    settings = %Cauldron2D.Drafter.Client.Settings{sfx: 0.85, music: 0.35, pointer: false}

    items =
      Screens.draw(
        %{screen: :settings, settings: settings, setting: 1, from: :lobby, status: ""},
        @size
      )

    text = texts(items)
    assert Enum.any?(text, &(&1 =~ ~r/^  effects\s+█{17}░{3}\s+85%$/u))
    assert Enum.any?(text, &(&1 =~ ~r/^▶ music\s+█{7}░{13}\s+35%$/u))
    assert Enum.any?(text, &(&1 =~ ~r/^  pointer steers\s+off$/))
    assert Enum.any?(items, &match?({_, _, _, _, _, {:setting, 0}}, &1))
    assert Enum.any?(items, &match?({_, _, "−", _, _, {:step, 1, -1}}, &1))
    assert Enum.any?(items, &match?({_, _, "+", _, _, {:step, 1, 1}}, &1))
    assert Enum.any?(items, &match?({_, _, _, _, _, {:step, 2, 1}}, &1))
    assert Enum.any?(text, &(&1 =~ "Esc  back to the arenas"))

    arena =
      Screens.draw(
        %{screen: :settings, settings: settings, setting: 0, from: :arena, status: ""},
        @size
      )
      |> texts()

    assert Enum.any?(arena, &(&1 =~ "Esc  back to the arena"))
  end

  test "the connect screen shows the wheres, the fields with the chosen one marked, secrets hidden, and the actions" do
    state = %{
      screen: :connect,
      wheres: [{"a server", []}, {"a node", []}],
      where: 1,
      fields: [{"url", "http://x", false}, {"password", "hunter2", true}],
      field: 1,
      actions: [{:connect, "log in"}, {:register, "register"}],
      status: "nope"
    }

    items = Screens.draw(state, @size)
    text = texts(items)
    assert "  a server" in text and "▶ a node" in text
    assert Enum.any?(text, &(&1 =~ ~r/^url\s+http:\/\/x$/))
    assert Enum.any?(text, &(&1 =~ ~r/^password\s+•••••••▏$/))
    assert "  log in" in text and "  register" in text
    assert Enum.any?(items, &match?({_, _, "  log in", _, _, {:choose, 0}}, &1))
    assert Enum.any?(items, &match?({_, _, _, _, _, {:where, 1}}, &1))
    assert List.last(text) == "nope"

    on_action = Screens.draw(%{state | field: 3}, @size) |> texts()
    assert "▶ register" in on_action
  end

  test "the lobby lists a window of arenas in columns with the chosen one marked and its note and team below" do
    arenas =
      for n <- 1..30,
          do: %{
            name: "arena #{n}",
            map: "Map #{n}",
            note: "#{n} robots",
            players: rem(n, 2),
            teams: if(n == 3, do: [1, 2], else: []),
            kind: ExPilot.Mode.kind(if(n == 3, do: :ctf, else: :dogfight))
          }

    items =
      Screens.draw(
        %{screen: :lobby, arenas: arenas, selected: 2, team: 2, status: "", who: "alice"},
        @size
      )

    text = texts(items)
    assert Enum.any?(items, &match?({_, _, _, _, _, {:row, 2}}, &1))
    assert Enum.any?(text, &(&1 =~ ~r/^▶ arena 3\s+$/))
    assert Enum.any?(text, &(&1 =~ ~r/^capture the flag\s*$/))
    assert Enum.any?(text, &(&1 =~ ~r/^1 flying\s*$/))
    assert "3 robots" in text
    assert Enum.any?(text, &(&1 =~ "team: 2"))
    assert Enum.any?(text, &(&1 =~ ~r/▼ \d+ more/))
    refute Enum.any?(text, &(&1 =~ "arena 30"))

    last =
      Screens.draw(
        %{screen: :lobby, arenas: arenas, selected: 29, team: nil, status: "", who: ""},
        @size
      )
      |> texts()

    assert Enum.any?(last, &(&1 =~ "▶ arena 30"))
    assert Enum.any?(last, &(&1 =~ ~r/▲ \d+ more/))
  end

  test "the summary and the serve screen" do
    defeat =
      Screens.draw(
        %{screen: :summary, summary: %{title: "Defeat", lines: ["a  3", "b  1"]}, status: ""},
        @size
      )

    assert {_, _, "Defeat", {255, 107, 107}, :title, nil} = hd(defeat)
    assert "a  3" in texts(defeat)

    serve =
      Screens.draw(
        %{
          screen: :serve,
          server: nil,
          serve_fields: [{"ssh port", "2222", false}],
          field: 0,
          serve_lines: [],
          status: ""
        },
        @size
      )

    assert "▶ start the server" in texts(serve)

    assert Enum.find_index(texts(serve), &(&1 == "▶ start the server")) <
             Enum.find_index(texts(serve), &(&1 =~ "ssh port"))

    on_field =
      Screens.draw(
        %{
          screen: :serve,
          server: nil,
          serve_fields: [{"ssh port", "2222", false}],
          field: 1,
          serve_lines: [],
          status: ""
        },
        @size
      )

    assert "  start the server" in texts(on_field) and
             Enum.any?(texts(on_field), &(&1 =~ ~r/^ssh port\s+2222▏$/))

    running =
      Screens.draw(
        %{
          screen: :serve,
          server: :some,
          serve_fields: [{"ssh port", "2222", false}],
          field: 0,
          serve_lines: ["play: ssh …"],
          status: ""
        },
        @size
      )

    assert "▶ stop the server" in texts(running) and "play: ssh …" in texts(running)
  end
end
