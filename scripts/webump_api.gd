extends Node
## weBump Connected Games client for this demo (autoload `WeBumpAPI`).
##
## One node owns the delegated session (OAuth device grant, public client), the
## player's private save, the reviewed public capsule/showcase values, the selected
## shared replay, and the authorized visitor cards. Tokens live only in memory.
## docs/API_INTEGRATION.md explains the contract this file implements.

signal auth_started(is_mock: bool)
signal auth_succeeded(player_profile: Dictionary, is_mock: bool)
signal auth_failed(error_message: String)
signal session_disconnected()
signal car_body_changed(body_id: String)
signal state_saved(key: String, value: Variant)
signal state_loaded(key: String, value: Variant)
signal capsule_saved(value: Dictionary)
signal capsule_loaded(value: Dictionary)
signal showcase_saved(value: Dictionary)
signal showcase_loaded(value: Dictionary)
signal shared_data_published(value: Dictionary)
signal permissions_loaded(permissions: Dictionary)
## Approval is waiting on the player's phone. `qr` is null when the weBump app was
## opened directly on this device, so no code needs scanning.
signal approval_started(qr: Texture2D, approval_url: String)
signal approval_finished()
signal visitors_updated(cards: Array)
signal visitors_failed(error_message: String)
signal request_failed(operation: String, status: int)

const CONFIG_PATH := "res://config.json"
const SAVE_STATE_PATH := "user://webump_state.json"
const REFRESH_MARGIN_SECONDS := 30

# Public identifiers from config.json. Hiding them is not a security boundary.
var client_id := "wb_5c296d5bb9144ad9a039d24056eaa802"
var api_origin := "https://api.webump.app"
var redirect_uri := "https://webump.app/demo"
var scopes: Array = ["profile.basic", "game.state", "visitors.receive", "game.capsule", "game.showcase", "game.shared"]
## How the player is asked to approve. "auto" opens the weBump app when this game is
## running on an iPhone and shows a scannable code everywhere else; "app" and "scan"
## force one of the two. Set it in config.json when you know your platform.
var approval_display := "auto"

var is_editor_mode := OS.has_feature("editor")
var is_mock_mode := OS.has_feature("editor")
var is_authenticated := false
var is_connecting := false

# Delegated tokens: ten-minute access token, rotating refresh token. Never on disk.
var access_token := ""
var refresh_token := ""
var token_expires_at := 0
var current_player_profile: Dictionary = {}

var selected_car_body := "truck_yellow"
var local_state: Dictionary = {}
var local_capsule: Dictionary = {}
var local_showcase: Dictionary = {}
## Player-controlled weBump toggle; the game cannot enable it. Read from /v1/me/permissions.
var shared_data_sharing := false
var current_etag := ""
var last_write_status := 0
## Session-only authorized cards from the redeemed visitor handoff.
var visitor_cards: Array = []

var _current_verifier := ""
var _current_state := ""
var _handoff_pkce: Dictionary = {}
var _write_queue: Array[Dictionary] = []
var _writing := false
var _refreshing := false
var _session_generation := 0
var _web_callback # JavaScriptObject; kept referenced so the browser callback stays alive.

func _ready() -> void:
	selected_car_body = CarPresets.get_selected_car()
	_load_config()
	_load_local_state()
	# Mock mode exists only inside the editor; every export talks to the real API.
	is_editor_mode = OS.has_feature("editor")
	is_mock_mode = is_editor_mode
	if OS.has_feature("web"):
		# The export shell (web/shell.html) relays approval results from the popup here.
		_web_callback = JavaScriptBridge.create_callback(_on_web_callback)
		JavaScriptBridge.get_interface("window").webumpDeliverCallback = _web_callback

