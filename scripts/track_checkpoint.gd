class_name TrackCheckpoint extends Area3D

@export var checkpoint_index: int = 0 # 0, 1, 2 for sectors; -1 for Finish Gate
@export var race_manager: RaceManager

func _ready() -> void:
	collision_layer = 0
	collision_mask = 8 # Vehicle Sphere is on collision layer 8
	body_entered.connect(_on_body_entered)
	if race_manager == null:
		race_manager = get_node_or_null("../RaceManager") as RaceManager

func _on_body_entered(body: Node3D) -> void:
	if race_manager == null:
		return
	
	var is_player: bool = false
	if race_manager.player_vehicle != null:
		if body == race_manager.player_vehicle.sphere or body.get_parent() == race_manager.player_vehicle:
			is_player = true
	else:
		if body.get_parent() is Vehicle or body is Vehicle:
			is_player = true
	
	if is_player:
		if checkpoint_index >= 0:
			race_manager.trigger_checkpoint(checkpoint_index)
		else:
			race_manager.trigger_finish_line()
