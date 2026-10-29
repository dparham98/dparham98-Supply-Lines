extends SceneTree
# Rendered UI phase C check: map overlay with damage, production, routes, hover card and Alt; screenshots.
var game: Node3D
var hud: CanvasLayer
var overlay: Control
const TestOutput = preload("res://tests/test_output.gd")
const OUTPUT = "map_status_work/"
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	Input.action_release("map_show_all")
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
	for frame in range(10): await process_frame
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	TestOutput.save_png(self, root.get_texture().get_image(), OUTPUT+name+".png")
func target(node: Node3D) -> Vector2:
	return game.get_viewport().get_camera_3d().unproject_position(node.global_position+Vector3.UP*1.5)
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game); await process_frame
	game.set_process(false); hud = game.get_node("Interface"); overlay = hud.get_node("MapOverlay")
	for group in ["units","depots"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	var rig = game.get_node("CameraRig"); rig.set_process(false)
	var depot = game.depot
	var worker = game.get_node("Entities/Units/Infantry")
	worker.health -= 20; worker.cargo = 6; worker.cargo_kind = &"iron"
	var tank = load("res://scenes/gameplay/tank.tscn").instantiate()
	tank.position = depot.global_position+Vector3(14,0,14)
	game.get_node("Entities/Units").add_child(tank); tank.set_process(false)
	tank.fuel = 5
	var truck = load("res://scenes/gameplay/cargo_vehicle.tscn").instantiate()
	truck.position = depot.global_position+Vector3(-14,0,10)
	game.get_node("Entities/Units").add_child(truck); truck.set_process(false)
	var outpost = load("res://scenes/gameplay/depot.tscn").instantiate()
	outpost.name = "Outpost"; outpost.team = "player"
	outpost.position = depot.global_position+Vector3(34,0,-2)
	game.get_node("Entities/Buildings").add_child(outpost); outpost.set_process(false)
	truck.start_supply_route(depot,outpost,10,0,true)
	depot.energy = 1000; depot.iron = 1000
	depot.request_cargo(); depot.progress = depot.print_seconds*0.6
	game.mark_attacked(outpost)
	game.delivered(depot,&"iron",10)
	rig.focus_position(depot.global_position+Vector3(10,0,8),55)
	for frame in range(180): rig.advance_camera(1.0/60)
	for frame in range(30): await process_frame
	if not check(not worker.get_node("Status").visible and not depot.get_node("Progress").visible,"Text labels still shown"): return
	await click_at(target(truck))
	if not check(truck.is_selected and overlay.route_lines().size() == 1,"Selected truck has no route line"): return
	await move_to(game.get_viewport().get_camera_3d().unproject_position(depot.global_position))
	if not check(overlay.hovered == depot and hud.get_node("HoverCard").visible,"Hover card did not appear over the Depot"): return
	await shot("map_status")
	Input.action_press("map_show_all")
	await shot("map_show_all")
	Input.action_release("map_show_all")
	print("MAP_STATUS_RUNTIME_CHECK_PASSED"); quit(TestOutput.exit_code())
