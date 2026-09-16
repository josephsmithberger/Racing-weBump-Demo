extends SceneTree
## Run: godot --headless --path . --script tests/test_racing.gd

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var track := TrackPath.new()
	var cards := RivalRoster.demo_cards(track.curve)
	var ghost: Dictionary = cards[0].ghost_telemetry
	check(GhostData.is_valid(ghost), "Mock ghost must cover all three laps")
	var broken := ghost.duplicate(true)
	broken.samples[-1][0] = 90000
	check(not GhostData.is_valid(broken), "Truncated ghosts must fall back to AI")
	broken = ghost.duplicate(true)
	broken.samples[1][0] = 0
	check(not GhostData.is_valid(broken), "Duplicate timestamps must be rejected")
	broken = ghost.duplicate(true)
	broken.samples[1][2] = NAN
	check(not GhostData.is_valid(broken), "Non-finite telemetry must be rejected")
	broken = ghost.duplicate(true)
	broken.track_id = "different-track"
	check(not GhostData.is_valid(broken), "Wrong track must fall back to AI")
	var large := ghost.duplicate(true)
	large.samples = []
	for i in range(2701):
		large.samples.append([roundi(96000.0 * i / 2700.0), -18.73, 0.65, 18.73, 3.14, 0.01])
	var compact := GhostData.compact(large)
	check(GhostData.is_valid(compact), "Decimation must preserve endpoints")
	check(JSON.stringify(compact).to_utf8_buffer().size() <= GhostData.PAYLOAD_BUDGET, "Recording must fit byte budget")
	var roster := RivalRoster.from_visitors([cards[1], cards[2], cards[0], cards[0], null])
	check(roster.size() == 3 and roster[0].kind == "Ghost", "Deduplicate and prioritize ghosts")
	check(roster[0].car_body == "truck_red" and roster[0].color == Color("#FF3366"), "Use recorded car and visitor theme")
	check(RaceStandings.predict_finish(60, 2, 3, [30]) == 90, "Project AI from observed lap pace")
	check(RaceStandings.predict_finish(120, 2.9, 3, [30, 30]) > 120, "Unfinished AI cannot rank ahead of a finished player")
	track.free()

	var api := root.get_node("WeBumpAPI")
	api.is_mock_mode = true
	api.set_visitor_cards(cards)
	var scene: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var manager: RaceManager = scene.get_node("RaceManager")
	# Integration checks never persist a simulated player race.
	manager.get_node("GhostRecorder").free()
	manager.set_physics_process(false)
	check(manager.rivals.size() == 3, "Spawn exactly the available rival slots")
	var replay := manager.rivals[0] as GhostDriver
	check(replay != null, "A valid bump recording must replace the AI driver")
	if replay:
		check(replay.nameplate_label.text == "Maya - Ghost", "Nameplate must identify the bump and driver")
		check(replay.current_preset_id == "truck_red", "Replay must use the recorded model")
		check(replay._paint_material.get_shader_parameter("paint_color") == Color("#FF3366"), "Replay must use the bump's paint")
		replay._apply_frame(48000, 0)
		var sample: Array = ghost.samples[120]
		check(replay.get_vehicle_position().distance_to(Vector3(sample[1], sample[2], sample[3])) < 0.01, "Replay must follow recorded positions")
		check(replay.sphere.freeze and replay.sphere.collision_layer == 0, "Ghost must not interact with physics")
	var ai := manager.rivals[1]
	check(ai.is_motorcycle, "AI must support bump motorcycle models")
	manager.total_time = 75
	manager._on_rival_finished(ai.rival_id, 70)
	ai.queue_free()
	await process_frame
	manager.rivals[2].race_progress = 2.0
	manager._build_leaderboard()
	check(manager.leaderboard.size() == 4, "Leaderboard must retain freed finishers")
	check(manager.leaderboard[0].time == 70 and manager.leaderboard[1].id == "player", "Sort actual finish times")
	check(manager.leaderboard[2].time == 96 and manager.leaderboard[2].status == "Recorded", "Use exact ghost duration")
	check(manager.leaderboard[3].status == "Finished", "Unfinished AI given finished score")
	var hud: RaceHUD = scene.get_node("RaceHUD")
	hud._show_results(75, [26, 25, 24], 24)
	await process_frame
	check(hud.leaderboard_rows.get_child_count() == 4, "Render a row for every entrant")
	if "--visual" in OS.get_cmdline_user_args():
		await create_timer(1).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/webump-leaderboard.png")
	print("Racing checks: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	scene.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
