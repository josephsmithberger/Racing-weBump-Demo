extends Control

@export_file("*.tscn") var main_scene_path: String = "res://scenes/main.tscn"

# UI Header & Mode
@onready var mode_banner: PanelContainer = %ModeBanner
@onready var mode_label: Label = %ModeLabel

# Car Chooser UI Nodes
@onready var car_chooser: VBoxContainer = %CarChooser
@onready var prev_car_button: Button = %PrevCarButton
@onready var next_car_button: Button = %NextCarButton
@onready var preview_card: PanelContainer = %PreviewCard
@onready var turntable: Node3D = %Turntable
@onready var model_pivot: Node3D = %ModelPivot
@onready var car_name_label: Label = %CarNameLabel
@onready var car_category_badge: Label = %CarCategoryBadge
@onready var car_desc_label: Label = %CarDescLabel
@onready var color_swatch: ColorRect = %ColorSwatch
@onready var color_status_label: Label = %ColorStatusLabel
@onready var pagination_container: HBoxContainer = %PaginationContainer

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
var _preview_nameplate: Label3D = null
var _drag_start_x: float = 0.0
var _is_dragging: bool = false
var _turntable_auto_spin: bool = true

func _ready() -> void:
	loading_container.visible = false
	button_container.visible = true
	hint_label.visible = true
	
	# Start button is disabled until connected to weBump
	play_button.disabled = true
	play_button.text = "Start Race (Locked)"
	
	_setup_mode_display()
	_setup_car_chooser()
	
	play_button.pressed.connect(_on_play_pressed)
	
	if connect_button:
		connect_button.connection_started.connect(_on_connection_started)
		connect_button.connection_changed.connect(_on_connection_changed)

func _get_api() -> Node:
	if is_inside_tree() and get_tree().root.has_node("WeBumpAPI"):
		return get_tree().root.get_node("WeBumpAPI")
	return null

func _setup_mode_display() -> void:
	var is_mock: bool = false
	var is_editor: bool = OS.has_feature("editor")
	var api = _get_api()
	
	if api:
		is_mock = api.is_mock_mode
		is_editor = api.is_editor_mode
	else:
		is_mock = is_editor
	
	if is_mock:
		mode_banner.visible = true
		if is_editor:
			mode_label.text = "🛠️ MOCK MODE (EDITOR) — SIMULATED API"
			hint_label.text = "Editor Mock Mode: Connect simulates a local weBump player"
		else:
			mode_label.text = "🛠️ MOCK MODE — SIMULATED API"
			hint_label.text = "Mock Mode active: simulated weBump player session"
		mode_label.add_theme_color_override("font_color", Color(1.0, 0.72, 0.0, 1.0))
		hint_label.add_theme_color_override("font_color", Color(0.75, 0.7, 0.6, 1.0))
	else:
		mode_banner.visible = true
		mode_label.text = "🌐 LIVE API — api.webump.app"
		mode_label.add_theme_color_override("font_color", Color(0.0, 0.89, 1.0, 1.0))
		hint_label.text = "Connect with weBump on iPhone to race against real bumps"
		hint_label.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7, 1.0))

# ===================================================================
# TOUCH-FRIENDLY CAR CHOOSER
# ===================================================================
func _setup_car_chooser() -> void:
	# 1. Determine starting car index from saved state or default
	var initial_id: String = "truck_yellow"
	var api = _get_api()
	if api:
		initial_id = api.get_selected_car_body()
	_current_car_index = CarPresets.get_preset_index(initial_id)
	
	# 2. Connect large touch navigation buttons
	prev_car_button.pressed.connect(_on_prev_car_pressed)
	next_car_button.pressed.connect(_on_next_car_pressed)
	
	# 3. Touch drag / swipe gesture receiver on preview card
	preview_card.gui_input.connect(_on_preview_gui_input)
	
	# 4. Build pagination dots
	_build_pagination_dots()
	
	# 5. Load and display selected vehicle
	_update_car_display(false)

