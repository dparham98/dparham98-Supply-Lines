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
	if not check(train.is_selected and hud.supply.visible,"Train storage HUD did not open"): return
	hud.supply.get_node("Source").select(hud.route_depots.find(game.depot))
	hud.supply.get_node("Destination").select(hud.route_depots.find(destination))
	for id in ["Energy","Iron","Wood"]: hud.supply.get_node("Amounts/"+id).value = 0
	hud.supply.get_node("Amounts/Coal").value = 20
	hud.supply.get_node("Repeat").button_pressed = false
	await click(hud.supply.get_node("StartRoute"))
	if not check(train.route_active and train.requested_coal == 20,"Coal route GUI assignment failed"): return
	for frame in range(1000): train._process(1.0/60)
	await shot("storage_train_full")
	if not check(train.carried_coal == 10 and destination.coal == 10 and train.route_active,"Coal did not remain aboard at full storage"): return
	var end: Vector2 = hud.supply.get_global_rect().end
	if not check(end.x <= root.size.x and end.y <= root.size.y,"Coal cargo controls overflow viewport"): return
	destination.stockpile.withdraw(&"energy",10)
	for frame in range(180): train._process(1.0/60)
	await shot("storage_delivery_complete")
	if not check(destination.coal == 20 and not train.route_active,"Freed storage did not accept remainder"): return
	root.size = Vector2i(1440,960)
	await shot("storage_wide")
	print("STORAGE_RUNTIME_CHECKS_PASSED")
	quit()
