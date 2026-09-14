class_name AIVehicle extends Vehicle

@export var driver_name: String = "Racer"
@export var track_path: Path3D
@export var model_scene: PackedScene
@export var start_delay: float = 0.0
@export var look_ahead_distance: float = 4.5
@export var lane_offset: float = 0.0
@export var apex_cut_strength: float = 0.0
@export var max_throttle: float = 0.95
@export var corner_throttle: float = 0.68
@export var steer_gain: float = 1.8
@export var steer_smoothness: float = 12.0
@export var driver_frequency: float = 1.0
@export var ghost_transparency: float = 0.72
@export var ghost_tint: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var enable_ghost_visuals: bool = true
@export var max_laps: int = 3

var current_lap: int = 1
var is_finished: bool = false

var _curve: Curve3D
var _race_manager: RaceManager
var _stuck_timer: float = 0.0
var _last_pos: Vector3 = Vector3.ZERO
var _prev_offset: float = 0.0
var _reached_backstretch: bool = false
var _racing_active: bool = false

var _confetti_emitter: CPUParticles3D
var _pop_player: AudioStreamPlayer3D

static var _shared_confetti_mesh: QuadMesh
static var _shared_pop_audio: AudioStreamWAV

static func _get_shared_confetti_mesh() -> QuadMesh:
	if _shared_confetti_mesh == null:
		var q = QuadMesh.new()
		q.size = Vector2(0.14, 0.22)
		var mat = StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		q.material = mat
		_shared_confetti_mesh = q
	return _shared_confetti_mesh

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
	# 1. Swap visual model if custom model_scene is assigned
	if model_scene != null:
		_swap_model(model_scene)
	
	# 2. Ghost collision: Layer 16 (AI), Mask 1 (Track/ground only)
	if sphere != null:
		sphere.collision_layer = 16
		sphere.collision_mask = 1
	
	# 3. Apply uniform ghost translucent visuals with depth pre-pass
	if enable_ghost_visuals:
		_apply_ghost_visuals()
	
	# 4. Soften AI audio
	if engine_sound != null:
		engine_sound.volume_db -= 4.0
	if screech_sound != null:
		screech_sound.volume_db -= 4.0
	if impact_sound != null:
		impact_sound.volume_db -= 4.0
	
	# 5. Pre-warm and pre-allocate confetti effects to prevent first-time stutter
	_init_prewarmed_effects()
	
	# 6. Acquire track path curve
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
	_race_manager = get_node_or_null("../RaceManager") as RaceManager
	if _race_manager != null:
		_race_manager.race_started.connect(_on_race_started)
		_race_manager.race_finished.connect(_on_race_finished)
	else:
		get_tree().create_timer(1.5).timeout.connect(func(): _on_race_started())
	
	_last_pos = global_position
	if _curve != null:
		_prev_offset = _curve.get_closest_offset(global_position)

func _init_prewarmed_effects() -> void:
	# Pre-create particle emitter and pre-bind mesh/shader so GPU compiles during countdown
	_confetti_emitter = CPUParticles3D.new()
	_confetti_emitter.name = "PrewarmedConfetti"
	_confetti_emitter.emitting = false
	_confetti_emitter.one_shot = true
	_confetti_emitter.explosiveness = 0.98
	_confetti_emitter.amount = 180
	_confetti_emitter.lifetime = 3.0
	_confetti_emitter.direction = Vector3(0, 1, 0)
	_confetti_emitter.spread = 75.0
	_confetti_emitter.initial_velocity_min = 7.0
	_confetti_emitter.initial_velocity_max = 13.0
	_confetti_emitter.damping_min = 2.5
	_confetti_emitter.damping_max = 4.5
	_confetti_emitter.angular_velocity_min = -360.0
	_confetti_emitter.angular_velocity_max = 360.0
	_confetti_emitter.mesh = _get_shared_confetti_mesh()
	_confetti_emitter.hue_variation_min = -1.0
	_confetti_emitter.hue_variation_max = 1.0
	_confetti_emitter.color = Color(1.0, 0.8, 0.2, 1.0)
	add_child(_confetti_emitter)
	
	# Pre-create audio player with pre-baked sound
	_pop_player = AudioStreamPlayer3D.new()
	_pop_player.stream = _get_shared_pop_audio()
	_pop_player.volume_db = 3.0
	_pop_player.unit_size = 20.0
	add_child(_pop_player)

