extends Node

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
signal visitors_updated(cards: Array)
signal request_failed(operation: String, status: int)

const CONFIG_PATH: String = "res://config.json"
const SAVE_STATE_PATH: String = "user://webump_state.json"

var client_id: String = "wb_5c296d5bb9144ad9a039d24056eaa802"
var api_origin: String = "https://api.webump.app"
var redirect_uri: String = "https://webump.app/demo"
var scopes: Array = ["profile.basic", "game.state", "visitors.receive", "game.capsule", "game.showcase", "game.shared"]

var is_editor_mode: bool = OS.has_feature("editor")
var is_mock_mode: bool = OS.has_feature("editor")
var is_authenticated: bool = false
var is_connecting: bool = false

var access_token: String = ""
var refresh_token: String = ""
var token_expires_at: int = 0
var current_player_profile: Dictionary = {}

var selected_car_body: String = "truck_yellow"
var local_state: Dictionary = {}
var local_capsule: Dictionary = {}
var local_showcase: Dictionary = {}
## Player-controlled weBump toggle; the game cannot enable it. Read from /v1/me/permissions.
var shared_data_sharing: bool = false
var current_etag: String = ""
var last_write_status: int = 0
var visitor_cards: Array = []
var _handoff_pkce: Dictionary = {}
var _write_queue: Array[Dictionary] = []
var _writing := false
var _session_generation := 0

var _current_verifier: String = ""
var _current_state: String = ""
var _http_request: HTTPRequest

func _get_tree_safe() -> SceneTree:
	if is_inside_tree() and get_tree():
		return get_tree()
	return Engine.get_main_loop() as SceneTree

func _ready() -> void:
	selected_car_body = CarPresets.get_selected_car()
	_load_config()
	_load_local_state()
	
	# Determine mode: editor always enables mock mode unless explicitly forced
	is_editor_mode = OS.has_feature("editor")
	is_mock_mode = is_editor_mode or _config_mock_mode
	
	# Internal HTTP request node for live API requests
	if _http_request == null:
		_http_request = HTTPRequest.new()
		_http_request.name = "WeBumpHTTPRequest"
		add_child(_http_request)

var _config_mock_mode: bool = false

func _load_config() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		return
	
	var file = FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if not file:
		return
	
	var json_str = file.get_as_text()
	var parsed = JSON.parse_string(json_str)
	if typeof(parsed) == TYPE_DICTIONARY:
		client_id = parsed.get("client_id", client_id)
		api_origin = parsed.get("api_origin", api_origin)
		redirect_uri = parsed.get("redirect_uri", redirect_uri)
		scopes = parsed.get("scopes", scopes)
		_config_mock_mode = parsed.get("mock_mode", false)

func get_mode_description() -> String:
	if is_mock_mode:
		if is_editor_mode:
			return "Mock Mode (Editor)"
		else:
			return "Mock Mode (Simulated)"
	else:
		return "Live API (api.webump.app)"

func connect_player() -> void:
	if is_connecting or is_authenticated:
		return
	
	is_connecting = true
	auth_started.emit(is_mock_mode)
	
	if is_mock_mode:
		_start_mock_connection()
	else:
		_start_live_oauth_flow()

# -------------------------------------------------------------------
# Mock Mode Flow (Used in Godot Editor)
# -------------------------------------------------------------------
func _start_mock_connection() -> void:
	var tree = _get_tree_safe()
	if tree:
		var timer = tree.create_timer(0.8)
		timer.timeout.connect(_complete_mock_auth)
	else:
		_complete_mock_auth()

func _complete_mock_auth() -> void:
	if not is_connecting:
		return
	is_connecting = false
	is_authenticated = true
	
	# Synthetic player profile; rival identities come from visitor cards.
	current_player_profile = {
		"display_name": "Demo Player",
		"theme_color": "#FF3366",
		"player_id": "demo-player",
		"is_mock": true,
		"mode": "Mock Mode (Editor)",
		"connected_at": Time.get_datetime_string_from_system()
	}
	
	auth_succeeded.emit(current_player_profile, true)

