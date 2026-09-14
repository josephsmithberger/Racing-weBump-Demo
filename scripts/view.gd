extends Node3D

@export_group("Properties")
@export var target: Vehicle

@onready var camera = $Camera

var _shake_intensity: float = 0.0
var _shake_timer: float = 0.0
var _shake_duration: float = 0.0

# Functions

func shake(intensity: float = 0.4, duration: float = 0.3) -> void:
	_shake_intensity = intensity
	_shake_duration = duration
	_shake_timer = duration

func _physics_process(delta):
	
	# Ease position towards target vehicle position
	if target:
		self.position = self.position.lerp(target.get_vehicle_position(), delta * 4)

		# Zoom camera based on the speed of the vehicle
		var speed_factor = clamp(abs(target.linear_speed), 0.0, 1.0)
		var target_z = remap(speed_factor, 0.0, 1.0, 10, 20)
		camera.position.z = lerp(camera.position.z, target_z, delta * 0.5)

	# Handle screen shake
	if _shake_timer > 0.0:
		_shake_timer -= delta
		var damping: float = _shake_timer / _shake_duration
		var offset_x: float = randf_range(-1.0, 1.0) * _shake_intensity * damping
		var offset_y: float = randf_range(-1.0, 1.0) * _shake_intensity * damping
		camera.h_offset = offset_x
		camera.v_offset = offset_y
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