func _load_config() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if parsed is Dictionary:
		client_id = parsed.get("client_id", client_id)
		api_origin = parsed.get("api_origin", api_origin)
		redirect_uri = parsed.get("redirect_uri", redirect_uri)
		scopes = parsed.get("scopes", scopes)
		approval_display = str(parsed.get("approval_display", approval_display))
		if not ["auto", "app", "scan"].has(approval_display):
			push_warning("Unknown approval_display %s; using auto." % approval_display)
			approval_display = "auto"

func get_mode_description() -> String:
	if is_mock_mode:
		return "Mock Mode (Editor)" if is_editor_mode else "Mock Mode (Simulated)"
	return "Live API (%s)" % api_origin

# -------------------------------------------------------------------
# Connecting: mock in the editor, explicit OAuth device approval elsewhere
# -------------------------------------------------------------------
func connect_player() -> void:
	if is_connecting or is_authenticated:
		return
	is_connecting = true
	auth_started.emit(is_mock_mode)
	if is_mock_mode:
		var tree := _get_tree_safe()
		if tree:
			tree.create_timer(0.8).timeout.connect(_complete_mock_auth)
		else:
			_complete_mock_auth()
	else:
		_start_live_oauth_flow()

func _complete_mock_auth() -> void:
	if not is_connecting:
		return
	is_connecting = false
	is_authenticated = true
	# Synthetic player profile; rival identities come from visitor cards.
	current_player_profile = {
		"display_name": "Demo Player", "theme_color": "#FF3366", "player_id": "demo-player",
		"is_mock": true, "mode": "Mock Mode (Editor)", "connected_at": Time.get_datetime_string_from_system(),
	}
	auth_succeeded.emit(current_player_profile, true)

func _generate_pkce_pair() -> Dictionary:
	var crypto := Crypto.new()
	var verifier := _base64url(crypto.generate_random_bytes(32))
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(verifier.to_ascii_buffer())
	return {"verifier": verifier, "challenge": _base64url(ctx.finish()), "state": _base64url(crypto.generate_random_bytes(16))}

