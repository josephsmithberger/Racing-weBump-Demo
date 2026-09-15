extends SceneTree

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	print("--- Running test_title_screen ---")
	var scn = load("res://scenes/title_screen.tscn")
	if not scn:
		push_error("Failed to load title_screen.tscn")
		quit(1)
		return
	
	var inst = scn.instantiate()
	if not inst:
		push_error("Failed to instantiate title_screen.tscn")
		quit(1)
		return
	
	root.add_child(inst)
	# Wait for ready
	await process_frame
	
	print("Title screen instantiated and ready.")
	
	var car_name_label = inst.get_node_or_null("%CarNameLabel")
	assert(car_name_label != null, "CarNameLabel must exist")
	print("Current car name: ", car_name_label.text)
	
	var play_button = inst.get_node_or_null("%PlayButton")
	assert(play_button != null, "PlayButton must exist")
	print("Play button text: ", play_button.text)
	
	# Test cycling cars
	print("Testing car next/prev...")
	inst._on_next_car_pressed()
	print("After next car: ", car_name_label.text)
	inst._on_prev_car_pressed()
	print("After prev car: ", car_name_label.text)
	
	# Test direct car tab selection
	print("Testing car direct tab select...")
	inst._select_car_index(4) # Street Cycle
	print("After tab select index 4: ", car_name_label.text)
	assert(car_name_label.text == "Street Cycle", "Car name should be Street Cycle")
	
	print("--- test_title_screen PASSED ---")
	quit(0)
