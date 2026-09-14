class_name GhostRecorder extends Node

signal ghost_saved(ghost_data: Dictionary, is_new_record: bool)

@export var race_manager: RaceManager
@export var sample_rate_hz: float = 15.0

# 16 KiB Quota Guard & AFK Cutoff Constants
const MAX_SAMPLES: int = 400
const MAX_RACE_TIME_SEC: float = 180.0 # 3 minute maximum
const MOVEMENT_EPSILON: float = 0.05 # Minimum distance to record movement

var _is_recording: bool = false
var _sample_timer: float = 0.0
var _elapsed_time: float = 0.0
var _samples: Array = []
var _target_vehicle: Vehicle = null
var _last_recorded_pos: Vector3 = Vector3(9999, 9999, 9999)
var _stationary_frame_counter: int = 0

func _ready() -> void:
	if race_manager == null:
		race_manager = get_parent() as RaceManager
		if race_manager == null:
			race_manager = get_node_or_null("../RaceManager") as RaceManager
	
	if race_manager != null:
		race_manager.race_started.connect(_on_race_started)
		race_manager.race_finished.connect(_on_race_finished)

func _on_race_started() -> void:
	_target_vehicle = null
	if race_manager and race_manager.player_vehicle:
		_target_vehicle = race_manager.player_vehicle
	else:
		_target_vehicle = get_tree().get_first_node_in_group("player") as Vehicle
		if _target_vehicle == null:
			_target_vehicle = get_node_or_null("../Vehicle") as Vehicle
	
	_samples.clear()
	_elapsed_time = 0.0
	_sample_timer = 0.0
	_last_recorded_pos = Vector3(9999, 9999, 9999)
	_stationary_frame_counter = 0
	_is_recording = true
	print("[GhostRecorder] Telemetry recording started (Cap: %d frames, Cutoff: %0.0fs)..." % [MAX_SAMPLES, MAX_RACE_TIME_SEC])

func _physics_process(delta: float) -> void:
	if not _is_recording or _target_vehicle == null:
		return
	
	_elapsed_time += delta
	_sample_timer += delta
	
	# Hard cutoff if race takes over MAX_RACE_TIME_SEC (AFK protection)
	if _elapsed_time > MAX_RACE_TIME_SEC:
		return
	
	var interval = 1.0 / sample_rate_hz
	if _sample_timer >= interval:
		_sample_timer -= interval
		_record_frame()

func _record_frame() -> void:
	var pos = _target_vehicle.get_vehicle_position()
	
	# Stationary Deadband Filter: Avoid adding duplicate frames when stopped/AFK
	var dist_moved = pos.distance_to(_last_recorded_pos)
	var speed = absf(_target_vehicle.linear_speed)
	if dist_moved < MOVEMENT_EPSILON and speed < 0.15:
		_stationary_frame_counter += 1
		# Only record one idle frame every ~1 second (15 ticks) to maintain timeline without bloat
		if _stationary_frame_counter % int(sample_rate_hz) != 0:
			return
	else:
		_stationary_frame_counter = 0
	
	_last_recorded_pos = pos
	var rot_y = _target_vehicle.vehicle_model.global_rotation.y if _target_vehicle.vehicle_model else 0.0
	var lean = _target_vehicle.calculated_lean
	var time_offset_ms = int(_elapsed_time * 1000.0)
	
	# Compact frame: [time_ms, x, y, z, rot_y, lean]
	_samples.append([
		time_offset_ms,
		snappedf(pos.x, 0.01),
		snappedf(pos.y, 0.01),
		snappedf(pos.z, 0.01),
		snappedf(rot_y, 0.01),
		snappedf(lean, 0.01)
	])

func _decimate_samples_if_needed() -> void:
	# Downsample recursively if sample count exceeds MAX_SAMPLES (guaranteeing <= 13 KiB)
	while _samples.size() > MAX_SAMPLES:
		var reduced: Array = []
		var count = _samples.size()
		for i in range(count):
			# Keep even indexed frames and always keep the very last finish frame
			if i % 2 == 0 or i == count - 1:
				reduced.append(_samples[i])
		_samples = reduced
		print("[GhostRecorder] Decimated telemetry samples to %d frames to stay under 16 KiB quota." % _samples.size())

func _on_race_finished(total_time: float, lap_times: Array, best_lap_time: float) -> void:
	if not _is_recording:
		return
	_is_recording = false
	
	# 1. Enforce payload budget decimation
	_decimate_samples_if_needed()
	
	var car_body_id = CarPresets.get_selected_car()
	var display_name = "Player"
	var theme_color_hex = "#FFB300"
	var total_time_ms = int(total_time * 1000.0)
	var best_lap_ms = int(best_lap_time * 1000.0)
	
	var api = _get_api()
	if api:
		car_body_id = api.get_selected_car_body()
		display_name = api.get_player_display_name()
		theme_color_hex = api.get_player_theme_color_hex()
	
	# 2. Check if this run is a new High Score / Personal Best
	var is_new_record: bool = false
	var previous_best_ms: int = -1
	
	if api:
		var saved_save = api.local_state.get("racing_save", {})
		if typeof(saved_save) == TYPE_DICTIONARY:
			previous_best_ms = int(saved_save.get("best_3lap_ms", -1))
	
	if previous_best_ms <= 0 or total_time_ms < previous_best_ms:
		is_new_record = true
	
	var ghost_payload = {
		"car_body": car_body_id,
		"display_name": display_name,
		"theme_color": theme_color_hex,
		"total_time_ms": total_time_ms,
		"best_lap_ms": best_lap_ms,
		"highscore_seconds": int(round(total_time)),
		"best_lap_sec": int(round(best_lap_time)),
		"lap_count": lap_times.size(),
		"samples_count": _samples.size(),
		"is_personal_best": is_new_record,
		"recorded_at": Time.get_datetime_string_from_system(),
		"samples": _samples
	}
	
	if is_new_record:
		var highscore_sec: int = int(round(total_time))
		print("[GhostRecorder] 🏆 NEW PERSONAL BEST! (%d ms / %ds, previous: %d ms). Saving ghost & public highscore." % [
			total_time_ms, highscore_sec, previous_best_ms
		])
		if api:
			# Update ghost telemetry with new record
			api.save_ghost_telemetry(ghost_payload)
			
			# Update racing save state (private state)
			var save_state = {
				"car_body": car_body_id,
				"best_3lap_ms": total_time_ms,
				"best_lap_ms": best_lap_ms,
				"highscore_seconds": highscore_sec,
				"best_lap_sec": int(round(best_lap_time)),
				"updated_at": Time.get_datetime_string_from_system()
			}
			api.put_state("racing_save", save_state)
			
			# Update public weBump Capsule and Showcase shown on app (in seconds)
			api.save_public_highscore(total_time, best_lap_time)
	else:
		print("[GhostRecorder] ⏱️ Race finished in %d ms (Record is %d ms). Preserving existing personal best ghost." % [
			total_time_ms, previous_best_ms
		])
	
	ghost_saved.emit(ghost_payload, is_new_record)

func _get_api() -> Node:
	return CarPresets.get_api()
