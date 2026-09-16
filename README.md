# ExPilot

A multiplayer XPilot in the terminal, played over ssh. Classic block maps, newtonian
ships, thrust and shields and fuel, cannons, wormholes, robots, items — mines, missiles,
lasers, cloaks, ECM, transporters, tractor beams, deflectors, phasing, hyperjumps and the
rest — teams, targets, capture the flag, races, a radar, and seven pieces of music
written in Strudel that follow the fight — on [`cauldron_2d`](../cauldron_2d), drawn by [`drafter`](../drafter), heard through
[`tuning_fork`](../tuning_fork).

```bash
mix ex_pilot.play                       # this terminal, this machine's speaker
mix ex_pilot.serve --port 2222          # over ssh and in the browser, one process
mix ex_pilot.maps                       # fetch the 132 classic maps into priv/maps
```

Every map under `priv/maps` is an arena in the lobby — Dogfight is bundled, the rest
come from `mix ex_pilot.maps` — with its size and robot count beside its name (an arena
with none is practice); robots never take every base, one is always left for you. A
ship sits on its base facing away from the wall the base is on — up off a floor, down
under a ceiling, sideways off a wall — and launches that way. The list
scrolls (`PgUp`/`PgDn`, `Home`/`End`, the wheel); a click chooses a row and a second
click joins it. An arena's world and robots start when someone
joins it and stop again after two minutes with nobody in it.

## In the browser

The same server serves the game to browsers — `http://host:2280/` by default; `--http N`,
`-p N` or `PORT=N` choose the port, `--http 0` turns it off. Log in or make an account
(the same accounts as ssh), pick an arena, and play on a canvas beside ssh players in
the same world: `a`/`d` or the arrows turn, `s`/`↑` or the right mouse button thrust,
space or the left button fire, `w`/shift shield, the pointer steers, Enter steps
through the ships when you are watching. Every arena card offers a team or a plain join
and `watch`; the guide page shows everything in the game with its sprite. Sound plays
in the page, nothing to set up. The web client is `cauldron_2d_web` plus `ExPilot.Web`; the
design is `CAULDRON_WEB_DESIGN.md` at the repository root.

## Playing over ssh

```bash
ssh -p 2222 new@host                                       # register: pick a name and password, then play
ssh -p 2222 alice@host                                     # play
ssh -p 2222 -R 24713:127.0.0.1:4713 alice@host             # play with sound
```

Every account has its own sound port on the server — 24713 for the first account
registered, 24714 for the next, and so on; the game's settings screen shows yours with
the lines to use. The accounts are in `$XDG_DATA_HOME/expilot/accounts.terms`
(`~/.local/share/expilot/accounts.terms`), a text file with one Erlang term per account
— name, `number`, props — that you can read as it is (`number` 1 means port 24714). The game synthesises on the server and sends raw PCM (signed 16-bit,
44100 Hz, stereo) through the reverse tunnel to whatever listens on your machine's
port 4713, on any OS with `ffmpeg` (`brew install ffmpeg`, `winget install ffmpeg`,
`apt install ffmpeg`):

```bash
while :; do ffplay -nodisp -autoexit -fflags nobuffer -analyzeduration 0 -probesize 32 -f s16le -ar 44100 -ch_layout stereo -i "tcp://127.0.0.1:4713?listen"; done
```

`ffplay` ends when a session's connection closes, so the loop puts a fresh listener up
for the next session; on Windows the loop is `for /L %i in (1,0,2) do ffplay …` in
`cmd` and `while ($true) { ffplay … }` in PowerShell, with the same options. The title
screen's "No sound?" (`n`, or a click) shows all three with your own port and `ssh`
line; `Esc` closes it. Start either before or after the game; the server reconnects
every two seconds until it is there. The server keeps 60 ms of audio in flight and, on
connecting, sends the first frames and then nothing for 300 ms: ffplay opens its device
before it reads in earnest, and anything sent meanwhile would sit in the socket and play
first, as lag, for the whole session. Someone with Elixir and this project on their
machine can run `mix ex_pilot.listen` instead of ffplay: it plays through the speaker
about 100 ms behind the game and needs no such care. `sox` works too (`sox -t raw -r 44100 -e signed -b 16 -c 2 - -d < <(nc -l 4713)`),
and on Linux `pacat --raw --format=s16le --rate=44100 --channels=2 < <(nc -l 4713)`. A
served game never plays through the server's own speaker; `mix ex_pilot.play` plays
through this machine's.