func _on_race_started() -> void:
	if is_finished:
		return
	if start_delay > 0.01:
		await get_tree().create_timer(start_delay).timeout
		if is_finished:
			return
	_racing_active = true
	set_controls_enabled(true)

func _on_race_finished(_total_time: float, _lap_times: Array, _best_lap_time: float) -> void:
	pass

func _swap_model(scene: PackedScene) -> void:
	var old_model = get_node_or_null("Container/Model")
	if old_model != null:
		old_model.queue_free()
	
	var new_model = scene.instantiate()
	new_model.name = "Model"
	$Container.add_child(new_model)
	
	vehicle_body = get_node_or_null("Container/Model/body")
	wheel_fl = get_node_or_null("Container/Model/wheel-front-left")
	wheel_fr = get_node_or_null("Container/Model/wheel-front-right")
	wheel_bl = get_node_or_null("Container/Model/wheel-back-left")
	wheel_br = get_node_or_null("Container/Model/wheel-back-right")

func _apply_ghost_visuals() -> void:
	var meshes: Array[MeshInstance3D] = []
	var queue: Array[Node] = [$Container]
	while queue.size() > 0:
		var cur = queue.pop_front()
		if cur is MeshInstance3D:
			meshes.append(cur)
		for child in cur.get_children():
			queue.push_back(child)
	
	for m in meshes:
		if m.name == "underside":
			m.visible = false
			continue
		
		for s in range(m.mesh.get_surface_count()):
			var mat = m.get_active_material(s)
			if mat is StandardMaterial3D:
				var ghost_mat = mat.duplicate() as StandardMaterial3D
				ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
				ghost_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
				ghost_mat.cull_mode = BaseMaterial3D.CULL_BACK
				ghost_mat.albedo_color = Color(ghost_tint.r, ghost_tint.g, ghost_tint.b, ghost_transparency)
				ghost_mat.rim_enabled = true
				ghost_mat.rim = 0.45
				ghost_mat.rim_tint = 0.5
				m.set_surface_override_material(s, ghost_mat)

func handle_input(delta: float) -> void:
	if is_finished or not controls_enabled or not raycast.is_colliding() or _curve == null:
		input = Vector3.ZERO
		linear_speed = lerp(linear_speed, 0.0, delta * 4.0)
		sphere.angular_velocity += vehicle_model.get_global_transform().basis.x * (linear_speed * 100.0) * delta
		return

	var current_pos = vehicle_model.global_position
	var baked_len = _curve.get_baked_length()
	if baked_len <= 0.0:
		return

	# 1. Track curve progress & lap completion
	var current_offset = _curve.get_closest_offset(current_pos)
	_update_lap_tracking(current_offset, baked_len)
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

func _update_lap_tracking(current_offset: float, baked_len: float) -> void:
	if current_offset > 35.0 and current_offset < 75.0:
		_reached_backstretch = true
	
	if _reached_backstretch and _prev_offset > (baked_len - 15.0) and current_offset < 15.0:
		_reached_backstretch = false
		current_lap += 1
		print("[AI Race] ", driver_name, " completed lap ", current_lap - 1, "! (Now on Lap ", current_lap, "/", max_laps, ")")
		
		if current_lap > max_laps and not is_finished:
			is_finished = true
			_disappear_into_confetti()
	
	_prev_offset = current_offset

func _disappear_into_confetti() -> void:
	print("[AI Race] ", driver_name, " crossed the finish line on Lap 3! Vanishing into confetti!")
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
