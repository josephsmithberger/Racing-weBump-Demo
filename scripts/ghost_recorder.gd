class_name GhostRecorder extends Node
## Records a complete run, keeps the best replay, and persists local-first saves.

signal ghost_saved(ghost_data: Dictionary, is_new_record: bool)
signal ghost_shared(ok: bool, message: String)

@export var race_manager: RaceManager
@export var sample_rate_hz: float = 15.0

var result_message := ""
var share_message := ""
var _sharing := false
var _recording := false
var _sample_timer := 0.0
var _samples: Array = []
var _target_vehicle: Vehicle

func _ready() -> void:
	if race_manager == null:
		race_manager = get_parent() as RaceManager
	if race_manager:
		race_manager.race_started.connect(_on_race_started)
		race_manager.race_finished.connect(_on_race_finished)

func _on_race_started() -> void:
	_target_vehicle = race_manager.player_vehicle
	_samples.clear()
	_sample_timer = 0.0
	_recording = _target_vehicle != null
	if _recording:
		_record_frame(0)

func _physics_process(delta: float) -> void:
	if not _recording:
		return
	if race_manager.total_time * 1000.0 > GhostData.MAX_DURATION_MS:
		_recording = false
		return
	_sample_timer += delta
	if _sample_timer >= 1.0 / maxf(sample_rate_hz, 1.0):
		_sample_timer = 0.0
		_record_frame(roundi(race_manager.total_time * 1000.0))

func _record_frame(time_ms: int) -> void:
	var pos := _target_vehicle.get_vehicle_position()
	var frame := [time_ms, snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), snappedf(pos.z, 0.01),
		snappedf(_target_vehicle.vehicle_model.global_rotation.y, 0.01), snappedf(_target_vehicle.calculated_lean, 0.01)]
	if not _samples.is_empty() and _samples.back()[0] == time_ms:
		_samples[-1] = frame
	else:
		_samples.append(frame)

func _on_race_finished(total_time: float, lap_times: Array, best_lap_time: float) -> void:
	var complete := _recording and total_time * 1000.0 <= GhostData.MAX_DURATION_MS
	_recording = false
	if complete:
		_record_frame(roundi(total_time * 1000.0))
	var api := CarPresets.get_api()
	if not api:
		return
	var previous: Variant = api.local_state.get("racing_save", {})
	if not previous is Dictionary:
		previous = {}
	var total_ms := roundi(total_time * 1000.0)
	var best_ms := roundi(best_lap_time * 1000.0)
	var is_record: bool = previous.get("best_3lap_ms", 0) <= 0 or total_ms < previous.best_3lap_ms
	var previous_lap := int(previous.get("best_lap_ms", 0))
	var save: Dictionary = previous.duplicate(true)
	save["races"] = int(previous.get("races", 0)) + 1
	save["best_lap_ms"] = mini(previous_lap, best_ms) if previous_lap > 0 else best_ms
	save["car_body"] = api.get_selected_car_body()
	if is_record:
		save["best_3lap_ms"] = total_ms
	var payload: Dictionary = {}
	if complete:
		payload = GhostData.compact({"track_id": GhostData.TRACK_ID, "car_body": api.get_selected_car_body(),
			"lap_count": lap_times.size(), "total_time_ms": total_ms, "samples": _samples})
	var saved_ghost: Variant = api.local_state.get("ghost_telemetry", {})
	var improves_ghost := not GhostData.is_valid(saved_ghost) or total_ms < int(saved_ghost.get("total_time_ms", 0))
	if complete and improves_ghost and GhostData.is_valid(payload, race_manager.max_laps):
		api.save_ghost_telemetry(payload)
	result_message = "Personal best saved on this device" if is_record else "Race saved · Personal best preserved"
	if not complete:
		result_message += " · Replay limit: 3 minutes"
	api.put_state("racing_save", save, func(ok: bool, _value: Variant):
		if api.is_authenticated and not api.is_mock_mode:
			result_message += " · weBump save confirmed" if ok else " · Cloud save failed; local save kept"
	)
	api.save_public_highscore(float(save.best_3lap_ms) / 1000.0, float(save.best_lap_ms) / 1000.0)
	ghost_saved.emit(payload, is_record)

## The best complete replay saved on this device, or empty.
func best_ghost() -> Dictionary:
	var api := CarPresets.get_api()
	var saved: Variant = api.local_state.get("ghost_telemetry", {}) if api else {}
	return GhostData.shared_document(saved, race_manager.max_laps if race_manager else 3)

func can_share_best_ghost() -> bool:
	var api := CarPresets.get_api()
	return api != null and api.is_authenticated and not _sharing and not best_ghost().is_empty()

## Explicit player action: publish only the selected replay. Private saves are untouched.
func share_best_ghost() -> void:
	if not can_share_best_ghost():
		return
	var api := CarPresets.get_api()
	var document := best_ghost()
	_sharing = true
	share_message = "Sharing replay…"
	api.publish_shared_data(document, func(ok: bool, _value: Variant):
		_sharing = false
		if ok:
			share_message = "Replay shared with people you bump for 7 days"
		elif api.last_write_status == 403:
			share_message = "Turn on “Share selected game data” for this game in weBump, then try again"
		elif api.last_write_status == 409:
			share_message = "Save changed elsewhere · try sharing again"
		else:
			share_message = "Sharing failed · replay kept private"
		ghost_shared.emit(ok, share_message)
	)
