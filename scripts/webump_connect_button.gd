class_name WeBumpConnectButton extends Button

signal connection_started()
signal connection_success(player_data: Dictionary)
signal connection_failed(error_msg: String)
signal connection_changed(is_connected: bool, player_data: Dictionary)

const COLOR_READY_BG: Color = Color(0.0, 0.5608, 1.0, 1.0)          # #008fff
const COLOR_READY_HOVER: Color = Color(0.102, 0.627, 1.0, 1.0)      # Brightness 1.06
const COLOR_READY_PRESSED: Color = Color(0.0, 0.4627, 0.8745, 1.0)  # #0076df
const COLOR_READY_BORDER: Color = Color(0.0, 0.4627, 0.8745, 1.0)   # #0076df
const COLOR_READY_TEXT: Color = Color(0.0196, 0.0824, 0.1529, 1.0)  # #051527
const COLOR_READY_SHADOW: Color = Color(0.0, 0.5608, 1.0, 0.15)     # #008fff26

const COLOR_CONN_BG: Color = Color(0.9294, 0.9647, 1.0, 1.0)        # #edf6ff
const COLOR_CONN_HOVER: Color = Color(0.878, 0.937, 0.99, 1.0)      # Slightly darker blue-white
const COLOR_CONN_PRESSED: Color = Color(0.82, 0.90, 0.98, 1.0)
const COLOR_CONN_BORDER: Color = Color(0.5647, 0.7373, 0.8902, 1.0) # #90bce3
const COLOR_CONN_TEXT: Color = Color(0.0275, 0.2, 0.3608, 1.0)      # #07335c

var is_connected: bool = false
var is_connecting: bool = false
var player_profile: Dictionary = {}

var _style_normal: StyleBoxFlat
var _style_hover: StyleBoxFlat
var _style_pressed: StyleBoxFlat
var _style_disabled: StyleBoxFlat
var _style_focus: StyleBoxFlat

@onready var content_box: HBoxContainer = $HBoxContainer
@onready var icon_rect: TextureRect = $HBoxContainer/IconRect
@onready var label: Label = $HBoxContainer/Label

func _ready() -> void:
	custom_minimum_size = Vector2(340, 64)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_ALL
	
	_setup_styles()
	_update_visuals()
	
	pressed.connect(_on_pressed)
	
	# Wire to WeBumpAPI Autoload
	_connect_to_api_singleton()

func _connect_to_api_singleton() -> void:
	var api = _get_api()
	if api:
		api.auth_started.connect(_on_api_auth_started)
		api.auth_succeeded.connect(_on_api_auth_succeeded)
		api.auth_failed.connect(_on_api_auth_failed)
		api.session_disconnected.connect(_on_api_disconnected)
		
		# If API already has an active session
		if api.is_authenticated:
			_on_api_auth_succeeded(api.current_player_profile, api.is_mock_mode)

func _get_api() -> Node:
	if has_node("/root/WeBumpAPI"):
		return get_node("/root/WeBumpAPI")
	return null

func _setup_styles() -> void:
	_style_normal = StyleBoxFlat.new()
	_style_hover = StyleBoxFlat.new()
	_style_pressed = StyleBoxFlat.new()
	_style_disabled = StyleBoxFlat.new()
	_style_focus = StyleBoxFlat.new()
	
	for s in [_style_normal, _style_hover, _style_pressed, _style_disabled]:
		s.set_corner_radius_all(20)
		s.set_border_width_all(1)
		s.content_margin_top = 10
		s.content_margin_bottom = 10
		s.content_margin_left = 10
		s.content_margin_right = 22
	
	_style_focus.set_corner_radius_all(23)
	_style_focus.set_border_width_all(3)
	_style_focus.border_color = Color.WHITE
	_style_focus.draw_center = false
	_style_focus.expand_margin_left = 3
	_style_focus.expand_margin_top = 3
	_style_focus.expand_margin_right = 3
	_style_focus.expand_margin_bottom = 3
	
	add_theme_stylebox_override("normal", _style_normal)
	add_theme_stylebox_override("hover", _style_hover)
	add_theme_stylebox_override("pressed", _style_pressed)
	add_theme_stylebox_override("disabled", _style_disabled)
	add_theme_stylebox_override("focus", _style_focus)

