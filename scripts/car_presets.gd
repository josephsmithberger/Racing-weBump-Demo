class_name CarPresets extends RefCounted

const PRESETS: Array[Dictionary] = [
	{
		"id": "truck_yellow",
		"name": "Classic Cab",
		"category": "ALL-ROUNDER",
		"model_path": "res://models/vehicle-truck-yellow.glb",
		"type": "truck",
		"default_color": Color(1.0, 0.70, 0.0), # Amber
		"desc": "Balanced cornering and dependable top speed."
	},
	{
		"id": "truck_red",
		"name": "Sport Racer",
		"category": "HIGH SPEED",
		"model_path": "res://models/vehicle-truck-red.glb",
		"type": "truck",
		"default_color": Color(1.0, 0.09, 0.27), # Racing Red
		"desc": "Aerodynamic chassis tuned for long straights."
	},
	{
		"id": "truck_green",
		"name": "Heavy Hauler",
		"category": "MAX TRACTION",
		"model_path": "res://models/vehicle-truck-green.glb",
		"type": "truck",
		"default_color": Color(0.0, 0.90, 0.46), # Electric Green
		"desc": "Stiff suspension with maximum road grip."
	},
	{
		"id": "truck_purple",
		"name": "Compact Bug",
		"category": "AGILE DRIFT",
		"model_path": "res://models/vehicle-truck-purple.glb",
		"type": "truck",
		"default_color": Color(0.83, 0.0, 0.98), # Neon Purple
		"desc": "Lightweight body with razor-sharp steering."
	},
	{
		"id": "motorcycle",
		"name": "Street Cycle",
		"category": "EXTREME AGILITY",
		"model_path": "res://models/vehicle-motorcycle.glb",
		"type": "motorcycle",
		"default_color": Color(0.0, 0.90, 1.0), # Cyan Blue
		"desc": "Dynamic leaning physics and ultra-tight lines."
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
