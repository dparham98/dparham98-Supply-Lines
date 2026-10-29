extends SceneTree
var game: Node3D
var hud: CanvasLayer
const TestOutput = preload("res://tests/test_output.gd")
const OUTPUT = ""
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
	TestOutput.save_png(self, root.get_texture().get_image(), OUTPUT+name+".png")
func shift(down: bool) -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_SHIFT; key.physical_keycode = KEY_SHIFT; key.pressed = down
	Input.parse_input_event(key); Input.flush_buffered_events()
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/storage_exercise.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	hud = game.get_node("Interface")
	for group in ["units","depots"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	var rig = game.get_node("CameraRig")
	rig.set_process(false)
	rig.focus_position(Vector3(185,0,150),55)
	for frame in range(180): rig.advance_camera(1.0/60)
	await shot("storage_depot_capacity")
	var train = game.get_node("Entities/Units/Train")
	var destination = game.get_node("Entities/Buildings/EastDepot")
	await click_at(rig.camera.unproject_position(train.selection_point()))
	if not check(train.is_selected and hud.card.get_node("Load").visible,"Train storage HUD did not open"): return
	# Two coal crates; the destination has room for 30, so the Train keeps the rest of the second.
	CrateYard.pack(game.depot,&"coal"); CrateYard.pack(game.depot,&"coal")
	destination.stockpile.set_amount(&"energy",destination.stockpile.amount(&"energy")+destination.stockpile.space()-30)
	var coal: int = destination.coal
	await click(hud.card.get_node("Load"))
	hud.shipment_target.item_selected.emit(hud.shipment_stops.find(game.depot)+1)
	await click(hud.card.get_node("Unload"))
	shift(true)
	hud.shipment_target.item_selected.emit(hud.shipment_stops.find(destination)+1)
	shift(false)
	game.pending_unit_command = ""
	for frame in range(3000):
		train._process(1.0/60)
		if train.order == "idle" and train.order_queue.is_empty() and not train.crates.is_empty() and destination.coal > coal: break
	await shot("storage_train_full")
	if not check(train.crates.size() == 1 and train.crate_units(&"coal") == 20 and destination.coal == coal+30 and "retained" in train.state,"Coal crate did not remain aboard at full storage"): return
	var end: Vector2 = hud.get_node("Bottom").get_global_rect().end
	if not check(end.x <= root.size.x and end.y <= root.size.y,"Cargo controls overflow viewport"): return
	destination.stockpile.withdraw(&"energy",25)
	train.command_unload(destination)
	for frame in range(600):
		train._process(1.0/60)
		if train.order == "idle": break
	await shot("storage_delivery_complete")
	if not check(destination.coal == coal+50 and train.crates.is_empty(),"Freed storage did not accept the remaining crate"): return
	root.size = Vector2i(1440,960)
	await shot("storage_wide")
	print("STORAGE_RUNTIME_CHECKS_PASSED")
	quit(TestOutput.exit_code())
