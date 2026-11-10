extends SceneTree
func _initialize() -> void:
	call_deferred("check_edges")
func check_edges() -> void:
	root.size = Vector2i(1280,960)
	var rig = load("res://scenes/camera/rts_camera.tscn").instantiate()
	root.add_child(rig)
	await process_frame
	rig.set_process(false)
	var size := Vector2(1280, 960)
	var cases := [Vector2(0,480), Vector2(2,480), Vector2(1279,480), Vector2(640,0), Vector2(640,959), Vector2(0,0)]
	var keys := [Vector2.LEFT, Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN, Vector2(-1,-1).normalized()]
	for i in range(cases.size()):
		var edge: Vector2 = rig.edge_pan_vector(cases[i], size)
		assert(edge.is_equal_approx(keys[i]))
		for fast in [false, true]:
			var ends: Array[Vector3] = []
			for input in [edge, keys[i]]:
				rig.set_view(Vector3.ZERO,95,37,50)
				for frame in range(60):
					rig.apply_navigation(input,0,fast,1.0/60)
					rig.advance_camera(1.0/60)
				for frame in range(60):
					rig.apply_navigation(Vector2.ZERO,0,fast,1.0/60)
					rig.advance_camera(1.0/60)
				ends.append(rig.global_position)
			assert(ends[0].distance_to(ends[1]) < 0.001)
	assert(rig.edge_pan_vector(Vector2(640,480),size) == Vector2.ZERO)
	# Only the thin strip at the edge pans: a few pixels in, nothing moves.
	for inside in [Vector2(4,480),Vector2(30,480),Vector2(1275,480),Vector2(640,4),Vector2(640,955)]:
		assert(rig.edge_pan_vector(inside,size) == Vector2.ZERO)
	# The live pointer: on the edge it pans, off it it stops, and direction comes only from the sides touched.
	var motion := InputEventMouseMotion.new()
	for pair in [[Vector2(640,958),Vector2.DOWN],[Vector2(640,940),Vector2.ZERO],[Vector2(0,958),Vector2(-1,1).normalized()],[Vector2(300,958),Vector2.DOWN],[Vector2(640,480),Vector2.ZERO]]:
		motion.position = pair[0]; motion.global_position = pair[0]
		Input.parse_input_event(motion); Input.flush_buffered_events()
		assert(rig.pointer_edge_pan().is_equal_approx(pair[1]))
	# A pointer that has left the window does not keep panning from where it was.
	motion.position = Vector2(640,958); motion.global_position = motion.position
	Input.parse_input_event(motion); Input.flush_buffered_events()
	rig._pointer_outside = true
	assert(rig.pointer_edge_pan() == Vector2.ZERO)
	rig._pointer_outside = false
	# The cursor is held in the window in a real run only, so test scripts never capture it.
	assert(not rig.wants_cursor_confined())
	current_scene = rig
	assert(rig.wants_cursor_confined())
	rig.confine_cursor = false
	assert(not rig.wants_cursor_confined())
	rig.confine_cursor = true
	current_scene = null
	rig.set_view(Vector3.ZERO,95,0,50)
	rig.show_overview()
	for frame in range(180): rig.advance_camera(1.0/60)
	for frame in range(180):
		rig.apply_navigation(rig.edge_pan_vector(Vector2(1279,480),size),0,false,1.0/60)
		rig.advance_camera(1.0/60)
	assert(not rig.overview and is_equal_approx(rig._zoom_target,rig.default_zoom))
	assert(rig.global_position.x > 20)
	print("EDGE_PAN_CHECKS_PASSED")
	quit()
