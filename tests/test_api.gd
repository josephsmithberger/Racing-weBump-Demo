extends SceneTree

class FakeAPI extends "res://scripts/webump_api.gd":
	var requests: Array[String] = []
	var revision := 7
	var fail_write := false
	func _ready() -> void:
		is_mock_mode = false
		is_authenticated = true
	func _save_local_state() -> void:
		pass # Tests never write the player's save file.
	var player_opted_in := true
	var shared_bodies: Array = []
	func _request_json(path: String, method: HTTPClient.Method = HTTPClient.METHOD_GET, payload: Dictionary = {}, etag: String = "") -> Dictionary:
		var verb: String = {HTTPClient.METHOD_GET: "GET ", HTTPClient.METHOD_PUT: "PUT ", HTTPClient.METHOD_DELETE: "DELETE "}.get(method, "POST ")
		requests.append(verb + path)
		await get_tree().process_frame
		if method == HTTPClient.METHOD_GET:
			if path == "/v1/me/permissions":
				return {"ok": true, "status": 200, "data": {"shared_data_sharing": player_opted_in}}
			if path == "/v1/me/visitors/shares/shared":
				return {"ok": true, "status": 200, "data": {"reference": "shares", "data": {"track_id": "demo_loop_v1", "samples": []}, "expires_at": "2026-09-21T00:00:00Z"}}
			if path.ends_with("/shared"):
				return {"ok": false, "status": 410, "data": {"error": "consent_required"}}
			if path == "/v1/me/visitors":
				return {"ok": true, "status": 200, "data": {"visitors": [{"reference": "shares", "display_name": "Rival", "theme_color": "#112233"}, {"reference": "private", "display_name": "Quiet", "theme_color": "#445566"}]}}
			if path.begins_with("/v1/me/visitors/"):
				return {"ok": true, "status": 200, "data": {"reference": path.get_slice("/", 4), "display_name": "Rival", "theme_color": "#112233", "stats": {}}}
			return {"ok": true, "status": 200, "etag": '"%d"' % revision, "data": {"data": {"racing_save": {"best_3lap_ms": 99000}}}}
		if path == "/v1/me/shared" and method == HTTPClient.METHOD_PUT:
			# Mirrors store.ts: publication needs the player's toggle and an explicit publish flag.
			if not player_opted_in or payload.get("publish") != true:
				return {"ok": false, "status": 403, "data": {"error": "consent_required"}}
			shared_bodies.append(payload.value)
		var ok := not fail_write and etag == '"%d"' % revision
		if ok:
			revision += 1
		return {"ok": ok, "status": 200 if ok else 409, "data": {}}

var ok := true

func _check(name: String, passed: bool) -> void:
	if not passed:
		push_error("API contract check failed: " + name)
	ok = ok and passed

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var api := FakeAPI.new()
	root.add_child(api)
	var read: Array = []
	await api.get_state("racing_save", func(ok, value): read.append([ok, value]))
	_check("read state", read[0][0] and read[0][1].best_3lap_ms == 99000)
	api.requests.clear()
	var writes: Array[bool] = []
	api.put_state("ghost_telemetry", {"samples": []}, func(saved, _value): writes.append(saved))
	api.put_state("racing_save", {"best_3lap_ms": 95000}, func(saved, _value): writes.append(saved))
	api.put_capsule({"highscore_seconds": 95}, func(saved, _value): writes.append(saved))
	api.put_showcase({"highscore_seconds": 95}, func(saved, _value): writes.append(saved))
	while api._writing:
		await process_frame
	_check("step 1", writes == [true, true, true, true] and api.revision == 11)
	_check("step 2", api.requests == ["GET /v1/me/state", "PUT /v1/me/state/ghost_telemetry",
		"GET /v1/me/state", "PUT /v1/me/state/racing_save", "GET /v1/me/state", "PUT /v1/me/capsule",
		"GET /v1/me/state", "PUT /v1/me/showcase"])
	api.fail_write = true
	api.put_state("racing_save", {"best_3lap_ms": 90000}, func(saved, _value): writes.append(saved))
	while api._writing:
		await process_frame
	_check("step 3", not writes.back() and api.local_state.racing_save.best_3lap_ms == 90000)
	api.fail_write = false
	# Shared replay: explicit publish flag, declared keys only, and the player's weBump toggle.
	api.requests.clear()
	var document := GhostData.shared_document({"track_id": "demo_loop_v1", "car_body": "truck_red", "lap_count": 3,
		"total_time_ms": 1000, "samples": [[0, 1, 0, 1, 0, 0], [1000, 2, 0, 2, 0.5, 0.1]], "private_note": "never sent"})
	_check("step 4", document.keys() == GhostData.SHARED_KEYS and document.version == 1)
	_check("step 5", GhostData.shared_document({"track_id": "other", "samples": []}).is_empty())
	api.publish_shared_data(document, func(saved, _value): writes.append(saved))
	while api._writing:
		await process_frame
	print("DEBUG writes=", writes, " requests=", api.requests, " bodies=", api.shared_bodies, " status=", api.last_write_status)
	_check("step 6", writes.back() and api.requests == ["GET /v1/me/state", "PUT /v1/me/shared"])
	_check("step 7", api.shared_bodies == [document] and not api.shared_bodies[0].has("private_note"))
	api.player_opted_in = false
	api.publish_shared_data(document, func(saved, _value): writes.append(saved))
	while api._writing:
		await process_frame
	_check("step 8", not writes.back() and api.last_write_status == 403)
	api.requests.clear()
	await api.fetch_permissions()
	_check("step 9", not api.shared_data_sharing and api.requests == ["GET /v1/me/permissions"])
	# Visitor refresh attaches only an authorized game.shared read; 410 rivals race as AI.
	api.set_visitor_cards([{"reference": "shares"}, {"reference": "private"}])
	api.requests.clear()
	await api.refresh_visitors()
	_check("step 10", api.requests == ["GET /v1/me/visitors/shares", "GET /v1/me/visitors/shares/shared",
		"GET /v1/me/visitors/private", "GET /v1/me/visitors/private/shared"])
	_check("step 11", api.visitor_cards.size() == 2 and api.visitor_cards[0].ghost_telemetry.track_id == "demo_loop_v1")
	_check("step 12", not api.visitor_cards[1].has("ghost_telemetry"))
	# Automatic listing: one call for the roster, one per rival for the shared replay.
	api.set_visitor_cards([])
	api.requests.clear()
	await api.load_visitors()
	_check("step 14", api.requests == ["GET /v1/me/visitors", "GET /v1/me/visitors/shares/shared", "GET /v1/me/visitors/private/shared"])
	_check("step 15", api.visitor_cards.size() == 2 and api.visitor_cards[0].has("ghost_telemetry") and not api.visitor_cards[1].has("ghost_telemetry"))
	api.set_visitor_cards([{"reference": "example"}])
	api.disconnect_player()
	_check("step 13", api.visitor_cards.is_empty() and not api.shared_data_sharing)
	print("API contract checks: ", "PASS" if ok else "FAIL")
	api.queue_free()
	await process_frame
	quit(0 if ok else 1)
