extends SceneTree
# Rendered hotkey check: real window key presses and clicks; screenshots for review.
var game: Node3D
var hud: CanvasLayer
const TestOutput = preload("res://tests/test_output.gd")
const OUTPUT = "hotkeys_work/"
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
func press(keycode: int, ctrl := false) -> void:
	for pressed in [true,false]:
		var event := InputEventKey.new()
		event.physical_keycode = keycode
		event.keycode = keycode
		event.ctrl_pressed = ctrl
		if keycode >= KEY_A and keycode <= KEY_Z: event.unicode = keycode+32
		event.pressed = pressed
		root.push_input(event)
		for frame in range(3): await process_frame
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
	game.get_node("Entities/Units").add_child(tank)
	tank.set_process(false)
	rig.focus_position(depot.global_position+Vector3(4,0,12),45)
	for frame in range(180): rig.advance_camera(1.0/60)
	await click_at(target(worker))
	if not check(worker.is_selected and hud.card.get_node("Gather/Key").text == "G","Infantry card key labels missing"): return
	await shot("infantry_keys")
	await press(KEY_M)
	if not check(game.pending_unit_command == "move","M did not arm Move"): return
	await press(KEY_ESCAPE)
	await click_at(target(tank),true)
	if not check(worker.is_selected and tank.is_selected,"Shift-click did not add the Tank"): return
	await press(KEY_1,true)
	await click_at(target(tank))
	await press(KEY_1)
	if not check(worker.is_selected and tank.is_selected,"Control group did not recall"): return
	await shot("group_recalled")
	await click_at(target(tank))
	await press(KEY_T)
	if not check(not tank.auto_refuel and hud.card.get_node("ToggleRefuel").text.begins_with("Auto-refuel: off"),"T did not toggle Auto-refuel"): return
	await shot("tank_keys")
	print("HUD_HOTKEYS_RUNTIME_CHECK_PASSED"); quit(TestOutput.exit_code())
