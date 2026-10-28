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
	var prototype := scene.instantiate()
	var parts: Array = []
	_collect(prototype, Transform3D.IDENTITY, parts)
	prototype.free()
	if parts.is_empty():
		push_error("Terrain asset needs at least one MeshInstance3D: " + scene.resource_path)
		return
	var group := Node3D.new()
	group.name = name_
	root.add_child(group)
	group.owner = root
	for part in parts:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = part["mesh"]
		mm.instance_count = placements.size()
		for i in range(placements.size()):
			mm.set_instance_transform(i, placements[i] * part["transform"])
			mm.set_instance_color(i, colors[i])
		var item := MultiMeshInstance3D.new()
		item.name = part["name"]
		item.multimesh = mm
		item.material_override = part["material"]
		group.add_child(item)
		item.owner = root

func build(tree_scene: PackedScene, mountain_scene: PackedScene, ore_scene: PackedScene, seed_: int = 2817) -> Node3D:
	var cells := FileAccess.get_file_as_bytes("res://assets/maps/terrain_cells.bin")
	assert(cells.size() == 250000)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
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
				trees.append(Transform3D(b, p))
				tree_colors.append(Color.WHITE * rng.randf_range(0.8, 1.18))
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
	_scatter(root, "Forests", tree_scene, trees, tree_colors)
	_scatter(root, "Mountains", mountain_scene, rocks, rock_colors)
	_scatter(root, "OreDeposits", ore_scene, ores, ore_colors)
	return root