func _build_pagination_dots() -> void:
	for child in pagination_container.get_children():
		child.queue_free()
	
	for i in range(CarPresets.PRESETS.size()):
		var dot_btn = Button.new()
		dot_btn.custom_minimum_size = Vector2(24, 24)
		dot_btn.focus_mode = Control.FOCUS_NONE
		dot_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		dot_btn.flat = true
		
		# Build flat stylebox for the dot
		var dot_panel = Panel.new()
		dot_panel.name = "DotPill"
		dot_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot_panel.anchor_left = 0.1
		dot_panel.anchor_right = 0.9
		dot_panel.anchor_top = 0.35
		dot_panel.anchor_bottom = 0.65
		
		var sb = StyleBoxFlat.new()
		sb.corner_radius_top_left = 4
		sb.corner_radius_top_right = 4
		sb.corner_radius_bottom_right = 4
		sb.corner_radius_bottom_left = 4
		sb.bg_color = Color(0.25, 0.3, 0.42, 0.7)
		dot_panel.add_theme_stylebox_override("panel", sb)
		dot_btn.add_child(dot_panel)
		
		var dot_idx = i
		dot_btn.pressed.connect(func(): _select_car_index(dot_idx))
		pagination_container.add_child(dot_btn)

func _on_prev_car_pressed() -> void:
	_select_car_index(posmod(_current_car_index - 1, CarPresets.PRESETS.size()))

func _on_next_car_pressed() -> void:
	_select_car_index(posmod(_current_car_index + 1, CarPresets.PRESETS.size()))

func _select_car_index(idx: int) -> void:
	if idx == _current_car_index:
		return
	_current_car_index = idx
	_update_car_display(true)

func _on_preview_gui_input(event: InputEvent) -> void:
	# Mobile Touchscreen Swipe Gestures
	if event is InputEventScreenTouch:
		if event.pressed:
			_is_dragging = true
			_drag_start_x = event.position.x
			_turntable_auto_spin = false
		else:
			if _is_dragging:
				_is_dragging = false
				_turntable_auto_spin = true
				var delta_x = event.position.x - _drag_start_x
				if delta_x < -35.0:
					_on_next_car_pressed()
				elif delta_x > 35.0:
					_on_prev_car_pressed()
	
	elif event is InputEventScreenDrag:
		# Interactive turntable drag feedback under finger
		if turntable != null:
			turntable.rotate_y(event.relative.x * 0.015)
	
	# Desktop Mouse Gestures (for testing)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_is_dragging = true
				_drag_start_x = event.position.x
				_turntable_auto_spin = false
			else:
				if _is_dragging:
					_is_dragging = false
					_turntable_auto_spin = true
					var delta_x = event.position.x - _drag_start_x
					if delta_x < -35.0:
						_on_next_car_pressed()
					elif delta_x > 35.0:
						_on_prev_car_pressed()
	
	elif event is InputEventMouseMotion:
		if _is_dragging and turntable != null:
			turntable.rotate_y(event.relative.x * 0.015)

func _update_car_display(animate: bool) -> void:
	var preset = CarPresets.PRESETS[_current_car_index]
	var car_id: String = preset["id"]
	
	# 1. Update text metadata
	car_name_label.text = preset["name"]
	car_category_badge.text = preset["category"]
	car_desc_label.text = preset["desc"]
	
	# 2. Update WeBumpAPI selection
	var api = _get_api()
	if api:
		api.set_selected_car_body(car_id)
	
	# 3. Swap 3D preview model
	_load_preview_model(preset, animate)
	
	# 4. Update color indicator & swatch
	_update_color_swatch()
	
	# 5. Update pagination dots
	_update_pagination_dots()

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
	
	# Recolor paint mesh
	var body_mesh: MeshInstance3D = _preview_model_inst.find_child("body", true, false)
	if body_mesh:
		var col = _get_current_paint_color(preset)
		var shader = preload("res://shaders/car_paint.gdshader")
		_preview_paint_mat = ShaderMaterial.new()
		_preview_paint_mat.shader = shader
		_preview_paint_mat.set_shader_parameter("albedo_texture", preload("res://models/Textures/colormap.png"))
		_preview_paint_mat.set_shader_parameter("paint_color", col)
		_preview_paint_mat.set_shader_parameter("use_paint_override", true)
		body_mesh.material_override = _preview_paint_mat
	
	# Add overhead billboard nameplate in preview
	_update_preview_nameplate()
	
	if animate and model_pivot != null:
		model_pivot.scale = Vector2(0.75, 0.75).x * Vector3.ONE
		var tw = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(model_pivot, "scale", Vector3.ONE, 0.22)

