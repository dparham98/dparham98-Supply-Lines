extends SceneTree
# Rendered UI phase D check: real right-clicks show order pings and target highlights; hover ring;
# plan outline; alert feed icons; restyled minimap with alert pulses. Screenshots for review.
var game: Node3D
var hud: CanvasLayer
const TestOutput = preload("res://tests/test_output.gd")
const OUTPUT = "feedback_work/"
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func press(point: Vector2, button: int, shift := false) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion,true)
	Input.warp_mouse(point)
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = button
		event.pressed = pressed
		event.shift_pressed = shift
		root.push_input(event,true)
		for frame in range(2): await process_frame
func shot(name: String) -> void:
	for frame in range(3): await process_frame
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
	var hostile = game.get_node("Entities/Units/Hostile")
	hostile.global_position = worker.global_position+Vector3(-10,0,6)
	var plan = game.get_node("DepotNetwork").queue_plan(depot.global_position+Vector3(30,0,-20),&"generator",null,false)
	if not check(plan != null,"Plan could not be queued"): return
	game.alert("Depot under attack",depot.global_position,"","attack")
	game.alert("Tank out of fuel",depot.global_position+Vector3(20,0,20),"","fuel")
	rig.focus_position(depot.global_position+Vector3(10,0,2),50)
	for frame in range(180): rig.advance_camera(1.0/60)
	for frame in range(30): await process_frame
	await press(target(worker),MOUSE_BUTTON_LEFT)
	if not check(worker.is_selected,"Worker not selected"): return
	var overlay = hud.get_node("MapOverlay")
	await press(game.get_viewport().get_camera_3d().unproject_position(worker.global_position+Vector3(14,0,-4)),MOUSE_BUTTON_RIGHT)
	await press(game.get_viewport().get_camera_3d().unproject_position(worker.global_position+Vector3(18,0,0)),MOUSE_BUTTON_RIGHT,true)
	await press(target(hostile),MOUSE_BUTTON_RIGHT,true)
	if not check(overlay.pings.size() >= 3 and overlay.pings[-1].target == hostile,"Real right-clicks did not ping (%d)" % overlay.pings.size()): return
	var motion := InputEventMouseMotion.new()
	motion.position = target(hostile)
	root.push_input(motion,true)
	Input.warp_mouse(target(hostile))
	for frame in range(3): await process_frame
	if not check(overlay.hovered == hostile,"Hover ring target not set"): return
	await shot("order_feedback")
	print("FEEDBACK_POLISH_RUNTIME_CHECK_PASSED"); quit(TestOutput.exit_code())