static func _base64url(bytes: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(bytes).replace("+", "-").replace("/", "_").replace("=", "")

var approval_user_code := ""
var approval_app_url := ""
var approval_page_url := ""

func _start_live_oauth_flow() -> void:
	# Explicit reviewed device grant works in native apps and browser exports alike.
	var response := await _http("/oauth/device_authorization", HTTPClient.METHOD_POST, {
		"client_id": client_id, "scope": " ".join(scopes)})
	if not response.ok:
		_fail_connection("Could not start device connection (%s). Check that this project is approved for device connections." % str(response.data.get("error", response.status)))
		return
	await _await_device_approval(response.data)

func _await_device_approval(begin: Dictionary) -> void:
	var generation := _session_generation
	var device_code := str(begin.get("device_code", ""))
	approval_user_code = str(begin.get("user_code", ""))
	var approval_url := str(begin.get("verification_uri_complete", ""))
	approval_page_url = approval_url
	approval_app_url = str(begin.get("app_url", "")) if _opens_app_directly() else ""
	if device_code.is_empty() or approval_user_code.is_empty():
		_fail_connection("Invalid device connection response")
		return
	# Display the matching code before leaving the game, including on this phone.
	if _opens_app_directly():
		approval_started.emit(null, approval_url)
	else:
		approval_started.emit(await _load_qr(str(begin.get("qr_url", ""))), approval_url)
	var interval := maxi(5, int(begin.get("interval", 5)))
	var deadline := Time.get_unix_time_from_system() + int(begin.get("expires_in", 300))
	while generation == _session_generation and Time.get_unix_time_from_system() < deadline:
		await get_tree().create_timer(float(interval)).timeout
		if generation != _session_generation:
			return
		var result := await _http("/oauth/token", HTTPClient.METHOD_POST, {
			"grant_type": "urn:ietf:params:oauth:grant-type:device_code", "client_id": client_id, "device_code": device_code})
		if generation != _session_generation:
			return
		if result.ok:
			approval_finished.emit()
			_store_tokens(result.data)
			await fetch_player_profile()
			return
		var problem := str(result.data.get("error", "connection_failed"))
		if problem == "authorization_pending":
			continue
		if problem == "slow_down":
			interval += 5
			continue
		# Never retry an uncertain successful token response; start a fresh connection.
		approval_finished.emit()
		_fail_connection("Connection ended: " + problem)
		return
	if generation == _session_generation:
		approval_finished.emit()
		_fail_connection("Connection expired. Please try again.")

func open_device_approval() -> void:
	if is_connecting and not approval_page_url.is_empty():
		_open_approval(approval_app_url, approval_page_url)

# Explicit legacy visitor handoff remains callback-based; polling cannot deliver its code.
func _await_approval(begin: Dictionary) -> void:
	_open_approval(str(begin.get("app_url", "")), str(begin.get("authorization_url", "")))

## Whether approval hands straight to the weBump app on this device, or the player
## scans a code with a separate phone. The API returns both links every time; this
## is purely a presentation choice, so a game that knows its platform should say so
## through `approval_display` rather than leave it to detection.
func _opens_app_directly() -> bool:
	match approval_display:
		"app":
			return true
		"scan":
			return false
		_:
			# weBump is an iOS app, so only an iOS device can approve without scanning.
			return _is_apple_mobile()

## Whether this device can hand straight to an iOS app. Godot's `web_ios` feature reads
## the user agent, which iPadOS deliberately reports as a Mac for desktop-class browsing,
## so an iPad is indistinguishable from a desktop by user agent alone. A Mac that reports
## more than one touch point is an iPad; a real Mac reports none.
func _is_apple_mobile() -> bool:
	if OS.has_feature("ios") or OS.has_feature("web_ios"):
		return true
	if not OS.has_feature("web"):
		return false
	var touch_mac: Variant = JavaScriptBridge.eval(
		"(navigator.maxTouchPoints > 1 && /Mac|iPad|iPhone|iPod/.test(navigator.platform || navigator.userAgent || '')) ? 1 : 0",
		true)
	return typeof(touch_mac) in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT] and int(touch_mac) == 1

func _open_approval(app_url: String, page_url: String) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.webumpOpenApproval ? window.webumpOpenApproval(%s, %s) : window.open(%s, '_blank')" % [
			JSON.stringify(app_url), JSON.stringify(page_url), JSON.stringify(page_url)], true)
	else:
		OS.shell_open(page_url if app_url.is_empty() else app_url)

## Stops waiting for an approval still pending on the player's phone. Nothing is
## authorized by cancelling; the request simply expires on its own.
func cancel_approval() -> void:
	if not is_connecting and _handoff_pkce.is_empty():
		return
	_session_generation += 1
	_handoff_pkce.clear()
	approval_finished.emit()
	if is_connecting:
		_fail_connection("Connection cancelled")

## The approval QR as a texture. Any failure returns null and the panel falls back
## to showing the link, so a missing image never blocks connecting.
func _load_qr(url: String) -> Texture2D:
	var http := HTTPRequest.new()
	http.timeout = 10.0
	add_child(http)
	if http.request(url, PackedStringArray(["Accept: image/svg+xml"])) != OK:
		http.queue_free()
		return null
	var response: Array = await http.request_completed
	http.queue_free()
	if response[0] != HTTPRequest.RESULT_SUCCESS or response[1] != 200:
		return null
	var image := Image.new()
	if image.load_svg_from_string(response[3].get_string_from_utf8(), 2.0) != OK:
		return null
	return ImageTexture.create_from_image(image)

## Parse the registered callback URL exactly as a redirect handler would.
func _deliver_callback_url(url: String) -> void:
	var params := {}
	var query := url.get_slice("?", 1).get_slice("#", 0)
	for pair in query.split("&", false):
		params[pair.get_slice("=", 0).uri_decode()] = pair.get_slice("=", 1).uri_decode()
	_route_callback(str(params.get("code", "")), str(params.get("state", "")), str(params.get("error", "")))

