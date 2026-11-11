extends SceneTree
# Headless: the sculpted landscape (docs/LANDSCAPE_LOOKDEV.md) is saved in the scenery, keeps walkable ground level
# enough for units on the flat grid, keeps rock under Drone height and off walkable cells, stands one removable tree
# per Forest cell, and leaves the gameplay grid alone.
const DRONE_HEIGHT := 12.0
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func run() -> void:
	var settings: LandscapeSettings = load("res://assets/terrain/landscape_settings.tres")
	var region := settings.region
	var cells := FileAccess.get_file_as_bytes("res://assets/maps/terrain_cells.bin")
	var terrain = load("res://scenes/maps/terrain.tscn").instantiate()
	if not check(terrain.landscape == settings,"terrain.tscn should hold the landscape settings"): return
	var ground: MeshInstance3D = terrain.get_node_or_null("Landmarks/Landscape/Ground")
	var water: MeshInstance3D = terrain.get_node_or_null("Landmarks/Landscape/Water")
	if not check(ground != null and ground.mesh != null and water != null and water.mesh != null,"Landscape ground and water should be saved in the scenery before the scene runs"): return
	if not check(ground.mesh.surface_get_material(0) is ShaderMaterial and water.mesh.surface_get_material(0) is ShaderMaterial,"Landscape meshes need their saved materials"): return
	# Heights: gentle where units walk, and never up to where Drones fly.
	var vertices: PackedVector3Array = ground.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var highest := -INF
	var walk_low := 0.0
	var walk_high := 0.0
	var edge := 0.0
	for vertex in vertices:
		highest = maxf(highest,vertex.y)
		var x := vertex.x+250.0
		var z := vertex.z+250.0
		if x <= region.position.x+0.01 or z <= region.position.y+0.01 or x >= region.end.x-0.01 or z >= region.end.y-0.01: edge = maxf(edge,absf(vertex.y))
		# A vertex well inside open ground: every cell around it is grass or desert.
		var open := true
		for dz in range(-1,1):
			for dx in range(-1,1):
				var kind := int(cells[clampi(floori(z)+dz,0,499)*500+clampi(floori(x)+dx,0,499)])
				if kind != 0 and kind != 2: open = false
		if open:
			walk_low = minf(walk_low,vertex.y)
			walk_high = maxf(walk_high,vertex.y)
	print("Highest %.2f m, walkable %.3f to %.3f m, edge %.4f m, %d ground triangles" % [highest,walk_low,walk_high,edge,ground.mesh.get_faces().size()/3])
	if not check(highest < DRONE_HEIGHT and highest > 5.0,"Rock height wrong: %.2f" % highest): return
	if not check(walk_low > -0.35 and walk_high < 0.08,"Walkable ground strays from the flat grid: %.3f to %.3f" % [walk_low,walk_high]): return
	if not check(edge < 0.001,"The landscape should meet the flat map at height 0 along its edge"): return
	# The flat ground and the old mountains leave the region to the landscape.
	var flat: ShaderMaterial = load("res://assets/materials/terrain/terrain_surface.tres")
	var cut: Vector4 = flat.get_shader_parameter("landscape_region")
	if not check(cut.is_equal_approx(Vector4(region.position.x,region.position.y,region.end.x,region.end.y)/500.0),"Flat ground cut-out does not match the region: run build_landscape.gd"): return
	# Forest: one batch instance at most per Forest cell, each on its own cell, and the old patches are empty there.
	var forest: Node = terrain.get_node("Landmarks/Landscape/Forest")
	var trees := 0
	for batch in forest.get_children():
		var buffer: PackedFloat32Array = batch.multimesh.buffer
		if not check(buffer.size() == batch.multimesh.instance_count*16,"Forest batch has incomplete instance data"): return
		for i in range(batch.multimesh.instance_count):
			var x := floori(buffer[i*16+3]+250.0)
			var z := floori(buffer[i*16+11]+250.0)
			if not check(region.has_point(Vector2i(x,z)) and cells[z*500+x] == 3,"Forest scenery stands off a Forest cell at %d,%d" % [x,z]): return
			trees += 1
	var forest_cells := 0
	for z in range(region.position.y,region.end.y):
		for x in range(region.position.x,region.end.x):
			if cells[z*500+x] == 3: forest_cells += 1
	print("%d forest pieces on %d Forest cells" % [trees,forest_cells])
	if not check(trees > forest_cells/2,"Too little forest scenery: %d on %d cells" % [trees,forest_cells]): return
	# Nothing large on cells units can walk: boulders and cliffs stay on Mountain cells or their first metre.
	var triangles := ground.mesh.get_faces().size()/3+water.mesh.get_faces().size()/3
	for batch in terrain.get_node("Landmarks/Landscape").find_children("*","MultiMeshInstance3D",true,false):
		triangles += batch.multimesh.mesh.get_faces().size()/3*batch.multimesh.instance_count
		if not String(batch.name).contains("boulder"): continue
		var buffer: PackedFloat32Array = batch.multimesh.buffer
		for i in range(batch.multimesh.instance_count):
			var x := floori(buffer[i*16+3]+250.0)
			var z := floori(buffer[i*16+11]+250.0)
			if not check(cells[z*500+x] == 4,"A boulder stands on a cell units can reach at %d,%d" % [x,z]): return
	print("Landscape total %d triangles over %d square metres" % [triangles,region.get_area()])
	if not check(triangles < 450000,"Landscape over its triangle budget: %d" % triangles): return
	root.add_child(terrain)
	await process_frame
	var grid = terrain.get_node("Ground")
	if not check(grid.grid_size == Vector2i(500,500) and is_equal_approx(grid.tile_size,1.0),"Gameplay grid changed"): return
	# Clearing a Forest cell opens it, as before, and fells what stands on it. Pick a cell that holds a tree.
	var state: ForestStateVisuals = terrain.forest_state
	var cell := Vector2i(-1,-1)
	for part in range(state.batches.size()):
		if state.patch_cells[part] == 1 and cell.x < 0 and not state.indices[part].is_empty(): cell = state.indices[part].keys()[0]
	if not check(cell.x >= 0 and cells[cell.y*500+cell.x] == 3,"No tree is indexed to a Forest cell"): return
	if not check(grid.get_terrain(cell) == 3 and grid.clear_forest(cell) and grid.is_tile_valid(cell),"Clearing a Forest cell in the landscape should open it"): return
	if not check(state.is_felling(),"Clearing a cell with a tree should start it falling"): return
	# Half-way down a tree leans but still stands on its own spot; afterwards it is gone.
	var upright := Transform3D(Basis.IDENTITY,Vector3(3,0,4))
	var leaning := ForestStateVisuals.toppled(upright,Vector3.RIGHT,ForestStateVisuals.FALL_SECONDS*0.8)
	if not check(leaning.origin.is_equal_approx(upright.origin) and leaning.basis.y.y < 0.95 and leaning.basis.y.y > 0.2,"A falling tree should lean about its foot"): return
	state.advance(ForestStateVisuals.FALL_SECONDS+ForestStateVisuals.SINK_SECONDS+1.0)
	if not check(not state.is_felling(),"Felled trees should finish falling"): return
	print("LANDSCAPE_LOOKDEV_TEST_PASSED"); quit()
