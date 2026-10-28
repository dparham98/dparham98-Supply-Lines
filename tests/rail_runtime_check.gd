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
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/rail_exercise.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	hud = game.get_node("Interface")
	for group in ["units","depots"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	var source = game.depot
	var destination = game.get_node("Entities/Buildings/EastDepot")
	var rails = game.get_node("RailNetwork")
	var network = game.get_node("DepotNetwork")
	var rig = game.get_node("CameraRig")
	rig.set_process(false)
	rig.focus_position(Vector3(185,0,150),55)
	for frame in range(180): rig.advance_camera(1.0/60)
	await click(hud.card.get_node("PrintTrain"))
	if not check(source.queue == 1 and source.pending[0] == "train" and source.energy == 350 and source.iron == 470,"Print Train GUI payment failed"): return
	await shot("rail_depot_card")
	await click(hud.card.get_node("Build"))
	await click(hud.build_menu.get_node("Actions/Rail"))
	if not check(game.placing_rail,"Rail Build button failed"): return
	var cell = game.ground.get_tile_at_position(source.global_position+Vector3(0,0,10))
	await click_at(rig.camera.unproject_position(game.ground.tile_to_world(cell)))
	await click_at(rig.camera.unproject_position(game.ground.tile_to_world(cell+Vector2i(1,0))))
	if not check(rails.segments.has(cell) and rails.segments.has(cell+Vector2i(1,0)) and source.iron == 466 and game.placing_rail,"Repeated world placement or payer debit failed"): return
	await shot("rail_construction")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE; escape.pressed = true
	root.push_input(escape,true)
	for frame in range(3): await process_frame
	if not check(not game.placing_rail,"Esc failed to finish rail placement"): return
	await click(hud.build_menu.get_node("Actions/Back"))
	var train = game.get_node("Entities/Units/Train")
	await click_at(rig.camera.unproject_position(train.selection_point()))
	if not check(train.is_selected and hud.supply.visible and hud.object_name(train) == "Train","Train selection did not open rail cargo HUD"): return
	hud.supply.get_node("Source").select(hud.route_depots.find(source))
	hud.supply.get_node("Destination").select(hud.route_depots.find(destination))
	hud.supply.get_node("Amounts/Energy").value = 60
	hud.supply.get_node("Amounts/Iron").value = 40
	hud.supply.get_node("Amounts/Wood").value = 20
	hud.supply.get_node("Repeat").button_pressed = false
	var energy: int = destination.energy
	var iron: int = destination.iron
	var wood: int = destination.wood
	await click(hud.supply.get_node("StartRoute"))
	if not check(train.route_active and train.requested_wood == 20,"Train Assign route GUI failed"): return
	for frame in range(180): train._process(1.0/60)
	await shot("rail_train_loaded")
	await click(hud.supply.get_node("PauseRoute"))
	if not check(train.route_paused,"Train Pause GUI failed"): return
	await click(hud.supply.get_node("PauseRoute"))
	if not check(not train.route_paused,"Train Resume GUI failed"): return
	for frame in range(900): train._process(1.0/60)
	if not check(not train.route_active and destination.energy == energy+60 and destination.iron == iron+40 and destination.wood == wood+20,"GUI-assigned train failed cargo delivery"): return
	await shot("rail_train_delivered")
	root.size = Vector2i(1440,960)
	await shot("rail_train_wide")
	if not check(hud.info.get_node("Details").get_global_rect().end.y <= root.size.y,"Train HUD overflow"): return
	print("RAIL_RUNTIME_CHECKS_PASSED")
	quit()
