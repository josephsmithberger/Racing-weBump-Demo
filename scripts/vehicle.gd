class_name Vehicle extends Node3D

# Nodes

@onready var sphere: RigidBody3D = $Sphere
@onready var raycast: RayCast3D = $Ground

# Vehicle elements

@onready var vehicle_model = $Container
@onready var vehicle_body = get_node_or_null("Container/Model/body")

# (Optional) wheels

@onready var wheel_fl = get_node_or_null("Container/Model/wheel-front-left")
@onready var wheel_fr = get_node_or_null("Container/Model/wheel-front-right")
@onready var wheel_bl = get_node_or_null("Container/Model/wheel-back-left")
@onready var wheel_br = get_node_or_null("Container/Model/wheel-back-right")

# Motorcycle specific elements
var motorcycle: Node3D
var fork: Node3D
var wheel_front: Node3D
var wheel_back: Node3D
var is_motorcycle: bool = false

# Nameplate & Custom Paint
@onready var nameplate_label: Label3D = get_node_or_null("Container/Nameplate")
var current_preset_id: String = "truck_yellow"
var _paint_material: ShaderMaterial

const PAINT_SHADER: Shader = preload("res://shaders/car_paint.gdshader")
const GHOST_PAINT_SHADER: Shader = preload("res://shaders/car_paint_ghost.gdshader")

## Rivals race as see-through ghosts and cast no shadow, which is also what keeps
## them out of the directional light's shadow pass. Set before the model is built.
var ghost_look: bool = false

# Effects

@onready var trail_left = get_node_or_null("Container/TrailLeft")
@onready var trail_right = get_node_or_null("Container/TrailRight")

# Sounds

@onready var screech_sound: AudioStreamPlayer3D = $Container/ScreechSound
@onready var engine_sound: AudioStreamPlayer3D = $Container/EngineSound
@onready var impact_sound: AudioStreamPlayer3D = $Container/ImpactSound

var input: Vector3
var normal: Vector3

var acceleration: float
var angular_speed: float
var linear_speed: float

var colliding: bool

var linear_velocity: Vector3
var prev_position: Vector3

var calculated_lean: float
var controls_enabled: bool = true

func _ready() -> void:
	# Rival subclasses implement their own setup. Keep the base independent of drivers.
	var selected_id = CarPresets.get_selected_car()
	var api = _get_api()
	if api:
		api.auth_succeeded.connect(func(_profile: Dictionary, _is_mock: bool):
			var col = api.get_player_theme_color()
			apply_body_color(col)
			setup_nameplate(api.get_player_display_name())
		)
		api.session_disconnected.connect(func():
			var preset = CarPresets.get_preset_by_id(current_preset_id)
			apply_body_color(preset.get("default_color", Color(1.0, 0.70, 0.0)))
			setup_nameplate("Player")
		)
		api.car_body_changed.connect(func(new_body: String):
			apply_car_preset(new_body)
		)

	print("[Vehicle] Applying player car preset: '%s'" % selected_id)
	apply_car_preset(selected_id)

	var name_str = "Player"
	if api:
		name_str = api.get_player_display_name()
	setup_nameplate(name_str)


func _get_api() -> Node:
	return CarPresets.get_api()

# Public Functions

func get_vehicle_position() -> Vector3: return vehicle_model.global_position
func set_controls_enabled(enabled: bool) -> void:
	controls_enabled = enabled
	if not enabled:
		input = Vector3.ZERO

func apply_car_preset(car_id: String) -> void:
	current_preset_id = car_id
	var preset = CarPresets.get_preset_by_id(car_id)
	var model_path: String = preset.get("model_path", "res://models/vehicle-truck-yellow.glb")
	var model_scene = load(model_path)
	if not model_scene:
		push_error("Failed to load model: %s" % model_path)
		return
	
	# Cleanly remove previous model from tree before adding new one
	var old_model = $Container.get_node_or_null("Model")
	if old_model:
		$Container.remove_child(old_model)
		old_model.queue_free()
	for child in $Container.get_children():
		if child.name.begins_with("Model") or child.has_node("motorcycle"):
			$Container.remove_child(child)
			child.queue_free()
	
	var new_model = model_scene.instantiate()
	new_model.name = "Model"
	$Container.add_child(new_model)
	
	# Check if motorcycle
	if new_model.has_node("motorcycle"):
		is_motorcycle = true
		motorcycle = new_model.get_node("motorcycle")
		vehicle_body = motorcycle.get_node_or_null("body")
		fork = motorcycle.get_node_or_null("body/fork")
		wheel_front = motorcycle.get_node_or_null("wheel-front")
		wheel_back = motorcycle.get_node_or_null("wheel-back")
		wheel_fl = null
		wheel_fr = null
		wheel_bl = null
		wheel_br = null
	else:
		is_motorcycle = false
		motorcycle = null
		fork = null
		wheel_front = null
		wheel_back = null
		vehicle_body = new_model.get_node_or_null("body")
		wheel_fl = new_model.get_node_or_null("wheel-front-left")
		wheel_fr = new_model.get_node_or_null("wheel-front-right")
		wheel_bl = new_model.get_node_or_null("wheel-back-left")
		wheel_br = new_model.get_node_or_null("wheel-back-right")
	
	# Apply active theme color
	var col = _get_active_color(preset)
	apply_body_color(col)

