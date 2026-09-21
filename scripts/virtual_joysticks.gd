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

	if is_web_touch_device():
		return true

	for arg in OS.get_cmdline_user_args():
		if arg == "--mobile":
			return true
	for arg in OS.get_cmdline_args():
		if arg == "--mobile":
			return true

	return false

## A touch device the engine's own features miss. `web_ios` and `web_android` are
## plain user agent matches, and iPadOS reports itself as a Mac for desktop-class
## browsing, so an iPad reads as `web_macos` and loses the joysticks it is the only
## way to steer with. Two or more touch points plus either an Apple desktop agent
## (an iPad; a real Mac reports zero touch points) or a coarse primary pointer (an
## Android or Windows tablet, where a mouse would report a fine one) marks a device
## with no keyboard to fall back on. WeBumpAPI runs the Apple-only half of this
## check to decide whether it can hand an approval straight to the weBump app.
static func is_web_touch_device() -> bool:
	if not OS.has_feature("web"):
		return false
	var touch_only: Variant = JavaScriptBridge.eval("""
		(function () {
			if ((navigator.maxTouchPoints || 0) < 2) return 0;
			if (/Mac|iPad|iPhone|iPod/.test(navigator.platform || navigator.userAgent || '')) return 1;
			return (window.matchMedia && window.matchMedia('(pointer: coarse)').matches) ? 1 : 0;
		})()
	""", true)
	return typeof(touch_only) in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT] and int(touch_only) == 1
