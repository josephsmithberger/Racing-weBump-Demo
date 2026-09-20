class_name RivalRoster extends RefCounted
## Convert authorized visitor cards to a bounded race roster. Ghosts take priority.

const MAX_RIVALS := 3

## Live visitor cards supply theme color; optional model fields and older/mock
## cards may omit appearance values. Anyone who does not bring a
## look of their own borrows an unused one from the weBump palette.
const BRAND_COLORS: Array[Color] = [
	RacingBackground.COLOR_BRAND_PINK,
	RacingBackground.COLOR_BRAND_BLUE,
	RacingBackground.COLOR_BRAND_GREEN,
	RacingBackground.COLOR_BRAND_ORANGE,
	RacingBackground.COLOR_BRAND_YELLOW,
]
const BRAND_CAR_BODIES: Array[String] = ["truck_red", "truck_green", "truck_purple", "motorcycle", "truck_yellow"]
## Two paints closer than this read as the same car from the chase camera.
const COLOR_MIN_DISTANCE := 0.35

static func from_visitors(cards: Array, laps: int = 3) -> Array[Dictionary]:
	var rivals: Array[Dictionary] = []
	var seen := {}
	var people := {}
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
		var car_id := str(recording.get("car_body", "")) if has_ghost else str(stats.get("car_body", ""))
		var named := str(card.get("display_name", "")).strip_edges() if card.get("display_name") is String else ""
		var theme := str(card.get("theme_color", "")).strip_edges()
		var entry := {
			"id": reference,
			"display_name": named.substr(0, 48) if not named.is_empty() else "Bump racer",
			"kind": "Ghost" if has_ghost else "AI",
			"ghost": recording.duplicate(true) if has_ghost else {},
		}
		# Only a look the visitor actually published is kept here; the rest is assigned
		# below, once the final three are known and collisions can be seen.
		if _html_is_color(theme):
			var color := Color.from_string(theme, Color.DODGER_BLUE)
			color.a = 1.0
			entry["color"] = color
		if CarPresets.has_preset(car_id):
			entry["car_body"] = car_id
		# Recognition is scoped by the API to this game and recipient. Appearance
		# is never identity. Older cards can only be deduplicated by receipt.
		var visitor: Variant = card.get("visitor_id")
		var person: String = "receipt:" + reference
		if visitor is String and not visitor.is_empty():
			person = "visitor:" + visitor
			entry["visitor_id"] = visitor
		if not person.is_empty() and people.has(person):
			var at: int = people[person]
			if entry.kind == "Ghost" and rivals[at].kind != "Ghost":
				rivals[at] = entry
			continue
		if not person.is_empty():
			people[person] = rivals.size()
		rivals.append(entry)
	rivals.sort_custom(func(a, b): return a.kind == "Ghost" and b.kind != "Ghost")
	rivals = rivals.slice(0, MAX_RIVALS)
	_assign_looks(rivals)
	_unique_names(rivals)
	return rivals

## Connected sessions with no eligible bumps still need a full grid. Practice drivers
## take whatever brand colors and car bodies the real rivals left unused.
static func fill(roster: Array[Dictionary]) -> void:
	while roster.size() < MAX_RIVALS:
		roster.append({"id": "practice-%d" % roster.size(),
			"display_name": "Practice %d" % (roster.size() + 1), "kind": "AI", "ghost": {}})
	_assign_looks(roster)
	_unique_names(roster)

## Fills in every look the visitor cards left open, keeping the grid readable: no two
## rivals, and no rival and the player, end up in the same paint or the same model.
static func _assign_looks(roster: Array[Dictionary]) -> void:
	var player := _player_look()
	var used_colors: Array[Color] = [player.color]
	var used_cars: Array[String] = [player.car_body]
	for entry in roster:
		if entry.has("color"):
			used_colors.append(entry.color)
		if entry.has("car_body"):
			used_cars.append(entry.car_body)
	for entry in roster:
		# Recognition keeps fallback looks steady across repeat receipts.
		var seed_index: int = absi(hash(entry.get("visitor_id", entry.id)))
		if not entry.has("color"):
			entry["color"] = _unused_color(seed_index, used_colors)
			used_colors.append(entry.color)
		if not entry.has("car_body"):
			entry["car_body"] = _unused_car(seed_index, used_cars)
			used_cars.append(entry.car_body)

static func _unused_color(seed_index: int, used: Array[Color]) -> Color:
	for step in BRAND_COLORS.size():
		var candidate: Color = BRAND_COLORS[(seed_index + step) % BRAND_COLORS.size()]
		var clash := false
		for other in used:
			if Vector3(candidate.r - other.r, candidate.g - other.g, candidate.b - other.b).length() < COLOR_MIN_DISTANCE:
				clash = true
				break
		if not clash:
			return candidate
	return BRAND_COLORS[seed_index % BRAND_COLORS.size()]

static func _unused_car(seed_index: int, used: Array[String]) -> String:
	for step in BRAND_CAR_BODIES.size():
		var candidate: String = BRAND_CAR_BODIES[(seed_index + step) % BRAND_CAR_BODIES.size()]
		if not used.has(candidate):
			return candidate
	return BRAND_CAR_BODIES[seed_index % BRAND_CAR_BODIES.size()]

## What the player is driving, so the rivals can avoid it. Unconnected players race the
## preset's own paint, the same color Vehicle applies without a profile.
static func _player_look() -> Dictionary:
	var car := CarPresets.get_selected_car()
	var color: Color = CarPresets.get_preset_by_id(car).get("default_color", Color.GOLD)
	var api := CarPresets.get_api()
	if api and api.is_authenticated:
		color = api.get_player_theme_color()
	return {"color": color, "car_body": car}

## Two people really can share a display name; their nameplates should not.
static func _unique_names(roster: Array[Dictionary]) -> void:
	var counts := {}
	for entry in roster:
		var key: String = entry.display_name.to_lower()
		counts[key] = int(counts.get(key, 0)) + 1
		if counts[key] > 1:
			entry["display_name"] = ("%s %d" % [entry.display_name, counts[key]]).substr(0, 48)

static func _html_is_color(value: String) -> bool:
	# from_string() swallows anything it cannot parse, so ask it twice.
	return not value.is_empty() and Color.from_string(value, Color.BLACK) == Color.from_string(value, Color.WHITE)

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