## Deliver the callback's code and state exactly as returned to the registered redirect.
func exchange_authorization_code(code: String, returned_state: String = "") -> void:
	if _current_state.is_empty() or returned_state != _current_state:
		_fail_connection("Invalid OAuth callback state")
		return
	_current_state = ""
	var verifier := _current_verifier
	_current_verifier = ""
	var response := await _http("/oauth/token", HTTPClient.METHOD_POST, {
		"grant_type": "authorization_code", "client_id": client_id, "redirect_uri": redirect_uri,
		"code": code, "code_verifier": verifier})
	if not response.ok:
		_fail_connection("Token exchange failed (HTTP %d)" % response.status)
		return
	_store_tokens(response.data)
	await fetch_player_profile()

func fetch_player_profile() -> void:
	var response := await _request_json("/v1/me")
	if not response.ok:
		_fail_connection("Profile fetch failed (HTTP %d)" % response.status)
		return
	current_player_profile = response.data
	current_player_profile["is_mock"] = false
	current_player_profile["mode"] = "Live API"
	is_authenticated = true
	is_connecting = false
	# Remember who played here (name and color only) so a return visit greets them
	# instead of looking like a fresh install. Tokens are never stored.
	local_state["known_player"] = {"display_name": get_player_display_name(), "theme_color": get_player_theme_color_hex(),
		"connected_at": Time.get_datetime_string_from_system()}
	_save_local_state()
	await get_state("racing_save")
	await fetch_permissions()
	auth_succeeded.emit(current_player_profile, false)
	await load_visitors()

func _store_tokens(tokens: Dictionary) -> void:
	access_token = str(tokens.get("access_token", ""))
	refresh_token = str(tokens.get("refresh_token", ""))
	token_expires_at = int(Time.get_unix_time_from_system()) + int(tokens.get("expires_in", 600))

func _fail_connection(message: String) -> void:
	is_connecting = false
	access_token = ""
	refresh_token = ""
	_current_state = ""
	_current_verifier = ""
	auth_failed.emit(message)

## Ends the session. Revocation is best effort; local saves are always kept.
func disconnect_player(revoke: bool = true) -> void:
	if revoke and not is_mock_mode and not refresh_token.is_empty():
		_revoke(refresh_token)
	is_authenticated = false
	is_connecting = false
	access_token = ""
	refresh_token = ""
	token_expires_at = 0
	current_player_profile.clear()
	visitor_cards.clear()
	_handoff_pkce.clear()
	_current_state = ""
	_current_verifier = ""
	_session_generation += 1
	current_etag = ""
	shared_data_sharing = false
	visitors_updated.emit(visitor_cards)
	session_disconnected.emit()

func _revoke(token: String) -> void:
	await _http("/oauth/revoke", HTTPClient.METHOD_POST, {"client_id": client_id, "token": token})

## Legacy popup relay (see web/shell.html): the callback page posts code/state back.
func _on_web_callback(args: Array) -> void:
	var payload: Variant = JSON.parse_string(str(args[0])) if not args.is_empty() else null
	if payload is Dictionary:
		_route_callback(str(payload.get("code", "")), str(payload.get("state", "")), str(payload.get("error", "")))

## Routes a callback by state to the pending connect or visitor flow.
func _route_callback(code: String, state: String, error: String) -> void:
	if not _handoff_pkce.is_empty() and state == str(_handoff_pkce.get("state", "")):
		if not error.is_empty():
			_handoff_pkce.clear()
			visitors_failed.emit("Visitor handoff was cancelled" if error == "access_denied" else "Visitor handoff error: " + error)
		elif not await redeem_visitor_handoff(code, state):
			visitors_failed.emit("Visitor handoff could not be completed")
		return
	if not _handoff_pkce.is_empty() and state.is_empty() and not error.is_empty():
		_handoff_pkce.clear()
		visitors_failed.emit("Visitor handoff " + ("expired" if error == "expired" else "failed"))
		return
	if not error.is_empty():
		match error:
			"access_denied": _fail_connection("Connection request was cancelled on your phone")
			"expired": _fail_connection("The connection request expired. Press Connect to try again")
			_: _fail_connection("Connection error: " + error)
		return
	exchange_authorization_code(code, state)

