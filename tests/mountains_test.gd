extends SceneTree
# Headless: the sculpted mountains (docs/MOUNTAINS.md) are baked into the saved scenery, stay under Drone flight
# height, stay on the Mountain cells of the map, and leave gameplay terrain alone.
const DRONE_HEIGHT := 12.0
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func run() -> void:
	var terrain = load("res://scenes/maps/terrain.tscn").instantiate()
	var massif: MeshInstance3D = terrain.get_node_or_null("Landmarks/Mountains/Massif")
	if not check(massif != null and massif.mesh != null,"Mountains should be saved in the scenery before the scene runs"): return
	if not check(massif.mesh.resource_path == "res://assets/models/terrain/mountains.res","Massif uses the wrong mesh: "+massif.mesh.resource_path): return
	if not check(not terrain.get_node("Landmarks/Mountains").has_node("Rock"),"Old cone mountains still baked"): return
	if not check(massif.mesh.surface_get_material(0).resource_path == "res://assets/materials/terrain/mountain_massif.tres","Mountain material missing"): return
	var cells := FileAccess.get_file_as_bytes("res://assets/maps/terrain_cells.bin")
	var vertices: PackedVector3Array = massif.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	if not check(massif.mesh.get_faces().size()/3 <= 200000,"Mountain mesh over budget"): return
	var highest := -INF
	var stray := 0
	for vertex in vertices:
		highest = maxf(highest,vertex.y)
		# Anything taller than a Scout must stand within the wander of the outline from real Mountain ground.
		if vertex.y > 1.7:
			var near := false
			var cx := floori(vertex.x+250.0)
			var cz := floori(vertex.z+250.0)
			for dz in range(-3,4):
				for dx in range(-3,4):
					var x := cx+dx
					var z := cz+dz
					if x >= 0 and z >= 0 and x < 500 and z < 500 and cells[z*500+x] == 4: near = true
			if not near: stray += 1
	print("Highest %.2f m, %d vertices" % [highest,vertices.size()])
	if not check(highest < DRONE_HEIGHT and highest > 6.0,"Peak height wrong: %.2f" % highest): return
	if not check(stray == 0,"%d tall vertices are away from Mountain cells" % stray): return
	root.add_child(terrain)
	await process_frame
	var ground = terrain.get_node("Ground")
	var mountain_cell := Vector2i(-1,-1)
	for i in range(cells.size()):
		if cells[i] == 4:
			mountain_cell = Vector2i(i%500,i/500)
			break
	if not check(ground.get_terrain(mountain_cell) == 4 and not ground.is_tile_valid(mountain_cell),"Mountain cells should stay blocked"): return
	print("MOUNTAINS_TEST_PASSED"); quit()
