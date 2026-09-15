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

var rivals: Array[AIVehicle] = []
var leaderboard: Array[Dictionary] = []
var _rival_entries: Dictionary = {}

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
	
	_spawn_rivals.call_deferred()
	_start_countdown()

func is_racing() -> bool:
	return state == State.RACING

func _start_countdown() -> void:
	state = State.COUNTDOWN
	_countdown_step = 4
	_countdown_timer = 0.5 # Initial breather before "3"

func _physics_process(delta: float) -> void:
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
		_build_leaderboard()
		state = State.FINISHED
		if player_vehicle:
			player_vehicle.set_controls_enabled(false)
		race_finished.emit(total_time, lap_times, best_lap_time)

func _spawn_rivals() -> void:
	var path := get_node("../TrackPath") as TrackPath
	var api := CarPresets.get_api()
	var cards: Array = api.visitor_cards if api else []
	if cards.is_empty() and (api == null or api.is_mock_mode or not api.is_authenticated):
		cards = RivalRoster.demo_cards(path.curve)
	var roster := RivalRoster.from_visitors(cards, max_laps)
	# Connected sessions with no eligible bumps still have generic practice opponents.
	while roster.size() < RivalRoster.MAX_RIVALS:
		var i := roster.size()
		roster.append({"id": "practice-%d" % i, "display_name": "Practice %d" % (i + 1),
			"color": [Color.SEA_GREEN, Color.MEDIUM_PURPLE, Color.ORANGE][i],
			"car_body": ["truck_green", "truck_purple", "truck_red"][i], "kind": "AI", "ghost": {}})
	for i in range(roster.size()):
		var entry := roster[i]
		var prefab := preload("res://scenes/ghost_vehicle.tscn") if entry.kind == "Ghost" else preload("res://scenes/ai_vehicle.tscn")
		var driver := prefab.instantiate() as AIVehicle
		driver.name = "Rival%d" % i
		driver.rival_id = entry.id
		driver.driver_name = entry.display_name
		driver.rival_color = entry.color
		driver.car_body = entry.car_body
		driver.track_path = path
		driver.max_laps = max_laps
		driver.position = Vector3(2.2 + (i % 2) * 2.6, 0, 3.0 - i * 1.7)
		driver.max_throttle = 0.98 - i * 0.04
		driver.corner_throttle = 0.76 - i * 0.05
		driver.lane_offset = -0.5 if i % 2 == 0 else 0.5
		if driver is GhostDriver:
			driver.recording = entry.ghost
		_rival_entries[entry.id] = entry.duplicate(true)
		_rival_entries[entry.id]["time"] = -1.0
		driver.rival_finished.connect(_on_rival_finished)
		get_parent().add_child(driver)
		driver.setup_nameplate("%s · %s" % [entry.display_name, entry.kind])
		rivals.append(driver)

func _on_rival_finished(rival_id: String, finish_time: float) -> void:
	# Keep results even after the rival's confetti animation frees the vehicle.
	_rival_entries[rival_id]["time"] = finish_time

func _build_leaderboard() -> void:
	var api := CarPresets.get_api()
	var rows: Array[Dictionary] = [{"id": "player", "display_name": api.get_player_display_name() if api else "Player",
		"color": api.get_player_theme_color() if api else Color.GOLD,
		"car_body": CarPresets.get_selected_car(), "kind": "You", "status": "Finished", "time": total_time}]
	for entry in _rival_entries.values():
		var row: Dictionary = entry.duplicate(true)
		row.erase("ghost")
		if entry.kind == "Ghost":
			row.time = float(entry.ghost.total_time_ms) / 1000.0
			row.status = "Recorded"
		elif entry.time >= 0:
			row.status = "Finished"
		else:
			row.status = "Finished"
			for rival in rivals:
				if is_instance_valid(rival) and rival.rival_id == entry.id:
					row.time = rival.estimate_finish_time(total_time)
					break
		rows.append(row)
	leaderboard = RaceStandings.sorted(rows)
