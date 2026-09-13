extends Control

@export_file("*.tscn") var main_scene_path: String = "res://scenes/main.tscn"

@onready var play_button: Button = %PlayButton
@onready var loading_container: VBoxContainer = %LoadingContainer
@onready var progress_bar: ProgressBar = %ProgressBar
@onready var status_label: Label = %StatusLabel

var _is_loading: bool = false
var _progress: Array = []

func _ready() -> void:
	loading_container.visible = false
	play_button.visible = true
	play_button.disabled = false
	play_button.pressed.connect(_on_play_pressed)

func _on_play_pressed() -> void:
	if _is_loading:
		return

	_is_loading = true
	play_button.visible = false
	loading_container.visible = true
	progress_bar.value = 0.0
	status_label.text = "Loading game..."

	var err: Error = ResourceLoader.load_threaded_request(main_scene_path, "", true)
	if err != OK:
		_is_loading = false
		play_button.visible = true
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
				play_button.visible = true
				loading_container.visible = false
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_is_loading = false
			status_label.text = "Failed to load scene."
			play_button.visible = true
			loading_container.visible = false
			push_error("Multithreaded scene load failed with status: %d" % status)
