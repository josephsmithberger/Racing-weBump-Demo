class_name CarPresets extends RefCounted

const PRESETS: Array[Dictionary] = [
	{
		"id": "truck_yellow",
		"name": "Classic Cab",
		"model_path": "res://models/vehicle-truck-yellow.glb",
		"type": "truck",
		"default_color": Color(1.0, 0.70, 0.0), # Amber
		"paint_cell": Vector2i(7, 2) # Orange paint swatch
	},
	{
		"id": "truck_red",
		"name": "Sport Racer",
		"model_path": "res://models/vehicle-truck-red.glb",
		"type": "truck",
		"default_color": Color(1.0, 0.09, 0.27), # Racing Red
		"paint_cell": Vector2i(11, 2) # Pink paint swatch
	},
	{
		"id": "truck_green",
		"name": "Heavy Hauler",
		"model_path": "res://models/vehicle-truck-green.glb",
		"type": "truck",
		"default_color": Color(0.0, 0.90, 0.46), # Electric Green
		"paint_cell": Vector2i(1, 3) # Green paint swatch
	},
	{
		"id": "truck_purple",
		"name": "Compact Bug",
		"model_path": "res://models/vehicle-truck-purple.glb",
		"type": "truck",
		"default_color": Color(0.83, 0.0, 0.98), # Neon Purple
		"paint_cell": Vector2i(1, 1) # Blue paint swatch
	},
	{
		"id": "motorcycle",
		"name": "Street Cycle",
		"model_path": "res://models/vehicle-motorcycle.glb",
		"type": "motorcycle",
		"default_color": Color(0.0, 0.90, 1.0), # Cyan Blue
		"paint_cell": Vector2i(1, 3) # Green paint swatch
	}
]

static func get_preset_by_id(id: String) -> Dictionary:
	for p in PRESETS:
		if p["id"] == id:
			return p
	return PRESETS[0]

static func get_preset_index(id: String) -> int:
	for i in range(PRESETS.size()):
		if PRESETS[i]["id"] == id:
			return i
	return 0

static func has_preset(id: String) -> bool:
	for p in PRESETS:
		if p["id"] == id:
			return true
	return false

# Every vehicle shares one palette texture, laid out as a grid of swatches. A model's
# painted body panels all sample a single swatch, so recoloring keys off that swatch's
# UV rectangle - exact whatever the palette hue, and identical on every renderer.
const PALETTE_GRID := Vector2i(16, 4)

static func paint_region(preset: Dictionary) -> Vector4:
	var cell: Vector2i = preset.get("paint_cell", Vector2i(7, 2))
	var w := 1.0 / float(PALETTE_GRID.x)
	var h := 1.0 / float(PALETTE_GRID.y)
	return Vector4(cell.x * w, cell.y * h, (cell.x + 1) * w, (cell.y + 1) * h)

const SELECTION_FILE_PATH: String = "user://selected_car.txt"
static var _active_car_id: String = ""

static func get_selected_car() -> String:
	# 1. In-memory static cache
	if _active_car_id != "" and has_preset(_active_car_id):
		return _active_car_id
	
	# 2. Standalone selection file
	if FileAccess.file_exists(SELECTION_FILE_PATH):
		var f = FileAccess.open(SELECTION_FILE_PATH, FileAccess.READ)
		if f:
			var txt = f.get_as_text().strip_edges()
			if txt != "" and has_preset(txt):
				_active_car_id = txt
				return _active_car_id
	
	# 3. webump_state.json fallback
	if FileAccess.file_exists("user://webump_state.json"):
		var f = FileAccess.open("user://webump_state.json", FileAccess.READ)
		if f:
			var parsed = JSON.parse_string(f.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY and parsed.has("selected_car_body"):
				var cid = str(parsed["selected_car_body"]).strip_edges()
				if cid != "" and has_preset(cid):
					_active_car_id = cid
					return _active_car_id
	
	_active_car_id = "truck_yellow"
	return _active_car_id

static func set_selected_car(id: String) -> void:
	if not has_preset(id):
		push_warning("[CarPresets] Unknown preset id: %s" % id)
		return
	
	_active_car_id = id
	
	# 1. Persist to standalone file
	var f = FileAccess.open(SELECTION_FILE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(id)
	
	# 2. Persist to webump_state.json
	var state: Dictionary = {}
	if FileAccess.file_exists("user://webump_state.json"):
		var rf = FileAccess.open("user://webump_state.json", FileAccess.READ)
		if rf:
			var parsed = JSON.parse_string(rf.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				state = parsed
	state["selected_car_body"] = id
	var wf = FileAccess.open("user://webump_state.json", FileAccess.WRITE)
	if wf:
		wf.store_string(JSON.stringify(state, "  "))
	
	# 3. Inform WeBumpAPI
	var api = get_api()
	if api:
		if api.get("selected_car_body") != id:
			api.set("selected_car_body", id)
			if api.has_signal("car_body_changed"):
				api.emit_signal("car_body_changed", id)
	
	print("[CarPresets] Active car updated to: '%s'" % id)

static func get_api(caller: Node = null) -> Node:
	var tree := caller.get_tree() if caller and caller.is_inside_tree() else Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("WeBumpAPI") if tree else null
