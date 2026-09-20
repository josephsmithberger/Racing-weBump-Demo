class_name AIVehicle extends Vehicle

@export var driver_name: String = "Racer"
@export var track_path: Path3D
@export var start_delay: float = 0.0
@export var look_ahead_distance: float = 4.5
@export var lane_offset: float = 0.0
@export var apex_cut_strength: float = 0.0
@export var max_throttle: float = 0.95
@export var corner_throttle: float = 0.68
@export var steer_gain: float = 1.8
@export var steer_smoothness: float = 12.0
@export var driver_frequency: float = 1.0
@export var max_laps: int = 3

signal rival_finished(rival_id: String, finish_time: float)

var rival_id: String = ""
var rival_color: Color = Color.DODGER_BLUE
var car_body: String = "truck_yellow"
var finish_time: float = -1.0
var race_progress: float = 0.0
var completed_lap_times: Array[float] = []
var _last_lap_time: float = 0.0

var current_lap: int = 1
var is_finished: bool = false

var _curve: Curve3D
var _race_manager: Node
var _stuck_timer: float = 0.0
var _last_pos: Vector3 = Vector3.ZERO
var _prev_offset: float = 0.0
var _reached_backstretch: bool = false
var _racing_active: bool = false
var _finish_offset: float = -1.0
var _baked_len: float = 0.0

# Finish effects are scene nodes (ai_vehicle.tscn); only the pop sound is synthesized once.
@onready var _confetti_emitter: CPUParticles3D = $Confetti
@onready var _pop_player: AudioStreamPlayer3D = $PopSound

static var _shared_pop_audio: AudioStreamWAV

static func _get_shared_pop_audio() -> AudioStreamWAV:
	if _shared_pop_audio == null:
		var wav = AudioStreamWAV.new()
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.mix_rate = 22050
		wav.stereo = false
		var num_samples = int(22050 * 0.20)
		var data = PackedByteArray()
		data.resize(num_samples * 2)
		for i in range(num_samples):
			var t = float(i) / 22050.0
			var freq = lerpf(880.0, 140.0, clampf(t / 0.10, 0.0, 1.0))
			var env = clampf(1.0 - t / 0.20, 0.0, 1.0)
			env = env * env
			var sample = (sin(t * freq * TAU) * 0.75 + (randf() * 2.0 - 1.0) * 0.25) * env
			var val = int(clampf(sample, -1.0, 1.0) * 32767.0)
			data.encode_s16(i * 2, val)
		wav.data = data
		_shared_pop_audio = wav
	return _shared_pop_audio

func _ready() -> void:
	# Every rival is a ghost, whether it is replaying a real shared lap or driving
	# as practice AI. Set before the model exists so the first paint applies it.
	ghost_look = true
	apply_car_preset(car_body)
	apply_body_color(rival_color)
	# Opponents pass through the player and each other.
	sphere.collision_layer = 16
	sphere.collision_mask = 1

	# 4. Soften AI audio
	if engine_sound != null:
		engine_sound.volume_db -= 4.0
	if screech_sound != null:
		screech_sound.volume_db -= 4.0
	if impact_sound != null:
		impact_sound.volume_db -= 4.0
	
	# 5. The confetti emitter is pre-built in the scene; bind the shared pop sound.
	_pop_player.stream = _get_shared_pop_audio()
	
	# 6. Overhead driver nameplate
	setup_nameplate(driver_name)
	
	# 7. Acquire track path curve
	if track_path != null:
		if track_path is TrackPath and (track_path.curve == null or track_path.curve.point_count == 0):
			track_path.build_track_curve()
		_curve = track_path.curve
	else:
		var tp = get_node_or_null("../TrackPath")
		if tp is Path3D:
			track_path = tp
			if tp is TrackPath and (tp.curve == null or tp.curve.point_count == 0):
				tp.build_track_curve()
			_curve = tp.curve
	
	# 7. Synchronize with RaceManager countdown
	set_controls_enabled(false)
	_racing_active = false
	_race_manager = get_node_or_null("../RaceManager")
	if _race_manager != null:
		_race_manager.race_started.connect(_on_race_started)
	else:
		get_tree().create_timer(1.5).timeout.connect(func(): _on_race_started())
	
	_last_pos = global_position
	if _curve != null:
		_cache_curve_metrics()
		_prev_offset = _lap_offset(vehicle_model.global_position)
		race_progress = _prev_offset / _baked_len