# -------------------------------------------------------------------
# Transport
# -------------------------------------------------------------------
## Low-level JSON request. OAuth calls pass no token; game calls go through _request_json.
func _http(path: String, method: HTTPClient.Method, payload: Dictionary = {}, token: String = "", etag: String = "") -> Dictionary:
	var generation := _session_generation
	var http := HTTPRequest.new()
	http.timeout = 15.0
	add_child(http)
	var headers := PackedStringArray(["Accept: application/json", "Content-Type: application/json"])
	if not token.is_empty():
		headers.append("Authorization: Bearer " + token)
	if not etag.is_empty():
		headers.append("If-Match: " + etag)
	var has_body := method == HTTPClient.METHOD_PUT or method == HTTPClient.METHOD_POST
	var error := http.request(api_origin + path, headers, method, JSON.stringify(payload) if has_body else "")
	if error != OK:
		http.queue_free()
		request_failed.emit(path, 0)
		return {"ok": false, "status": 0, "data": {}, "etag": ""}
	var response: Array = await http.request_completed
	http.queue_free()
	if generation != _session_generation:
		return {"ok": false, "status": 401, "data": {}, "etag": ""}
	var parsed: Variant = JSON.parse_string(response[3].get_string_from_utf8())
	var ok: bool = response[0] == HTTPRequest.RESULT_SUCCESS and response[1] >= 200 and response[1] < 300 and parsed is Dictionary
	var revision := ""
	for header in response[2]:
		if header.to_lower().begins_with("etag:"):
			revision = header.substr(5).strip_edges()
	if not ok:
		request_failed.emit(path, response[1])
	return {"ok": ok, "status": response[1], "data": parsed if parsed is Dictionary else {}, "etag": revision}

## Authorized game call. Refreshes an expiring access token first.
func _request_json(path: String, method: HTTPClient.Method = HTTPClient.METHOD_GET, payload: Dictionary = {}, etag: String = "") -> Dictionary:
	if not await _ensure_fresh_token():
		return {"ok": false, "status": 401, "data": {}, "etag": ""}
	return await _http(path, method, payload, access_token, etag)

## Refresh responses are single-use and must never be retried: one attempt, and a
## failure ends the session so the player reconnects deliberately.
func _ensure_fresh_token() -> bool:
	if access_token.is_empty():
		return false
	if refresh_token.is_empty() or Time.get_unix_time_from_system() < token_expires_at - REFRESH_MARGIN_SECONDS:
		return true
	if _refreshing:
		while _refreshing:
			await get_tree().process_frame
		return not access_token.is_empty()
	_refreshing = true
	var generation := _session_generation
	var response := await _http("/oauth/token", HTTPClient.METHOD_POST, {
		"grant_type": "refresh_token", "client_id": client_id, "refresh_token": refresh_token})
	_refreshing = false
	if generation != _session_generation:
		return false
	if not response.ok:
		disconnect_player(false)
		auth_failed.emit("Session expired. Connect again to keep syncing.")
		return false
	_store_tokens(response.data)
	return true

# -------------------------------------------------------------------
# Local state and player preferences
# -------------------------------------------------------------------
func _load_local_state() -> void:
	if FileAccess.file_exists(SAVE_STATE_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_STATE_PATH))
		if parsed is Dictionary:
			local_state = parsed
			if local_state.get("capsule") is Dictionary:
				local_capsule = local_state.capsule
			if local_state.get("showcase") is Dictionary:
				local_showcase = local_state.showcase
	if local_state.has("selected_car_body") and CarPresets.has_preset(str(local_state.selected_car_body)):
		selected_car_body = str(local_state.selected_car_body)
		CarPresets._active_car_id = selected_car_body
	else:
		selected_car_body = CarPresets.get_selected_car()

