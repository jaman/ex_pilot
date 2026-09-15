# ExPilot

A multiplayer XPilot in the terminal, played over ssh. Classic block maps, newtonian
ships, thrust and shields and fuel, cannons, wormholes, robots, and seven pieces of music
written in Strudel that follow the fight — on [`cauldron_2d`](../cauldron_2d), drawn by [`drafter`](../drafter), heard through
[`tuning_fork`](../tuning_fork).

```bash
mix ex_pilot.play                       # this terminal, this machine's speaker
mix ex_pilot.serve --port 2222          # over ssh, players register on first connection
mix ex_pilot.maps                       # fetch the 131 classic maps into priv/maps
```

## Playing

```bash
ssh -p 2222 new@host                                       # register, then play
ssh -p 2222 -R 24713:localhost:4713 alice@host             # play with sound
```

Sound reaches you through the reverse tunnel: run a PulseAudio or PipeWire server
listening on TCP (`pactl load-module module-native-protocol-tcp auth-ip-acl=127.0.0.1`)
and set the port in the game's settings. The game synthesises on the server and pipes PCM
to your machine.

Title → lobby (arenas, team, chat) → settings → arena. The defaults are WASD: `a`/`d`
turn, `s` or the right mouse button thrust, space or the left mouse button fire, `w` or
left shift shield — a shielded ship shows a ring; settings offers arrows and vi
presets, rebinding (`↑`/`↓` to the action, `Enter` then a key or mouse button adds it,
`Backspace` removes the last), pointer steering,
effects and music levels, display (pixels where the terminal has them, braille, or
glyphs) and frame rate (auto is the terminal's best: 15 on iTerm2 and sixel terminals,
where every frame is a whole image; 30 elsewhere), and keeps them under
`$XDG_CONFIG_HOME/expilot/<player>.settings`. The arena shows your ship's status and
the scores under the world; `?` shows the keys (tap to keep, hold to peek); `Esc` goes
back to the lobby, `q` to the title, `^Q` quits. A ship sits on its base until it
thrusts. With limited lives, held turn keys take over from the pointer until it moves
again; a ship out of lives watches the nearest ship still flying; and when every other
ship is out the round ends in a summary — Victory or Defeat with the standings. `Enter`
after a Victory joins the next arena in the list, after a Defeat the same one again;
`Esc` returns to the lobby. Robots seek the nearest enemy anywhere in the arena and fire
within reach, and the status bar counts the enemies still in the round. On a terminal that
reports key releases (kitty, Ghostty, WezTerm, foot, Alacritty, iTerm2 3.5+) keys are
held; elsewhere a tap turns a step and thrust and shield toggle.

## What is here

| Module | |
|---|---|
| `ExPilot.Map` | the classic legend over `Cauldron2D.Map`, features and options |
| `ExPilot.Game` | the rules, a pure `Cauldron2D.Game` |
| `ExPilot.Ship`, `ExPilot.Shipshape` | a ship and the classic shape notation |
| `ExPilot.Robot` | a robot player |
| `ExPilot.Art` | the atlas, drawn with `linocut` |
| `ExPilot.Sound`, `ExPilot.Music` | effects per event; "orbit" in sections and layers |
| `ExPilot.Client` | what the generic client needs from the game |
| `ExPilot.Arenas`, `ExPilot.Server` | worlds with robots; the ssh daemon |

Not yet: items, treasures and capture-the-flag, race mode, team scoring.

## License

MIT. The classic maps are community contributions with no stated licence and are fetched
rather than shipped; the XPilot source is GPL and was read, not copied.
