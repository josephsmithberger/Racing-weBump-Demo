extends Node

signal auth_started(is_mock: bool)
signal auth_succeeded(player_profile: Dictionary, is_mock: bool)
signal auth_failed(error_message: String)
signal session_disconnected()

const CONFIG_PATH: String = "res://config.json"

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

var _current_verifier: String = ""
var _current_state: String = ""
var _http_request: HTTPRequest

func _ready() -> void:
	_load_config()
	
	# Determine mode: editor always enables mock mode unless explicitly forced
	is_editor_mode = OS.has_feature("editor")
	is_mock_mode = is_editor_mode or _config_mock_mode
	
	# Internal HTTP request node for live API requests
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
	var timer = get_tree().create_timer(0.8)
	timer.timeout.connect(func():
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
	)

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