func _get_active_color(preset: Dictionary = {}) -> Color:
	var api = _get_api()
	if api and api.is_authenticated:
		return api.get_player_theme_color()
	if preset.has("default_color"):
		return preset["default_color"]
	return Color(1.0, 0.70, 0.0)

func apply_body_color(color: Color) -> void:
	# The ghost shader is a separate one rather than an alpha uniform on the solid
	# one: transparency is a property of the shader, so a single shared shader
	# would move the player's car into the transparent pass too.
	var shader: Shader = GHOST_PAINT_SHADER if ghost_look else PAINT_SHADER
	if _paint_material == null or _paint_material.shader != shader:
		_paint_material = ShaderMaterial.new()
		_paint_material.shader = shader
		_paint_material.set_shader_parameter("albedo_texture", preload("res://models/Textures/colormap.png"))

	_paint_material.set_shader_parameter("paint_color", color)
	var preset = CarPresets.get_preset_by_id(current_preset_id)
	_paint_material.set_shader_parameter("paint_region", CarPresets.paint_region(preset))
	_paint_material.set_shader_parameter("use_paint_override", true)

	var shadow_mode := (
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if ghost_look
		else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	)

	# Paint panels may live on separate body, fork, or wheel meshes. The shader's
	# per-preset palette mask leaves lights, glass, tires, and neutral trim intact.
	var model = $Container.get_node_or_null("Model")
	if model:
		for child in model.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := child as MeshInstance3D
			mesh_instance.material_override = _paint_material
			mesh_instance.cast_shadow = shadow_mode
	elif vehicle_body:
		vehicle_body.material_override = _paint_material
		vehicle_body.cast_shadow = shadow_mode

func setup_nameplate(display_name: String) -> void:
	if nameplate_label == null:
		return
	nameplate_label.text = display_name
	nameplate_label.visible = true

# Functions

func _physics_process(delta):

	handle_input(delta)

	var direction = sign(linear_speed)
	if direction == 0: direction = sign(input.z) if abs(input.z) > 0.1 else 1

	var steering_grip = clamp(abs(linear_speed), 0.2, 1.0)

	var target_angular = -input.x * steering_grip * 4 * direction
	angular_speed = lerp(angular_speed, target_angular, delta * 4)

	vehicle_model.rotate_y(angular_speed * delta)

	# Ground alignment

	if raycast.is_colliding():
		if !colliding:
			if vehicle_body != null: vehicle_body.position = Vector3(0, 0.1, 0) # Bounce
			input.z = 0

		normal = raycast.get_collision_normal()

		# Orient model to colliding normal

		if normal.dot(vehicle_model.global_basis.y) > 0.5:
			var xform = align_with_y(vehicle_model.global_transform, normal)
			vehicle_model.global_transform = vehicle_model.global_transform.interpolate_with(xform, 0.2).orthonormalized()

	colliding = raycast.is_colliding()

	var target_speed = input.z

	if (target_speed < 0 and linear_speed > 0.01):
		linear_speed = lerp(linear_speed, 0.0, delta * 8)
	else:
		if (target_speed < 0):
			linear_speed = lerp(linear_speed, target_speed / 2, delta * 2)
		else:
			linear_speed = lerp(linear_speed, target_speed, delta * 6)

	acceleration = lerpf(acceleration, linear_speed + (abs(sphere.angular_velocity.length() * linear_speed) / 100), delta * 1)

	# Match vehicle model to physics sphere

	vehicle_model.position = sphere.position - Vector3(0, 0.65, 0)
	raycast.position = sphere.position

	# Calculate vehicle model linear velocity

	linear_velocity = (vehicle_model.position - prev_position) / delta
	prev_position = vehicle_model.position

	# Visual and audio effects

	effect_engine(delta)
	effect_body(delta)
	effect_wheels(delta)
	effect_trails()