# -------------------------------------------------------------------
# Live OAuth 2.0 PKCE Flow (Used in Public Builds / Web / Staging)
# -------------------------------------------------------------------
func _generate_pkce_pair() -> Dictionary:
	var crypto = Crypto.new()
	var random_bytes = crypto.generate_random_bytes(32)
	var verifier = Marshalls.raw_to_base64(random_bytes).replace("+", "-").replace("/", "_").replace("=", "")
	
	var ctx = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(verifier.to_ascii_buffer())
	var digest = ctx.finish()
	var challenge = Marshalls.raw_to_base64(digest).replace("+", "-").replace("/", "_").replace("=", "")
	
	var state_bytes = crypto.generate_random_bytes(16)
	var state = Marshalls.raw_to_base64(state_bytes).replace("+", "-").replace("/", "_").replace("=", "")
	
	return {
		"verifier": verifier,
		"challenge": challenge,
		"state": state
	}

func _start_live_oauth_flow() -> void:
	var pkce = _generate_pkce_pair()
	_current_verifier = pkce["verifier"]
	_current_state = pkce["state"]
	
	var scope_str = " ".join(scopes).uri_encode()
	var auth_url = "%s/oauth/authorize?response_type=code&client_id=%s&redirect_uri=%s&scope=%s&code_challenge=%s&code_challenge_method=S256&state=%s" % [
		api_origin,
		client_id.uri_encode(),
		redirect_uri.uri_encode(),
		scope_str,
		pkce["challenge"],
		_current_state
	]
	
	# If running on Web with JavaScript bridge
	if OS.has_feature("web") and ClassDB.class_exists("JavaScriptBridge"):
		var js = Engine.get_singleton("JavaScriptBridge")
		if js:
			js.eval("window.open('%s', '_blank', 'width=500,height=700');" % auth_url)
			return
	
	# On desktop standalone builds, open default browser
	OS.shell_open(auth_url)

func exchange_authorization_code(code: String, returned_state: String = "") -> void:
	if _current_state.is_empty() or returned_state != _current_state:
		is_connecting = false
		auth_failed.emit("Invalid OAuth callback state")
		return
	_current_state = ""
	if _current_verifier.is_empty():
		push_error("No PKCE code_verifier found for token exchange.")
		auth_failed.emit("Missing PKCE code verifier")
		return
	
	var token_url = "%s/oauth/token" % api_origin
	var headers = [
		"Content-Type: application/json",
		"Accept: application/json"
	]
	
	var payload = {
		"grant_type": "authorization_code",
		"client_id": client_id,
		"redirect_uri": redirect_uri,
		"code": code,
		"code_verifier": _current_verifier
	}
	
	var json_body = JSON.stringify(payload)
	
	if _http_request.is_inside_tree():
		_http_request.request_completed.connect(_on_token_exchange_completed, CONNECT_ONE_SHOT)
		var err = _http_request.request(token_url, headers, HTTPClient.METHOD_POST, json_body)
		if err != OK:
			is_connecting = false
			auth_failed.emit("Failed to initiate token request: Error %d" % err)

func _on_token_exchange_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		is_connecting = false
		auth_failed.emit("Token exchange failed (HTTP %d)" % response_code)
		return
	
	var response_json = JSON.parse_string(body.get_string_from_utf8())
	if typeof(response_json) != TYPE_DICTIONARY:
		is_connecting = false
		auth_failed.emit("Invalid token JSON response.")
		return
	
	access_token = response_json.get("access_token", "")
	refresh_token = response_json.get("refresh_token", "")
	var expires_in = response_json.get("expires_in", 600)
	token_expires_at = int(Time.get_unix_time_from_system()) + int(expires_in)
	
	# Fetch player profile with access token
	fetch_player_profile()

