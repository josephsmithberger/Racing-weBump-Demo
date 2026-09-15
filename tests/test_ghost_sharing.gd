extends SceneTree
## Results-card sharing flow: godot --headless --fixed-fps 60 --path . --script tests/test_ghost_sharing.gd

var ok := true

func _check(name: String, passed: bool) -> void:
	if not passed:
		push_error("Ghost sharing check failed: " + name)
	ok = ok and passed

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var api := root.get_node("WeBumpAPI")
	api.is_mock_mode = true
	api.local_state.erase("ghost_telemetry")
	var scene: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var manager: RaceManager = scene.get_node("RaceManager")
	var recorder: GhostRecorder = manager.get_node("GhostRecorder")
	var hud: RaceHUD = scene.get_node("RaceHUD")
	_check("share hidden before a race", not hud.share_button.visible)
	manager.state = RaceManager.State.RACING
	manager.race_started.emit()
	manager.player_vehicle.set_controls_enabled(false)
	for i in range(90):
		await physics_frame
	# Not connected: a complete replay is saved locally but cannot be shared.
	manager._build_leaderboard()
	var total := manager.total_time
	manager.race_finished.emit(total, [total / 3.0, total / 3.0, total / 3.0], total / 3.0)
	await process_frame
	_check("complete replay saved", GhostData.is_valid(api.local_state.get("ghost_telemetry"), 3))
	_check("share hidden while disconnected", not hud.share_button.visible and not recorder.can_share_best_ghost())
	# Connected (mock): the explicit button appears and publishes only the declared document.
	api.is_connecting = true
	api._complete_mock_auth()
	manager.race_finished.emit(total, [total / 3.0, total / 3.0, total / 3.0], total / 3.0)
	# The results card appears after the finish banner animation.
	for i in range(900):
		if hud.results_screen.visible and hud.share_button.visible:
			break
		await process_frame
	_check("share offered to connected player", hud.share_button.visible and recorder.can_share_best_ghost())
	var document := recorder.best_ghost()
	_check("declared keys only", document.keys() == GhostData.SHARED_KEYS and document.version == 1 and document.samples.size() >= 2)
	var published: Array = []
	api.shared_data_published.connect(func(value): published.append(value))
	hud._on_share_pressed()
	while api._writing:
		await process_frame
	for i in range(3):
		await process_frame
	_check("publication uses the selected document", published == [document])
	_check("player sees confirmation", recorder.share_message.begins_with("Replay shared") and hud.share_label.visible)
	_check("private save untouched", GhostData.is_valid(api.local_state.get("ghost_telemetry"), 3))
	print("Ghost sharing flow: ", "PASS" if ok else "FAIL")
	scene.queue_free()
	await process_frame
	quit(0 if ok else 1)