func _update_visuals() -> void:
	if is_connected:
		_style_normal.bg_color = COLOR_CONN_BG
		_style_normal.border_color = COLOR_CONN_BORDER
		_style_normal.shadow_size = 0
		
		_style_hover.bg_color = COLOR_CONN_HOVER
		_style_hover.border_color = COLOR_CONN_BORDER
		_style_hover.shadow_size = 0
		
		_style_pressed.bg_color = COLOR_CONN_PRESSED
		_style_pressed.border_color = COLOR_CONN_BORDER
		_style_pressed.shadow_size = 0
		
		_style_disabled.bg_color = COLOR_CONN_BG
		_style_disabled.border_color = COLOR_CONN_BORDER
		_style_disabled.shadow_size = 0
		
		if label:
			if player_profile.get("is_mock", false):
				label.text = "Connected to weBump (Mock)"
			else:
				label.text = "Connected to weBump"
			label.add_theme_color_override("font_color", COLOR_CONN_TEXT)
		
		modulate.a = 1.0
	elif is_connecting:
		_style_disabled.bg_color = COLOR_READY_BG
		_style_disabled.border_color = COLOR_READY_BORDER
		_style_disabled.shadow_size = 14
		_style_disabled.shadow_color = COLOR_READY_SHADOW
		_style_disabled.shadow_offset = Vector2(0, 5)
		
		if label:
			label.text = "Connecting to weBump…"
			label.add_theme_color_override("font_color", COLOR_READY_TEXT)
		
		modulate.a = 0.75
	else:
		_style_normal.bg_color = COLOR_READY_BG
		_style_normal.border_color = COLOR_READY_BORDER
		_style_normal.shadow_size = 18
		_style_normal.shadow_color = COLOR_READY_SHADOW
		_style_normal.shadow_offset = Vector2(0, 5)
		
		_style_hover.bg_color = COLOR_READY_HOVER
		_style_hover.border_color = COLOR_READY_BORDER
		_style_hover.shadow_size = 20
		_style_hover.shadow_color = COLOR_READY_SHADOW
		_style_hover.shadow_offset = Vector2(0, 6)
		
		_style_pressed.bg_color = COLOR_READY_PRESSED
		_style_pressed.border_color = COLOR_READY_BORDER
		_style_pressed.shadow_size = 10
		_style_pressed.shadow_offset = Vector2(0, 2)
		
		_style_disabled.bg_color = COLOR_READY_BG
		_style_disabled.border_color = COLOR_READY_BORDER
		_style_disabled.shadow_size = 0
		
		if label:
			label.text = "Connect to weBump"
			label.add_theme_color_override("font_color", COLOR_READY_TEXT)
		
		modulate.a = 1.0

func _on_pressed() -> void:
	if is_connecting:
		return
	
	if is_connected:
		_animate_connected_click()
		return
	
	start_connection()

func start_connection() -> void:
	if is_connecting or is_connected:
		return
	
	var api = _get_api()
	if api:
		api.connect_player()
	else:
		_fallback_mock_connection()

func _fallback_mock_connection() -> void:
	is_connecting = true
	disabled = true
	connection_started.emit()
	_update_visuals()
	
	var timer = get_tree().create_timer(0.8)
	timer.timeout.connect(func():
		_on_api_auth_succeeded({
			"display_name": "Racer Maya",
			"theme_color": "#FF3366",
			"is_mock": true
		}, true)
	)

func _on_api_auth_started(_is_mock: bool) -> void:
	is_connecting = true
	disabled = true
	connection_started.emit()
	_update_visuals()

func _on_api_auth_succeeded(profile: Dictionary, _is_mock: bool) -> void:
	is_connecting = false
	is_connected = true
	disabled = false
	player_profile = profile
	_update_visuals()
	
	# Gentle pop feedback on completion
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2(1.04, 1.04), 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.12).set_trans(Tween.TRANS_SINE)
	
	connection_success.emit(player_profile)
	connection_changed.emit(true, player_profile)

func _on_api_auth_failed(error_msg: String) -> void:
	is_connecting = false
	is_connected = false
	disabled = false
	_update_visuals()
	connection_failed.emit(error_msg)
	connection_changed.emit(false, {})

func _on_api_disconnected() -> void:
	is_connecting = false
	is_connected = false
	disabled = false
	player_profile.clear()
	_update_visuals()
	connection_changed.emit(false, {})

func _animate_connected_click() -> void:
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2(0.98, 0.98), 0.08)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.08)
