@tool
class_name RacingBackground extends Control

# Authentic weBump Brand Colors
const COLOR_BRAND_ORANGE: Color = Color(1.0, 0.553, 0.157, 1.0) # #FF8D28
const COLOR_BRAND_PINK: Color = Color(0.922, 0.325, 0.471, 1.0)   # #EB5378
const COLOR_BRAND_BLUE: Color = Color(0.235, 0.561, 0.949, 1.0)   # #3C8FF2
const COLOR_BRAND_GREEN: Color = Color(0.165, 0.690, 0.388, 1.0)  # #2AB063
const COLOR_BRAND_YELLOW: Color = Color(1.0, 0.839, 0.0, 1.0)     # #FFD600

# Dark Theme Base Colors
const COLOR_BG_BASE: Color = Color(0.043, 0.055, 0.086, 1.0)      # #0B0E16
const COLOR_BG_SURFACE: Color = Color(0.067, 0.086, 0.137, 1.0)   # #111623
const COLOR_GRID_LINE: Color = Color(0.10, 0.13, 0.20, 0.35)

# Height of the angled header band the title and the racing stripes sit in.
const HEADER_HEIGHT: float = 88.0

func _ready() -> void:
	resized.connect(queue_redraw)

func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w <= 0.0 or h <= 0.0:
		return
	
	# 1. Base dark background
	draw_rect(Rect2(0, 0, w, h), COLOR_BG_BASE)
	
	# 2. Diagonal racing grid lines (subtle dark slate, no glow)
	var step: float = 48.0
	var offset_x: float = h * 0.25
	var total_lines: int = int((w + offset_x * 2.0) / step) + 4
	for i in range(-4, total_lines):
		var x1: float = float(i) * step
		var y1: float = 0.0
		var x2: float = x1 - offset_x
		var y2: float = h
		draw_line(Vector2(x1, y1), Vector2(x2, y2), COLOR_GRID_LINE, 1.0)
	
	# 3. Bold angled racing band across top header area
	var slant: float = 70.0
	var header_poly: PackedVector2Array = [
		Vector2(0, 0),
		Vector2(w, 0),
		Vector2(w, HEADER_HEIGHT),
		Vector2(0, HEADER_HEIGHT)
	]
	draw_colored_polygon(header_poly, COLOR_BG_SURFACE)
	draw_line(Vector2(0, HEADER_HEIGHT), Vector2(w, HEADER_HEIGHT), Color(0.16, 0.21, 0.32, 0.8), 2.0)
	
	# Diagonal racing stripes accent along top right. Each stripe is a
	# parallelogram rather than a line so both ends are cut square against the
	# band edges: a line's caps sit perpendicular to its slant, which leaves the
	# group of stripes with a ragged staircase top and bottom.
	var start_x: float = w - 420.0
	var stripes: Array[Dictionary] = [
		{"color": COLOR_BRAND_ORANGE, "width": 8.0},
		{"color": COLOR_BRAND_PINK, "width": 6.0},
		{"color": COLOR_BRAND_BLUE, "width": 5.0},
		{"color": COLOR_BRAND_GREEN, "width": 4.0},
		{"color": COLOR_BRAND_YELLOW, "width": 4.0},
	]
	
	# A slanted stripe covers more horizontal room than its own thickness, so
	# widths are stretched to keep the drawn stripe as thick as it looks now.
	var skew: float = slant / HEADER_HEIGHT
	var stretch: float = sqrt(1.0 + skew * skew)
	var cur_x: float = start_x
	for s in stripes:
		var col: Color = s["color"]
		var span: float = float(s["width"]) * stretch
		var stripe: PackedVector2Array = [
			Vector2(cur_x, 0.0),
			Vector2(cur_x + span, 0.0),
			Vector2(cur_x + span - slant, HEADER_HEIGHT),
			Vector2(cur_x - slant, HEADER_HEIGHT),
			Vector2(cur_x, 0.0),
		]
		draw_colored_polygon(stripe, col)
		# 2D MSAA is off, so trace the outline to smooth the diagonal edges.
		draw_polyline(stripe, col, 1.0, true)
		cur_x += span + 5.0
	
	# Sharp bottom racing border line in brand orange
	draw_line(Vector2(0, h - 3), Vector2(w, h - 3), COLOR_BRAND_ORANGE, 3.0)
