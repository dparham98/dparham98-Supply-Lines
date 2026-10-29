extends SceneTree
# Rendered crate-container check: real clicks pack crates beside a Depot, Load clicks a crate on the
# map, Shift-Unload clicks open ground, and a worker right-clicks an empty crate. Screenshots of the
# crates beside the Depot, the loaded truck and the dropped crates.
var game: Node3D
var hud: CanvasLayer
const TestOutput = preload("res://tests/test_output.gd")
const OUTPUT = "crate_work/"
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func move_to(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion,true)
	Input.warp_mouse(point)
	for frame in range(4): await process_frame
func click_at(point: Vector2, shift := false, button := MOUSE_BUTTON_LEFT) -> void:
	await move_to(point)
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = button
		event.pressed = pressed
		event.shift_pressed = shift
		root.push_input(event,true)
		for frame in range(4): await process_frame
func click(node: Control) -> void:
	for frame in range(10): await process_frame
	await click_at(node.get_global_rect().get_center())
func shot(name: String) -> void:
	for frame in range(10): await process_frame
	if not check(is_equal_approx(hud.get_node("Bottom").size.y,260),"%s HUD height changed" % name): return
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	TestOutput.save_png(self, root.get_texture().get_image(), OUTPUT+name+".png")
func screen(point: Vector3) -> Vector2:
	return game.get_viewport().get_camera_3d().unproject_position(point)
func run_for(unit: Node3D, condition: Callable, seconds: float) -> bool:
	for i in range(ceili(seconds*60)):
		unit._process(1.0/60)
		if condition.call(): return true
	return false
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game); await process_frame
	game.set_process(false); hud = game.get_node("Interface")
	for group in ["units","depots"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	var rig = game.get_node("CameraRig"); rig.set_process(false)
	var depot = game.depot
	var truck = load("res://scenes/gameplay/cargo_vehicle.tscn").instantiate()
	truck.position = depot.global_position+Vector3(-14,0,10)
	game.get_node("Entities/Units").add_child(truck); truck.set_process(false)
	depot.coal = 100
	rig.focus_position(depot.global_position+Vector3(-4,0,6),40)
	for frame in range(180): rig.advance_camera(1.0/60)
	for frame in range(30): await process_frame
	# Real + clicks set crates down beside the Depot; its storage bar shows loose stock only.
	await click_at(screen(depot.global_position))
	if not game.selected_building == depot: await click_at(screen(depot.global_position))
	if not check(game.selected_building == depot and hud.shipment.is_visible_in_tree(),"Depot crate panel not shown"): return
	var iron: int = depot.iron
	for i in 3: await click(hud.shipment.get_node("Rows/Iron/Plus"))
	await click(hud.shipment.get_node("Rows/Coal/Plus"))
	await click(hud.shipment.get_node("Foot/EmptyCrate"))
	if not check(CrateYard.count_beside(depot,&"iron") == 3 and CrateYard.count_beside(depot,&"coal") == 1 and CrateYard.beside(depot).size() == 5 and depot.iron == iron-75,"Real clicks did not pack crates beside the Depot"): return
	var iron_crate: Node3D
	var empty_crate: Node3D
	for crate in CrateYard.beside(depot):
		if crate.resource_kind == &"iron" and iron_crate == null: iron_crate = crate
		if crate.amount == 0: empty_crate = crate
	await move_to(screen(iron_crate.global_position+Vector3(0,0.3,0)))
	if not check(hud.get_node("MapOverlay").hovered == iron_crate and hud.get_node("HoverCard").visible,"Crate hover card missing"): return
	await shot("depot_crates")
	# Load: click a crate on the map. The truck takes it and the filled crates next to it.
	await click_at(screen(truck.selection_point()))
	if not truck.is_selected: await click_at(screen(truck.selection_point()))
	if not check(truck.is_selected and hud.card.get_node("Load").is_visible_in_tree(),"Cargo tiles not shown"): return
	await click(hud.card.get_node("Load"))
	await click_at(screen(iron_crate.global_position+Vector3(0,0.3,0)))
	if not check(truck.order == "load" and truck.job_target == iron_crate,"Load click on a crate failed"): return
	# Shift-Unload on open ground queues a ground drop.
	var drop: Vector3 = game.ground.tile_to_world(CrateYard.free_cell(self,depot.global_position+Vector3(-18,0,2)))
	await click(hud.card.get_node("Unload"))
	await click_at(screen(drop),true)
	game.pending_unit_command = ""
	if not check(truck.order_queue.size() == 1 and truck.order_queue[0].kind == "unload" and truck.order_queue[0].get("target") == null,"Shift Unload on the ground did not queue"): return
	if not check(run_for(truck,func(): return truck.order == "unload",30) and truck.crates.size() >= 3,"Truck did not load the crates"): return
	hud._process(0)
	await shot("cargo_crates_aboard")
	if not check(run_for(truck,func(): return truck.order == "idle",40) and truck.crates.is_empty() and CrateYard.crates_near(self,drop,4.0).size() >= 3,"Crates were not set down on the ground"): return
	# A worker right-clicks the empty crate to deliver into it.
	var worker = game.get_node("Entities/Units").get_children().filter(func(u): return u.get("can_gather") == true and not u.is_cargo_vehicle)[0]
	worker.cargo_kind = &"wood"; worker.cargo = 10
	await click_at(screen(worker.selection_point()))
	if not worker.is_selected: await click_at(screen(worker.selection_point()))
	await click_at(screen(empty_crate.global_position+Vector3(0,0.3,0)),false,MOUSE_BUTTON_RIGHT)
	if not check(worker.order == "return" and worker.return_depot == empty_crate,"Right-click on an empty crate did not deliver into it"): return
	if not check(run_for(worker,func(): return worker.cargo == 0,30) and empty_crate.amount == 10,"Worker delivery into the crate failed"): return
	rig.focus_position(drop,40)
	for frame in range(180): rig.advance_camera(1.0/60)
	await shot("ground_drop")
	print("CRATE_CONTAINERS_RUNTIME_CHECK_PASSED"); quit(TestOutput.exit_code())
