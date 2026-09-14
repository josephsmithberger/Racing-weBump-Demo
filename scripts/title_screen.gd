extends Control

@export_file("*.tscn") var main_scene_path: String = "res://scenes/main.tscn"

@onready var mode_banner: PanelContainer = %ModeBanner
@onready var mode_label: Label = %ModeLabel
@onready var connect_button: WeBumpConnectButton = %WeBumpConnectButton
@onready var play_button: Button = %PlayButton
@onready var hint_label: Label = %HintLabel
@onready var button_container: VBoxContainer = %ButtonContainer
@onready var loading_container: VBoxContainer = %LoadingContainer
@onready var progress_bar: ProgressBar = %ProgressBar
@onready var status_label: Label = %StatusLabel

var _is_loading: bool = false
var _progress: Array = []

func _ready() -> void:
	loading_container.visible = false
	button_container.visible = true
	hint_label.visible = true
	
	# Start button is disabled until the user has connected to weBump
	play_button.disabled = true
	play_button.text = "Start Race (Locked)"
	
	_setup_mode_display()
	
	play_button.pressed.connect(_on_play_pressed)
	
	if connect_button:
		connect_button.connection_started.connect(_on_connection_started)
		connect_button.connection_changed.connect(_on_connection_changed)

func _setup_mode_display() -> void:
	var is_mock: bool = false
	var is_editor: bool = OS.has_feature("editor")
	
	if has_node("/root/WeBumpAPI"):
		var api = get_node("/root/WeBumpAPI")
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
	loading_container.visible = true
	progress_bar.value = 0.0
	status_label.text = "Loading game..."

	var err: Error = ResourceLoader.load_threaded_request(main_scene_path, "", true)
	if err != OK:
		_is_loading = false
		button_container.visible = true
		hint_label.visible = true
		loading_container.visible = false
		status_label.text = "Failed to start loading: Error %d" % err
		push_error("Failed to start multithreaded load for %s: %s" % [main_scene_path, err])

func _process(_delta: float) -> void:
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
				loading_container.visible = false
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_is_loading = false
			status_label.text = "Failed to load scene."
			button_container.visible = true
			hint_label.visible = true
			loading_container.visible = false
			push_error("Multithreaded scene load failed with status: %d" % status)