Title → lobby (arenas, team, chat) → settings → arena. The defaults are WASD with the
pointer steering: `a`/`d` turn (and the ship follows the mouse until a turn key is
pressed), `s` or the right mouse button thrust, space or the left mouse button fire, `w` or
left shift shield — a shielded ship shows a ring; settings offers arrows and vi
presets, rebinding (`↑`/`↓` to the action, `Enter` then a key or mouse button adds it,
`Backspace` removes the last), pointer steering,
effects and music levels, display (pixels where the terminal has them, braille, or
glyphs) and frame rate (auto is the terminal's best: 15 on iTerm2 and sixel terminals,
where every frame is a whole image; 30 elsewhere), and keeps them under
`$XDG_CONFIG_HOME/expilot/<player>.settings`. The arena shows your ship's status and
the scores beside the world; `?` shows the keys (tap to keep, hold to peek); `Esc` goes
back to the lobby, `q` to the title, `^Q` quits. A ship sits on its base until it
thrusts. Held turn keys take over from the pointer until it moves again. A ship that has just appeared on its base — joined, respawned or at a new
round — cannot be hit for three seconds and shows its shield meanwhile. With limited
lives, a ship out of lives watches the nearest ship still flying — `Enter` steps to the
next one, for a spectator too — and the round ends as
in XPilot when one ship (one team) is left standing among two or more (alone in an
arena you fly for practice; nothing is won or lost): it is told it won, everyone is back
on their bases four seconds later, and for you it is a summary — Victory or Defeat with
the standings. `Enter` after a Victory joins the next arena in the list, after a Defeat
the same one again; `Esc` returns to the lobby. Robots launch off their bases, hunt the
nearest enemy anywhere in the arena along the clearest heading toward it, brake off
walls, fire within reach and go for a fuel station when the tank runs low. Each robot
is seated with a skill of its own, drawn at random: the sharp ones aim tight, fire from
far and react in three frames, the dull ones spray, wait for a closer shot, hesitate on
the trigger and think three times slower. A player who
finds every base taken gets a robot's, and the robot comes back when there is room
again. The hud counts the enemies still in the round and the radar marks every ship:
you in yellow, teammates blue, enemies red, bases grey. A tank that has been empty for
ten seconds loses the ship, on the base or off it. Ships that fly into each other crash
unless shielded; shielded ships bounce apart. Walls bounce a
ship that touches them slowly or with its shield up — an unshielded bounce costs fuel —
and crash one that hits them faster; the map's `maxunshieldedwallbouncespeed`,
`maxshieldedwallbouncespeed` and `wallbouncefueldrainmult` set the numbers.

Items appear on the map and are picked up by flying over them; the hud lists what you
carry, `1` drops a mine, `2` fires a missile (`n` picks torpedo, smart or heat),
`3` fires the laser, `c` cloaks, `e` jams, `r` steals with the transporter, `g`/`b` pull
and push with the tractor beam,
`x` deflects, `p` phases through walls, `u` hyperjumps, `[`/`]` emergency shield and
thrust, `o` autopilot, `v` drops the ball. On a team map (`teamplay: yes`) teammates'
shots pass through each other, the `!` targets take three hits, and carrying the other
team's ball from its `*` treasure into your own scores: the ball hangs on a string that
tugs the ship and snaps when overstretched, and falls, drifts and bounces on its own
when loose. Map headers set the rest of the rules XPilot's do — `allowshields`,
`initialfuel` and the `initial…` kit, `shotswallbounce`, `friction`,
`allowplayercrashes`, `targetkillteam`, `treasurekillteam`, `dropitemonkillprob`,
`laserisstungun`, `shieldeditempickup`, `gravityangle`, `gravitypoint`… — the full
list is in `ExPilot.Map`. A `racemode` map runs laps over
the `A`–`Z` checkpoints. `h` on the title or in the lobby opens the guide: everything
you can meet in an arena, drawn beside a line on what it does and the key that uses it.
The music follows the kind of arena — a dogfight, capture the flag, a team battle and a
race each have their own cruising and combat pieces (`ExPilot.Music`). The hud is a
column down the left as in XPilot: the radar on
top, then you, your items and the scores, with the arena's messages along the bottom;
`t` talks to the arena. Your
own shipshape is read from `$XDG_CONFIG_HOME/expilot/<player>.shipshape`. On a terminal that
reports key releases (kitty, Ghostty, WezTerm, foot, Alacritty, iTerm2 3.5+) keys are
held; elsewhere (Terminal.app, Alacritty) the key repeat stands in: a tap turns a step
or gives a short burst of thrust or shield, and holding the key holds it until about
150 ms after you let go.

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
