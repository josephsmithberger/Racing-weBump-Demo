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
	func _request_json(path: String, method: HTTPClient.Method = HTTPClient.METHOD_GET, _payload: Dictionary = {}, etag: String = "") -> Dictionary:
		requests.append(("GET " if method == HTTPClient.METHOD_GET else "PUT ") + path)
		await get_tree().process_frame
		if method == HTTPClient.METHOD_GET:
			return {"ok": true, "status": 200, "etag": '"%d"' % revision, "data": {"data": {"racing_save": {"best_3lap_ms": 99000}}}}
		var ok := not fail_write and etag == '"%d"' % revision
		if ok:
			revision += 1
		return {"ok": ok, "status": 200 if ok else 409, "data": {}}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var api := FakeAPI.new()
	root.add_child(api)
	var read: Array = []
	await api.get_state("racing_save", func(ok, value): read.append([ok, value]))
	var ok: bool = read[0][0] and read[0][1].best_3lap_ms == 99000
	api.requests.clear()
	var writes: Array[bool] = []
	api.put_state("ghost_telemetry", {"samples": []}, func(saved, _value): writes.append(saved))
	api.put_state("racing_save", {"best_3lap_ms": 95000}, func(saved, _value): writes.append(saved))
	api.put_capsule({"highscore_seconds": 95}, func(saved, _value): writes.append(saved))
	api.put_showcase({"highscore_seconds": 95}, func(saved, _value): writes.append(saved))
	while api._writing:
		await process_frame
	ok = ok and writes == [true, true, true, true] and api.revision == 11
	ok = ok and api.requests == ["GET /v1/me/state", "PUT /v1/me/state/ghost_telemetry",
		"GET /v1/me/state", "PUT /v1/me/state/racing_save", "GET /v1/me/state", "PUT /v1/me/capsule",
		"GET /v1/me/state", "PUT /v1/me/showcase"]
	api.fail_write = true
	api.put_state("racing_save", {"best_3lap_ms": 90000}, func(saved, _value): writes.append(saved))
	while api._writing:
		await process_frame
	ok = ok and not writes.back() and api.local_state.racing_save.best_3lap_ms == 90000
	api.set_visitor_cards([{"reference": "example"}])
	api.disconnect_player()
	ok = ok and api.visitor_cards.is_empty()
	print("API contract checks: ", "PASS" if ok else "FAIL")
	api.queue_free()
	await process_frame
	quit(0 if ok else 1)
