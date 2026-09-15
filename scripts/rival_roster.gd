class_name RivalRoster extends RefCounted
## Convert authorized visitor cards to a bounded race roster. Ghosts take priority.

const MAX_RIVALS := 3

static func from_visitors(cards: Array, laps: int = 3) -> Array[Dictionary]:
	var rivals: Array[Dictionary] = []
	var seen := {}
	for card in cards:
		if not card is Dictionary:
			continue
		var reference: Variant = card.get("reference", "")
		if not reference is String or reference.is_empty() or seen.has(reference):
			continue
		seen[reference] = true
		# ghost_telemetry is that rival's own game.shared publication (or a host adapter's
		# authorized copy), fetched separately by reference. Never private visitor state.
		var recording: Variant = card.get("ghost_telemetry", {})
		var has_ghost := GhostData.is_valid(recording, laps)
		var stats: Variant = card.get("stats", {})
		if not stats is Dictionary:
			stats = {}
		var car_id := str(recording.get("car_body", "truck_yellow")) if has_ghost else str(stats.get("car_body", "truck_yellow"))
		var display_name: Variant = card.get("display_name")
		if not display_name is String or display_name.strip_edges().is_empty():
			display_name = "Bump racer"
		var color := Color.from_string(str(card.get("theme_color", "")), Color.DODGER_BLUE)
		color.a = 1.0
		rivals.append({
			"id": reference, "display_name": display_name.substr(0, 48),
			"color": color, "car_body": car_id if CarPresets.has_preset(car_id) else "truck_yellow",
			"kind": "Ghost" if has_ghost else "AI",
			"ghost": recording.duplicate(true) if has_ghost else {},
		})
	rivals.sort_custom(func(a, b): return a.kind == "Ghost" and b.kind != "Ghost")
	return rivals.slice(0, MAX_RIVALS)

static func demo_cards(curve: Curve3D) -> Array:
	# Synthetic full-race recording: reproducible and playable without an account.
	var samples: Array = []
	var duration := 96000
	var finish_offset := curve.get_closest_offset(Vector3(3.75, 0, 1.5))
	var start_offset := curve.get_closest_offset(Vector3(3.5, 0, 5))
	var distance := 2.0 * curve.get_baked_length() + fposmod(finish_offset - start_offset, curve.get_baked_length())
	for i in range(241):
		var offset := start_offset + distance * float(i) / 240.0
		var pos := curve.sample_baked(fposmod(offset, curve.get_baked_length()), true)
		var next := curve.sample_baked(fposmod(offset + 0.2, curve.get_baked_length()), true)
		var yaw := atan2(next.x - pos.x, next.z - pos.z)
		samples.append([roundi(float(duration) * i / 240.0), snappedf(pos.x, 0.01), 0.0, snappedf(pos.z, 0.01), snappedf(yaw, 0.01), 0.0])
	return [
		{"reference": "demo-maya", "display_name": "Maya", "theme_color": "#FF3366", "ghost_telemetry": {
			"track_id": GhostData.TRACK_ID, "car_body": "truck_red", "lap_count": 3, "total_time_ms": duration, "samples": samples}},
		{"reference": "demo-liam", "display_name": "Liam", "theme_color": "#00E5FF", "stats": {"car_body": "motorcycle"}},
		{"reference": "demo-sam", "display_name": "Sam", "theme_color": "#FFB800", "stats": {"car_body": "truck_purple"}},
	]
