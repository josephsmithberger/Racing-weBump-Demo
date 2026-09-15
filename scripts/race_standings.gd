class_name RaceStandings extends RefCounted
## A snapshot at the player's finish: actual, recorded, and estimated times.

static func predict_finish(elapsed: float, progress: float, laps: int, lap_times: Array) -> float:
	var pace := elapsed / maxf(progress, 0.05)
	if not lap_times.is_empty():
		var sum := 0.0
		for lap in lap_times:
			sum += float(lap)
		# Include current slowdowns so a stuck car isn't given an unrealistically fast finish.
		pace = maxf(sum / lap_times.size(), pace)
	return maxf(elapsed + 0.01, elapsed + maxf(0, laps - progress) * pace)

static func sorted(entries: Array[Dictionary]) -> Array[Dictionary]:
	var rows: Array[Dictionary] = entries.duplicate(true)
	rows.sort_custom(func(a, b):
		if is_equal_approx(a.time, b.time):
			return str(a.id) < str(b.id)
		return a.time < b.time
	)
	for i in range(rows.size()):
		rows[i]["position"] = i + 1
	return rows