func _cache_curve_metrics() -> void:
	# Curve3D.get_closest_offset walks every baked point; the finish offset and
	# baked length never change, so compute them once instead of per physics tick.
	_baked_len = _curve.get_baked_length()
	_finish_offset = _curve.get_closest_offset(Vector3(3.75, 0, 1.5))

func _on_race_started() -> void:
	if is_finished:
		return
	if start_delay > 0.01:
		await get_tree().create_timer(start_delay).timeout
		if is_finished:
			return
	_racing_active = true
	set_controls_enabled(true)

func handle_input(delta: float) -> void:
	if is_finished or not controls_enabled or not raycast.is_colliding() or _curve == null or (_race_manager and not _race_manager.is_racing()):
		input = Vector3.ZERO
		linear_speed = lerp(linear_speed, 0.0, delta * 4.0)
		sphere.angular_velocity += vehicle_model.get_global_transform().basis.x * (linear_speed * 100.0) * delta
		return

	var current_pos = vehicle_model.global_position
	if _finish_offset < 0.0:
		_cache_curve_metrics()
	var baked_len = _baked_len
	if baked_len <= 0.0:
		return

	# 1. Track curve progress & lap completion (one closest-point search per tick)
	var current_offset = _curve.get_closest_offset(track_path.to_local(current_pos))
	_update_lap_tracking(fposmod(current_offset - _finish_offset, baked_len), baked_len)
	if is_finished:
		return

	# 2. Look-ahead target point
	var target_offset = fposmod(current_offset + look_ahead_distance, baked_len)
	var target_pos = _curve.sample_baked(target_offset, true)

	# Dynamic lane offset (Apex cutting on curves)
	var turn_severity = clampf(absf(input.x) * 1.3, 0.0, 1.0)
	var active_lane = lane_offset + (apex_cut_strength * turn_severity)
	if absf(active_lane) > 0.001:
		var next_offset = fposmod(target_offset + 0.5, baked_len)
		var next_pos = _curve.sample_baked(next_offset, true)
		var tangent = (next_pos - target_pos).normalized()
		var right_dir = Vector3.UP.cross(tangent).normalized()
		target_pos += right_dir * active_lane

	target_pos.y = current_pos.y

	# 3. Transform target to vehicle local coordinate space
	var local_target = vehicle_model.to_local(target_pos)
	var steer_angle = atan2(local_target.x, local_target.z)
	var desired_steer = -clampf(steer_angle * steer_gain, -1.0, 1.0)
	
	# Driver micro-oscillation for human feel
	var noise = sin(Time.get_ticks_msec() * 0.0025 * driver_frequency + float(get_instance_id() % 100)) * 0.03
	desired_steer = clampf(desired_steer + noise, -1.0, 1.0)
	
	input.x = lerpf(input.x, desired_steer, delta * steer_smoothness)

	# 4. Throttle calculation
	var desired_throttle = lerpf(max_throttle, corner_throttle, turn_severity)
	if local_target.z < 0.0:
		desired_throttle = 0.35
	input.z = lerpf(input.z, desired_throttle, delta * 8.0)

	# 5. Physics roll
	sphere.angular_velocity += vehicle_model.get_global_transform().basis.x * (linear_speed * 100.0) * delta

	# 6. Stuck check
	_check_stuck(delta, current_pos)

func _lap_offset(world_position: Vector3) -> float:
	# Match the actual finish gate, which is not the first point of the curve.
	if _finish_offset < 0.0:
		_cache_curve_metrics()
	return fposmod(_curve.get_closest_offset(track_path.to_local(world_position)) - _finish_offset, _baked_len)

