extends SceneTree
# Rendered Phase E check: real clicks prepare crates at a Depot, arm Load, click the Depot,
# Shift-click Unload on an outpost; screenshots of the shipment panel and cargo grid.
var game: Node3D
var hud: CanvasLayer
const TestOutput = preload("res://tests/test_output.gd")
const OUTPUT = "crate_work/"
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func click_at(point: Vector2, shift := false) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion,true)
	Input.warp_mouse(point)
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
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
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game); await process_frame
	game.set_process(false); hud = game.get_node("Interface")
	for group in ["units","depots"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	var rig = game.get_node("CameraRig"); rig.set_process(false)
	var depot = game.depot
	var outpost = load("res://scenes/gameplay/depot.tscn").instantiate()
	outpost.name = "Outpost"; outpost.team = "player"
	outpost.position = depot.global_position+Vector3(34,0,-2)
	game.get_node("Entities/Buildings").add_child(outpost); outpost.set_process(false)
	var truck = load("res://scenes/gameplay/cargo_vehicle.tscn").instantiate()
	truck.position = depot.global_position+Vector3(-14,0,10)
	game.get_node("Entities/Units").add_child(truck); truck.set_process(false)
	depot.coal = 100
	rig.focus_position(depot.global_position+Vector3(10,0,6),55)
	for frame in range(180): rig.advance_camera(1.0/60)
	for frame in range(30): await process_frame
	await click_at(screen(depot.global_position))
	if not check(game.selected_building == depot and hud.shipment.is_visible_in_tree(),"Depot shipment panel not shown"): return
	for i in 3: await click(hud.shipment.get_node("Rows/Iron/Plus"))
	await click(hud.shipment.get_node("Rows/Coal/Plus"))
	if not check(depot.stockpile.crate_count(&"iron") == 3 and depot.stockpile.crate_count(&"coal") == 1,"Real Plus clicks did not pack crates"): return
	await shot("depot_shipment")
	await click_at(screen(truck.selection_point()))
	if not truck.is_selected: await click_at(screen(truck.selection_point()))
	if not check(truck.is_selected and hud.card.get_node("Load").is_visible_in_tree(),"Cargo tiles not shown"): return
	await click(hud.card.get_node("Load"))
	await click_at(screen(depot.global_position))
	if not check(truck.order == "load" and truck.job_target == depot,"Load click on the Depot failed"): return
	await click(hud.card.get_node("Unload"))
	await click_at(screen(outpost.global_position),true)
	game.pending_unit_command = ""
	if not check(truck.order_queue.size() == 1 and truck.order_queue[0].target == outpost,"Shift Unload click did not queue"): return
	await shot("cargo_trip")
	print("CRATE_SHIPMENTS_RUNTIME_CHECK_PASSED"); quit(TestOutput.exit_code())
