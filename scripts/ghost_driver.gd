class_name GhostDriver extends AIVehicle
## Replay uses the same race clock as the player and never runs driving physics.

var recording: Dictionary = {}
var _frame_index := 0

func _ready() -> void:
	super._ready()
	sphere.freeze = true
	sphere.collision_layer = 0
	sphere.collision_mask = 0
	_apply_frame(0.0, 0.0)

func _physics_process(delta: float) -> void:
	if is_finished or _race_manager == null or not _race_manager.is_racing():
		return
	_apply_frame(_race_manager.total_time * 1000.0, delta)
	if _race_manager.total_time * 1000.0 >= float(recording.total_time_ms):
		finish_race(float(recording.total_time_ms) / 1000.0)

func _apply_frame(time_ms: float, delta: float) -> void:
	var samples: Array = recording.get("samples", [])
	if samples.size() < 2:
		return
	while _frame_index < samples.size() - 2 and time_ms >= samples[_frame_index + 1][0]:
		_frame_index += 1
	var a: Array = samples[_frame_index]
	var b: Array = samples[_frame_index + 1]
	var weight := clampf((time_ms - a[0]) / float(b[0] - a[0]), 0.0, 1.0)
	var old_position: Vector3 = vehicle_model.global_position
	vehicle_model.global_position = Vector3(a[1], a[2], a[3]).lerp(Vector3(b[1], b[2], b[3]), weight)
	vehicle_model.global_rotation = Vector3(0, lerp_angle(a[4], b[4], weight), 0)
	sphere.global_position = vehicle_model.global_position + Vector3(0, 0.65, 0)
	calculated_lean = lerpf(a[5], b[5], weight)
	if vehicle_body:
		vehicle_body.rotation.z = calculated_lean
	if delta > 0.0:
		linear_velocity = (vehicle_model.global_position - old_position) / delta
		linear_speed = clampf(linear_velocity.length() / 12.0, 0, 1)
		acceleration = linear_velocity.length() * delta * 2.0
		effect_wheels(delta)
		effect_engine(delta)
		effect_trails()
