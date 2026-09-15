extends SceneTree

const VirtualJoysticksScript = preload("res://scripts/virtual_joysticks.gd")

var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: %s" % message)
	else:
		print("  ✓ %s" % message)

func _run() -> void:
	print("--- Running test_virtual_joysticks ---")
	
	# 1. Test standalone scene instantiation
	var scn: PackedScene = load("res://scenes/virtual_joysticks.tscn")
	check(scn != null, "virtual_joysticks.tscn must load")
	
	var inst: CanvasLayer = scn.instantiate() as CanvasLayer
	check(inst != null, "virtual_joysticks.tscn must instantiate")
	
	var left_vj: VirtualJoystick = inst.get_node_or_null("LeftJoystick") as VirtualJoystick
	var right_vj: VirtualJoystick = inst.get_node_or_null("RightJoystick") as VirtualJoystick
	check(left_vj != null, "LeftJoystick must exist and be VirtualJoystick")
	check(right_vj != null, "RightJoystick must exist and be VirtualJoystick")
	
	if left_vj:
		check(left_vj.action_left == &"left", "LeftJoystick action_left must be 'left'")
		check(left_vj.action_right == &"right", "LeftJoystick action_right must be 'right'")
		check(left_vj.action_up == &"none", "LeftJoystick action_up must be 'none'")
		check(left_vj.action_down == &"none", "LeftJoystick action_down must be 'none'")
	
	if right_vj:
		check(right_vj.action_left == &"none", "RightJoystick action_left must be 'none'")
		check(right_vj.action_right == &"none", "RightJoystick action_right must be 'none'")
		check(right_vj.action_up == &"forward", "RightJoystick action_up must be 'forward'")
		check(right_vj.action_down == &"back", "RightJoystick action_down must be 'back'")
	
	# 2. Test desktop mode (should auto-remove when force_mobile is false)
	inst.set("force_mobile", false)
	root.add_child(inst)
	await process_frame
	await process_frame
	check(not is_instance_valid(inst) or inst.is_queued_for_deletion() or not inst.is_inside_tree(), "VirtualJoysticks must auto-free on desktop non-mobile")
	if is_instance_valid(inst) and inst.is_inside_tree():
		inst.queue_free()
	await process_frame
	
	# 3. Test mobile mode with force_mobile = true
	var mobile_inst: CanvasLayer = scn.instantiate() as CanvasLayer
	mobile_inst.set("force_mobile", true)
	root.add_child(mobile_inst)
	await process_frame
	await process_frame
	check(mobile_inst.is_inside_tree() and not mobile_inst.is_queued_for_deletion(), "VirtualJoysticks must stay in tree when mobile")
	
	var m_left: VirtualJoystick = mobile_inst.get("left_joystick") as VirtualJoystick
	var m_right: VirtualJoystick = mobile_inst.get("right_joystick") as VirtualJoystick
	check(m_left != null and m_right != null, "Joysticks must be accessible on mobile instance")
	
	# Test touch drag on LeftJoystick (Steering)
	var left_center: Vector2 = m_left.global_position + m_left.size * 0.5
	var touch_l := InputEventScreenTouch.new()
	touch_l.index = 0
	touch_l.position = left_center
	touch_l.pressed = true
	root.push_input(touch_l)
	
	var drag_l := InputEventScreenDrag.new()
	drag_l.index = 0
	drag_l.position = left_center + Vector2(60, 0) # Drag right
	root.push_input(drag_l)
	await process_frame
	
	check(Input.get_axis("left", "right") > 0.3, "Steering axis must respond to LeftJoystick right drag")
	
	touch_l.pressed = false
	root.push_input(touch_l)
	await process_frame
	check(abs(Input.get_axis("left", "right")) < 0.01, "Steering axis must return to neutral on release")
	
	# Test touch drag on RightJoystick (Throttle)
	var right_center: Vector2 = m_right.global_position + m_right.size * 0.5
	var touch_r := InputEventScreenTouch.new()
	touch_r.index = 1
	touch_r.position = right_center
	touch_r.pressed = true
	root.push_input(touch_r)
	
	var drag_r := InputEventScreenDrag.new()
	drag_r.index = 1
	drag_r.position = right_center + Vector2(0, -60) # Drag up (forward)
	root.push_input(drag_r)
	await process_frame
	
	check(Input.get_axis("back", "forward") > 0.3, "Throttle axis must respond to RightJoystick up drag")
	
	touch_r.pressed = false
	root.push_input(touch_r)
	await process_frame
	check(abs(Input.get_axis("back", "forward")) < 0.01, "Throttle axis must return to neutral on release")
	
	# Test race finished hiding
	mobile_inst.call("_on_race_finished", 60.0)
	check(mobile_inst.visible == false, "VirtualJoysticks must hide when race finishes")
	
	mobile_inst.queue_free()
	await process_frame
	
	# 4. Verify title_screen.tscn does NOT contain any VirtualJoystick
	var title_scn: PackedScene = load("res://scenes/title_screen.tscn")
	var title_inst: Node = title_scn.instantiate()
	var vj_in_title: Array = title_inst.find_children("*", "VirtualJoystick", true, false)
	check(vj_in_title.is_empty(), "title_screen.tscn must NOT contain any VirtualJoystick nodes")
	title_inst.free()
	
	# 5. Verify main.tscn contains VirtualJoysticks and VirtualJoystick nodes
	var main_scn: PackedScene = load("res://scenes/main.tscn")
	check(main_scn != null, "main.tscn must load")
	var main_inst: Node = main_scn.instantiate()
	check(main_inst != null, "main.tscn must instantiate")
	
	var vj_node: Node = main_inst.get_node_or_null("VirtualJoysticks")
	check(vj_node != null, "main.tscn must have VirtualJoysticks node")
	if vj_node:
		var left_child = vj_node.get_node_or_null("LeftJoystick")
		var right_child = vj_node.get_node_or_null("RightJoystick")
		check(left_child is VirtualJoystick, "main.tscn VirtualJoysticks must have LeftJoystick (VirtualJoystick)")
		check(right_child is VirtualJoystick, "main.tscn VirtualJoysticks must have RightJoystick (VirtualJoystick)")
	
	# When main.tscn is added to tree on desktop, VirtualJoysticks should auto-free
	root.add_child(main_inst)
	await process_frame
	await process_frame
	var vj_after = main_inst.get_node_or_null("VirtualJoysticks")
	check(vj_after == null or vj_after.is_queued_for_deletion(), "VirtualJoysticks in main.tscn must auto-free on desktop")
	main_inst.queue_free()
	await process_frame
	
	print("--- test_virtual_joysticks result: %s ---" % ("PASS" if failures == 0 else "%d FAILURES" % failures))
	quit(0 if failures == 0 else 1)
