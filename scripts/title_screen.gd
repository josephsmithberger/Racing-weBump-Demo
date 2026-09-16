extends Control

@export_file("*.tscn") var main_scene_path: String = "res://scenes/main.tscn"

# UI Header & Mode Caption
@onready var mode_banner: VBoxContainer = %ModeBanner
@onready var mode_label: Label = %ModeLabel

# Car Chooser UI Nodes
@onready var car_chooser: VBoxContainer = %CarChooser
@onready var prev_car_button: Button = %PrevCarButton
@onready var next_car_button: Button = %NextCarButton
@onready var preview_card: PanelContainer = %PreviewCard
@onready var turntable: Node3D = %Turntable
@onready var model_pivot: Node3D = %ModelPivot
@onready var car_name_label: Label = %CarNameLabel
@onready var color_swatch: ColorRect = %ColorSwatch
@onready var color_status_label: Label = %ColorStatusLabel
@onready var pagination_container: HBoxContainer = %PaginationContainer
@onready var car_tabs_container: HBoxContainer = %CarTabsContainer
@onready var _preview_nameplate: Label3D = %PreviewNameplate
@onready var _audio: RaceAudio = $RaceAudio

# Action buttons & loading
@onready var connect_button: WeBumpConnectButton = %WeBumpConnectButton
@onready var play_button: Button = %PlayButton
@onready var hint_label: Label = %HintLabel
@onready var button_container: VBoxContainer = %ButtonContainer
@onready var loading_container: VBoxContainer = %LoadingContainer
@onready var progress_bar: ProgressBar = %ProgressBar
@onready var status_label: Label = %StatusLabel

var _is_loading: bool = false
var _progress: Array = []

# Car Chooser State
var _current_car_index: int = 0
var _preview_model_inst: Node3D = null
var _preview_paint_mat: ShaderMaterial = null
var _is_dragging: bool = false
var _turntable_auto_spin: bool = true
var _car_tab_buttons: Array[Button] = []

func _ready() -> void:
	loading_container.visible = false
	button_container.visible = true
	hint_label.visible = true
	
	play_button.text = "START RACE"
	
	_setup_mode_display()
	_setup_car_chooser()
	
	play_button.pressed.connect(_on_play_pressed)
	play_button.mouse_entered.connect(func(): if _audio and not play_button.disabled: _audio.play_hover())
	
	if connect_button:
		connect_button.connection_started.connect(_on_connection_started)
		connect_button.connection_changed.connect(_on_connection_changed)
	var api = _get_api()
	if api:
		api.visitors_updated.connect(_on_visitors_updated)
		if api.is_authenticated and not api.is_mock_mode:
			_on_visitors_updated(api.visitor_cards)
			api.load_visitors()

func _get_api() -> Node:
	return CarPresets.get_api()

func _setup_mode_display() -> void:
	var is_mock: bool = false
	var is_editor: bool = OS.has_feature("editor")
	var api = _get_api()
	
	if api:
		is_mock = api.is_mock_mode
		is_editor = api.is_editor_mode
	else:
		is_mock = is_editor
	
	# Outside the editor a race needs a connected player: rivals come from real bumps.
	var connected: bool = api != null and api.is_authenticated
	play_button.disabled = not (is_mock or connected)
	if is_mock:
		mode_banner.visible = true
		if is_editor:
			mode_label.text = "Mock Mode (Editor) - simulated API"
		else:
			mode_label.text = "Mock Mode - simulated API"
		mode_label.add_theme_color_override("font_color", Color(1.0, 0.839, 0.0, 0.9))
		hint_label.text = "Connect to weBump to sync your profile & custom colors"
	else:
		mode_banner.visible = false
		hint_label.text = "Connect with weBump to race the people you bump"
	hint_label.add_theme_color_override("font_color", Color(0.55, 0.62, 0.75, 1.0))

# ===================================================================
# SAKURAI ARCADE CAR CHOOSER
# ===================================================================
func _setup_car_chooser() -> void:
	var initial_id: String = CarPresets.get_selected_car()
	_current_car_index = CarPresets.get_preset_index(initial_id)
	
	prev_car_button.pressed.connect(_on_prev_car_pressed)
	next_car_button.pressed.connect(_on_next_car_pressed)
	prev_car_button.mouse_entered.connect(func(): if _audio: _audio.play_hover())
	next_car_button.mouse_entered.connect(func(): if _audio: _audio.play_hover())
	
	# Direct swipe/drag gestures on preview showroom card
	preview_card.gui_input.connect(_on_preview_gui_input)
	
	_build_car_tabs()
	_build_pagination_dots()
	_update_car_display(false)