func _update_preview_nameplate() -> void:
	var name_text = "Player"
	var api = _get_api()
	if api:
		name_text = api.get_player_display_name()
	
	if _preview_nameplate == null and model_pivot != null:
		_preview_nameplate = Label3D.new()
		_preview_nameplate.name = "PreviewNameplate"
		_preview_nameplate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_preview_nameplate.position = Vector3(0, 1.45, 0)
		_preview_nameplate.font_size = 24
		_preview_nameplate.outline_size = 8
		_preview_nameplate.outline_modulate = Color(0.04, 0.05, 0.08, 0.95)
		_preview_nameplate.shaded = false
		_preview_nameplate.double_sided = true
		model_pivot.add_child(_preview_nameplate)
	
	if _preview_nameplate != null:
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
		color_status_label.text = "🎨 weBump Color: %s" % hex_str
		color_status_label.add_theme_color_override("font_color", Color(0.06, 0.85, 0.52, 1.0))
	else:
		color_status_label.text = "Default Paint • Connect to sync"
		color_status_label.add_theme_color_override("font_color", Color(0.65, 0.7, 0.8, 1.0))

func _update_pagination_dots() -> void:
	var dots = pagination_container.get_children()
	for i in range(dots.size()):
		var dot = dots[i]
		var panel = dot.get_node_or_null("DotPill") as Panel
		if panel != null:
			var sb = panel.get_theme_stylebox("panel") as StyleBoxFlat
			if sb != null:
				var is_active = (i == _current_car_index)
				sb.bg_color = Color(0.0, 0.89, 1.0, 1.0) if is_active else Color(0.25, 0.3, 0.42, 0.5)
				dot.custom_minimum_size = Vector2(28, 24) if is_active else Vector2(16, 24)

# ===================================================================
# CONNECTION HANDSHAKE & EVENT HANDLING
# ===================================================================
func _on_connection_started() -> void:
	var is_mock: bool = false
	if has_node("/root/WeBumpAPI"):
		is_mock = get_node("/root/WeBumpAPI").is_mock_mode
	
	if is_mock:
		hint_label.text = "Simulating weBump handshake in Editor (Mock Mode)…"
		hint_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.1, 1.0))
	else:
		hint_label.text = "Connecting to weBump API (OAuth PKCE)…"
		hint_label.add_theme_color_override("font_color", Color(0.0, 0.89, 1.0, 1.0))

func _on_connection_changed(is_connected: bool, profile: Dictionary) -> void:
	# Live update paint color & nameplate on the car chooser preview
	var preset = CarPresets.PRESETS[_current_car_index]
	var active_color = _get_current_paint_color(preset)
	if _preview_paint_mat != null:
		_preview_paint_mat.set_shader_parameter("paint_color", active_color)
	_update_color_swatch()
	_update_preview_nameplate()
	
	if is_connected:
		play_button.disabled = false
		play_button.text = "Start Race"
		var p_name = profile.get("display_name", "Player")
		var is_mock = profile.get("is_mock", false)
		
		if is_mock:
			hint_label.text = "[MOCK MODE] Connected as %s • Ready to Race!" % p_name
			hint_label.add_theme_color_override("font_color", Color(0.2, 0.9, 0.55, 1.0))
		else:
			hint_label.text = "Connected as %s • Ready to Race!" % p_name
			hint_label.add_theme_color_override("font_color", Color(0.06, 0.85, 0.52, 1.0))
		
		# Animate start button unlock
		play_button.pivot_offset = play_button.size * 0.5
		var tween = create_tween()
		tween.tween_property(play_button, "scale", Vector2(1.04, 1.04), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(play_button, "scale", Vector2(1.0, 1.0), 0.12).set_trans(Tween.TRANS_SINE)
	else:
		play_button.disabled = true
		play_button.text = "Start Race (Locked)"
		_setup_mode_display()

func _on_play_pressed() -> void:
	if _is_loading or play_button.disabled:
		return

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
	# Turntable smooth showroom rotation
	if turntable != null and _turntable_auto_spin:
		turntable.rotate_y(delta * 0.7)
	
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
