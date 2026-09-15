extends SceneTree

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var scn = load("res://scenes/title_screen.tscn")
	var inst = scn.instantiate()
	root.add_child(inst)
	
	# Select Classic Cab
	inst._select_car_index(0)
	
	for i in range(12):
		await process_frame
	
	var img = root.get_texture().get_image()
	if img:
		var err = img.save_png("title_screen_preview.png")
		print("Saved screenshot with code: ", err)
	
	quit(0)
