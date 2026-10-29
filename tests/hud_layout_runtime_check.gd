extends SceneTree
# Rendered HUD phase 4 check: real clicks on the type strip, alert feed and cargo pages.
var game: Node3D
var hud: CanvasLayer
const TestOutput = preload("res://tests/test_output.gd")
const OUTPUT = "hud_layout_work/"
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func click_at(point: Vector2, shift := false) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion,true)
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
	for frame in range(8): await process_frame
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
	var truck = load("res://scenes/gameplay/cargo_vehicle.tscn").instantiate()
	truck.position = depot.global_position+Vector3(-14,0,10)
	game.get_node("Entities/Units").add_child(truck); truck.set_process(false)
	tank.fuel = 10
	rig.focus_position(depot.global_position+Vector3(4,0,12),45)
	for frame in range(180): rig.advance_camera(1.0/60)
	await click_at(target(worker))
	await click_at(target(tank),true)
	if not check(worker.is_selected and tank.is_selected and hud.strip.visible,"Mixed selection strip not shown"): return
	game.alert("Depot under attack",depot.global_position)
	await shot("mixed_selection")
	var tank_button: Button = hud.strip.get_node("Type1") if hud.strip.get_node("Type1").text.begins_with("Tank") else hud.strip.get_node("Type2")
	await click(tank_button)
	if not check(tank.is_selected and not worker.is_selected,"Strip click did not narrow to the Tank"): return
	if not check(hud.bars.get_node("Fuel").visible,"Tank fuel bar not shown"): return
	await shot("tank_bars")
	var entry: Button = hud.feed.get_node("Entry1")
	await click(entry)
	if not check(rig._focus_target.is_equal_approx(depot.global_position),"Feed click did not focus the alert"): return
	await click_at(target(truck))
	if not check(truck.is_selected and hud.supply.is_visible_in_tree(),"Cargo route page not shown"): return
	await click(hud.pages.get_node("Orders"))
	if not check(hud.card.is_visible_in_tree() and hud.card.get_node("ToggleRefuel").is_visible_in_tree(),"Orders page click failed"): return
	await shot("cargo_orders")
	print("HUD_LAYOUT_RUNTIME_CHECK_PASSED"); quit(TestOutput.exit_code())
