extends SceneTree
# Rendered UI phase F check: real clicks on the compact grid and build page; pointer hover shows a tile's tooltip window.
var game: Node3D
var hud: CanvasLayer
const TestOutput = preload("res://tests/test_output.gd")
const OUTPUT = "compact_grid_work/"
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
func click(node: Control) -> void:
	for frame in range(10): await process_frame
	await click_at(node.get_global_rect().get_center())
func shot(name: String) -> void:
	for frame in range(10): await process_frame
	if not check(hud.get_node("Bottom").get_global_rect().end.x <= root.size.x+1,"%s HUD wider than the window" % name): return
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	TestOutput.save_png(self, root.get_texture().get_image(), OUTPUT+name+".png")
func target(node: Node3D) -> Vector2:
	return game.get_viewport().get_camera_3d().unproject_position(node.global_position+Vector3.UP*1.5)
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game); await process_frame
	game.set_process(false); hud = game.get_node("Interface")
	for group in ["units","depots"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	var rig = game.get_node("CameraRig"); rig.set_process(false)
	var depot = game.depot
	var worker = game.get_node("Entities/Units/Infantry")
	var tank = load("res://scenes/gameplay/tank.tscn").instantiate()
	tank.position = depot.global_position+Vector3(14,0,14)
	game.get_node("Entities/Units").add_child(tank); tank.set_process(false)
	tank.fuel = 10
	rig.focus_position(depot.global_position+Vector3(4,0,12),45)
	for frame in range(180): rig.advance_camera(1.0/60)
	for frame in range(30): await process_frame
	await click_at(target(tank))
	if not check(tank.is_selected,"Tank not selected"): return
	await move_to(hud.card.get_node("Attack").get_global_rect().get_center())
	if not check(hud.card.get_node("Attack").tooltip_text.begins_with("Attack [A]"),"Tile tooltip lacks its name and key: %s" % hud.card.get_node("Attack").tooltip_text): return
	# Let the tooltip window open before the screenshot.
	for frame in range(30): await process_frame
	await shot("tank_grid")
	await click_at(target(worker))
	# A click right after a screenshot capture can be dropped by the window; retry it once.
	if not worker.is_selected: await click_at(target(worker))
	if not check(worker.is_selected,"Worker not selected"): return
	await click(hud.get_node("Bottom/Body/Header/GlobalBuild"))
	if not check(hud.build_menu.is_visible_in_tree(),"Build page not opened by a real click"): return
	await move_to(hud.build_menu.get_node("Actions/Generator").get_global_rect().get_center())
	await shot("build_page")
	await click(hud.build_menu.get_node("Actions/Back"))
	if not check(hud.card.is_visible_in_tree(),"Back did not close the build page"): return
	await click_at(game.get_viewport().get_camera_3d().unproject_position(depot.global_position))
	if not check(game.selected_building == depot,"Depot not selected"): return
	await shot("depot_grid")
	print("COMPACT_GRID_RUNTIME_CHECK_PASSED"); quit(TestOutput.exit_code())
