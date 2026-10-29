extends SceneTree
# Rendered check for the 2026-10-29 playtest fixes: Depot hover bars, armed-command cursor
# indicator, Depot Truck footprint preview, and a fixed HUD while hovering tiles.
var game: Node3D
var hud: CanvasLayer
const TestOutput = preload("res://tests/test_output.gd")
const OUTPUT = "playtest_fixes_work/"
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
func click_at(point: Vector2) -> void:
	await move_to(point)
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event,true)
		for frame in range(4): await process_frame
func shot(name: String) -> void:
	for frame in range(8): await process_frame
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
	var truck = load("res://scenes/gameplay/depot_truck.tscn").instantiate()
	truck.position = depot.global_position+Vector3(-20,0,20)
	game.get_node("Entities/Units").add_child(truck); truck.set_process(false)
	rig.focus_position(depot.global_position+Vector3(-6,0,10),50)
	for frame in range(180): rig.advance_camera(1.0/60)
	for frame in range(30): await process_frame
	# Depot hover: health bar and the resource-split storage bar, on the map and in the card.
	await move_to(screen(depot.global_position))
	var overlay = hud.get_node("MapOverlay")
	if not check(overlay.hovered == depot and hud.get_node("HoverCard/Body/Storage").visible,"Depot hover bars missing"): return
	await shot("depot_hover")
	# Depot Truck deploy: a footprint preview at the pointer, red over the Depot, then a valid site.
	await click_at(screen(truck.selection_point()))
	if not truck.is_selected: await click_at(screen(truck.selection_point()))
	if not check(truck.is_selected,"Depot Truck not selected"): return
	var tile_y: float = hud.card.get_node("DeployTruck").global_position.y
	await move_to(hud.card.get_node("DeployTruck").get_global_rect().get_center())
	if not check(is_equal_approx(hud.card.get_node("DeployTruck").global_position.y,tile_y),"Hovering a tile moved the grid"): return
	await click_at(hud.card.get_node("DeployTruck").get_global_rect().get_center())
	if not check(game.pending_unit_command == "deploy","Deploy tile did not arm placement"): return
	await move_to(screen(depot.global_position))
	await shot("deploy_blocked")
	await move_to(screen(truck.global_position+Vector3(0,0,6)))
	await shot("deploy_preview")
	print("PLAYTEST_FIXES_RUNTIME_CHECK_PASSED"); quit(TestOutput.exit_code())
