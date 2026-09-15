class_name GhostData extends RefCounted
## Shared recording contract. Untrusted or incomplete replays fall back to AI.

const TRACK_ID := "demo_loop_v1"
const MAX_DURATION_MS := 180000
const MAX_SAMPLES := 256
const PAYLOAD_BUDGET := 12000 # Leave room in the shared 16 KiB state document.
const SHARED_VERSION := 1
## Keys declared in docs/shared_data_definition.json. The reviewed game.shared schema
## rejects anything else, so publication strips undeclared keys before sending.
const SHARED_KEYS := ["version", "track_id", "car_body", "lap_count", "total_time_ms", "samples"]

static func is_valid(value: Variant, laps: int = 3) -> bool:
	if not value is Dictionary:
		return false
	if value.get("track_id", TRACK_ID) != TRACK_ID or value.get("lap_count", 0) != laps:
		return false
	var duration: Variant = value.get("total_time_ms", 0)
	if not _number(duration) or duration <= 0 or duration > MAX_DURATION_MS:
		return false
	var samples: Variant = value.get("samples", [])
	if not samples is Array or samples.size() < 2 or samples.size() > MAX_SAMPLES:
		return false
	var previous := -1.0
	for frame in samples:
		if not frame is Array or frame.size() != 6:
			return false
		for component in frame:
			if not _number(component):
				return false
		if frame[0] <= previous or frame[0] < 0 or frame[0] > duration:
			return false
		for axis in range(1, 4):
			if absf(frame[axis]) > 1000.0:
				return false
		previous = frame[0]
	# Reject old recordings truncated by the AFK cutoff; don't teleport to a finish.
	return samples[0][0] <= 100 and duration - previous <= 100

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func compact(payload: Dictionary) -> Dictionary:
	var result := payload.duplicate(true)
	var samples: Array = result.get("samples", [])
	while samples.size() > MAX_SAMPLES or JSON.stringify(result).to_utf8_buffer().size() > PAYLOAD_BUDGET:
		if samples.size() <= 2:
			return {}
		var reduced: Array = []
		for i in range(0, samples.size() - 1, 2):
			reduced.append(samples[i])
		reduced.append(samples.back())
		samples = reduced
		result["samples"] = samples
	return result

## The exact document sent to PUT /v1/me/shared. Empty when the recording is not shareable.
static func shared_document(recording: Variant, laps: int = 3) -> Dictionary:
	if not is_valid(recording, laps) or not CarPresets.has_preset(str(recording.get("car_body", ""))):
		return {}
	var document := {"version": SHARED_VERSION, "track_id": TRACK_ID}
	for key in SHARED_KEYS:
		if recording.has(key):
			document[key] = recording[key]
	if document.get("version", SHARED_VERSION) != SHARED_VERSION:
		return {}
	return document.duplicate(true)
