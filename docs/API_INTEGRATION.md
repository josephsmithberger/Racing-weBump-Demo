# Integrating weBump visitors and replay data

## What is saved versus shared

`ghost_telemetry` is a game-defined private state key. `game.state` accepts bounded
JSON objects and arrays; the backend caps arrays at 256 items and the entire state
at 16 KiB measured as PostgreSQL JSONB text. It is never readable by other players.

Visitor `stats` is the peer's currently shared capsule; `capsule` is its encounter
snapshot. Approved capsule/showcase values are bounded integers, booleans, and
enums, with a 2 KiB limit. They cannot carry the recording's sample array.

`game.shared` is the third tier: one player-selected JSON document per project,
validated against the reviewed `data_definition.shared` schema, up to 16 KiB, and
delivered only through an authorized bump reference. That is where this game
publishes its best replay. It is off by default per player and never appears on a
weBump profile card.

These behaviors were checked against the app repository's
`home-api/platform/store.ts` (`visitor`, `getVisitorShared`, and document
operations), `home-api/platform/shared-data.ts` (schema and payload validation),
`home-api/platform/protocol.ts` (`stateValue` and `sharedValue`), and
`sdk/WeBumpKit/Sources/WeBumpKit/WeBumpClient.swift`.

## Shared replay flow

1. The project application requests `game.shared` and declares the schema in
   [shared_data_definition.json](shared_data_definition.json). Scope and schema
   changes are reviewed; until approval, `PUT /v1/me/shared` returns
   `insufficient_scope`.
2. The player turns on **Share selected game data** for this game in the weBump
   app. The game cannot enable it. `GET /v1/me/permissions` reports it as
   `shared_data_sharing`; `WeBumpAPI.fetch_permissions()` caches it.
3. **Share Replay** on the results card calls `GhostRecorder.share_best_ghost()`.
   It builds the document with `GhostData.shared_document()`, which keeps only the
   declared keys (`version`, `track_id`, `car_body`, `lap_count`, `total_time_ms`,
   `samples`), then `WeBumpAPI.publish_shared_data()` sends
   `{"publish": true, "value": …}` with the current `If-Match` revision.
   `403 consent_required` means the toggle is off; the HUD tells the player.
4. `WeBumpAPI.refresh_visitors()` revalidates each card and then requests
   `GET /v1/me/visitors/:reference/shared`. A `200` attaches `data` as
   `ghost_telemetry`; `410` means nothing is shared for that person, so the roster
   uses AI. Publications expire after seven days and only reach bumps that happen
   after the publication, so a rival's ghost can disappear between sessions.

Validation of the schema and a worst-case 256-frame payload against the backend
validator: 10,703 JSON bytes, about 12.2 KiB as JSONB text, under the 16 KiB cap.
Undeclared keys, unknown car bodies, five-component frames and other versions are
rejected server-side, so the recorder must not add fields without a schema update.

## Approval flow and session

The demo is a public OAuth client. `_start_live_oauth_flow()` requests
`/oauth/authorize` with `Accept: application/json` and `display=popup`, which
returns `authorization_url`, `app_url` and `request` instead of redirecting.
`_await_approval()` announces the game with `POST /oauth/pending`, asks the
export shell (`web/shell.html`) to open the approval, and polls
`GET /oauth/pending` every two seconds for up to five minutes. On an iPhone the
shell opens `app_url` (`webump://connect?…`), which opens weBump directly; the
player approves and returns to Safari, where the game is already connected.
Elsewhere the shell opens `authorization_url` in a popup, which shows a QR code
and closes itself once the phone decides. The callback URL delivered by polling
is parsed like a redirect and routed by `state` to `exchange_authorization_code()`
or `redeem_visitor_handoff()`. Desktop builds follow the same path with the
system browser. The API answers CORS for `/oauth/*` and `/v1/*`.

Tokens stay in memory. Access tokens last ten minutes; `_ensure_fresh_token()`
refreshes once, shortly before expiry, with the rotating refresh token. A
failed refresh ends the session (refresh responses are single-use and must not
be retried). Disconnecting revokes the refresh token best-effort.

1. `load_visitors()` runs after connecting and every 45 seconds on the title
   screen: `GET /v1/me/visitors` lists everyone the player bumped since
   connecting whose reveal delay has passed, and each card's shared replay is
   fetched by reference. No handoff or button is involved; the explicit handoff
   (`request_visitors()`) stays available as an example of a player-chosen
   transfer.
2. Visitor cards are session-only and cleared on disconnect. Expired receipt
   references are not permanent player IDs. Missing or rejected cards are
   dropped on refresh: revoked or expired rivals are never raced from cache.
3. The editor uses mock mode; every export, including desktop, is live.

The game takes a roster snapshot at countdown. `set_visitor_cards` accepts up to
50 cards and the roster picks three, prioritizing valid recordings. Malformed
recordings use AI. Names/colors come from the visitor profile, the ghost model
comes from the recording, and AI model selection uses the optional approved
`stats.car_body` enum. Unknown model IDs fall back to the bundled Classic Cab.

## Card shape after refresh

`ghost_telemetry` is filled from `GET /v1/me/visitors/:reference/shared`. It is
not part of the plain Visitor card and a host adapter may supply it the same way:

```gdscript
WeBumpAPI.set_visitor_cards([{
    "reference": authorized_card.reference,
    "display_name": authorized_card.display_name,
    "theme_color": authorized_card.theme_color,
    "stats": authorized_card.get("stats", {}),
    "ghost_telemetry": authorized_recording
}])
```

The recording contract is:

```json
{
  "version": 1,
  "track_id": "demo_loop_v1",
  "car_body": "truck_red",
  "lap_count": 3,
  "total_time_ms": 96000,
  "samples": [
    [0, 3.5, 0, 5, 0, 0],
    [96000, 3.75, 0, 1.5, 0, 0]
  ]
}
```

The two frames illustrate the schema; useful replays include intermediate frames.
Each frame is `[milliseconds, world_x, world_y, world_z, yaw_radians, lean_radians]`.
Timestamps must increase, coordinates must be finite/bounded, and the recording
must include the start and finish (within 100 ms). Legacy recordings without a
track ID are accepted for this original layout only. Change the validator's
legacy policy if the track changes. Playback interpolates position and wraps yaw
through the shortest angle, runs without collision physics, and uses recorded
finish time rather than inferring it from a high score.

## Saving and revisions

State, capsule, showcase and the shared document share one revision. The client serializes writes,
reads `/v1/me/state` for its strong ETag, and sends it in `If-Match`. Conflicts and
network failures surface through callbacks and `request_failed`; no blind retry
can overwrite a concurrent edit. All game records are persisted locally first.
Cloud failure does not destroy the local record. There is no background retry or
token-refresh scheduler in this demo; reconnect after token expiry.

Public highscore fields must match the project's approved definition:
`highscore_seconds`, `best_time_sec`, and `best_lap_sec` are the existing example
fields. Request approval for any new field (including `car_body`) before using
it in production. A private replay's name/color is not treated as profile truth.

## Leaderboard estimates

At player finish, completed rivals retain their measured times even after their
vehicles disappear. Ghosts have known recorded durations. For unfinished AI,
project the remaining lap fraction using elapsed time per completed lap fraction,
with completed-lap average as a lower bound on lap duration. Current slowdowns
therefore influence the forecast. Clamp each forecast beyond the player's finish
time and label it **Estimated**. The screen is a race snapshot, not a platform-wide
leaderboard or a claim that unfinished AI actually achieved those times.
