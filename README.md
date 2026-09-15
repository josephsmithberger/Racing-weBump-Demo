<p align="center"><img src="icon.png" width="160" alt="weBump Racing Demo"/></p>

# weBump Racing Demo

A playable Godot example of mapping weBump visitor cards to racing opponents.
Built on Kenney's arcade racing starter kit.

## Run locally

Open `project.godot` in **Godot 4.7** and press **F6** on the title scene, or **F5**
to run the project. Choose a car and select **Start Race**. No account is required.
**Connect with weBump** simulates a profile in the editor.

| Controls | Action |
| --- | --- |
| W / Up | Accelerate |
| S / Down | Brake / reverse |
| A, D / Left, Right | Steer |

Offline races include Maya's synthetic ghost, Liam, and Sam. Three rival slots
are filled from available visitor cards, with valid ghosts taking priority.
Empty slots use practice AI. A race roster stays fixed until the next race.

## Racing and results

- Three laps with ordered checkpoints.
- Visitor names and theme colors identify both ghost and AI opponents.
- Ghosts replay the saved car model, position, heading, and lean on the race clock.
- Missing, malformed, incomplete, or incompatible recordings fall back to AI.
- The finish screen ranks all entrants. Ghost times are **Recorded**; completed AI
  times are **Finished**. Unfinished AI times are **Estimated**, using observed
  track progress and lap pace. Estimates cannot put an unfinished AI ahead of
  the player who just finished.
- Personal bests and complete replays save locally; connected saves attempt cloud
  synchronization. A replay takes at most three minutes, 256 frames, and 12 KB
  of compact JSON, leaving space in weBump's 16 KiB private state document.

## API example: implemented boundary

`WeBumpAPI` is a normal Godot autoload. Public configuration lives in `config.json`;
local preferences and records live under Godot's `user://` directory. Tokens stay
in memory and are never bundled or written into the save file.

| Resource | Example use |
| --- | --- |
| `/oauth/authorize`, `/oauth/token` | PKCE connection; callback state validation |
| `GET /v1/me` | Player name and color |
| `GET /v1/me/state` | Read custom private saves |
| `PUT /v1/me/state/:key` | Save `racing_save` and `ghost_telemetry` |
| `GET/PUT /v1/me/capsule`, `/showcase` | Approved integer high scores |
| `POST /v1/me/visitor-handoff` | Begin and redeem approved visitor handoff |
| `GET /v1/me/visitors/:reference` | Revalidate an authorized visitor card |

**Current platform limitation:** custom ghost data is saved in private state.
The app backend returns a visitor's profile and approved scalar capsule, not
that visitor's private saves. Live cross-player ghost exchange therefore needs
a consent-controlled shared replay API or an authorized game-host adapter.
This repository implements playback and the adapter boundary; it does not claim
that ordinary visitor cards already contain recordings. See
[API integration](docs/API_INTEGRATION.md) for the exact handoff and replay shape.

The website's callback page also needs a complete game session integration before
live OAuth/handoff works end to end. Desktop browser callbacks are not delivered
automatically. This repository does not deploy or change the website/backend.

## Code map

| File | Responsibility |
| --- | --- |
| `scripts/webump_api.gd` | Profile, saves, serialized revision writes, visitor adapter |
| `scripts/rival_roster.gd` | Validate identity, prioritize ghosts, synthetic demo cards |
| `scripts/ghost_data.gd` | Replay validation and byte-budget compaction |
| `scripts/ghost_recorder.gd` | Record complete runs and preserve best saves |
| `scripts/ghost_driver.gd` | Interpolate recorded telemetry |
| `scripts/ai_vehicle.gd` | Waypoint driver, lap progress, finish events |
| `scripts/race_manager.gd` | Countdown, roster, checkpoints, results snapshot |
| `scripts/race_standings.gd` | Finish projection and ranking |
| `scripts/race_hud.gd` | Race feedback and leaderboard |
| `scripts/vehicle.gd`, `car_presets.gd` | Shared vehicle physics and paint/model selection |

AI and ghost scenes inherit the player vehicle prefab so geometry, sound, and
physics setup remain in one place. Track geometry is in `scenes/main.tscn`;
update `track_path.gd` and increment `GhostData.TRACK_ID` when changing its layout.
Planning notes, local experiments, credentials, and build outputs are gitignored.

## Verify

```sh
godot --headless --path . --editor --import --quit
godot --headless --path . --script tests/test_racing.gd
godot --headless --path . --script tests/test_api.gd
godot --headless --path . --script tests/test_loading.gd
godot --headless --fixed-fps 60 --path . --script tests/test_race_simulation.gd
```

Checks cover malformed/truncated telemetry, payload limits, roster replacement,
model/paint/name matching, playback, result retention after rivals disappear,
actual/recorded/estimated ordering, sequential API revisions, cold threaded loading,
and complete AI races. Add `-- --visual` to the racing UI check
and omit `--headless` to capture `/tmp/webump-leaderboard.png`.

## License and credits

Code: [MIT](LICENSE), including the original Kenney copyright notice.
Sprites, models, and sounds: [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
Skid sound by [Landeplage](https://github.com/Landeplage).
