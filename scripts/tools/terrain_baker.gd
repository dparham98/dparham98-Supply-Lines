extends RefCounted

func _collect(node: Node, parent_transform: Transform3D, parts: Array) -> void:
	var local := parent_transform
	if node is Node3D: local = parent_transform * node.transform
	if node is MeshInstance3D and node.mesh:
		var model: Mesh = node.mesh
		for surface in range(node.mesh.get_surface_count()):
			var override: Material = node.get_surface_override_material(surface)
			if override:
				if model == node.mesh: model = node.mesh.duplicate()
				model.surface_set_material(surface, override)
		parts.append({"name": node.name, "mesh": model, "transform": local, "material": node.material_override})
	for child in node.get_children(): _collect(child, local, parts)

func _scatter(root: Node3D, name_: String, scene: PackedScene, placements: Array[Transform3D], colors: Array[Color]) -> void:
	var group := Node3D.new()
	group.name = name_
	root.add_child(group)
	group.owner = root
	_batches(root, group, scene, placements, colors, "")

# One batch per mesh of the scene, named after the mesh plus a suffix when a group holds several scenes.
func _batches(root: Node3D, group: Node3D, scene: PackedScene, placements: Array[Transform3D], colors: Array[Color], suffix: String) -> void:
	var prototype := scene.instantiate()
	var parts: Array = []
	_collect(prototype, Transform3D.IDENTITY, parts)
	prototype.free()
	if parts.is_empty():
		push_error("Terrain asset needs at least one MeshInstance3D: " + scene.resource_path)
		return
	for part in parts:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = part["mesh"]
		mm.instance_count = placements.size()
		# Keep the serialized data on the CPU too: the headless rendering backend does
		# not retain buffers populated only through individual instance setters.
		var buffer := PackedFloat32Array()
		buffer.resize(placements.size()*16)
		for i in range(placements.size()):
			var transform: Transform3D = placements[i] * part["transform"]
			var color: Color = colors[i]
			var values := PackedFloat32Array([
				transform.basis.x.x,transform.basis.y.x,transform.basis.z.x,transform.origin.x,
				transform.basis.x.y,transform.basis.y.y,transform.basis.z.y,transform.origin.y,
				transform.basis.x.z,transform.basis.y.z,transform.basis.z.z,transform.origin.z,
				color.r,color.g,color.b,color.a])
			for component in range(16): buffer[i*16+component] = values[component]
		mm.buffer = buffer
		var item := MultiMeshInstance3D.new()
		item.name = str(part["name"]) + suffix
		item.multimesh = mm
		item.material_override = part["material"]
		group.add_child(item)
		item.owner = root

## With forest_tiles, each forest spot takes one of those scenes in place of tree_scene.
## With mountain_mesh, that sculpted mesh replaces the scattered mountain_scene props.
func build(tree_scene: PackedScene, mountain_scene: PackedScene, ore_scene: PackedScene, seed_: int = 2817, forest_tiles: Array = [], mountain_mesh: Mesh = null) -> Node3D:
	var cells := FileAccess.get_file_as_bytes("res://assets/maps/terrain_cells.bin")
	assert(cells.size() == 250000)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	# Separate generator, so rocks and ore keep their places whichever forest is used.
	var tile_rng := RandomNumberGenerator.new()
	tile_rng.seed = seed_+1
	var tile_trees: Array = []
	var tile_colors: Array = []
	for i in range(forest_tiles.size()):
		tile_trees.append([] as Array[Transform3D])
		tile_colors.append([] as Array[Color])
	var trees: Array[Transform3D] = []
	var tree_colors: Array[Color] = []
	var rocks: Array[Transform3D] = []
	var rock_colors: Array[Color] = []
	var ores: Array[Transform3D] = []
	var ore_colors: Array[Color] = []
	for z in range(1, 499, 2):
		for x in range(1, 499, 2):
			var t := int(cells[z * 500 + x])
			var p := Vector3(x + 0.5 - 250, 0, z + 0.5 - 250)
			var scale_ := rng.randf_range(0.8, 1.25)
			var b := Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3.ONE * scale_)
			if t == 3:
				p.x += rng.randf_range(-0.3, 0.3)
				p.z += rng.randf_range(-0.3, 0.3)
				var tint: Color = Color.WHITE * rng.randf_range(0.8, 1.18)
				if forest_tiles.is_empty():
					trees.append(Transform3D(b, p))
					tree_colors.append(tint)
				else:
					var tile := tile_rng.randi_range(0, forest_tiles.size()-1)
					tile_trees[tile].append(Transform3D(b, p))
					tile_colors[tile].append(tint)
			elif t == 4 and x % 4 == 1 and z % 4 == 1:
				var h := rng.randf_range(3, 7.5)
				rocks.append(Transform3D(b.scaled(Vector3(1, h / 5, 1)), p))
				rock_colors.append(Color.WHITE * rng.randf_range(0.7, 1.2))
			elif t == 5:
				for j in range(3):
					var ob := Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3(rng.randf_range(0.5, 1), rng.randf_range(0.4, 1.2), rng.randf_range(0.5, 1)))
					ores.append(Transform3D(ob, p + Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4))))
					ore_colors.append(Color(1, rng.randf_range(0.65, 1), rng.randf_range(0.65, 1)))
	var root := Node3D.new()
	root.name = "Landmarks"
	if forest_tiles.is_empty():
		_scatter(root, "Forests", tree_scene, trees, tree_colors)
	else:
		var forests := Node3D.new()
		forests.name = "Forests"
		root.add_child(forests)
		forests.owner = root
		for i in range(forest_tiles.size()):
			var typed_trees: Array[Transform3D] = tile_trees[i]
			var typed_colors: Array[Color] = tile_colors[i]
			_batches(root, forests, forest_tiles[i], typed_trees, typed_colors, "%02d" % (i+1))
	if mountain_mesh == null:
		_scatter(root, "Mountains", mountain_scene, rocks, rock_colors)
	else:
		var mountains := Node3D.new()
		mountains.name = "Mountains"
		root.add_child(mountains)
		mountains.owner = root
		var massif := MeshInstance3D.new()
		massif.name = "Massif"
		massif.mesh = mountain_mesh
		mountains.add_child(massif)
		massif.owner = root
	_scatter(root, "OreDeposits", ore_scene, ores, ore_colors)
	return root
