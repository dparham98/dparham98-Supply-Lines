extends SceneTree
# Rendered fuel HUD check: real clicks select a vehicle and toggle auto-refuel; screenshots for review.
var game: Node3D
var hud: CanvasLayer
const TestOutput = preload("res://tests/test_output.gd")
const OUTPUT = "fuel_work/"
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
func focus(point: Vector3, zoom: float = 55) -> void:
	var rig = game.get_node("CameraRig")
	rig.focus_position(point,zoom)
	for frame in range(180): rig.advance_camera(1.0/60)
func target(node: Node3D) -> Vector2:
	return game.get_viewport().get_camera_3d().unproject_position(node.global_position+Vector3.UP*1.5)
func step(unit: Node3D, seconds: float) -> void:
	for i in range(ceili(seconds*60)): unit._process(1.0/60)
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game); await process_frame
	game.set_process(false); hud = game.get_node("Interface")
	for group in ["units","depots"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	var rig = game.get_node("CameraRig"); rig.set_process(false)
	var depot = game.depot
	depot.coal = 0
	var tank = load("res://scenes/gameplay/tank.tscn").instantiate()
	tank.position = depot.global_position+Vector3(14,0,14)
	game.get_node("Entities/Units").add_child(tank)
	tank.set_process(false)
	tank.fuel = 8
	focus(tank.global_position,45)
	await click_at(target(tank))
	if not check(hud.shown == tank and hud.card.get_node("ToggleRefuel").visible and "LOW FUEL" in hud.info.get_node("Details").text,"Low-fuel tank HUD selection failed"): return
	await shot("fuel_low")
	await click(hud.card.get_node("ToggleRefuel"))
	if not check(not tank.auto_refuel and hud.card.get_node("ToggleRefuel").text.begins_with("Auto-refuel: off"),"Auto-refuel click failed"): return
	await shot("fuel_auto_off")
	await click(hud.card.get_node("ToggleRefuel"))
	depot.coal = 100
	step(tank,3)
	if not check(tank.auto_refuel and depot.coal+tank.fuel == 108 and tank.fuel > 8,"Refuel after re-enabling failed"): return
	await shot("fuel_refuelling")
	# Cargo Trucks use the Supply panel; its toggle must take a real click too.
	var truck = load("res://scenes/gameplay/cargo_vehicle.tscn").instantiate()
	truck.position = depot.global_position+Vector3(-14,0,14)
	game.get_node("Entities/Units").add_child(truck)
	truck.set_process(false)
	focus(truck.global_position,45)
	await click_at(target(truck))
	if not check(hud.shown == truck and hud.pages.is_visible_in_tree(),"Cargo truck pages not shown"): return
	# Cargo vehicles reach Auto-refuel from the Orders page of the command card.
	await click(hud.pages.get_node("Orders"))
	var truck_refuel: Button = hud.card.get_node("ToggleRefuel")
	if not check(truck_refuel.is_visible_in_tree(),"Cargo truck refuel toggle not shown"): return
	await click(truck_refuel)
	if not check(not truck.auto_refuel and truck_refuel.text.begins_with("Auto-refuel: off"),"Cargo truck refuel click failed"): return
	await shot("fuel_truck_toggle")
	print("FUEL_RUNTIME_CHECKS_PASSED"); quit(TestOutput.exit_code())
