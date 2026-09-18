defmodule ExPilot.Wx.Screens do
  @moduledoc """
  What the desktop's screens look like, as items `Cauldron2D.Wx.Text` draws: the title,
  the connect form, the lobby, the settings, the leaders, the summary and the serve form
  (the start or stop first, the settings under it), from the window's state.

      ExPilot.Wx.Screens.draw(state, {width, height})

  An item is `{x, y, text, colour, size, action}`, `x` a left edge or `{:centre, x}`,
  `size` one of `:small`, `:normal`, `:big`, `:title`, and `action` what a click on the
  item does — `{:key, code}` as if that key went down, `{:row, index}`, `{:where, index}`,
  `{:field, index}`, `{:choose, index}`, `{:setting, index}`, `{:step, index, -1 | 1}`,
  `{:period, index}`, `{:metric, index}`, `{:found, index}`, `:serve` — or `nil`. Pure:
  nothing here touches wx.
  """

  @type item ::
          {integer() | {:centre, integer()}, integer(), String.t(), {byte(), byte(), byte()},
           :small | :normal | :big | :title, term()}

  @text {228, 231, 243}
  @dim {129, 137, 168}
  @cyan {127, 214, 255}
  @amber {255, 184, 77}
  @green {111, 227, 154}
  @red {255, 107, 107}
  @line 22
  @window 14
  @enter {:key, 13}
  @escape {:key, 27}

  @doc "The items for the screen the state is on."
  @spec draw(map(), {pos_integer(), pos_integer()}) :: [item()]
  def draw(%{screen: :title} = state, size), do: title(state, size)
  def draw(%{screen: :connect} = state, size), do: connect(state, size)
  def draw(%{screen: :lobby} = state, size), do: lobby(state, size)
  def draw(%{screen: :settings} = state, size), do: settings(state, size)
  def draw(%{screen: :leaders} = state, size), do: leaders(state, size)
  def draw(%{screen: :summary} = state, size), do: summary(state, size)
  def draw(%{screen: :serve} = state, size), do: serve(state, size)
  def draw(_state, _size), do: []

  @doc "How many arenas the lobby lists at once."
  @spec window() :: pos_integer()
  def window, do: @window

  @doc "The leaders screen's periods, in order, as `Cauldron2D.Ledger` names them with their titles."
  @spec periods() :: [{Cauldron2D.Ledger.period(), String.t()}]
  def periods, do: [day: "today", week: "this week", all: "all time"]

  @doc "The leaders screen's metrics, in order, with their titles: `ExPilot.Ledger.metrics/0`."
  @spec metrics() :: [{atom(), String.t()}]
  def metrics, do: ExPilot.Ledger.metrics()

  @doc "The settings screen's rows, top to bottom: the fields of `Cauldron2D.Drafter.Client.Settings` it changes."
  @spec settings_rows() :: [:sfx | :music | :pointer]
  def settings_rows, do: [:sfx, :music, :pointer]

  defp title(%{title: %{name: name} = info} = state, {width, height}) do
    centre = div(width, 2)
    top = div(height, 3)

    [
      {{:centre, centre}, top, name, @cyan, :title, nil},
      {{:centre, centre}, top + 70, Map.get(info, :tagline, ""), @dim, :normal, nil},
      {{:centre, centre}, top + 140, "Enter  play", @text, :big, @enter},
      {{:centre, centre}, top + 140 + (@line + 8), "c  connect to a server or a node", @text,
       :big, {:key, ?C}},
      {{:centre, centre}, top + 140 + 2 * (@line + 8), "l  leaders", @text, :big, {:key, ?L}},
      {{:centre, centre}, top + 140 + 3 * (@line + 8), "s  settings", @text, :big, {:key, ?S}},
      {{:centre, centre}, top + 140 + 4 * (@line + 8), "h  host a server", @text, :big,
       {:key, ?H}},
      {{:centre, centre}, top + 140 + 5 * (@line + 8), "q  quit", @text, :big, {:key, ?Q}},
      {{:centre, centre}, height - 40, Map.get(state, :status, ""), @dim, :small, nil}
    ]
  end

  defp connect(state, {width, height}) do
    left = div(width, 2) - 260
    top = div(height, 4)

    tabs =
      state.wheres
      |> Enum.with_index()
      |> Enum.map(fn {{label, _fields}, i} ->
        {left + i * 200, top, if(i == state.where, do: "▶ " <> label, else: "  " <> label),
         if(i == state.where, do: @cyan, else: @dim), :normal, {:where, i}}
      end)

    found_top = top + 50 + (length(state.fields) + length(state.actions) + 2) * @line

    [{left, top - 50, "Where are the arenas?", @text, :big, nil}] ++
      tabs ++
      form_items(state.fields, state.field, left, top + 50) ++
      actions(
        state.actions,
        state.field,
        length(state.fields),
        left,
        top + 50 + (length(state.fields) + 1) * @line
      ) ++
      found_items(Map.get(state, :found, []), left, found_top) ++
      [
        {left, height - 70,
         "←→  where     ↑↓  field     type to fill in     Enter  choose     r  look again     Esc  back",
         @dim, :small, @escape},
        {left, height - 40, Map.get(state, :status, ""), @amber, :small, nil}
      ]
  end

  defp found_items([], left, top),
    do: [{left, top, "No server is calling on this network.", @dim, :small, nil}]

  defp found_items(found, left, top) do
    [{left, top, "Calling on this network — click one to fill the form in", @dim, :small, nil}] ++
      Enum.map(Enum.with_index(found), fn {server, i} ->
        {left, top + (i + 1) * @line,
         "▸ #{server.host}   #{server.http || "no web"}   #{server.node || "no node"}", @green,
         :normal, {:found, i}}
      end)
  end

  defp form_items(fields, chosen, left, top) do
    fields
    |> Enum.with_index()
    |> Enum.map(fn {{name, value, secret?}, i} ->
      shown = if secret?, do: String.duplicate("•", String.length(value)), else: value
      cursor = if i == chosen, do: "▏", else: ""
      colour = if i == chosen, do: @cyan, else: @text

      {left, top + i * @line, String.pad_trailing(name, 12) <> shown <> cursor, colour, :normal,
       {:field, i}}
    end)
  end

  defp actions(actions, chosen, offset, left, top) do
    actions
    |> Enum.with_index()
    |> Enum.map(fn {{_key, label}, i} ->
      chosen? = chosen == offset + i

      {left, top + i * @line, if(chosen?, do: "▶ " <> label, else: "  " <> label),
       if(chosen?, do: @cyan, else: @text), :normal, {:choose, i}}
    end)
  end

  defp lobby(state, {width, height}) do
    left = 60
    top = 60
    arenas = state.arenas
    count = length(arenas)
    first = state.selected |> Kernel.-(div(@window, 2)) |> min(count - @window) |> max(0)
    shown = arenas |> Enum.with_index() |> Enum.slice(first, @window)

    rows =
      shown
      |> Enum.with_index()
      |> Enum.flat_map(fn {{arena, index}, row} ->
        y = top + 50 + row * @line
        chosen? = index == state.selected
        {kind, kind_colour} = kind_of(arena)
        players = Map.get(arena, :players, 0)

        [
          {left, y, if(chosen?, do: "▶ ", else: "  ") <> fit(arena.name, 20),
           if(chosen?, do: @cyan, else: @text), :normal, {:row, index}},
          {left + 260, y, fit(kind, 18), kind_colour, :normal, {:row, index}},
          {left + 470, y, fit(flying(players), 12), if(players > 0, do: @green, else: @dim),
           :normal, {:row, index}},
          {left + 610, y, fit(Map.get(arena, :map, ""), 32), if(chosen?, do: @text, else: @dim),
           :normal, {:row, index}}
        ]
      end)

    more_above =
      if first > 0,
        do: [{left, top + 50 - @line, "  ▲ #{first} more", @dim, :small, {:key, 366}}],
        else: []

    more_below =
      if first + @window < count,
        do: [
          {left, top + 50 + @window * @line, "  ▼ #{count - first - @window} more", @dim, :small,
           {:key, 367}}
        ],
        else: []

    empty =
      if arenas == [],
        do: [{left, top + 50, "no arenas — r refreshes", @dim, :normal, {:key, ?R}}],
        else: []

    [
      {left, top, "Arenas", @text, :big, nil},
      {left + 260, top + 20, "kind", @dim, :small, nil},
      {left + 470, top + 20, "flying", @dim, :small, nil},
      {left + 610, top + 20, "map", @dim, :small, nil},
      {width - 60 - 9 * String.length(Map.get(state, :who, "")), top, Map.get(state, :who, ""),
       @dim, :normal, nil}
    ] ++
      more_above ++
      rows ++
      more_below ++
      empty ++ chosen_arena(state, {width, height}) ++ lobby_hints(state, left, height)
  end

  defp lobby_hints(state, left, height) do
    hints = [
      {"Enter  join", @enter},
      {"w  watch", {:key, ?W}},
      {"t  team", {:key, ?T}},
      {"l  leaders", {:key, ?L}},
      {"s  settings", {:key, ?S}},
      {"r  refresh", {:key, ?R}},
      {"c  connect elsewhere", {:key, ?C}},
      {"↑↓ PgUp PgDn  choose", nil},
      {"Esc  title", @escape}
    ]

    {items, _} =
      Enum.map_reduce(hints, left, fn {text, action}, x ->
        {{x, height - 70, text, @dim, :small, action}, x + 9 * String.length(text) + 30}
      end)

    items ++ [{left, height - 40, Map.get(state, :status, ""), @amber, :small, nil}]
  end

  defp kind_of(%{kind: {text, colour}}), do: {text, colour}
  defp kind_of(_arena), do: ExPilot.Mode.kind(:dogfight)

  defp chosen_arena(%{arenas: arenas, selected: selected} = state, {_width, height}) do
    case Enum.at(arenas, selected) do
      nil ->
        []

      arena ->
        teams = Map.get(arena, :teams, [])
        team = Map.get(state, :team)
        y = height - 130

        [
          {60, y, Map.get(arena, :note) || "", @dim, :small, nil},
          {60, y + @line,
           if(teams == [],
             do: "no teams",
             else:
               "team: " <>
                 to_string(team || "any") <> "   (t cycles " <> Enum.join(teams, ", ") <> ")"
           ), @text, :small, {:key, ?T}}
        ]
    end
  end

  defp settings(state, {width, height}) do
    left = div(width, 2) - 300
    top = div(height, 4)

    rows =
      settings_rows()
      |> Enum.with_index()
      |> Enum.flat_map(fn {row, index} ->
        setting_row(row, index, state, left, top + 50 + index * (@line + 10))
      end)

    [{left, top - 50, "Settings", @text, :big, nil}] ++
      rows ++
      [
        {left, height - 70,
         "↑↓  choose     ←→  change     Enter  switch     Esc  " <> back_text(state.from), @dim,
         :small, @escape},
        {left, height - 40, Map.get(state, :status, ""), @amber, :small, nil}
      ]
  end

  defp setting_row(:pointer, index, state, left, y) do
    chosen? = index == state.setting

    label =
      if(chosen?, do: "▶ ", else: "  ") <>
        String.pad_trailing("pointer steers", 18) <>
        if(state.settings.pointer, do: "on", else: "off")

    [{left, y, label, if(chosen?, do: @cyan, else: @text), :normal, {:setting, index}}] ++
      steps(index, left, y)
  end

  defp setting_row(level, index, state, left, y) do
    chosen? = index == state.setting
    value = Map.fetch!(state.settings, level)
    filled = round(value * 20)
    bar = String.duplicate("█", filled) <> String.duplicate("░", 20 - filled)

    label =
      if(chosen?, do: "▶ ", else: "  ") <>
        String.pad_trailing(level_name(level), 18) <> bar <> "  " <> "#{round(value * 100)}%"

    [{left, y, label, if(chosen?, do: @cyan, else: @text), :normal, {:setting, index}}] ++
      steps(index, left, y)
  end

  defp steps(index, left, y) do
    [
      {left + 520, y, "−", @amber, :big, {:step, index, -1}},
      {left + 560, y, "+", @amber, :big, {:step, index, 1}}
    ]
  end

  defp level_name(:sfx), do: "effects"
  defp level_name(:music), do: "music"

  defp back_text(:arena), do: "back to the arena"
  defp back_text(:lobby), do: "back to the arenas"
  defp back_text(_title), do: "back to the title"

  defp leaders(%{leaders: leaders} = state, {width, height}) do
    left = div(width, 2) - 360
    top = div(height, 6)

    periods =
      periods()
      |> Enum.with_index()
      |> Enum.map(fn {{period, title}, i} ->
        {left + i * 150, top,
         if(period == leaders.period, do: "▶ " <> title, else: "  " <> title),
         if(period == leaders.period, do: @cyan, else: @dim), :normal, {:period, i}}
      end)

    metrics =
      metrics()
      |> Enum.with_index()
      |> Enum.map(fn {{metric, title}, i} ->
        {left + i * 130, top + @line + 6,
         if(metric == leaders.metric, do: "▶ " <> title, else: "  " <> title),
         if(metric == leaders.metric, do: @amber, else: @dim), :small, {:metric, i}}
      end)

    rows =
      leaders.board
      |> Enum.take(@window)
      |> Enum.with_index(1)
      |> Enum.map(fn {entry, rank} ->
        {left, top + 3 * @line + rank * @line,
         "#{String.pad_leading(Integer.to_string(rank), 2)}  #{fit(entry.name, 18)} #{String.pad_leading(ExPilot.Ledger.value(entry.value, leaders.metric), 9)}   #{entry.rounds} rounds  #{ExPilot.Ledger.value(entry.values[:kills] || 0, :kills)} kills  #{ExPilot.Ledger.value(entry.values[:wins] || 0, :wins)} won",
         if(rank == 1, do: @green, else: @text), :normal, nil}
      end)

    empty =
      if leaders.board == [],
        do: [{left, top + 4 * @line, "nobody yet — fly a round", @dim, :normal, nil}],
        else: []

    [{left, top - 50, "Leaders", @text, :big, nil}] ++
      periods ++
      metrics ++
      rows ++
      empty ++
      [
        {left, height - 70, "←→  period     Tab  metric     Esc  " <> back_text(state.from), @dim,
         :small, @escape},
        {left, height - 40, Map.get(state, :status, ""), @amber, :small, nil}
      ]
  end

  defp summary(%{summary: %{title: title, lines: lines}} = state, {width, height}) do
    centre = div(width, 2)
    top = div(height, 3)
    colour = if String.downcase(title) =~ "defeat", do: @red, else: @amber

    [{{:centre, centre}, top, title, colour, :title, nil}] ++
      Enum.with_index(lines, fn line, i ->
        {{:centre, centre}, top + 80 + i * @line, line, @text, :normal, nil}
      end) ++
      [
        {{:centre, centre - 200}, height - 70, "Enter  fly again", @dim, :small, @enter},
        {{:centre, centre}, height - 70, "Esc  arenas", @dim, :small, @escape},
        {{:centre, centre + 200}, height - 70, "q  title", @dim, :small, {:key, ?Q}},
        {{:centre, centre}, height - 40, Map.get(state, :status, ""), @amber, :small, nil}
      ]
  end

  defp summary(state, size), do: summary(%{state | summary: %{title: "Over", lines: []}}, size)

  defp serve(state, {width, height}) do
    left = div(width, 2) - 300
    top = div(height, 5)
    running? = state.server != nil

    [
      {left, top - 50, if(running?, do: "Serving", else: "Host a server"), @text, :big, nil},
      serve_action(state, running?, left, top)
    ] ++
      form_items(state.serve_fields, state.field - 1, left, top + 2 * @line) ++
      Enum.with_index(state.serve_lines, fn line, i ->
        {left, top + (length(state.serve_fields) + 3) * @line + i * @line, line,
         if(running?, do: @green, else: @dim), :small, nil}
      end) ++
      [
        {left, height - 70,
         "Enter  start or stop     ↓  a setting to change, type to fill it in     Esc  back",
         @dim, :small, @escape},
        {left, height - 40, Map.get(state, :status, ""), @amber, :small, nil}
      ]
  end

  defp serve_action(state, running?, left, y) do
    chosen? = state.field == 0
    label = if running?, do: "stop the server", else: "start the server"

    {left, y, if(chosen?, do: "▶ " <> label, else: "  " <> label),
     if(chosen?, do: @cyan, else: @text), :big, :serve}
  end

  defp fit(text, width), do: text |> String.slice(0, width - 1) |> String.pad_trailing(width)

  defp flying(0), do: "nobody"
  defp flying(1), do: "1 flying"
  defp flying(n), do: "#{n} flying"
end
