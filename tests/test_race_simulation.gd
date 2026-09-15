extends SceneTree
## Full physics smoke test: godot --headless --fixed-fps 60 --path . --script tests/test_race_simulation.gd

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var api := root.get_node("WeBumpAPI")
	api.is_mock_mode = true
	var scene: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var manager: RaceManager = scene.get_node("RaceManager")
	manager.get_node("GhostRecorder").free()
	manager.state = RaceManager.State.RACING
	manager.race_started.emit()
	manager.player_vehicle.set_controls_enabled(false)
	while manager.total_time < 180:
		await physics_frame
		var finished := 0
		for entry in manager._rival_entries.values():
			if entry.time >= 0:
				finished += 1
		if finished == 3:
			break
	manager._build_leaderboard()
	var ok := true
	for entry in manager._rival_entries.values():
		print("%s: %.2f seconds" % [entry.display_name, entry.time])
		ok = ok and entry.time > 0
	print("Full race simulation: ", "PASS" if ok else "FAIL")
	scene.queue_free()
	await process_frame
	quit(0 if ok else 1)
