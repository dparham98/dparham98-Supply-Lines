extends "res://tests/hud_click_test.gd"
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	hud = game.get_node("Interface")
	for i in range(4): await process_frame
	for unit in get_nodes_in_group("units"): unit.set_process(false); unit.set_selected(false)
	for depot in get_nodes_in_group("depots"): depot.set_process(false)
	var network = game.get_node("DepotNetwork")
	network.select_depot(null)
	var rig = game.get_node("CameraRig")
	rig.set_process(false); rig.focus_hq()
	for i in range(180): rig.advance_camera(1.0/60)
	game.depot.energy = 0; game.depot.iron = 0
	for i in range(3): await process_frame
	await click(hud.get_node("Bottom/Body/Header/GlobalBuild"))
	if not check(hud.global_build_open and hud.build_menu.visible,"Global Build unavailable without selection/funds"): return
	await click(hud.build_menu.get_node("Actions/Generator"))
	if not check(game.global_plan_kind == &"generator" and get_nodes_in_group("construction_plans").is_empty(),"UI choice issued unintended world placement"): return
	var point := Vector3.INF
	var spec: Dictionary = network.plan_spec(&"generator")
	for x in range(-25,26,5):
		for z in range(-25,26,5):
			var candidate: Vector3 = game.depot.global_position+Vector3(x,0,z)
			var screen: Vector2 = rig.camera.unproject_position(candidate)
			if screen.x > 80 and screen.x < 1200 and screen.y > 80 and screen.y < 540 and network.plan_terrain_valid(network.footprint_start(candidate,spec.size),spec.size,&"generator") and network.can_place_size(candidate,game.depot,spec.size): point = candidate
	if not check(point != Vector3.INF,"No on-screen test site"): return
	await click_at(rig.camera.unproject_position(point))
	if not check(get_nodes_in_group("construction_plans").size() == 1 and game.depot.energy == 0,"World plan placement failed or spent early"): return
	var plan = get_nodes_in_group("construction_plans")[0]
	var plan_screen: Vector2 = rig.camera.unproject_position(plan.global_position+Vector3(0,0.2,0))
	await click_at(plan_screen)
	if not check(hud.shown == plan and hud.card.get_node("CancelPlan").visible and not hud.global_build_open,"Cannot select unpaid grid plan"): return
	await click(hud.card.get_node("CancelPlan"))
	if not check(get_nodes_in_group("construction_plans").is_empty() and game.depot.energy == 0,"Cancel plan GUI failed"): return
	await click(hud.get_node("Bottom/Body/Header/GlobalBuild"))
	await click(hud.build_menu.get_node("Actions/Generator"))
	await click_at(rig.camera.unproject_position(point))
	plan = get_nodes_in_group("construction_plans")[0]
	var worker = game.get_node("Entities/Units/Infantry")
	await click_at(rig.camera.unproject_position(worker.selection_point()))
	if not check(worker.is_selected and not hud.global_build_open,"Global menu blocked direct selection switching"): return
	game.depot.energy = spec.energy; game.depot.iron = spec.iron
	plan._process(0.3)
	for i in range(3): await process_frame
	if not check(get_nodes_in_group("construction_plans").is_empty() and get_nodes_in_group("energy_generators").size() == 1 and game.depot.energy == 0 and game.depot.iron == 0,"Pending plan did not complete through process update"): return
	if not check(worker.is_selected and hud.shown == worker,"Background completion stole current selection"): return
	await click(hud.get_node("Bottom/Body/Header/GlobalBuild"))
	await click(hud.build_menu.get_node("Actions/Barracks"))
	var key := InputEventKey.new()
	key.pressed = true; key.keycode = KEY_ESCAPE
	root.push_input(key,true)
	if not check(game.global_plan_kind.is_empty(),"Escape did not cancel global placement"): return
	print("PENDING_CONSTRUCTION_GUI_CHECKS_PASSED")
	quit()
