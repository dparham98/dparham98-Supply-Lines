extends SceneTree
# Rendered playtest panel check: real F10, clicks on panel buttons and an armed spawn click.
var game: Node3D
var panel: PanelContainer
const TestOutput = preload("res://tests/test_output.gd")
const OUTPUT = "playtest_work/"
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	paused = false; Engine.time_scale = 1.0
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
func click(node: Control) -> void:
	for frame in range(10): await process_frame
	await click_at(node.get_global_rect().get_center())
func shot(name: String) -> void:
	for frame in range(8): await process_frame
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	TestOutput.save_png(self, root.get_texture().get_image(), OUTPUT+name+".png")
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game); await process_frame
	game.set_process(false)
	for group in ["units","depots"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	var rig = game.get_node("CameraRig"); rig.set_process(false)
	var depot = game.depot
	panel = game.get_node("Interface/PlaytestPanel")
	rig.focus_position(depot.global_position+Vector3(0,0,8),45)
	for frame in range(180): rig.advance_camera(1.0/60)
	var camera := game.get_viewport().get_camera_3d()
	for pressed in [true,false]:
		var key := InputEventKey.new()
		key.physical_keycode = KEY_F10; key.keycode = KEY_F10; key.pressed = pressed
		root.push_input(key)
		await process_frame
	if not check(panel.is_visible_in_tree(),"F10 did not open the panel"): return
	await click_at(camera.unproject_position(depot.global_position))
	if not check(game.selected_building == depot,"Depot click did not select it"): return
	var coal: int = depot.coal
	await click(panel.get_node("Body/Resources/Coal"))
	if not check(depot.coal == coal+100,"+100 Coal click did not add coal"): return
	await shot("panel_depot")
	var before := get_nodes_in_group("units").size()
	panel.get_node("Body/Spawn/Unit").select(3)
	await click(panel.get_node("Body/Spawn/Place"))
	await click_at(camera.unproject_position(depot.global_position+Vector3(14,0,-6)))
	if not check(get_nodes_in_group("units").size() == before+1 and not panel.spawn_armed,"Spawn click did not place one unit"): return
	for node in get_nodes_in_group("units"): node.set_process(false)
	await click(panel.get_node("Body/Speed/Pause"))
	if not check(paused and panel.get_node("Body/Speed/Pause").text == "Resume","Pause click failed"): return
	await shot("panel_paused")
	await click(panel.get_node("Body/Speed/Pause"))
	if not check(not paused,"Resume click failed"): return
	print("PLAYTEST_TOOLS_RUNTIME_CHECK_PASSED"); quit(TestOutput.exit_code())