func _save_local_state() -> void:
	local_state["capsule"] = local_capsule
	local_state["showcase"] = local_showcase
	var file := FileAccess.open(SAVE_STATE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(local_state, "  "))

func set_selected_car_body(body_id: String) -> void:
	selected_car_body = body_id
	local_state["selected_car_body"] = body_id
	_save_local_state()
	CarPresets._active_car_id = body_id
	car_body_changed.emit(body_id)

func get_selected_car_body() -> String:
	return selected_car_body

## The player who last connected on this device, or empty. Used only for greetings.
func known_player() -> Dictionary:
	var known: Variant = local_state.get("known_player", {})
	return known if known is Dictionary else {}

func has_progress() -> bool:
	var save: Variant = local_state.get("racing_save", {})
	return save is Dictionary and int(save.get("races", 0)) > 0

func get_player_display_name() -> String:
	if is_authenticated and current_player_profile.has("display_name"):
		return str(current_player_profile.display_name)
	if not is_mock_mode and known_player().has("display_name"):
		return str(known_player().display_name)
	return "Player"

func get_player_theme_color() -> Color:
	if is_authenticated and current_player_profile.has("theme_color"):
		return Color.from_string(str(current_player_profile.theme_color), Color(0.06, 0.72, 0.44, 1.0))
	return CarPresets.get_preset_by_id(selected_car_body).get("default_color", Color(1.0, 0.70, 0.0))

func get_player_theme_color_hex() -> String:
	if is_authenticated and current_player_profile.has("theme_color"):
		return str(current_player_profile.theme_color)
	return "#" + get_player_theme_color().to_html(false)

# -------------------------------------------------------------------
# Private save (game.state) and reviewed public values (game.capsule / game.showcase)
# -------------------------------------------------------------------
func get_state(key: String, callback: Callable = Callable()) -> void:
	var ok := true
	var value: Variant = local_state.get(key)
	if not is_mock_mode and is_authenticated:
		var response := await _request_json("/v1/me/state")
		ok = response.ok
		if ok:
			value = response.data.get("data", {}).get(key)
			local_state[key] = value
			_save_local_state()
	state_loaded.emit(key, value)
	if callback.is_valid():
		callback.call(ok, value)

func put_state(key: String, value: Variant, callback: Callable = Callable()) -> void:
	local_state[key] = value
	_save_local_state()
	_queue_write("/v1/me/state/" + key.uri_encode(), value, Callable(), callback, key)

## The personal-best replay stays in private state. Nothing here is visible to others.
func save_ghost_telemetry(ghost_data: Dictionary) -> void:
	put_state("ghost_telemetry", ghost_data)

## Public high score in integer seconds: the capsule travels with bump cards, the
## showcase can appear on the player's weBump profile. Both use reviewed fields only.
func save_public_highscore(total_time_seconds: float, best_lap_seconds: float = 0.0, callback: Callable = Callable()) -> Dictionary:
	var highscore_sec := int(round(total_time_seconds))
	var public_data := {"highscore_seconds": highscore_sec, "best_time_sec": highscore_sec, "best_lap_sec": int(round(best_lap_seconds))}
	put_capsule(public_data, callback)
	put_showcase(public_data)
	return public_data

func get_public_highscore_seconds() -> int:
	for source in [local_capsule, local_showcase, local_state.get("racing_save", {})]:
		if source is Dictionary:
			if source.has("highscore_seconds"):
				return int(source.highscore_seconds)
			if source.has("best_time_sec"):
				return int(source.best_time_sec)
	return -1

func get_capsule(callback: Callable = Callable()) -> void:
	await _get_public("capsule", callback)

func get_showcase(callback: Callable = Callable()) -> void:
	await _get_public("showcase", callback)