# Handle input when vehicle is colliding with ground

func handle_input(delta):

	if not controls_enabled:
		input = Vector3.ZERO
		linear_speed = lerp(linear_speed, 0.0, delta * 4)
	elif raycast.is_colliding():
		input.x = Input.get_axis("left", "right")
		input.z = Input.get_axis("back", "forward")

	sphere.angular_velocity += vehicle_model.get_global_transform().basis.x * (linear_speed * 100) * delta

func effect_body(delta):
	if is_motorcycle and motorcycle != null:
		var target_lean = -input.x / 5.0 * linear_speed 
		calculated_lean = lerp_angle(calculated_lean, target_lean, delta * 5.0)
		motorcycle.rotation.z = lerp_angle(motorcycle.rotation.z, input.x * linear_speed, delta * 3.0)
		if vehicle_body != null:
			vehicle_body.rotation.x = lerp_angle(vehicle_body.rotation.x, -(linear_speed - acceleration) / 6.0, delta * 10.0)
	else:
		calculated_lean = lerp_angle(calculated_lean, -input.x / 5.0 * linear_speed, delta * 5.0)
		if vehicle_body != null:
			vehicle_body.rotation.x = lerp_angle(vehicle_body.rotation.x, -(linear_speed - acceleration) / 6.0, delta * 10.0)
			vehicle_body.rotation.z = calculated_lean
			vehicle_body.position = vehicle_body.position.lerp(Vector3(0, 0.2, 0), delta * 5.0)
	
func effect_wheels(delta):
	if is_motorcycle:
		for wheel in [wheel_front, wheel_back]:
			if wheel != null:
				wheel.rotation.x += acceleration
		if wheel_front != null and fork != null:
			fork.rotation.y = lerp_angle(fork.rotation.y, -input.x / 1.5, delta * 5.0)
			wheel_front.rotation.y = lerp_angle(wheel_front.rotation.y, -input.x / 1.5, delta * 10.0)
	else:
		for wheel in [wheel_fl, wheel_fr, wheel_bl, wheel_br]:
			if wheel != null:
				wheel.rotation.x += acceleration
		if wheel_fl != null: wheel_fl.rotation.y = lerp_angle(wheel_fl.rotation.y, -input.x / 1.5, delta * 10.0)
		if wheel_fr != null: wheel_fr.rotation.y = lerp_angle(wheel_fr.rotation.y, -input.x / 1.5, delta * 10.0)

# Engine sounds

func effect_engine(delta):

	var speed_factor = clamp(abs(linear_speed), 0.0, 1.0)
	var throttle_factor = clamp(abs(input.z), 0.0, 1.0)

	var target_volume = remap(speed_factor + (throttle_factor * 0.5), 0.0, 1.5, -15.0, -5.0)
	engine_sound.volume_db = lerp(engine_sound.volume_db, target_volume, delta * 5.0)

	var target_pitch = remap(speed_factor, 0.0, 1.0, 0.5, 3)
	if throttle_factor > 0.1: target_pitch += 0.2

	engine_sound.pitch_scale = lerp(engine_sound.pitch_scale, target_pitch, delta * 2.0)

# Show trails (and play skid sound)

func effect_trails():

	var drift_intensity = abs(linear_speed - acceleration) + (abs(calculated_lean) * 2.0)
	var should_emit = drift_intensity > 0.25

	if trail_left != null: trail_left.emitting = should_emit
	if trail_right != null: trail_right.emitting = should_emit

	var target_volume = -80.0
	if should_emit: target_volume = remap(clamp(drift_intensity, 0.25, 2.0), 0.25, 2.0, -10.0, 0.0)

	screech_sound.pitch_scale = lerp(screech_sound.pitch_scale, clamp(abs(linear_speed), 1.0, 3.0), 0.1)
	screech_sound.volume_db = lerp(screech_sound.volume_db, target_volume, 10.0 * get_physics_process_delta_time())

# Align vehicle with normal

func align_with_y(xform, new_y):

	xform.basis.y = new_y
	xform.basis.x = -xform.basis.z.cross(new_y)
	xform.basis = xform.basis.orthonormalized()
	return xform

# Detect collisions and play impact sound

func _on_sphere_body_entered(_body: Node) -> void:
	
	if vehicle_body == null: return
	
	if not impact_sound.playing:
		var impact_velocity := absf(linear_velocity.dot(vehicle_body.global_basis.z))
		impact_sound.volume_db = clampf(remap(impact_velocity, 0.0, 6.0, -20.0, 0.0), -20.0, 0.0)
		impact_sound.play()
