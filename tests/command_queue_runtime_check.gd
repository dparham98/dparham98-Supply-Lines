extends SceneTree
# Rendered command queue check: real selection click and Shift-right-clicks; marker screenshots.
var game: Node3D
const TestOutput = preload("res://tests/test_output.gd")
const OUTPUT = "queue_work/"
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func click_at(point: Vector2, button := MOUSE_BUTTON_LEFT, shift := false) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion,true)
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = button
		event.pressed = pressed
		event.shift_pressed = shift
		root.push_input(event,true)
		for frame in range(4): await process_frame
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
	var worker = game.get_node("Entities/Units/Infantry")
	rig.focus_position(game.depot.global_position+Vector3(4,0,12),45)
	for frame in range(180): rig.advance_camera(1.0/60)
	var camera := game.get_viewport().get_camera_3d()
	await click_at(camera.unproject_position(worker.global_position+Vector3.UP*1.5))
	if not check(worker.is_selected,"Worker click did not select it"): return
	var start: Vector3 = worker.global_position
	for offset in [Vector3(8,0,-2),Vector3(14,0,-4),Vector3(18,0,0)]:
		await click_at(camera.unproject_position(start+offset),MOUSE_BUTTON_RIGHT,true)
	var markers = game.get_node("WaypointMarkers")
	for frame in range(3): await process_frame
	if not check(worker.order == "move" and worker.order_queue.size() == 2 and markers.visible_count() == 3,"Shift-right-clicks did not build a 3-step queue (queue %d, markers %d)" % [worker.order_queue.size(),markers.visible_count()]): return
	await shot("queue_markers")
	for i in range(60*12):
		worker._process(1.0/60)
		if worker.order_queue.size() == 1: break
	for frame in range(3): await process_frame
	if not check(worker.order_queue.size() == 1 and markers.visible_count() == 2,"Markers did not follow queue progress"): return
	await shot("queue_progress")
	print("COMMAND_QUEUE_RUNTIME_CHECK_PASSED"); quit(TestOutput.exit_code())
