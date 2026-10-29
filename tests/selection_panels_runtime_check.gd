extends SceneTree
# Rendered UI phase B check: real clicks select each kind of object; panels must fit; screenshots for review.
var game: Node3D
var hud: CanvasLayer
const TestOutput = preload("res://tests/test_output.gd")
const OUTPUT = "panels_work/"
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func click_at(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion,true)
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event,true)
		for frame in range(4): await process_frame
func shot(name: String) -> void:
	for frame in range(10): await process_frame
	if not check(hud.info.get_global_rect().end.y <= root.size.y+1,"%s panel overflows the window" % name): return
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	TestOutput.save_png(self, root.get_texture().get_image(), OUTPUT+name+".png")
func target(node: Node3D) -> Vector2:
	return game.get_viewport().get_camera_3d().unproject_position(node.global_position+Vector3.UP*1.5)
func load_game(path: String) -> void:
	if is_instance_valid(game): game.free()
	game = load(path).instantiate()
	root.add_child(game); await process_frame
	game.set_process(false); hud = game.get_node("Interface")
	for group in ["units","depots"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	game.get_node("CameraRig").set_process(false)
func focus(point: Vector3) -> void:
	var rig = game.get_node("CameraRig")
	rig.focus_position(point,45)
	for frame in range(180): rig.advance_camera(1.0/60)
func run() -> void:
	root.size = Vector2i(1280,900)
	await load_game("res://scenes/maps/resource_skirmish.tscn")
	var depot = game.depot
	var tank = load("res://scenes/gameplay/tank.tscn").instantiate()
	tank.position = depot.global_position+Vector3(14,0,14)
	game.get_node("Entities/Units").add_child(tank); tank.set_process(false)
	tank.fuel = 10
	var truck = load("res://scenes/gameplay/cargo_vehicle.tscn").instantiate()
	truck.position = depot.global_position+Vector3(-14,0,10)
	game.get_node("Entities/Units").add_child(truck); truck.set_process(false)
	truck.carried_energy = 10; truck.carried_coal = 30; truck.fuel = 22
	focus(depot.global_position+Vector3(4,0,12))
	# The first input after the window opens can be lost before it has focus.
	for frame in range(30): await process_frame
	await click_at(target(tank))
	if not check(tank.is_selected and hud.context.get_node("Stats").visible,"Tank panel not shown"): return
	await shot("tank_panel")
	await click_at(target(truck))
	await click_at(hud.pages.get_node("Orders").get_global_rect().get_center())
	if not check(truck.is_selected and hud.context.get_node("Storage").visible,"Cargo panel not shown"): return
	await shot("cargo_panel")
	depot.energy = 1000; depot.iron = 1000; depot.stockpile.set_amount(&"coal",100)
	depot.request_cargo(); depot.request_cargo(); depot.progress = depot.print_seconds*0.62
	await click_at(game.get_viewport().get_camera_3d().unproject_position(depot.global_position))
	if not check(game.selected_building == depot and hud.context.get_node("Production").visible,"Depot production panel not shown"): return
	await shot("depot_panel")
	await load_game("res://scenes/maps/rail_exercise.tscn")
	game.vehicle_fuel_required = true
	var train = game.get_node("Entities/Units/Train")
	train.fuel = 20
	train.start_supply_route(game.depot,game.get_node("Entities/Buildings/EastDepot"),1,0,true)
	focus(train.global_position)
	await click_at(target(train))
	await click_at(hud.pages.get_node("Orders").get_global_rect().get_center())
	if not check(train.is_selected and hud.context.get_node("Storage").visible,"Train panel not shown"): return
	await shot("train_panel")
	print("SELECTION_PANELS_RUNTIME_CHECK_PASSED"); quit(TestOutput.exit_code())
