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

const CONFIG_PATH: String = "res://config.json"
const SAVE_STATE_PATH: String = "user://webump_state.json"

var client_id: String = "wb_5c296d5bb9144ad9a039d24056eaa802"
var api_origin: String = "https://api.webump.app"
var redirect_uri: String = "https://webump.app/demo"
var scopes: Array = ["profile.basic", "game.state", "visitors.receive", "game.capsule", "game.showcase"]

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
var current_etag: String = "\"1\""

var _current_verifier: String = ""
var _current_state: String = ""
var _http_request: HTTPRequest

func _enter_tree() -> void:
	if get_tree() and get_tree().root:
		if get_tree().root.has_node("WeBumpAPI") and get_tree().root.get_node("WeBumpAPI") != self:
			queue_free()
			return
		if get_parent() != get_tree().root:
			reparent.call_deferred(get_tree().root)

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
	is_connecting = false
	is_authenticated = true
	
	# In editor mock mode, use Maya's profile (#FF3366 Neon Rose) per planning docs
	current_player_profile = {
		"display_name": "Racer Maya",
		"theme_color": "#FF3366",
		"player_id": "wb_mock_maya_01",
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

func exchange_authorization_code(code: String) -> void:
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
		var err_str = body.get_string_from_utf8()
		auth_failed.emit("Token exchange failed (HTTP %d): %s" % [response_code, err_str])
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
		var err_str = body.get_string_from_utf8()
		auth_failed.emit("Profile fetch failed (HTTP %d): %s" % [response_code, err_str])
		return
	
	var profile_json = JSON.parse_string(body.get_string_from_utf8())
	if typeof(profile_json) == TYPE_DICTIONARY:
		current_player_profile = profile_json
		current_player_profile["is_mock"] = false
		current_player_profile["mode"] = "Live API"
		is_authenticated = true
		auth_succeeded.emit(current_player_profile, false)
	else:
		auth_failed.emit("Invalid profile JSON received.")

func disconnect_player() -> void:
	is_authenticated = false
	is_connecting = false
	access_token = ""
	refresh_token = ""
	current_player_profile.clear()
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

# -------------------------------------------------------------------
# Platform State & Ghost API (/v1/me/state/{key})
# -------------------------------------------------------------------
func get_state(key: String, callback: Callable = Callable()) -> void:
	if is_mock_mode:
		var val = local_state.get(key, null)
		state_loaded.emit(key, val)
		if callback.is_valid():
			callback.call(true, val)
		return
	
	if access_token.is_empty():
		if callback.is_valid():
			callback.call(false, null)
		return
	
	var url = "%s/v1/me/state/%s" % [api_origin, key.uri_encode()]
	var headers = [
		"Authorization: Bearer %s" % access_token,
		"Accept: application/json"
	]
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(result: int, response_code: int, response_headers: PackedStringArray, body: PackedByteArray):
		http.queue_free()
		if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			for h in response_headers:
				if h.to_lower().begins_with("etag:"):
					current_etag = h.substr(5).strip_edges()
			var json = JSON.parse_string(body.get_string_from_utf8())
			var val = null
			if typeof(json) == TYPE_DICTIONARY and json.has("value"):
				val = json["value"]
			state_loaded.emit(key, val)
			if callback.is_valid():
				callback.call(true, val)
		else:
			if callback.is_valid():
				callback.call(false, null)
	)
	http.request(url, headers, HTTPClient.METHOD_GET)

func put_state(key: String, value: Variant, callback: Callable = Callable()) -> void:
	local_state[key] = value
	_save_local_state()
	
	if is_mock_mode:
		print("[WeBumpAPI Mock] Persisted state key '%s' (%s)" % [key, str(value).substr(0, 60)])
		state_saved.emit(key, value)
		if callback.is_valid():
			callback.call(true, value)
		return
	
	if access_token.is_empty():
		if callback.is_valid():
			callback.call(false, null)
		return
	
	var url = "%s/v1/me/state/%s" % [api_origin, key.uri_encode()]
	var headers = [
		"Authorization: Bearer %s" % access_token,
		"Content-Type: application/json",
		"Accept: application/json",
		"If-Match: %s" % current_etag
	]
	var payload = {
		"value": value
	}
	var json_body = JSON.stringify(payload)
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(result: int, response_code: int, response_headers: PackedStringArray, _body: PackedByteArray):
		http.queue_free()
		if result == HTTPRequest.RESULT_SUCCESS and (response_code == 200 or response_code == 201):
			for h in response_headers:
				if h.to_lower().begins_with("etag:"):
					current_etag = h.substr(5).strip_edges()
			state_saved.emit(key, value)
			if callback.is_valid():
				callback.call(true, value)
		else:
			push_warning("[WeBumpAPI] put_state failed with code %d" % response_code)
			if callback.is_valid():
				callback.call(false, null)
	)
	http.request(url, headers, HTTPClient.METHOD_PUT, json_body)

func save_ghost_telemetry(ghost_data: Dictionary) -> void:
	print("[WeBumpAPI] Saving ghost telemetry with car_body: '%s' (%d samples)..." % [
		ghost_data.get("car_body", "unknown"),
		ghost_data.get("samples", []).size()
	])
	put_state("ghost_telemetry", ghost_data)

