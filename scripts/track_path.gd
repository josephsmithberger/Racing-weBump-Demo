class_name TrackPath extends Path3D

func _init() -> void:
	if curve == null or curve.point_count == 0:
		build_track_curve()

func _ready() -> void:
	if curve == null or curve.point_count == 0:
		build_track_curve()

func build_track_curve() -> void:
	var c = Curve3D.new()
	var pts: Array[Vector3] = [
		Vector3(3.75, 0.0, 3.75),
		Vector3(3.75, 0.0, 11.24),
		Vector3(3.75, 0.0, 15.0),
		Vector3(2.65, 0.0, 17.65),
		Vector3(0.0, 0.0, 18.73),
		Vector3(-3.75, 0.0, 18.73),
		Vector3(-7.5, 0.0, 18.73),
		Vector3(-10.15, 0.0, 17.65),
		Vector3(-11.24, 0.0, 15.0),
		Vector3(-11.24, 0.0, 11.24),
		Vector3(-11.24, 0.0, 3.75),
		Vector3(-11.24, 0.0, 0.0),
		Vector3(-12.35, 0.0, -2.65),
		Vector3(-15.0, 0.0, -3.75),
		Vector3(-17.65, 0.0, -4.85),
		Vector3(-18.73, 0.0, -7.5),
		Vector3(-18.73, 0.0, -11.24),
		Vector3(-18.73, 0.0, -15.0),
		Vector3(-17.65, 0.0, -17.65),
		Vector3(-15.0, 0.0, -18.73),
		Vector3(-11.24, 0.0, -18.73),
		Vector3(-3.75, 0.0, -18.73),
		Vector3(0.0, 0.0, -18.73),
		Vector3(2.65, 0.0, -17.65),
		Vector3(3.75, 0.0, -15.0),
		Vector3(3.75, 0.0, -11.24),
		Vector3(3.75, 0.0, -3.75),
	]
	for p in pts:
		c.add_point(p)
	c.add_point(pts[0])
	curve = c
