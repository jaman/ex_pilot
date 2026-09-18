# ExPilot

A multiplayer XPilot in the terminal, played over ssh. Classic block maps, newtonian
ships, thrust and shields and fuel, cannons, wormholes, robots, items — mines, missiles,
lasers, cloaks, ECM, transporters, tractor beams, deflectors, phasing, hyperjumps and the
rest — teams, targets, capture the flag, races, a radar, and seven pieces of music
written in Strudel that follow the fight — on [`cauldron_2d`](https://hex.pm/packages/cauldron_2d), drawn by [`drafter`](https://hex.pm/packages/drafter), heard through
[`tuning_fork`](https://hex.pm/packages/tuning_fork).

[![ExPilot in play: the lobby, CurlyWorld with fifteen robots, following ships, zooming out to the whole map, with the music](https://img.youtube.com/vi/mCryFL8HUOo/maxresdefault.jpg)](https://www.youtube.com/watch?v=mCryFL8HUOo)

A tour of the game, with its music, is [on YouTube](https://www.youtube.com/watch?v=mCryFL8HUOo).

![CurlyWorld zoomed out to an eighth, the arena wrapping around itself, robots fighting across it](https://raw.githubusercontent.com/jaman/ex_pilot/main/assets/ex_pilot-curlyworld.png)

The engine, the arenas, the robots' runner, the ledger, the beacon, the remote calls,
the load test, the ssh and web servers and every client's screens are Cauldron's
([Cauldron](https://github.com/jaman/cauldron): `cauldron_2d`, `cauldron_2d_drafter`, `cauldron_2d_net`,
`cauldron_2d_wx`, `linocut`); ExPilot is the rules, the maps, the art, the sound, the
robots' judgement and its own pages.

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
through the ships when you are watching, `m` shows the frames a second (in every
client), and `♪` in the bar switches the music off and on without touching the
effects (kept in the browser). The pointer's aim follows the ship: it is worked out
again from where the mouse sits after every draw, so a ship flying under a still
mouse keeps aiming ahead of itself. On a phone or a tablet the arena is the game alone — no bars, nothing to
scroll: a thumbstick steers and, pushed far, thrusts; buttons fire, shield, fire a
missile and thrust; fuel and score ride over the world, `≡` opens the rest of the hud
over it, `⇄` swaps the stick and the buttons between hands, `♪` switches the music,
`⤢` goes full screen and
`✕` leaves; the sound comes at 22 kHz mono, a quarter of the bytes of the 44.1 kHz
stereo a desktop browser gets (one session's sound costs the server 0.39 of a core at
44 kHz and 0.22 at 22; `use Cauldron2D.Net.Channel, audio:` in `ExPilot.Web.ArenaChannel`
is where to trade quality for sessions). The stick is analog: thrust grows with the push
from its ring to its rim. The pages have a tab bar along the bottom instead of the
top bar; "Add to Home Screen" opens the game without the browser's bars. `?touch=1` or
`?touch=0` on any address forces the phone layout either way and is remembered.
Every arena card offers a team or a plain join
and `watch`; the guide page shows everything in the game with its sprite. Sound plays
in the page, nothing to set up. The web client is `cauldron_2d_net` plus `ExPilot.Web`; the
design is `CAULDRON_WEB_DESIGN.md` at the repository root.

## On the desktop

`mix ex_pilot.desktop` opens a window (Erlang's wx) played with the keys like the ssh
client: `Enter` from the title, pick where the arenas are — a server by its URL (log
in or register, then fly over the same WebSocket a browser uses), a node (connect, then
fly in its worlds across the connection), or this app — pick an arena, `Enter` joins,
`w` watches, `t` picks a team; in the arena `Esc` or `q` returns to the lobby. `s` on
the title or in the lobby, and `Tab` in the arena, is the settings:
effects and music levels and whether the pointer steers, `←`/`→` change them, kept in
the same `$XDG_CONFIG_HOME/expilot/<player>.settings` the ssh client reads, and `Esc`
returns to where you were — from the arena, to your ship where it was. `h` on the
title is the serve screen: ssh and web ports, interfaces, accounts file and robots,
`Enter` starts or stops the server. `--url`, `--name`, `--node`, `--cookie` fill the
fields in. Keys and the pointer are the browser's; sound plays through your speaker.
The design is `CAULDRON_WX_DESIGN.md` at the repository root.

## In a terminal, with everything

```bash
mix ex_pilot.terminal                       # play here, connect elsewhere, host, leaders
mix ex_pilot.terminal --name alice --url http://arcade:2280
```

The terminal has the desktop's flow: `Enter` plays the arenas this program carries,
`c` connects — to a server by URL (log in or register, then fly over its WebSocket) or
to a node — `h` hosts a server from inside (ssh, web, the node name and cookie others
need, calling on the local network so their connect screens list it), `l` shows the
leaders. `mix ex_pilot.play` is the same client with its own title and only the local
arenas; `mix ex_pilot.serve` is the headless server.

## Settings and your name

Sound levels, the pointer and keys are kept per kind of client — the terminal, the
desktop, a browser, a phone or tablet — in `$XDG_CONFIG_HOME/expilot/` and in your
account, so what suits a phone does not follow you to the desktop. The web settings
page also keeps a **nickname**, the name every client flies under and the boards show;
the boards count by account, so changing it keeps your record.

## Duels

From the browser's lobby, challenge a pilot on an arena, first to a number of kills:
a private arena appears in every lobby — the two of you fly it, anyone can watch —
and closes when it is won. `+`/`-` (the wheel, a pinch) zoom any view — terminal,
browser, desktop — out to the whole arena and back, `0` puts it back; watching, the
arrows or a drag pan the view, the wheel and a pinch zoom about the pointer, and `0`
recentres it: watch a duel from above, or close in on it.

## Leaders

Every round's result — kills, deaths, whether it was won, the best streak of kills
without dying, the longest contact (seconds alive with an enemy within thirty tiles)
— goes to a ledger on disk (`$XDG_DATA_HOME/expilot/ledger.dets`); robots' do not.
The boards, today / this week / all time, by kills, kills a death, rounds won, streak,
contact or laps, over every arena or one: `/leaders` in the browser, `l` in the
terminal and on the desktop, `GET /api/leaders` for anything else. The load tool's
accounts fly rounds like anyone else and land on the boards; `mix ex_pilot.ledger
--forget "load_*"` (with the server stopped — the ledger is held by one process) drops
their results, or any name's by pattern (`ExPilot.Ledger.forget/1` while it runs).

## Load testing

```bash
mix ex_pilot.serve --port 2422 --http 2480 --robots 4      # the server, here or on another machine
mix ex_pilot.load --url http://localhost:2480 --players 20 --watchers 50 --seconds 60
mix ex_pilot.load --url http://host:2480 --arenas Arena,Bali --players 10 --ramp 10 --every 10 --seconds 300
mix ex_pilot.load --players 10 --ramp 10 --audio off        # the worlds and the wire alone
```

`mix ex_pilot.load` runs `Cauldron2D.Net.Load` with ExPilot's actions: players
(steering at random) and watchers join a running server over the same WebSocket a
browser uses. Every few seconds a report: the sessions joined, the frames a second
they get against the worlds' tick rate, the longest gap between frames, the node's
busy share, run queue, processes and memory, then the three worlds with the longest
ticks — mean, 95th percentile and longest against the tick's budget, and the share of
ticks that ran behind (`GET /api/stats` has all of them). A report is **degraded**
when a world's 95th-percentile tick is over its budget, a world ran behind on more
than a fifth of its ticks, a session got under 80% of the frame rate or waited over a
second for a frame; it says so and why. `--ramp N` adds N sessions every report until
that happens, and the summary names the count before the last addition as the
capacity. Every report and the summary go to a JSON-lines file
(`$XDG_DATA_HOME/expilot/load/<time>.jsonl`, or `--out`) as the run goes, and `Ctrl-C`
ends a run early with the summary so far. Run the generator on another machine when the
number has to be exact; on the same one, its cores count too. The load accounts are
`load_1`, `load_2`… (password `load test`), registered on the server as needed.

Sound is the server's largest cost a session: a synthesiser each at 44.1 kHz, a third
of a core or so. `mix ex_pilot.serve --music arena` synthesises one music stage a world
and mixes it under each session's own effects; `--music dynamic` keeps personal music
but drops every session to 22.05 kHz while the node's schedulers are over 60% busy
(back at under 30%, thirty seconds apart at least); `--music static` plays each
session a piece of the repertoire arranged for its kind of arena (`ExPilot.Music.Static`,
played from the MIDI scores under `priv/scores`: Paganini's Caprice No. 24 for a
dogfight; Joplin's The Entertainer for capture the flag; Grieg's In the Hall of the
Mountain King for a team battle; Mozart's Rondo alla Turca for a race; the Prelude to
Bizet's Carmen for a duel — sixty to eighty bars each on the Salamander grand with a
recorded bass (`ExPilot.Music.Instruments`, FreePats' and Karoryfer's through `TuningFork.Sfz`, fetched note by
note the first time), a kit and a doubling instrument arranged under it, made to loop and
never changing with the fight), all five rendered in the background as the server starts
(a few minutes, once; a changed song is rendered again, an unchanged one is read from disk)
and kept under `$XDG_CACHE_HOME/expilot/music`, looped as a recording at the cost of a
copy a chunk; the layered pieces that follow the play are for the other modes;
`--music off` and `--sfx off` do without. A browser or desktop that asks for no sound
(`audio: false` on the join) costs nothing whatever the policy. Effects are rendered
once a node in any mode and replayed with each listener's gain and pan.

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
the scores beside the world; `?` shows the keys (tap to keep, hold to peek); `Esc` or
`q` goes back to the lobby, `^Q` quits. A ship sits on its base until it
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
| `ExPilot.Robot` | a robot's judgement, a `Cauldron2D.Robot` brain: it hunts, fires with a line of sight, refuels, and finds its way on `Cauldron2D.Grid.Coarse` |
| `ExPilot.Ledger` | ExPilot's metrics on `Cauldron2D.Ledger`, and the boards' values as text |
| `ExPilot.Mode` | the kinds of arena, in words and colour |
| `ExPilot.Radar` | the hud's minimap on `Cauldron2D.Minimap` |
| `ExPilot.Duels`, `ExPilot.Duels.Remote` | challenges as private arenas; a challenge sent to another server |
| `ExPilot.Terminal`, `ExPilot.Wx` | the terminal and the desktop, each with its own title around the shared screens |
| `ExPilot.Art` | the atlas, drawn with `linocut` |
| `ExPilot.Sound`, `ExPilot.Music` | effects per event; "orbit" in sections and layers |
| `ExPilot.Client` | the `Cauldron2D.Client.Game`: what every client needs from the game |
| `ExPilot.Arenas`, `ExPilot.Server` | the maps' arenas on `Cauldron2D.Arenas`, with robots and a recorder beside each world; the servers on `Cauldron2D.Drafter.Server` |
| `ExPilot.Web` | the Phoenix endpoint and pages (login, lobby, arena, settings, guide, leaders) around `Cauldron2D.Net`'s socket, channel and API |

Not yet: items, treasures and capture-the-flag, race mode, team scoring.

## License

MIT. The classic maps are community contributions with no stated licence and are fetched
rather than shipped; the XPilot source is GPL and was read, not copied.

The scores under `priv/scores` are LilyPond engravings from the Mutopia Project
(mutopiaproject.org) of music long in the public domain: Grieg's In the Hall of the
Mountain King (Coyau), Joplin's The Entertainer (Chris Sawer) and Mozart's Rondo alla
Turca (Rune Zedeler, Chris Sawer) are released to the public domain; the Prelude to
Bizet's Carmen (Alex O'S) is under Creative Commons Attribution-ShareAlike 2.5 and
Paganini's Caprice No. 24 (Samuel Rummel) under Creative Commons Attribution-ShareAlike
4.0, so the renders made from those two carry their engravers' names and the same
terms. The piano is the Salamander grand, CC BY 3.0 by Alexander Holm; the basses are
FreePats' fingered and picked electric bass and Karoryfer Samples' meatbass, all CC0.
