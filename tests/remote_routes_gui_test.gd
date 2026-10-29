extends "res://tests/hud_click_test.gd"
func click(control: Control) -> void:
	var previous := Rect2()
	var stable := 0
	for i in range(30):
		await process_frame
		var rect := control.get_global_rect()
		stable = stable+1 if rect == previous and control.is_visible_in_tree() else 0
		previous = rect
		if stable >= 3: break
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	await click_at(control.get_global_rect().get_center())
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/rail_exercise.tscn").instantiate()
	root.add_child(game)
	for i in range(4): await process_frame
	hud = game.get_node("Interface")
	game.set_process(false)
	for group in ["units","depots"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	var train = game.get_node("Entities/Units/Train")
	var source = game.depot
	var target = game.get_node("Entities/Buildings/EastDepot")
	var rig = game.get_node("CameraRig")
	rig.set_process(false)
	rig.focus_position(train.global_position)
	for i in range(180): rig.advance_camera(1.0/60)
	var rails = game.get_node("RailNetwork")
	var gap := Vector2i(435,406)
	var payer = rails.segments[gap].assigned_depot
	rails.segments[gap].free()
	await click_at(rig.camera.unproject_position(train.selection_point()))
	if not check(hud.shown == train and hud.card.get_node("Load").visible and hud.card.get_node("Unload").visible,"Train selection did not show crate tiles"): return
	# Crate shipments replaced the route panel: stops are chosen from the HUD's distant-stop list.
	source.energy = 100
	source.stockpile.pack(&"energy"); source.stockpile.pack(&"energy")
	var delivered: int = target.stockpile.amount(&"energy")
	await click(hud.card.get_node("Load"))
	if not check(game.pending_unit_command == "load" and hud.shipment_target.visible and hud.shipment_stops.has(source) and hud.shipment_stops.has(target),"Distant stops unavailable with cut rails"): return
	hud.shipment_target.item_selected.emit(hud.shipment_stops.find(source)+1)
	if not check(train.order == "load" and train.job_target == source and game.pending_unit_command.is_empty(),"Distant Load not ordered"): return
	await click(hud.card.get_node("Unload"))
	var shift := InputEventKey.new()
	shift.keycode = KEY_SHIFT; shift.physical_keycode = KEY_SHIFT; shift.pressed = true
	Input.parse_input_event(shift); Input.flush_buffered_events()
	hud.shipment_target.item_selected.emit(hud.shipment_stops.find(target)+1)
	shift.pressed = false
	Input.parse_input_event(shift); Input.flush_buffered_events()
	if not check(train.order_queue.size() == 1 and train.order_queue[0].kind == "unload" and train.order_queue[0].target == target,"Shift distant Unload not queued"): return
	game.pending_unit_command = ""
	# The pickup is reachable; the delivery waits for the cut rails without losing crates.
	for i in range(60*30):
		train._process(1.0/60)
		if train.order == "unload": break
	if not check(train.order == "unload" and train.stockpile.crate_count(&"energy") == 2 and source.stockpile.crate_count() == 0,"Train did not load the crates"): return
	for i in range(60*5): train._process(1.0/60)
	if not check(train.state.contains("blocked") and train.stockpile.crate_count() == 2 and target.stockpile.amount(&"energy") == delivered,"Cut rails did not hold the delivery"): return
	var replacement = rails.segment_scene.instantiate()
	replacement.assigned_depot = payer; replacement.position = game.ground.tile_to_world(gap)
	game.add_child(replacement)
	for i in range(60*60):
		train._process(1.0/60)
		if train.order == "idle": break
	if not check(train.order == "idle" and target.stockpile.amount(&"energy") == delivered+50 and train.stockpile.total() == 0,"Repaired rails did not complete the delivery"): return
	# Trains only stop at Depots: a deployed truck is not offered or accepted.
	var truck = load("res://scenes/gameplay/cargo_vehicle.tscn").instantiate()
	truck.position = source.global_position+Vector3(-10,0,8)
	game.get_node("Entities/Units").add_child(truck); truck.set_process(false)
	truck.deployed = true
	train.command_load(truck)
	if not check(train.order == "idle" and game.message.contains("friendly Depot"),"Train accepted a deployed truck as a stop"): return
	print("REMOTE_ROUTES_GUI_CHECKS_PASSED")
	quit()