# -------------------------------------------------------------------
# Public Capsule & Showcase APIs (/v1/me/capsule & /v1/me/showcase)
# Public data shown on the weBump app upon bumping or on profile shelf
# -------------------------------------------------------------------
func get_capsule(callback: Callable = Callable()) -> void:
	if is_mock_mode:
		capsule_loaded.emit(local_capsule)
		if callback.is_valid():
			callback.call(true, local_capsule)
		return
	
	if access_token.is_empty():
		if callback.is_valid():
			callback.call(false, {})
		return
	
	var url = "%s/v1/me/capsule" % api_origin
	var headers = [
		"Authorization: Bearer %s" % access_token,
		"Accept: application/json"
	]
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(result: int, response_code: int, response_headers: PackedStringArray, body: PackedByteArray):
		http.queue_free()
		if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			for h in response_headers:
				if h.to_lower().begins_with("etag:"):
					current_etag = h.substr(5).strip_edges()
			var json = JSON.parse_string(body.get_string_from_utf8())
			var val: Dictionary = {}
			if typeof(json) == TYPE_DICTIONARY and json.has("data") and typeof(json["data"]) == TYPE_DICTIONARY:
				val = json["data"]
			local_capsule = val
			local_state["capsule"] = val
			_save_local_state()
			capsule_loaded.emit(val)
			if callback.is_valid():
				callback.call(true, val)
		else:
			if callback.is_valid():
				callback.call(false, {})
	)
	http.request(url, headers, HTTPClient.METHOD_GET)

func put_capsule(value: Dictionary, callback: Callable = Callable()) -> void:
	local_capsule = value
	local_state["capsule"] = value
	_save_local_state()
	
	if is_mock_mode:
		print("[WeBumpAPI Mock] Persisted public capsule: %s" % str(value))
		capsule_saved.emit(value)
		if callback.is_valid():
			callback.call(true, value)
		return
	
	if access_token.is_empty():
		if callback.is_valid():
			callback.call(false, {})
		return
	
	var url = "%s/v1/me/capsule" % api_origin
	var headers = [
		"Authorization: Bearer %s" % access_token,
		"Content-Type: application/json",
		"Accept: application/json",
		"If-Match: %s" % current_etag
	]
	var payload = {
		"value": value
	}
	var json_body = JSON.stringify(payload)
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(result: int, response_code: int, response_headers: PackedStringArray, _body: PackedByteArray):
		http.queue_free()
		if result == HTTPRequest.RESULT_SUCCESS and (response_code == 200 or response_code == 201):
			for h in response_headers:
				if h.to_lower().begins_with("etag:"):
					current_etag = h.substr(5).strip_edges()
			capsule_saved.emit(value)
			if callback.is_valid():
				callback.call(true, value)
		else:
			push_warning("[WeBumpAPI] put_capsule failed with code %d" % response_code)
			if callback.is_valid():
				callback.call(false, {})
	)
	http.request(url, headers, HTTPClient.METHOD_PUT, json_body)

func get_showcase(callback: Callable = Callable()) -> void:
	if is_mock_mode:
		showcase_loaded.emit(local_showcase)
		if callback.is_valid():
			callback.call(true, local_showcase)
		return
	
	if access_token.is_empty():
		if callback.is_valid():
			callback.call(false, {})
		return
	
	var url = "%s/v1/me/showcase" % api_origin
	var headers = [
		"Authorization: Bearer %s" % access_token,
		"Accept: application/json"
	]
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(result: int, response_code: int, response_headers: PackedStringArray, body: PackedByteArray):
		http.queue_free()
		if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			for h in response_headers:
				if h.to_lower().begins_with("etag:"):
					current_etag = h.substr(5).strip_edges()
			var json = JSON.parse_string(body.get_string_from_utf8())
			var val: Dictionary = {}
			if typeof(json) == TYPE_DICTIONARY and json.has("data") and typeof(json["data"]) == TYPE_DICTIONARY:
				val = json["data"]
			local_showcase = val
			local_state["showcase"] = val
			_save_local_state()
			showcase_loaded.emit(val)
			if callback.is_valid():
				callback.call(true, val)
		else:
			if callback.is_valid():
				callback.call(false, {})
	)
	http.request(url, headers, HTTPClient.METHOD_GET)

func put_showcase(value: Dictionary, callback: Callable = Callable()) -> void:
	local_showcase = value
	local_state["showcase"] = value
	_save_local_state()
	
	if is_mock_mode:
		print("[WeBumpAPI Mock] Persisted public showcase: %s" % str(value))
		showcase_saved.emit(value)
		if callback.is_valid():
			callback.call(true, value)
		return
	
	if access_token.is_empty():
		if callback.is_valid():
			callback.call(false, {})
		return
	
	var url = "%s/v1/me/showcase" % api_origin
	var headers = [
		"Authorization: Bearer %s" % access_token,
		"Content-Type: application/json",
		"Accept: application/json",
		"If-Match: %s" % current_etag
	]
	var payload = {
		"value": value
	}
	var json_body = JSON.stringify(payload)
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(result: int, response_code: int, response_headers: PackedStringArray, _body: PackedByteArray):
		http.queue_free()
		if result == HTTPRequest.RESULT_SUCCESS and (response_code == 200 or response_code == 201):
			for h in response_headers:
				if h.to_lower().begins_with("etag:"):
					current_etag = h.substr(5).strip_edges()
			showcase_saved.emit(value)
			if callback.is_valid():
				callback.call(true, value)
		else:
			push_warning("[WeBumpAPI] put_showcase failed with code %d" % response_code)
			if callback.is_valid():
				callback.call(false, {})
	)
	http.request(url, headers, HTTPClient.METHOD_PUT, json_body)

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


