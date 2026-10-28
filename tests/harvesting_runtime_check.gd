extends SceneTree
var game: Node3D
var hud: CanvasLayer
const OUTPUT = "C:/Users/video/.codex/.chatgpt-projects/g-p-6ad16a23380c8191877dbcafdb316068/"
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func click_at(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion,true)
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event,true)
	# A human click spans multiple process frames. Do not emit button signals directly.
	for frame in range(5): await process_frame
	event = InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	root.push_input(event,true)
	for frame in range(3): await process_frame

func click(node: Control) -> void:
	var previous := Rect2()
	var stable := 0
	for frame in range(30):
		await process_frame
		var current := node.get_global_rect()
		if current == previous and node.is_visible_in_tree(): stable += 1
		else: stable = 0
		previous = current
		if stable >= 3: break
	await click_at(node.get_global_rect().get_center())
func shot(name: String) -> void:
	for frame in range(8): await process_frame
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT+name+".png")
func focus(point: Vector3, zoom: float = 55) -> void:
	var rig = game.get_node("CameraRig")
	rig.focus_position(point,zoom)
	for frame in range(180): rig.advance_camera(1.0/60)
func target(node: Node3D) -> Vector2:
	return game.get_viewport().get_camera_3d().unproject_position(node.global_position+Vector3.UP*1.5)
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/harvesting_exercise.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	hud = game.get_node("Interface")
	for group in ["units","depots","mines"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	var rig = game.get_node("CameraRig")
	rig.set_process(false)
	var payer = game.depot
	focus(Vector3(160,0,150))
	await click(hud.card.get_node("Build"))
	await click(hud.build_menu.get_node("Actions/Mine"))
	if not check(game.placing_structure == &"iron_mine","Depot Mine build card failed"): return
	await click_at(rig.camera.unproject_position(Vector3(150,0,154)))
	if not check(get_nodes_in_group("mines").size() == 2 and payer.energy == 425 and payer.iron == 475,"Depot Mine world placement failed"): return
	await shot("harvesting_depot_build")
	await click(hud.build_menu.get_node("Actions/Back"))
	var worker = game.get_node("Entities/Units/Infantry")
	await click_at(rig.camera.unproject_position(worker.selection_point()))
	if not check(worker.is_selected,"Main Infantry could not be selected"): return
	await click(hud.card.get_node("Build"))
	await click(hud.build_menu.get_node("Actions/Mine"))
	await click_at(rig.camera.unproject_position(Vector3(148,0,154)))
	if not check(get_nodes_in_group("mines").size() == 3 and payer.energy == 350 and payer.iron == 450,"Infantry Mine construction/local payment failed"): return
	await click(hud.build_menu.get_node("Actions/Back"))
	var mine = get_nodes_in_group("mines")[-1]
	mine.take_damage(50)
	await click(hud.card.get_node("Repair"))
	await click_at(target(mine))
	if not check(worker.order == "repair" and worker.order_target == mine,"Shared Mine Repair GUI failed"): return
	for frame in range(1800):
		worker._process(1.0/60)
		if mine.health == mine.max_health: break
	if not check(mine.health == mine.max_health and payer.energy == 340 and payer.iron == 445,"Shared Mine repair did not spend exact local stock"): return
	await shot("harvesting_shared_mine_repair")
	worker._stop_route(); worker.order = "idle"; worker.set_selected(false)
	game.get_node("DepotNetwork").select_depot(null)
	var forester = game.get_node("Entities/Units/ForestInfantry")
	var depot = game.get_node("Entities/Buildings/ForestDepot")
	focus(Vector3(100,0,28),42)
	await click_at(rig.camera.unproject_position(forester.selection_point()))
	if not check(forester.is_selected,"Forestry Infantry selection failed"): return
	await shot("harvesting_forest_before")
	# Right-click uses ordinary terrain-cell targeting rather than authored wood stands.
	var point: Vector2 = rig.camera.unproject_position(game.ground.tile_to_world(Vector2i(345,275)))
	var motion := InputEventMouseMotion.new(); motion.position = point; root.push_input(motion,true)
	var event := InputEventMouseButton.new(); event.position = point; event.button_index = MOUSE_BUTTON_RIGHT; event.pressed = true
	root.push_input(event,true)
	for frame in range(5): await process_frame
	event = InputEventMouseButton.new(); event.position = point; event.button_index = MOUSE_BUTTON_RIGHT; event.pressed = false; root.push_input(event,true)
	if not check(forester.order == "gather" and forester.source.cell == Vector2i(345,275),"Forest right-click targeting failed"): return
	for frame in range(2400):
		forester._process(1.0/60)
		if depot.wood == 20: break
	if not check(depot.wood == 20 and game.ground.get_terrain(Vector2i(345,275)) == 0,"Right-click forest harvest did not deplete/deliver"): return
	await click(hud.card.get_node("Gather"))
	await click_at(rig.camera.unproject_position(game.ground.tile_to_world(Vector2i(345,276))))
	if not check(forester.order == "gather" and forester.source.cell == Vector2i(345,276),"Gather card forest targeting failed"): return
	for frame in range(2400):
		forester._process(1.0/60)
		if depot.wood == 40: break
	game.ground._process(0)
	if not check(depot.wood == 40 and game.ground.get_terrain(Vector2i(345,276)) == 0,"Gather card failed to deliver next forest tile"): return
	await shot("harvesting_forest_after")
	root.size = Vector2i(1440,960)
	await shot("harvesting_wide")
	print("HARVESTING_RUNTIME_CHECKS_PASSED")
	quit()
