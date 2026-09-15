<p align="center"><img src="icon.png" width="160" alt="weBump Racing Demo"/></p>

# weBump Racing Demo

A small, playable Godot game that shows how to use the **weBump Connected Games
API**: people you bump in real life become your racing rivals, and a replay
they chose to share races you as a ghost. Think StreetPass, in your own game.

**Play it:** [webump.app/demo](https://webump.app/demo) ·
**Read the API docs:** [developer.webump.app](https://developer.webump.app)

| Docs | What it covers |
| --- | --- |
| [Get started](https://developer.webump.app/tutorial) | Apply for a project, OAuth with PKCE, private saves, visitor handoffs |
| [Share selected game data](https://developer.webump.app/tutorial#shared-data) | The `game.shared` flow this demo uses for replays |
| [API reference](https://developer.webump.app/reference) | Every endpoint, error code and limit (OpenAPI) |
| [Connect button](https://developer.webump.app/brand) | The official control and assets used on the title screen |
| [Project lifecycle](https://developer.webump.app/lifecycle) | Review, permissions changes, suspension and data export |
| [Changelog](https://developer.webump.app/changelog) | Platform changes |

## What the demo does with the API

Everything API-related lives in [`scripts/webump_api.gd`](scripts/webump_api.gd),
a single autoload. The rest of the game only calls its public functions and
listens to its signals.

| Step | Endpoint | Scope | In this repo |
| --- | --- | --- | --- |
| Connect (OAuth 2.0 + PKCE, public client) | `GET /oauth/authorize`, `POST /oauth/token` | `profile.basic` | `connect_player()`, `exchange_authorization_code()`, refresh in `_ensure_fresh_token()` |
| Read the player's name and color | `GET /v1/me` | `profile.basic` | `fetch_player_profile()` → nameplate and paint |
| Private save (never visible to others) | `GET /v1/me/state`, `PUT /v1/me/state/:key` | `game.state` | `racing_save`, `ghost_telemetry` |
| Public high score on bump cards / profile | `PUT /v1/me/capsule`, `PUT /v1/me/showcase` | `game.capsule`, `game.showcase` | `save_public_highscore()` |
| Share one replay, on purpose | `PUT /v1/me/shared` (`{"publish":true,…}`) | `game.shared` | **Share Replay** button on the results card |
| Bring in bumps | `POST /v1/me/visitor-handoff` (begin / redeem) | `visitors.receive` | **Bring in your bumps** on the title screen |
| Revalidate rivals and fetch their replay | `GET /v1/me/visitors/:ref`, `…/:ref/shared` | `visitors.receive` + `game.shared` | `refresh_visitors()` → `RivalRoster` |
| Disconnect | `POST /oauth/revoke` | — | `disconnect_player()` |

Privacy rules the demo follows, and that you should too:

- Tokens live in memory only. Public identifiers (`client_id`, API origin,
  callback) are in [`config.json`](config.json); nothing secret ships in the export.
- A rival's replay is never read from their private state. Each player publishes
  one replay through `game.shared` after pressing a button; the server also
  requires their own "Share selected game data" toggle in the weBump app.
- `410` on a visitor read means that person opted out, expired, withdrew, or
  blocked. The demo races them as AI instead of complaining.
- Every write sends `If-Match` with the latest revision. A `409` is surfaced,
  never retried blindly; the local save is always kept.

The reviewed shared-data schema for this game is
[`docs/shared_data_definition.json`](docs/shared_data_definition.json).
[`docs/API_INTEGRATION.md`](docs/API_INTEGRATION.md) documents the replay
contract, the web callback relay, and revision handling in detail.

## Run it locally

Open `project.godot` in **Godot 4.7** and press **F5**. No account is needed:
inside the editor the API runs in **mock mode**, which simulates a connected
profile and races you against Maya's synthetic ghost plus Liam and Sam. Every
export talks to the real API.

| Controls | Action |
| --- | --- |
| W / Up | Accelerate |
| S / Down | Brake / reverse |
| A, D / Left, Right | Steer |

Three laps with ordered checkpoints. Three rival slots are filled from visitor
cards (valid ghosts first), then practice AI. Ghost times are **Recorded**,
finished AI times are **Finished**, unfinished AI times are projected from
observed pace. Personal bests and complete replays (≤ 3 minutes, ≤ 256 frames,
≤ 12 KB) save locally first; connected saves sync to weBump afterwards.

## Code map

| File | Responsibility |
| --- | --- |
| `scripts/webump_api.gd` | Session, transport, saves, shared replay, visitors |
| `scripts/webump_connect_button.gd` | Official connect control (see the brand page) |
| `scripts/title_screen.gd` | Car chooser, connect, bring in bumps, start |
| `scripts/rival_roster.gd` | Turn visitor cards into a bounded race roster |
| `scripts/ghost_data.gd` | Replay validation, compaction, shared document |
| `scripts/ghost_recorder.gd` | Record runs, keep the best, share on request |
| `scripts/ghost_driver.gd` | Replay a recording on the race clock |
| `scripts/ai_vehicle.gd` | Waypoint driver, laps, finish effects |
| `scripts/race_manager.gd`, `race_standings.gd` | Countdown, roster, checkpoints, results |
| `scripts/race_hud.gd` | HUD, results card, Share Replay |
| `scripts/vehicle.gd`, `car_presets.gd` | Vehicle physics, paint and model presets |
| `web/shell.html` | Web export shell with the approval popup relay |

Rival and ghost vehicles inherit `scenes/vehicle.tscn` so geometry, sounds,
nameplates and effects are set up once in the scene files.

## Web export and hosting

The `Web` preset is single-threaded (works in iOS Safari, no cross-origin
isolation headers) and uses `web/shell.html`, which adds the popup relay for the
OAuth callback. Export from the editor or:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --export-release Web build/web/index.html
```

`build/` is gitignored. The export is published on this repository's
`gh-pages` branch and embedded by [webump.app/demo](https://webump.app/demo),
which is also the registered OAuth callback. In the browser the game is a
public OAuth client: it completes PKCE itself (the API answers CORS for
third-party routes) and keeps tokens in memory. On desktop builds the approval
opens in your browser but the callback is not delivered back, so live mode is a
web feature; the editor stays in mock mode.

## Verify

```sh
godot --headless --path . --editor --import --quit
godot --headless --path . --script tests/test_racing.gd
godot --headless --path . --script tests/test_api.gd
godot --headless --path . --script tests/test_loading.gd
godot --headless --fixed-fps 60 --path . --script tests/test_race_simulation.gd
godot --headless --fixed-fps 60 --path . --script tests/test_ghost_sharing.gd
```

## Credits and license

Built on [Kenney's Starter Kit Racing](https://github.com/KenneyNL/Starter-Kit-Racing)
(CC0 assets and starter code) with the [Godot Engine](https://godotengine.org).
This demo keeps the same license; see [LICENSE](LICENSE). weBump and its API are
not affiliated with Kenney.
