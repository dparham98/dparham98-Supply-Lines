extends "res://tests/remote_routes_gui_test.gd"
func right_at(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion,true)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT; event.pressed = true; event.position = point
	root.push_input(event,true)
	for frame in range(3): await process_frame
	event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT; event.pressed = false; event.position = point
	root.push_input(event,true)
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/all_sides_exercise.tscn").instantiate()
	root.add_child(game)
	for frame in range(4): await process_frame
	hud = game.get_node("Interface")
	game.set_process(false)
	for group in ["units","depots","resources"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	var source = game.get_node("Entities/Resources/DemoWood")
	var depot = game.get_node("Entities/Buildings/WorkshopDepot")
	var rig = game.get_node("CameraRig")
	rig.set_process(false)
	for frame in range(180): rig.advance_camera(1.0/60)
	var camera: Camera3D = rig.camera
	var meshes: Array = preload("res://scripts/units/selection_bounds.gd").meshes(source)
	var source_point: Vector3 = meshes[0].global_transform*meshes[0].get_aabb().get_center()
	var delivered := 0
	for pair in [["EastHarvester",1],["WestHarvester",-1]]:
		var worker = game.get_node("Entities/Units/"+pair[0])
		await click_at(camera.unproject_position(worker.selection_point()))
		if not check(worker.is_selected,"World click did not select "+pair[0]): return
		await right_at(camera.unproject_position(source_point))
		if not check(worker.order == "gather" and worker.source == source,"Resource model click did not order harvesting"): return
		for frame in range(3000):
			worker._process(1.0/60)
			if worker.cargo == 10: break
		if not check(worker.cargo == 10 and (worker.global_position.x-source.global_position.x)*pair[1] > 0,"Clicked harvest order crossed to far side"): return
		var edge: Vector3 = depot.global_position+Vector3(pair[1]*3.8,0.4,3.8)
		await right_at(camera.unproject_position(edge))
		if not check(worker.order == "return" and worker.return_depot == depot and worker.return_explicit,"Depot edge click failed to order explicit delivery"): return
		for frame in range(3000):
			worker._process(1.0/60)
			if worker.cargo == 0: break
		delivered += 10
		if not check(worker.cargo == 0 and depot.wood == delivered,"Clicked all-side delivery failed conservation"): return
	if not check(source.remaining == 20 and game.wood_delivered == 20,"Two-sided GUI harvest/delivery accounting failed"): return
	print("ALL_SIDES_GUI_CHECKS_PASSED")
	quit()
