# ExPilot, technically

How the game is put together and run at scale. The [README](README.md) is the game;
this is for anyone reading or changing the code, hosting a server for many, or building
something like it on [Cauldron](https://github.com/jaman/cauldron).

## What each library does here

The engine, the arenas, the robots' runner, the ledger, the beacon, the remote calls,
the load test, the ssh and web servers and every client's screens are Cauldron's
([Cauldron](https://github.com/jaman/cauldron): `cauldron_2d`, `cauldron_2d_drafter`,
`cauldron_2d_net`, `cauldron_2d_wx`, `linocut`); ExPilot is the rules, the maps, the art,
the sound, the robots' judgement and its own pages. The terminal client is drawn by
[`drafter`](https://hex.pm/packages/drafter) and everything is heard through
[`tuning_fork`](https://hex.pm/packages/tuning_fork).

The web client is `cauldron_2d_net` plus `ExPilot.Web`; its design is
`CAULDRON_WEB_DESIGN.md` at the repository root. The desktop is Erlang's wx through
`cauldron_2d_wx`; its design is `CAULDRON_WX_DESIGN.md`.

## What is here

| Module | |
|---|---|
| `ExPilot.Map` | the classic legend over `Cauldron2D.Map`, features and options |
| `ExPilot.Game` | the rules, a pure `Cauldron2D.Game` |
| `ExPilot.Ship`, `ExPilot.Shipshape` | a ship and the classic shape notation |
| `ExPilot.Gear`, `ExPilot.Items`, `ExPilot.Weapons` | what a ship carries and fires |
| `ExPilot.Ball`, `ExPilot.Targets`, `ExPilot.Race` | the team modes: the ball on its string, the targets, the checkpoints |
| `ExPilot.Robot` | a robot's judgement, a `Cauldron2D.Robot` brain: it hunts, fires with a line of sight, refuels, and finds its way on `Cauldron2D.Grid.Coarse` |
| `ExPilot.Ledger` | ExPilot's metrics on `Cauldron2D.Ledger`, and the boards' values as text |
| `ExPilot.Mode` | the kinds of arena, in words and colour |
| `ExPilot.Radar` | the hud's minimap on `Cauldron2D.Minimap` |
| `ExPilot.Duels`, `ExPilot.Duels.Remote` | challenges as private arenas; a challenge sent to another server |
| `ExPilot.Terminal`, `ExPilot.Wx` | the terminal and the desktop, each with its own title around the shared screens |
| `ExPilot.Art` | the atlas, drawn with `linocut` |
| `ExPilot.Sound`, `ExPilot.Music` | effects per event; the pieces in sections and layers, and the static repertoire |
| `ExPilot.Client` | the `Cauldron2D.Client.Game`: what every client needs from the game |
| `ExPilot.Arenas`, `ExPilot.Server` | the maps' arenas on `Cauldron2D.Arenas`, with robots and a recorder beside each world; the servers on `Cauldron2D.Drafter.Server` |
| `ExPilot.Web` | the Phoenix endpoint and pages (login, lobby, arena, settings, guide, leaders) around `Cauldron2D.Net`'s socket, channel and API |

## Map rules

Map headers set the rules XPilot's do — `allowshields`, `initialfuel` and the `initial…`
kit, `shotswallbounce`, `friction`, `allowplayercrashes`, `targetkillteam`,
`treasurekillteam`, `dropitemonkillprob`, `laserisstungun`, `shieldeditempickup`,
`gravityangle`, `gravitypoint`, `maxunshieldedwallbouncespeed`,
`maxshieldedwallbouncespeed`, `wallbouncefueldrainmult`, `racemode`, `teamplay`… — the
full list is in `ExPilot.Map`. A ship sits on its base facing away from the wall the base
is on — up off a floor, down under a ceiling, sideways off a wall — and launches that way.

## Keys held and keys repeated

On a terminal that reports key releases (kitty, Ghostty, WezTerm, foot, iTerm2 3.5+) keys
are held for exactly as long as they are down. Elsewhere (Terminal.app, Alacritty) the
key repeat stands in: a tap turns a step or gives a short burst of thrust or shield, and
holding the key holds it until about 150 ms after you let go.

In the browser the pointer's aim follows the ship: it is worked out again from where the
mouse sits after every draw, so a ship flying under a still mouse keeps aiming ahead of
itself.

## Sound over ssh

Every account has its own sound port on the server — 24713 for the first account
registered, 24714 for the next, and so on. The accounts are in
`$XDG_DATA_HOME/expilot/accounts.terms` (`~/.local/share/expilot/accounts.terms`), a text
file with one Erlang term per account — name, `number`, props — that you can read as it
is (`number` 1 means port 24714). The game synthesises on the server and sends raw PCM
(signed 16-bit, 44100 Hz, stereo) through the reverse tunnel to whatever listens on the
player's port 4713.

The server keeps 60 ms of audio in flight and, on connecting, sends the first frames and
then nothing for 300 ms: `ffplay` opens its device before it reads in earnest, and
anything sent meanwhile would sit in the socket and play first, as lag, for the whole
session. It reconnects every two seconds until a listener is there. `mix ex_pilot.listen`
plays through the speaker about 100 ms behind the game and needs no such care. A served
game never plays through the server's own speaker.

A phone or tablet gets 22 kHz mono, a quarter of the bytes of the 44.1 kHz stereo a
desktop browser gets. `use Cauldron2D.Net.Channel, audio:` in `ExPilot.Web.ArenaChannel`
is where to trade quality for sessions.

## What a session costs, and the music policies

Sound is the server's largest cost a session: a synthesiser each at 44.1 kHz, a third of
a core or so (0.39 of a core at 44 kHz, 0.22 at 22). `mix ex_pilot.serve --music` picks
the policy:

- `personal` (the default) gives each session its own music, following its own view
- `arena` synthesises one music stage a world and mixes it under each session's own
  effects
- `dynamic` keeps personal music but drops every session to 22.05 kHz while the node's
  schedulers are over 60% busy (back at under 30%, thirty seconds apart at least)
- `static` plays each session a piece of the repertoire arranged for its kind of arena
  (`ExPilot.Music.Static`, played from the MIDI scores under `priv/scores`), all five
  rendered in the background as the server starts — a few minutes, once; a changed song
  is rendered again, an unchanged one is read from disk — and kept under
  `$XDG_CACHE_HOME/expilot/music`, looped as a recording at the cost of a copy a chunk.
  The recorded bass is `ExPilot.Music.Instruments`: FreePats' and Karoryfer's through
  `TuningFork.Sfz`, fetched note by note the first time
- `off`, and `--sfx off`, do without

A browser or desktop that asks for no sound (`audio: false` on the join) costs nothing
whatever the policy. Effects are rendered once a node in any mode and replayed with each
listener's gain and pan. The layered pieces that follow the play (`ExPilot.Music`) are for
the other modes.

## Load testing

```bash
mix ex_pilot.serve --port 2422 --http 2480 --robots 4      # the server, here or on another machine
mix ex_pilot.load --url http://localhost:2480 --players 20 --watchers 50 --seconds 60
mix ex_pilot.load --url http://host:2480 --arenas Arena,Bali --players 10 --ramp 10 --every 10 --seconds 300
mix ex_pilot.load --players 10 --ramp 10 --audio off        # the worlds and the wire alone
```

`mix ex_pilot.load` runs `Cauldron2D.Net.Load` with ExPilot's actions: players (steering
at random) and watchers join a running server over the same WebSocket a browser uses.
Every few seconds a report: the sessions joined, the frames a second they get against the
worlds' tick rate, the longest gap between frames, the node's busy share, run queue,
processes and memory, then the three worlds with the longest ticks — mean, 95th
percentile and longest against the tick's budget, and the share of ticks that ran behind
(`GET /api/stats` has all of them). A report is **degraded** when a world's
95th-percentile tick is over its budget, a world ran behind on more than a fifth of its
ticks, a session got under 80% of the frame rate or waited over a second for a frame; it
says so and why. `--ramp N` adds N sessions every report until that happens, and the
summary names the count before the last addition as the capacity. Every report and the
summary go to a JSON-lines file (`$XDG_DATA_HOME/expilot/load/<time>.jsonl`, or `--out`)
as the run goes, and `Ctrl-C` ends a run early with the summary so far. Run the generator
on another machine when the number has to be exact; on the same one, its cores count too.

The load accounts are `load_1`, `load_2`… (password `load test`), registered on the
server as needed. They fly rounds like anyone else and land on the boards; `mix
ex_pilot.ledger --forget "load_*"` (with the server stopped — the ledger is held by one
process) drops their results, or any name's by pattern (`ExPilot.Ledger.forget/1` while
it runs). The ledger is `$XDG_DATA_HOME/expilot/ledger.dets`; robots' results are not
kept.

## Files on disk

| | |
|---|---|
| `$XDG_CONFIG_HOME/expilot/<player>.settings`, `<player>.<kind>.settings` | a player's settings, per kind of client |
| `$XDG_CONFIG_HOME/expilot/<player>.shipshape` | a player's own shipshape |
| `$XDG_DATA_HOME/expilot/accounts.terms` | the server's accounts |
| `$XDG_DATA_HOME/expilot/ledger.dets` | the boards |
| `$XDG_DATA_HOME/expilot/load/<time>.jsonl` | load test reports |
| `$XDG_CACHE_HOME/expilot/music` | the rendered static repertoire |
| `priv/maps` | the arenas; `mix ex_pilot.maps` fetches the classic ones |

## Tests

```bash
mix test
```
