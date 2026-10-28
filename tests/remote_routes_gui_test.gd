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
	if not check(hud.shown == train and hud.supply.visible,"Train selection did not open delivery panel"): return
	if not check(hud.route_depots.has(source) and hud.route_depots.has(target) and not hud.supply.get_node("StartRoute").disabled,"Global endpoints unavailable with cut rails"): return
	hud.supply.get_node("Source").select(hud.route_depots.find(source))
	hud.supply.get_node("Destination").select(hud.route_depots.find(target))
	var balance: int = source.energy
	await click(hud.supply.get_node("StartRoute"))
	if not check(train.route_active and train.waiting_for_rail and source.energy == balance and game.message.contains("waiting for friendly rails"),"Assign click rejected disconnected route or transferred early"): return
	if not check(hud.supply.get_node("RouteStatus").text.contains("waiting for friendly rails"),"HUD did not explain accepted waiting route"): return
	await click(hud.supply.get_node("PauseRoute"))
	if not check(train.route_paused,"Pause click failed on queued route"): return
	await click(hud.supply.get_node("PauseRoute"))
	if not check(not train.route_paused and train.waiting_for_rail,"Resume should resume waiting before initial rail connection"): return
	await click(hud.supply.get_node("CancelRoute"))
	if not check(not train.route_active and not train.waiting_for_rail,"Cancel click retained queued route state"): return
	await click(hud.supply.get_node("StartRoute"))
	var replacement = rails.segment_scene.instantiate()
	replacement.assigned_depot = payer; replacement.position = game.ground.tile_to_world(gap)
	game.add_child(replacement)
	train._process(0.1)
	if not check(not train.waiting_for_rail and not train.route_paused,"Initial connection did not release queued route"): return
	# Invalid requests display the concrete cause and preserve the accepted route.
	hud.supply.get_node("Amounts/Energy").value = 1000
	await click(hud.supply.get_node("StartRoute"))
	if not check(game.message.contains("capacity") and train.route_active and train.requested_energy == 60,"Invalid GUI assignment changed route or hid its reason: "+game.message): return
	print("REMOTE_ROUTES_GUI_CHECKS_PASSED")
	quit()