func _get_public(resource: String, callback: Callable) -> void:
	var value: Dictionary = local_capsule if resource == "capsule" else local_showcase
	var ok := true
	if not is_mock_mode and is_authenticated:
		var response := await _request_json("/v1/me/" + resource)
		ok = response.ok
		if ok:
			value = response.data.get("data", {})
			if resource == "capsule":
				local_capsule = value
			else:
				local_showcase = value
			_save_local_state()
	if resource == "capsule":
		capsule_loaded.emit(value)
	else:
		showcase_loaded.emit(value)
	if callback.is_valid():
		callback.call(ok, value)

func put_capsule(value: Dictionary, callback: Callable = Callable()) -> void:
	local_capsule = value
	_save_local_state()
	_queue_write("/v1/me/capsule", value, capsule_saved.emit, callback)

func put_showcase(value: Dictionary, callback: Callable = Callable()) -> void:
	local_showcase = value
	_save_local_state()
	_queue_write("/v1/me/showcase", value, showcase_saved.emit, callback)

# -------------------------------------------------------------------
# Selected shared data (game.shared)
# -------------------------------------------------------------------
func fetch_permissions(callback: Callable = Callable()) -> void:
	var permissions: Dictionary = {"shared_data_sharing": shared_data_sharing}
	var ok := true
	if not is_mock_mode and is_authenticated:
		var response := await _request_json("/v1/me/permissions")
		ok = response.ok
		if ok:
			permissions = response.data
			shared_data_sharing = bool(permissions.get("shared_data_sharing", false))
	permissions_loaded.emit(permissions)
	if callback.is_valid():
		callback.call(ok, permissions)

## Publish one player-selected document. Call only from an explicit in-game action.
## 403 means the player has not enabled "Share selected game data" in weBump.
func publish_shared_data(value: Dictionary, callback: Callable = Callable()) -> void:
	_queue_write("/v1/me/shared", value, shared_data_published.emit, callback, "", true)

func withdraw_shared_data(callback: Callable = Callable()) -> void:
	_queue_write("/v1/me/shared", {}, shared_data_published.emit, callback, "", false, HTTPClient.METHOD_DELETE)

# -------------------------------------------------------------------
# Serialized writes: every resource shares one revision
# -------------------------------------------------------------------
func _queue_write(path: String, value: Variant, saved: Callable, callback: Callable, key: String = "", publish: bool = false, method: HTTPClient.Method = HTTPClient.METHOD_PUT) -> void:
	_write_queue.append({"path": path, "value": value, "saved": saved, "callback": callback, "key": key,
		"publish": publish, "method": method, "generation": _session_generation})
	if not _writing:
		_drain_writes()

func _drain_writes() -> void:
	_writing = true
	while not _write_queue.is_empty():
		var write: Dictionary = _write_queue.pop_front()
		var ok: bool = write.generation == _session_generation
		if ok and not is_mock_mode and is_authenticated:
			# Read a fresh strong ETag first and send it as If-Match; a 409 surfaces
			# instead of silently overwriting another session's save.
			var document := await _request_json("/v1/me/state")
			ok = document.ok and not document.get("etag", "").is_empty()
			if ok:
				current_etag = document.etag
				var body: Dictionary = {"value": write.value}
				if write.publish:
					body["publish"] = true # Explicit selection; the server rejects implicit publication.
				var response := await _request_json(write.path, write.method, body, current_etag)
				ok = response.ok
				last_write_status = response.status
		if ok:
			if not write.key.is_empty():
				state_saved.emit(write.key, write.value)
			else:
				write.saved.call(write.value)
		if write.callback.is_valid():
			write.callback.call(ok, write.value)
	_writing = false