func _update_lap_tracking(current_offset: float, baked_len: float) -> void:
	if current_offset > baked_len * 0.4 and current_offset < baked_len * 0.7:
		_reached_backstretch = true
	if _reached_backstretch and _prev_offset > baked_len * 0.85 and current_offset < baked_len * 0.15:
		_reached_backstretch = false
		current_lap += 1
		var elapsed: float = _race_manager.total_time if _race_manager else 0.0
		completed_lap_times.append(elapsed - _last_lap_time)
		_last_lap_time = elapsed
		if current_lap > max_laps:
			finish_race(elapsed)
	race_progress = minf(float(max_laps), current_lap - 1 + current_offset / baked_len)
	_prev_offset = current_offset

func finish_race(elapsed: float) -> void:
	if is_finished:
		return
	is_finished = true
	finish_time = elapsed
	rival_finished.emit(rival_id, elapsed)
	_disappear_into_confetti()

func estimate_finish_time(elapsed: float) -> float:
	return RaceStandings.predict_finish(elapsed, race_progress, max_laps, completed_lap_times)

func _disappear_into_confetti() -> void:
	set_controls_enabled(false)
	
	# Freeze physics
	if sphere != null:
		sphere.linear_velocity = Vector3.ZERO
		sphere.angular_velocity = Vector3.ZERO
		sphere.collision_layer = 0
		sphere.freeze = true
	
	# Stop vehicle sounds
	if engine_sound != null:
		engine_sound.stop()
	if screech_sound != null:
		screech_sound.stop()
	
	# Trigger pre-warmed audio instantly (0 frame delay, 0 runtime allocation)
	if _pop_player != null:
		_pop_player.reparent(get_parent())
		_pop_player.global_position = vehicle_model.global_position + Vector3(0, 0.8, 0)
		_pop_player.play()
	
	# Trigger pre-warmed confetti instantly (0 shader compiles / 0 hitch)
	if _confetti_emitter != null:
		_confetti_emitter.reparent(get_parent())
		_confetti_emitter.global_position = vehicle_model.global_position + Vector3(0, 0.8, 0)
		_confetti_emitter.emitting = true
	
	# Vanish animation
	if vehicle_model != null:
		var tw = create_tween().set_parallel(false).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(vehicle_model, "scale", Vector3(1.25, 1.25, 1.25), 0.08)
		tw.chain().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(vehicle_model, "scale", Vector3.ZERO, 0.14)
		tw.chain().tween_callback(func():
			if vehicle_model != null:
				vehicle_model.visible = false
		)
	
	# Clean up after confetti finishes
	await get_tree().create_timer(3.5).timeout
	if _confetti_emitter != null:
		_confetti_emitter.queue_free()
	if _pop_player != null:
		_pop_player.queue_free()
	queue_free()

func _check_stuck(delta: float, current_pos: Vector3) -> void:
	var dist_moved = current_pos.distance_to(_last_pos)
	if dist_moved < 0.15 and absf(linear_speed) < 0.25:
		_stuck_timer += delta
		if _stuck_timer > 2.5:
			_recover_to_track()
			_stuck_timer = 0.0
	else:
		_stuck_timer = 0.0
		_last_pos = current_pos

func _recover_to_track() -> void:
	if _curve == null:
		return
	var off = _curve.get_closest_offset(vehicle_model.global_position)
	var recovery_pos = _curve.sample_baked(off, true)
	var next_pos = _curve.sample_baked(fposmod(off + 1.0, _curve.get_baked_length()), true)
	var fwd = (next_pos - recovery_pos).normalized()
	
	recovery_pos.y += 0.5
	sphere.global_position = recovery_pos
	sphere.linear_velocity = Vector3.ZERO
	sphere.angular_velocity = Vector3.ZERO
	vehicle_model.global_position = recovery_pos - Vector3(0, 0.65, 0)
	if fwd.length_squared() > 0.1:
		vehicle_model.look_at(vehicle_model.global_position + fwd, Vector3.UP)
	linear_speed = 0.4