func _build_car_tabs() -> void:
	for child in car_tabs_container.get_children():
		child.queue_free()
	_car_tab_buttons.clear()
	
	var short_names = ["Cab", "Sport", "Hauler", "Bug", "Cycle"]
	for i in range(CarPresets.PRESETS.size()):
		var btn = Button.new()
		var tab_name = short_names[i] if i < short_names.size() else "V%d" % (i + 1)
		btn.text = tab_name
		btn.custom_minimum_size = Vector2(0, 34)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.add_theme_font_size_override("font_size", 12)
		
		var idx = i
		btn.pressed.connect(func():
			if _audio: _audio.play_click()
			_select_car_index(idx)
		)
		btn.mouse_entered.connect(func(): if _audio: _audio.play_hover())
		car_tabs_container.add_child(btn)
		_car_tab_buttons.append(btn)

func _build_pagination_dots() -> void:
	for child in pagination_container.get_children():
		child.queue_free()
	
	for i in range(CarPresets.PRESETS.size()):
		var dot_btn = Button.new()
		dot_btn.custom_minimum_size = Vector2(24, 24)
		dot_btn.focus_mode = Control.FOCUS_NONE
		dot_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		dot_btn.flat = true
		
		var dot_panel = Panel.new()
		dot_panel.name = "DotPill"
		dot_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot_panel.anchor_left = 0.15
		dot_panel.anchor_right = 0.85
		dot_panel.anchor_top = 0.35
		dot_panel.anchor_bottom = 0.65
		
		var sb = StyleBoxFlat.new()
		sb.corner_radius_top_left = 3
		sb.corner_radius_top_right = 3
		sb.corner_radius_bottom_right = 3
		sb.corner_radius_bottom_left = 3
		sb.shadow_size = 0
		sb.bg_color = Color(0.20, 0.25, 0.36, 0.7)
		dot_panel.add_theme_stylebox_override("panel", sb)
		dot_btn.add_child(dot_panel)
		
		var dot_idx = i
		dot_btn.pressed.connect(func(): 
			if _audio: _audio.play_click()
			_select_car_index(dot_idx)
		)
		dot_btn.mouse_entered.connect(func(): if _audio: _audio.play_hover())
		pagination_container.add_child(dot_btn)

func _on_prev_car_pressed() -> void:
	if _audio:
		_audio.play_click()
	_select_car_index(posmod(_current_car_index - 1, CarPresets.PRESETS.size()))

func _on_next_car_pressed() -> void:
	if _audio:
		_audio.play_click()
	_select_car_index(posmod(_current_car_index + 1, CarPresets.PRESETS.size()))

func _select_car_index(idx: int) -> void:
	if idx == _current_car_index:
		return
	_current_car_index = idx
	if _audio:
		_audio.play_car_select()
	_update_car_display(true)

func _on_preview_gui_input(event: InputEvent) -> void:
	# Touchscreen drag rotation
	if event is InputEventScreenTouch:
		if event.pressed:
			_is_dragging = true
			_turntable_auto_spin = false
		else:
			_is_dragging = false
			_turntable_auto_spin = true
	
	elif event is InputEventScreenDrag:
		if turntable != null:
			turntable.rotate_y(event.relative.x * 0.012)
	
	# Mouse drag rotation
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_is_dragging = true
				_turntable_auto_spin = false
			else:
				_is_dragging = false
				_turntable_auto_spin = true
	
	elif event is InputEventMouseMotion:
		if _is_dragging and turntable != null:
			turntable.rotate_y(event.relative.x * 0.012)

func _update_car_display(animate: bool) -> void:
	var preset = CarPresets.PRESETS[_current_car_index]
	var car_id: String = preset["id"]
	
	# 1. Update vehicle name
	car_name_label.text = preset["name"]
	
	# 2. Persist selection
	CarPresets.set_selected_car(car_id)
	
	# 3. Swap 3D model with punch-scale juice
	_load_preview_model(preset, animate)
	
	# 4. Update color indicator & swatch
	_update_color_swatch()
	
	# 5. Update pagination dots & tabs
	_update_pagination_dots()
	_update_car_tabs()