# -------------------------------------------------------------------
# Visitors (visitors.receive): people the player bumped, by their own choice
# -------------------------------------------------------------------
## Cards come from the redeemed handoff. ghost_telemetry is attached only from the
## authorized game.shared read in refresh_visitors(); never another player's private state.
func set_visitor_cards(cards: Array) -> void:
	visitor_cards = cards.slice(0, 50).duplicate(true)
	visitors_updated.emit(visitor_cards)

## Everyone the player bumped since connecting, once weBump's reveal delay has passed.
## No approval step: visitors.receive was granted when the player connected. Each
## rival's shared replay is fetched by reference; 410 means nothing is shared.
func load_visitors() -> void:
	if is_mock_mode or not is_authenticated:
		return
	var generation := _session_generation
	var response := await _request_json("/v1/me/visitors")
	if not response.ok or generation != _session_generation:
		return
	var cards: Array = []
	for card in response.data.get("visitors", []):
		if not card is Dictionary or not card.get("reference") is String:
			continue
		var fresh: Dictionary = card.duplicate(true)
		if scopes.has("game.shared"):
			var shared := await _request_json("/v1/me/visitors/" + card.reference.uri_encode() + "/shared")
			if shared.ok and shared.data.get("data") is Dictionary:
				fresh["ghost_telemetry"] = shared.data.data
		cards.append(fresh)
	if generation == _session_generation:
		set_visitor_cards(cards)

## Optional explicit transfer: lets the player hand over a chosen set of bumps through
## the weBump app. The demo relies on load_visitors() instead.
func request_visitors() -> bool:
	if is_mock_mode or not is_authenticated:
		return false
	var response := await begin_visitor_handoff()
	if not response.ok or not response.data.get("authorization_url") is String:
		visitors_failed.emit("Could not start the visitor handoff (HTTP %d)" % response.status)
		return false
	_await_approval(response.data)
	return true

func begin_visitor_handoff() -> Dictionary:
	_handoff_pkce = _generate_pkce_pair()
	return await _request_json("/v1/me/visitor-handoff", HTTPClient.METHOD_POST, {
		"action": "begin", "client_id": client_id, "redirect_uri": redirect_uri,
		"response_type": "code", "state": _handoff_pkce.state, "scope": "visitors.receive",
		"code_challenge": _handoff_pkce.challenge, "code_challenge_method": "S256", "display": "popup"})

func redeem_visitor_handoff(code: String, returned_state: String) -> bool:
	if _handoff_pkce.is_empty() or returned_state != _handoff_pkce.state:
		return false
	var verifier: String = _handoff_pkce.verifier
	_handoff_pkce.clear()
	var response := await _request_json("/v1/me/visitor-handoff", HTTPClient.METHOD_POST, {
		"action": "redeem", "code": code, "code_verifier": verifier, "redirect_uri": redirect_uri})
	if response.ok:
		set_visitor_cards(response.data.get("visitors", []))
		await refresh_visitors()
	return response.ok

## Revalidate every card and fetch each rival's shared replay by reference.
func refresh_visitors() -> void:
	if is_mock_mode or not is_authenticated:
		return
	var refreshed: Array = []
	for card in visitor_cards.duplicate(true):
		if not card is Dictionary or not card.get("reference") is String:
			continue
		var reference: String = card.reference.uri_encode()
		var response := await _request_json("/v1/me/visitors/" + reference)
		if not response.ok:
			continue
		var fresh: Dictionary = response.data
		if scopes.has("game.shared"):
			# 410 means nothing is shared (opt-out, expiry, withdrawal, block); race that person as AI.
			var shared := await _request_json("/v1/me/visitors/" + reference + "/shared")
			if shared.ok and shared.data.get("data") is Dictionary:
				fresh["ghost_telemetry"] = shared.data.data
		refreshed.append(fresh)
	# Fail closed: revoked, expired, or unavailable cards aren't raced from cache.
	set_visitor_cards(refreshed)

func _get_tree_safe() -> SceneTree:
	if is_inside_tree() and get_tree():
		return get_tree()
	return Engine.get_main_loop() as SceneTree
