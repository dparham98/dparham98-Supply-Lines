extends SceneTree
const OUTPUT = "C:/Users/video/.codex/.chatgpt-projects/g-p-6ad16a23380c8191877dbcafdb316068/camera_work/"

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var scene := load("res://scenes/maps/supply_lines_world.tscn").instantiate() as Node3D
	root.add_child(scene)
	await process_frame
	await create_timer(0.65).timeout
	var ground = scene.get_node("Terrain/Ground")
	assert(ground.tiles.size() == 250000)
	var counts := [0, 0, 0, 0, 0, 0]
	var representatives := {}
	for z in range(500):
		for x in range(500):
			var cell := Vector2i(x, z)
			var t: int = ground.get_terrain(cell)
			counts[t] += 1
			if not representatives.has(t): representatives[t] = cell
	for t in range(6):
		assert(counts[t] > 0)
		var cell: Vector2i = representatives[t]
		var expected := t == 0 or t == 2
		assert(ground.is_tile_valid(cell) == expected)
		ground.set_tile_feature(cell, "buildable", true)
		assert(ground.is_tile_valid(cell) == expected)
		assert(ground.get_tile_at_position(ground.tile_to_world(cell)) == cell)
	assert(ground.get_tile_at_position(Vector3(250.1, 0, 0)) == null)
	assert(ground.get_tile_at_position(Vector3(-250.1, 0, 0)) == null)
	var hq = scene.get_node("Entities/Buildings/Headquarters")
	for z in range(hq.grid_position.y, hq.grid_position.y + hq.grid_size.y):
		for x in range(hq.grid_position.x, hq.grid_position.x + hq.grid_size.x):
			var cell := Vector2i(x, z)
			assert(ground.get_terrain(cell) in [0, 2])
			assert(not ground.is_tile_valid(cell))
	for name_ in ["Infantry", "Enemy"]:
		assert(ground.get_terrain(scene.get_node("Entities/Units/" + name_).grid_position) in [0, 2])
	assert(scene.get_node("Entities/Units/Infantry").grid_position != scene.get_node("Entities/Units/Enemy").grid_position)
	var start: Vector2i = ground.find_nearest_open_tile(Vector2i(155, 245))
	var goal: Vector2i = ground.find_nearest_open_tile(Vector2i(340, 245))
	var path: Array[Vector2i] = ground.get_terrain_path(start, goal)
	assert(path.size() > 2)
	for cell in path: assert(ground.get_terrain(cell) in [0, 2])
	for i in range(1, path.size()):
		var diff := path[i] - path[i - 1]
		if diff.x != 0 and diff.y != 0:
			assert(ground.get_terrain(path[i - 1] + Vector2i(diff.x, 0)) in [0, 2])
			assert(ground.get_terrain(path[i - 1] + Vector2i(0, diff.y)) in [0, 2])
	var infantry = scene.get_node("Entities/Units/Infantry")
	var selection_camera = scene.get_node("CameraRig/YawPivot/PitchPivot/Camera")
	scene.get_node("CameraRig").set_process(false)
	scene.get_node("CameraRig").focus_hq()
	for i in range(120): scene.get_node("CameraRig").advance_camera(1.0 / 60.0)
	var manager := get_root().get_node("SelectionManager")
	var screen: Vector2 = selection_camera.unproject_position(infantry.global_position + Vector3.UP * 0.5)
	manager.start_selection(screen)
	manager.end_selection(screen)
	assert(infantry.is_selected and infantry.get_node("SelectionRing").visible)
	var second := load("res://scenes/units/infantry.tscn").instantiate() as Node3D
	second.name = "SecondPlayerTest"
	var second_cell: Vector2i = ground.find_nearest_open_tile(infantry.grid_position + Vector2i(3, 1))
	second.position = ground.tile_to_world(second_cell)
	scene.get_node("Entities/Units").add_child(second)
	await create_timer(0.15).timeout
	var second_screen: Vector2 = selection_camera.unproject_position(second.global_position + Vector3.UP * 0.5)
	manager.start_selection(Vector2(minf(screen.x, second_screen.x) - 8, minf(screen.y, second_screen.y) - 8))
	manager.end_selection(Vector2(maxf(screen.x, second_screen.x) + 8, maxf(screen.y, second_screen.y) + 8))
	assert(infantry.is_selected and second.is_selected)
	assert(not scene.get_node("Entities/Units/Enemy").is_selected)
	ground.set_tile_feature(second.grid_position, "buildable", true)
	ground.set_tile_feature(second.grid_position, "occupied_by", null)
	second.queue_free()
	await process_frame
	var previous_selection: bool = infantry.is_selected
	infantry.is_selected = true
	infantry.can_attack = false
	infantry.attack_cooldown = 9999
	var unit_cell = ground.get_tile_at_position(infantry.position)
	# Isolate route-following from any command issued by the selection checks.
	ground.set_tile_feature(infantry.grid_position, "buildable", true)
	ground.set_tile_feature(infantry.grid_position, "occupied_by", null)
	infantry.is_moving = false
	infantry.grid_position = unit_cell
	var target: Vector2i = ground.find_nearest_open_tile(unit_cell + Vector2i(0, 6))
	# Choose a reachable destination even when the nearest open cell is across water.
	if ground.get_terrain_path(unit_cell, target).size() < 2:
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var candidate: Vector2i = unit_cell + offset
			if ground.get_terrain_path(unit_cell, candidate).size() >= 2:
				target = candidate
				break
	infantry.start_move(ground.tile_to_world(target, 0.5), target)
	assert(infantry.is_moving)
	for i in range(1000):
		infantry._process(0.08)
		var cell = ground.get_tile_at_position(infantry.position)
		assert(cell != null and ground.get_terrain(cell) in [0, 2])
		if not infantry.is_moving: break
	assert(not infantry.is_moving)
	assert(ground.get_tile_at_position(infantry.position) == target)
	infantry.is_selected = previous_selection
	var results := {"terrain_counts": counts, "hq_cell": [hq.grid_position.x, hq.grid_position.y], "terrain_rules_passed": true, "route_avoids_blocked_terrain": true, "unit_followed_route": true, "decorations": {"trees": scene.get_node("Terrain/Landmarks/Forests/Trunk").multimesh.instance_count}}
	var camera = scene.get_node("CameraRig/YawPivot/PitchPivot/Camera")
	scene.get_node("CameraRig").set_process(false)
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1280, 960)
		scene.get_node("CameraRig").show_overview()
		for i in range(180): scene.get_node("CameraRig").advance_camera(1.0 / 60.0)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUTPUT + "terrain_overview.png")
		scene.get_node("CameraRig").set_view(Vector3.ZERO, 140.0, 0, 50)
		await process_frame
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUTPUT + "terrain_closeup.png")
		results["screenshots_rendered"] = true
	FileAccess.open(OUTPUT + "terrain_test_results.json", FileAccess.WRITE).store_string(JSON.stringify(results, "\t"))
	print("TERRAIN_CHECKS_PASSED")
	quit(0)