func _load_preview_model(preset: Dictionary, animate: bool) -> void:
	if _preview_model_inst != null:
		_preview_model_inst.queue_free()
		_preview_model_inst = null
	
	var model_path: String = preset["model_path"]
	var scn = load(model_path)
	if not scn:
		push_error("Could not load preview model: %s" % model_path)
		return
	
	_preview_model_inst = scn.instantiate()
	model_pivot.add_child(_preview_model_inst)
	
	var paint_meshes = _preview_model_inst.find_children("*", "MeshInstance3D", true, false)
	if not paint_meshes.is_empty():
		var col = _get_current_paint_color(preset)
		var shader = preload("res://shaders/car_paint.gdshader")
		_preview_paint_mat = ShaderMaterial.new()
		_preview_paint_mat.shader = shader
		_preview_paint_mat.set_shader_parameter("albedo_texture", preload("res://models/Textures/colormap.png"))
		_preview_paint_mat.set_shader_parameter("paint_color", col)
		_preview_paint_mat.set_shader_parameter("paint_mask", preset.get("paint_mask", 0))
		_preview_paint_mat.set_shader_parameter("use_paint_override", true)
		for mesh in paint_meshes:
			(mesh as MeshInstance3D).material_override = _preview_paint_mat
	
	_update_preview_nameplate()
	
	# Sakurai punch-scale pop on vehicle swap
	if animate and model_pivot != null:
		model_pivot.scale = Vector3(0.8, 0.8, 0.8)
		var tw = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(model_pivot, "scale", Vector3.ONE, 0.2)

func _update_preview_nameplate() -> void:
	var name_text = "Player"
	var api = _get_api()
	if api:
		name_text = api.get_player_display_name()
	
	_preview_nameplate.text = name_text

func _get_current_paint_color(preset: Dictionary) -> Color:
	var api = _get_api()
	if api and api.is_authenticated:
		return api.get_player_theme_color()
	return preset.get("default_color", Color(1.0, 0.70, 0.0))

func _update_color_swatch() -> void:
	var preset = CarPresets.PRESETS[_current_car_index]
	var col = _get_current_paint_color(preset)
	color_swatch.color = col
	
	var is_auth = false
	var hex_str = "#" + col.to_html(false)
	var api = _get_api()
	if api:
		is_auth = api.is_authenticated
		if is_auth:
			hex_str = api.get_player_theme_color_hex()
	
	if is_auth:
		color_status_label.text = "weBump color: %s" % hex_str
		color_status_label.add_theme_color_override("font_color", Color(0.165, 0.690, 0.388, 1.0)) # weBump Brand Green
	else:
		color_status_label.text = "Default Paint • Connect to sync"
		color_status_label.add_theme_color_override("font_color", Color(0.68, 0.74, 0.84, 1.0))

func _update_pagination_dots() -> void:
	var dots = pagination_container.get_children()
	for i in range(dots.size()):
		var dot = dots[i]
		var panel = dot.get_node_or_null("DotPill") as Panel
		if panel != null:
			var sb = panel.get_theme_stylebox("panel") as StyleBoxFlat
			if sb != null:
				var is_active = (i == _current_car_index)
				sb.bg_color = Color(1.0, 0.553, 0.157, 1.0) if is_active else Color(0.20, 0.25, 0.36, 0.6)
				dot.custom_minimum_size = Vector2(28, 24) if is_active else Vector2(16, 24)

func _update_car_tabs() -> void:
	for i in range(_car_tab_buttons.size()):
		var btn = _car_tab_buttons[i]
		var is_active = (i == _current_car_index)
		
		var sb = StyleBoxFlat.new()
		sb.set_corner_radius_all(6)
		sb.shadow_size = 0
		if is_active:
			sb.bg_color = Color(0.18, 0.24, 0.36, 1.0)
			sb.set_border_width_all(2)
			sb.border_color = Color(1.0, 0.553, 0.157, 1.0) # weBump Orange
			btn.add_theme_color_override("font_color", Color.WHITE)
		else:
			sb.bg_color = Color(0.08, 0.10, 0.16, 0.85)
			sb.set_border_width_all(1)
			sb.border_color = Color(0.18, 0.23, 0.34, 0.6)
			btn.add_theme_color_override("font_color", Color(0.65, 0.72, 0.82, 1.0))
		
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("hover", sb)
		btn.add_theme_stylebox_override("pressed", sb)

# ===================================================================
# CONNECTION HANDSHAKE & EVENT HANDLING
# ===================================================================
func _on_connection_started() -> void:
	var is_mock: bool = false
	if has_node("/root/WeBumpAPI"):
		is_mock = get_node("/root/WeBumpAPI").is_mock_mode
	
	if is_mock:
		hint_label.text = "Simulating weBump handshake in Editor (Mock Mode)…"
		hint_label.add_theme_color_override("font_color", Color(1.0, 0.839, 0.0, 1.0))
	else:
		hint_label.text = "Connecting to weBump API (OAuth PKCE)…"
		hint_label.add_theme_color_override("font_color", Color(0.235, 0.561, 0.949, 1.0))

