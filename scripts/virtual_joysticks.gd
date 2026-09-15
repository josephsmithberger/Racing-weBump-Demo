class_name VirtualJoysticks extends CanvasLayer

@export var force_mobile: bool = false
@export var race_manager: RaceManager

@onready var left_joystick: VirtualJoystick = $LeftJoystick
@onready var right_joystick: VirtualJoystick = $RightJoystick

func _ready() -> void:
	if not should_show():
		queue_free()
		return
	
	if race_manager == null:
		race_manager = get_node_or_null("../RaceManager") as RaceManager
	
	if race_manager:
		race_manager.race_finished.connect(_on_race_finished)

func _on_race_finished(_total_time: float) -> void:
	visible = false

func should_show() -> bool:
	if force_mobile:
		return true
	return is_mobile()

static func is_mobile() -> bool:
	if (
		OS.has_feature("mobile")
		or OS.has_feature("android")
		or OS.has_feature("ios")
		or OS.has_feature("web_android")
		or OS.has_feature("web_ios")
	):
		return true
	
	for arg in OS.get_cmdline_user_args():
		if arg == "--mobile":
			return true
	for arg in OS.get_cmdline_args():
		if arg == "--mobile":
			return true
	
	return false
