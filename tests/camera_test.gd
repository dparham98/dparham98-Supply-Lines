extends SceneTree
const OUTPUT = "C:/Users/video/.codex/.chatgpt-projects/g-p-6ad16a23380c8191877dbcafdb316068/camera_work/"
var rig: Node3D
func _initialize() -> void: call_deferred("test_camera")
func settle(frames: int = 180) -> void:
	for i in range(frames): rig.advance_camera(1.0 / 60.0)
func check_bounds() -> void:
	var size := root.get_visible_rect().size
	for point in [Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]:
		var world = rig.ground_point(point)
		assert(world != null)
		assert(world.x >= -250.01 and world.x <= 250.01)
		assert(world.z >= -250.01 and world.z <= 250.01)
func test_camera() -> void:
	root.size = Vector2i(1280, 960)
	rig = load("res://scenes/camera/rts_camera.tscn").instantiate()
	root.add_child(rig)
	await process_frame
	rig.set_process(false)
	await process_frame
	rig.set_view(Vector3.ZERO, 95, 0, 50)
	var cursor := Vector2(830, 620)
	var before: Vector3 = rig.ground_point(cursor)
	rig.zoom_at_screen_position(cursor, 3)
	settle()
	var cursor_error := before.distance_to(rig.ground_point(cursor))
	assert(cursor_error < 0.02, "Cursor zoom anchor drift")
	rig.zoom_at_screen_position(cursor, 500)
	settle()
	assert(absf(rig.camera.size - rig.min_zoom) < 0.01)
	rig.zoom_at_screen_position(cursor, -500)
	settle()
	assert(absf(rig.camera.size - rig.max_zoom) < 0.01)
	# Map clamping uses the full tilted/rotated viewport footprint, not camera position.
	for yaw in [0, 45, 90, -30]:
		for corner in [Vector3(-999, 0, -999), Vector3(999, 0, 999), Vector3(-999, 0, 999), Vector3(999, 0, -999)]:
			rig.set_view(corner, 95, yaw, 50)
			check_bounds()
	rig.set_view(Vector3.ZERO, 95, 90, 50)
	var start: Vector3 = rig.global_position
	for i in range(60):
		rig.apply_navigation(Vector2(0, -1), 0, false, 1.0 / 60.0)
		rig.advance_camera(1.0 / 60.0)
	assert(rig.global_position.x < start.x - 20 and absf(rig.global_position.z - start.z) < 0.01)
	# Identical pan input at 30 and 120 FPS yields the same target displacement.
	var endpoints: Array[Vector3] = []
	for fps in [30, 120]:
		rig.set_view(Vector3.ZERO, 95, 0, 50)
		for i in range(fps):
			rig.apply_navigation(Vector2(1, 0), 0, false, 1.0 / fps)
			rig.advance_camera(1.0 / fps)
		endpoints.append(rig._focus_target)
	var frame_rate_error := endpoints[0].distance_to(endpoints[1])
	assert(frame_rate_error < 0.001)
	rig.set_view(Vector3.ZERO, 95, 0, 50)
	Input.action_press("camera_rotate_right")
	for i in range(30):
		rig.apply_navigation(Vector2.ZERO, Input.get_axis("camera_rotate_left", "camera_rotate_right"), false, 1.0 / 60.0)
		rig.advance_camera(1.0 / 60.0)
	Input.action_release("camera_rotate_right")
	var yaw_target: float = rig._yaw_target
	for i in range(180):
		rig.apply_navigation(Vector2.ZERO, Input.get_axis("camera_rotate_left", "camera_rotate_right"), false, 1.0 / 60.0)
		rig.advance_camera(1.0 / 60.0)
	assert(absf(rig._yaw_target - yaw_target) < 0.0001)
	assert(absf(wrapf(rig._yaw - yaw_target, -PI, PI)) < 0.001)
	rig.set_view(Vector3.ZERO, 95, 0, 50)
	var grab := Vector2(640, 480)
	var world_grab: Vector3 = rig.ground_point(grab)
	rig.begin_drag(grab)
	rig.drag_to(grab + Vector2(100, 70))
	assert(world_grab.distance_to(rig.ground_point(grab + Vector2(100, 70))) < 0.02)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_MIDDLE
	release.pressed = false
	rig._input(release)
	assert(not rig._dragging)
	rig.begin_drag(grab)
	rig._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	assert(not rig._dragging and not rig._zoom_anchor_active)
	assert(rig.edge_pan_vector(Vector2(-2, 40), Vector2(1280, 960)) == Vector2.ZERO)
	assert(rig.edge_pan_vector(Vector2(600, 480), Vector2(1280, 960)) == Vector2.ZERO)
	assert(rig.edge_pan_vector(Vector2(2, 480), Vector2(1280, 960)).x < 0)
	# Overview fits every map corner at multiple aspect ratios and restores the previous view.
	for viewport_size in [Vector2i(1280, 720), Vector2i(900, 900), Vector2i(720, 1280)]:
		root.size = viewport_size
		await process_frame
		rig.set_view(Vector3(25, 0, -20), 83, 23, 50)
		var saved: Vector3 = rig.global_position
		rig.show_overview()
		settle()
		for corner in [Vector3(-250, 0, -250), Vector3(250, 0, -250), Vector3(250, 0, 250), Vector3(-250, 0, 250)]:
			var screen: Vector2 = rig.camera.unproject_position(corner)
			assert(screen.x >= 0 and screen.y >= 0 and screen.x <= viewport_size.x and screen.y <= viewport_size.y)
		rig.return_from_overview()
		settle()
		assert(saved.distance_to(rig.global_position) < 0.02)
		assert(absf(rig.camera.size - 83) < 0.01)
	root.size = Vector2i(1280, 960)
	await process_frame
	rig.set_view(Vector3.ZERO, 95, 0, 50)
	var hq := Node3D.new()
	hq.position = Vector3(70, 0, 70)
	hq.add_to_group("headquarters")
	root.add_child(hq)
	rig.focus_hq()
	settle()
	assert(rig.global_position.distance_to(hq.position) < 0.02)
	var fixture = load("res://tests/camera_focus_fixture.gd")
	for point in [Vector3(-90, 0, -30), Vector3(90, 0, 30)]:
		var unit := Node3D.new()
		unit.set_script(fixture)
		unit.add_to_group("units")
		unit.position = point
		root.add_child(unit)
	rig.focus_selection()
	settle()
	assert(rig.global_position.length() < 0.02 and rig.camera.size > 95)
	var result := {"cursor_anchor_error": cursor_error, "pan_30_vs_120_fps_target_error": frame_rate_error, "zoom_limits": true, "rotated_view_bounds": true, "camera_relative_pan": true, "rotation_release": true, "drag_and_focus_loss": true, "overview_fit_three_aspects_and_restore": true, "focus_hq_and_selection": true}
	FileAccess.open(OUTPUT + "camera_results.json", FileAccess.WRITE).store_string(JSON.stringify(result, "\t"))
	print("CAMERA_CHECKS_PASSED")
	quit(0)