func _on_connection_changed(connected: bool, profile: Dictionary) -> void:
	var preset = CarPresets.PRESETS[_current_car_index]
	var active_color = _get_current_paint_color(preset)
	if _preview_paint_mat != null:
		_preview_paint_mat.set_shader_parameter("paint_color", active_color)
	_update_color_swatch()
	_update_preview_nameplate()
	
	if connected:
		if _audio:
			_audio.play_connect_success()
		play_button.disabled = false
		play_button.text = "START RACE"
		var p_name = profile.get("display_name", "Player")
		var is_mock = profile.get("is_mock", false)
		
		if is_mock:
			hint_label.text = "[MOCK MODE] Connected as %s - Ready to race!" % p_name
		else:
			hint_label.text = "Connected as %s - loading your bumps..." % p_name
		hint_label.add_theme_color_override("font_color", Color(0.165, 0.690, 0.388, 1.0))
		
		# Animate start button bounce
		play_button.pivot_offset = play_button.size * 0.5
		var tween = create_tween()
		tween.tween_property(play_button, "scale", Vector2(1.04, 1.04), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(play_button, "scale", Vector2(1.0, 1.0), 0.12).set_trans(Tween.TRANS_SINE)
	else:
		play_button.text = "START RACE"
		_setup_mode_display()

# ===================================================================
# VISITORS: everyone the player bumped since connecting, refreshed automatically
# ===================================================================
const VISITOR_REFRESH_SECONDS := 45.0
var _visitor_refresh := 0.0

func _on_visitors_updated(cards: Array) -> void:
	var api = _get_api()
	if api == null or not api.is_authenticated or api.is_mock_mode:
		return
	if cards.is_empty():
		hint_label.text = "No bumps yet - people you bump from now on show up here after weBump's reveal delay"
		hint_label.add_theme_color_override("font_color", Color(0.55, 0.62, 0.75, 1.0))
		return
	var ghosts := 0
	for card in cards:
		if card is Dictionary and GhostData.is_valid(card.get("ghost_telemetry", {})):
			ghosts += 1
	hint_label.text = "%d rival%s from your bumps ready - %d shared replay%s" % [cards.size(), "" if cards.size() == 1 else "s", ghosts, "" if ghosts == 1 else "s"]
	hint_label.add_theme_color_override("font_color", Color(0.165, 0.690, 0.388, 1.0))

func _refresh_visitors(delta: float) -> void:
	var api = _get_api()
	if api == null or not api.is_authenticated or api.is_mock_mode or _is_loading:
		return
	_visitor_refresh += delta
	if _visitor_refresh >= VISITOR_REFRESH_SECONDS:
		_visitor_refresh = 0.0
		api.load_visitors()

func _on_play_pressed() -> void:
	if _is_loading or play_button.disabled:
		return

	if _audio:
		_audio.play_go()

	var preset = CarPresets.PRESETS[_current_car_index]
	var car_id: String = preset["id"]
	CarPresets.set_selected_car(car_id)

	_is_loading = true
	button_container.visible = false
	hint_label.visible = false
	car_chooser.visible = false
	loading_container.visible = true
	progress_bar.value = 0.0
	status_label.text = "Loading game..."

	var err: Error = ResourceLoader.load_threaded_request(main_scene_path, "", true)
	if err != OK:
		_is_loading = false
		button_container.visible = true
		hint_label.visible = true
		car_chooser.visible = true
		loading_container.visible = false
		status_label.text = "Failed to start loading: Error %d" % err
		push_error("Failed to start multithreaded load for %s: %s" % [main_scene_path, err])

func _process(delta: float) -> void:
	if turntable != null and _turntable_auto_spin:
		turntable.rotate_y(delta * 0.6)
	_refresh_visitors(delta)
	
	if not _is_loading:
		return

	_progress.clear()
	var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(main_scene_path, _progress)

	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if _progress.size() > 0:
				var progress_val: float = _progress[0] * 100.0
				progress_bar.value = progress_val
				status_label.text = "Loading game... %d%%" % int(progress_val)
		ResourceLoader.THREAD_LOAD_LOADED:
			_is_loading = false
			progress_bar.value = 100.0
			status_label.text = "Starting game..."
			var packed_scene: PackedScene = ResourceLoader.load_threaded_get(main_scene_path)
			if packed_scene:
				get_tree().change_scene_to_packed(packed_scene)
			else:
				status_label.text = "Error: Loaded resource is null"
				button_container.visible = true
				hint_label.visible = true
				car_chooser.visible = true
				loading_container.visible = false
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_is_loading = false
			status_label.text = "Failed to load scene."
			button_container.visible = true
			hint_label.visible = true
			car_chooser.visible = true
			loading_container.visible = false
			push_error("Multithreaded scene load failed with status: %d" % status)
