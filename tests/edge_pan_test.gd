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
	var cases := [Vector2(0,480), Vector2(63,480), Vector2(1279,480), Vector2(640,0), Vector2(640,959), Vector2(0,0)]
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
	# Dragging past a side keeps panning that way (windowed play), diagonals included.
	assert(rig.edge_pan_vector(Vector2(1281,480),size) == Vector2.RIGHT)
	assert(rig.edge_pan_vector(Vector2(640,1200),size) == Vector2.DOWN)
	assert(rig.edge_pan_vector(Vector2(-30,-30),size).is_equal_approx(Vector2(-1,-1).normalized()))
	# Over the HUD only the outermost strip pans, so the bottom of the screen still works in fullscreen.
	assert(rig.edge_pan_vector(Vector2(640,959),size,rig.ui_edge_margin) == Vector2.DOWN)
	assert(rig.edge_pan_vector(Vector2(640,940),size,rig.ui_edge_margin) == Vector2.ZERO)
	assert(rig.edge_pan_vector(Vector2(640,940),size) == Vector2.DOWN)
	# The live pointer: a pointer that left the window pans from the edge it last touched.
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(640,955); motion.global_position = motion.position
	Input.parse_input_event(motion); Input.flush_buffered_events()
	rig._pointer_outside = true
	assert(rig.pointer_edge_pan() == Vector2.DOWN)
	rig._pointer_outside = false
	motion.position = Vector2(640,480); motion.global_position = motion.position
	Input.parse_input_event(motion); Input.flush_buffered_events()
	assert(rig.pointer_edge_pan() == Vector2.ZERO)
	# The drag direction steers the pan inside a band: diagonal motion into the bottom pans diagonally,
	# straight motion pans straight, and a still or sideways-sliding pointer keeps the last direction.
	var diagonal := Vector2(1,1).normalized()
	for pair in [[Vector2(600,905),Vector2.DOWN],[Vector2(640,945),diagonal],[Vector2(640,946),diagonal],[Vector2(640,955),Vector2.DOWN],[Vector2(700,955),Vector2.DOWN],[Vector2(640,480),Vector2.ZERO],[Vector2(1240,480),Vector2.RIGHT],[Vector2(1275,445),Vector2(1,-1).normalized()],[Vector2(1275,400),Vector2(1,-1).normalized()]]:
		motion.position = pair[0]; motion.global_position = pair[0]
		Input.parse_input_event(motion); Input.flush_buffered_events()
		var pan: Vector2 = rig.pointer_edge_pan()
		assert(pan.is_equal_approx(pair[1]))
	var hud = load("res://scenes/ui/terrain_hud.tscn").instantiate()
	assert(hud.get_node("Legend").get_meta("edge_pan_passthrough", false))
	hud.free()
	var selection_hud = load("res://scenes/ui/skirmish_hud.tscn").instantiate()
	# Playtest feedback (2026-10-29): the HUD blocks the wide band; only its outermost strip pans.
	assert(not selection_hud.get_node("Bottom").get_meta("edge_pan_passthrough", false))
	selection_hud.free()
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