func fetch_player_profile() -> void:
	if access_token.is_empty():
		return
	
	var me_url = "%s/v1/me" % api_origin
	var headers = [
		"Authorization: Bearer %s" % access_token,
		"Accept: application/json"
	]
	
	_http_request.request_completed.connect(_on_player_profile_completed, CONNECT_ONE_SHOT)
	var err = _http_request.request(me_url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		is_connecting = false
		auth_failed.emit("Failed to fetch player profile: Error %d" % err)

func _on_player_profile_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	is_connecting = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		auth_failed.emit("Profile fetch failed (HTTP %d)" % response_code)
		return
	
	var profile_json = JSON.parse_string(body.get_string_from_utf8())
	if typeof(profile_json) == TYPE_DICTIONARY:
		current_player_profile = profile_json
		current_player_profile["is_mock"] = false
		current_player_profile["mode"] = "Live API"
		is_authenticated = true
		await get_state("racing_save")
		await fetch_permissions()
		auth_succeeded.emit(current_player_profile, false)
	else:
		auth_failed.emit("Invalid profile JSON received.")

func disconnect_player() -> void:
	is_authenticated = false
	is_connecting = false
	access_token = ""
	refresh_token = ""
	current_player_profile.clear()
	visitor_cards.clear()
	_handoff_pkce.clear()
	_session_generation += 1
	current_etag = ""
	shared_data_sharing = false
	visitors_updated.emit(visitor_cards)
	session_disconnected.emit()

# -------------------------------------------------------------------
# Local State & Player Preferences
# -------------------------------------------------------------------
func _load_local_state() -> void:
	if not FileAccess.file_exists(SAVE_STATE_PATH):
		selected_car_body = CarPresets.get_selected_car()
		return
	var file = FileAccess.open(SAVE_STATE_PATH, FileAccess.READ)
	if not file:
		selected_car_body = CarPresets.get_selected_car()
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		local_state = parsed
		if local_state.has("selected_car_body"):
			selected_car_body = str(local_state["selected_car_body"])
			CarPresets._active_car_id = selected_car_body
		else:
			selected_car_body = CarPresets.get_selected_car()
		if local_state.has("capsule") and typeof(local_state["capsule"]) == TYPE_DICTIONARY:
			local_capsule = local_state["capsule"]
		if local_state.has("showcase") and typeof(local_state["showcase"]) == TYPE_DICTIONARY:
			local_showcase = local_state["showcase"]

func _save_local_state() -> void:
	local_state["capsule"] = local_capsule
	local_state["showcase"] = local_showcase
	var file = FileAccess.open(SAVE_STATE_PATH, FileAccess.WRITE)
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

func get_player_display_name() -> String:
	if is_authenticated and current_player_profile.has("display_name"):
		return str(current_player_profile["display_name"])
	return "Player"

func get_player_theme_color() -> Color:
	if is_authenticated and current_player_profile.has("theme_color"):
		var hex: String = str(current_player_profile["theme_color"])
		return Color.from_string(hex, Color(0.06, 0.72, 0.44, 1.0))
	var preset = CarPresets.get_preset_by_id(selected_car_body)
	return preset.get("default_color", Color(1.0, 0.70, 0.0))

func get_player_theme_color_hex() -> String:
	if is_authenticated and current_player_profile.has("theme_color"):
		return str(current_player_profile["theme_color"])
	var c = get_player_theme_color()
	return "#" + c.to_html(false)

## Saves the player's highscore in seconds to the public weBump Capsule and Showcase.
## Public weBump data shown on the app upon bumping or on profile shelf uses integer seconds.
func save_public_highscore(total_time_seconds: float, best_lap_seconds: float = 0.0, callback: Callable = Callable()) -> Dictionary:
	var highscore_sec: int = int(round(total_time_seconds))
	var best_lap_sec: int = int(round(best_lap_seconds))
	
	var public_data: Dictionary = {
		"highscore_seconds": highscore_sec,
		"best_time_sec": highscore_sec,
		"best_lap_sec": best_lap_sec
	}
	
	print("[WeBumpAPI] ⏱️ Saving public weBump highscore: %d seconds (best lap: %d sec)" % [
		highscore_sec, best_lap_sec
	])
	
	put_capsule(public_data, callback)
	put_showcase(public_data)
	
	return public_data

func get_public_highscore_seconds() -> int:
	if local_capsule.has("highscore_seconds"):
		return int(local_capsule["highscore_seconds"])
	if local_capsule.has("best_time_sec"):
		return int(local_capsule["best_time_sec"])
	if local_showcase.has("highscore_seconds"):
		return int(local_showcase["highscore_seconds"])
	var saved_save = local_state.get("racing_save", {})
	if typeof(saved_save) == TYPE_DICTIONARY and saved_save.has("highscore_seconds"):
		return int(saved_save["highscore_seconds"])
	return -1



# One transport for game operations; OAuth retains its dedicated request node.
func _request_json(path: String, method: HTTPClient.Method = HTTPClient.METHOD_GET, payload: Dictionary = {}, etag: String = "") -> Dictionary:
	if access_token.is_empty():
		return {"ok": false, "status": 401, "data": {}}
	var generation := _session_generation
	var http := HTTPRequest.new()
	http.timeout = 15.0
	add_child(http)
	var headers := PackedStringArray(["Authorization: Bearer " + access_token, "Accept: application/json", "Content-Type: application/json"])
	if not etag.is_empty():
		headers.append("If-Match: " + etag)
	var error := http.request(api_origin + path, headers, method, JSON.stringify(payload) if method != HTTPClient.METHOD_GET else "")
	if error != OK:
		http.queue_free()
		request_failed.emit(path, 0)
		return {"ok": false, "status": 0, "data": {}}
	var response: Array = await http.request_completed
	http.queue_free()
	if generation != _session_generation:
		return {"ok": false, "status": 401, "data": {}}
	var ok: bool = response[0] == HTTPRequest.RESULT_SUCCESS and response[1] >= 200 and response[1] < 300
	var parsed: Variant = JSON.parse_string(response[3].get_string_from_utf8())
	ok = ok and parsed is Dictionary
	var revision := ""
	if ok:
		for header in response[2]:
			if header.to_lower().begins_with("etag:"):
				revision = header.substr(5).strip_edges()
	else:
		request_failed.emit(path, response[1])
	return {"ok": ok, "status": response[1], "data": parsed if parsed is Dictionary else {}, "etag": revision}

func get_state(key: String, callback: Callable = Callable()) -> void:
	var ok := true
	var value: Variant = local_state.get(key)
	if not is_mock_mode and is_authenticated:
		var response := await _request_json("/v1/me/state")
		ok = response.ok
		if ok:
			var document: Dictionary = response.data.get("data", {})
			value = document.get(key)
			local_state[key] = value
			_save_local_state()
	state_loaded.emit(key, value)
	if callback.is_valid():
		callback.call(ok, value)

func put_state(key: String, value: Variant, callback: Callable = Callable()) -> void:
	local_state[key] = value
	_save_local_state()
	_queue_write("/v1/me/state/" + key.uri_encode(), value, Callable(), callback, key)

## The personal-best replay stays in private state. Nothing here is visible to other players.
func save_ghost_telemetry(ghost_data: Dictionary) -> void:
	put_state("ghost_telemetry", ghost_data)

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

## Publish one player-selected document through game.shared. Call only from an explicit
## in-game action. The server also requires the player's weBump toggle, so a 403 means
## "ask the player to enable Share selected game data in weBump", not a bug.
func publish_shared_data(value: Dictionary, callback: Callable = Callable()) -> void:
	_queue_write("/v1/me/shared", value, shared_data_published.emit, callback, "", true)

func withdraw_shared_data(callback: Callable = Callable()) -> void:
	_queue_write("/v1/me/shared", {}, shared_data_published.emit, callback, "", false, HTTPClient.METHOD_DELETE)

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
			# All resources share a revision. Serialize writes and read a fresh strong
			# ETag first; surface conflicts without overwriting another session's save.
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

## Visitor cards come from the redeemed handoff. ghost_telemetry is attached only from the
## authorized game.shared read below (or a host adapter); it is never another player's private state.
func set_visitor_cards(cards: Array) -> void:
	visitor_cards = cards.slice(0, 50).duplicate(true)
	visitors_updated.emit(visitor_cards)

func begin_visitor_handoff() -> Dictionary:
	_handoff_pkce = _generate_pkce_pair()
	var response := await _request_json("/v1/me/visitor-handoff", HTTPClient.METHOD_POST, {
		"action": "begin", "client_id": client_id, "redirect_uri": redirect_uri,
		"response_type": "code", "state": _handoff_pkce.state, "scope": "visitors.receive",
		"code_challenge": _handoff_pkce.challenge, "code_challenge_method": "S256"})
	return response

func redeem_visitor_handoff(code: String, returned_state: String) -> bool:
	if _handoff_pkce.is_empty() or returned_state != _handoff_pkce.state:
		return false
	var verifier: String = _handoff_pkce.verifier
	_handoff_pkce.clear()
	var response := await _request_json("/v1/me/visitor-handoff", HTTPClient.METHOD_POST, {
		"action": "redeem", "code": code, "code_verifier": verifier, "redirect_uri": redirect_uri})
	if response.ok:
		set_visitor_cards(response.data.get("visitors", []))
	return response.ok

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
