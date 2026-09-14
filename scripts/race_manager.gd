class_name RaceManager extends Node

signal countdown_tick(number: int)
signal race_started()
signal lap_completed(lap_number: int, lap_time: float, is_best: bool)
signal final_lap_started()
signal race_finished(total_time: float, lap_times: Array, best_lap_time: float)
signal timer_updated(lap_time: float, total_time: float)

enum State { COUNTDOWN, RACING, FINISHED }

@export var max_laps: int = 3
@export var player_vehicle: Vehicle
@export var view_camera: Node3D

var state: State = State.COUNTDOWN
var current_lap: int = 1
var total_time: float = 0.0
var current_lap_time: float = 0.0
var lap_times: Array = []
var best_lap_time: float = -1.0

var _checkpoints_passed: Array[bool] = [false, false, false]
var _countdown_timer: float = 0.0
var _countdown_step: int = 4 # 4: not started, 3, 2, 1, 0: GO

func _ready() -> void:
	if player_vehicle == null:
		player_vehicle = get_tree().get_first_node_in_group("player") as Vehicle
		if player_vehicle == null:
			var veh = get_node_or_null("../Vehicle")
			if veh and veh is Vehicle:
				player_vehicle = veh
	
	if view_camera == null:
		view_camera = get_node_or_null("../View")
	
	if player_vehicle:
		player_vehicle.set_controls_enabled(false)
	
	_start_countdown()

func _start_countdown() -> void:
	state = State.COUNTDOWN
	_countdown_step = 4
	_countdown_timer = 0.5 # Initial breather before "3"

func _process(delta: float) -> void:
	match state:
		State.COUNTDOWN:
			_process_countdown(delta)
		State.RACING:
			total_time += delta
			current_lap_time += delta
			timer_updated.emit(current_lap_time, total_time)
		State.FINISHED:
			pass

func _process_countdown(delta: float) -> void:
	_countdown_timer -= delta
	if _countdown_timer <= 0.0:
		if _countdown_step == 4:
			_countdown_step = 3
			_countdown_timer = 1.0
			countdown_tick.emit(3)
		elif _countdown_step == 3:
			_countdown_step = 2
			_countdown_timer = 1.0
			countdown_tick.emit(2)
		elif _countdown_step == 2:
			_countdown_step = 1
			_countdown_timer = 1.0
			countdown_tick.emit(1)
		elif _countdown_step == 1:
			_countdown_step = 0
			_countdown_timer = 0.0
			state = State.RACING
			if player_vehicle:
				player_vehicle.set_controls_enabled(true)
			race_started.emit()

func trigger_checkpoint(checkpoint_index: int) -> void:
	if state != State.RACING:
		return
	if checkpoint_index == 0:
		_checkpoints_passed[0] = true
	elif checkpoint_index == 1:
		if _checkpoints_passed[0]:
			_checkpoints_passed[1] = true
	elif checkpoint_index == 2:
		if _checkpoints_passed[1]:
			_checkpoints_passed[2] = true

func trigger_finish_line() -> void:
	if state != State.RACING:
		return
	
	# Must pass all checkpoints around the loop
	if not (_checkpoints_passed[0] and _checkpoints_passed[1] and _checkpoints_passed[2]):
		return
	
	var completed_lap_time: float = current_lap_time
	lap_times.append(completed_lap_time)
	var is_best: bool = false
	if best_lap_time < 0.0 or completed_lap_time < best_lap_time:
		best_lap_time = completed_lap_time
		is_best = true
	
	_checkpoints_passed = [false, false, false]
	
	if current_lap < max_laps:
		var just_finished_lap: int = current_lap
		current_lap += 1
		current_lap_time = 0.0
		lap_completed.emit(just_finished_lap, completed_lap_time, is_best)
		if current_lap == max_laps:
			final_lap_started.emit()
	else:
		state = State.FINISHED
		if player_vehicle:
			player_vehicle.set_controls_enabled(false)
		race_finished.emit(total_time, lap_times, best_lap_time)
