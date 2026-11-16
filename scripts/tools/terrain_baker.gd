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
		parts.append({"name": node.name, "mesh": model, "transform": local, "material": node.material_override, "shadows": node.cast_shadow})
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
		item.cast_shadow = part["shadows"]
		group.add_child(item)
		item.owner = root

const DEFAULT_CELLS := "res://assets/maps/terrain_cells.bin"

## With forest_tiles, each forest spot takes one of those scenes in place of tree_scene.
## With mountain_mesh, that sculpted mesh replaces the scattered mountain_scene props.
## With landscape, its region gets the sculpted ground, water and scenery of docs/LANDSCAPE_LOOKDEV.md.
## cells_path is the map baked. With coal_scene, every Coal cell gets lumps of it. With forest_chunk above zero,
## the forest_tiles batches are split into squares that many metres across. shore holds the scenes that dress the
## water's edge, as arrays under "reeds", "rocks" and "lilies"; empty leaves the shore bare. With "basin" and
## "surface" meshes in it (scripts/tools/build_water_basin.gd) the water is sunk: both go into the scenery, the bed
## drawn with "ground_material", and the shore pieces stand on the bed or float at the water level.
func build(tree_scene: PackedScene, mountain_scene: PackedScene, ore_scene: PackedScene, seed_: int = 2817, forest_tiles: Array = [], mountain_mesh: Mesh = null, landscape: LandscapeSettings = null, cells_path: String = DEFAULT_CELLS, coal_scene: PackedScene = null, forest_chunk: int = 0, shore: Dictionary = {}) -> Node3D:
	var cells := FileAccess.get_file_as_bytes(cells_path)
	assert(cells.size() == 250000)
	var sculpted = load("res://scripts/tools/landscape_baker.gd").new() if landscape != null else null
	if sculpted != null: sculpted.settings = landscape
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
				# Where the landscape grows its own forest the old patch keeps its place in the batch, so every index
				# outside the region is unchanged, but has no size.
				if sculpted != null and sculpted.replaces_forest() and sculpted.covers(x, z): b = b.scaled(Vector3.ZERO)
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
					# As with forest: the landscape stands its own ore here, and the old rock keeps its place with no size.
					if sculpted != null and sculpted.replaces_ore() and sculpted.covers(x, z): ob = ob.scaled(Vector3.ZERO)
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
			if forest_chunk <= 0:
				_batches(root, forests, forest_tiles[i], typed_trees, typed_colors, "%02d" % (i+1))
				continue
			# One batch per square of the map, so only the squares in view are drawn.
			var squares := {}
			for j in range(typed_trees.size()):
				var square := Vector2i(floori((typed_trees[j].origin.x+250.0)/forest_chunk),floori((typed_trees[j].origin.z+250.0)/forest_chunk))
				if not squares.has(square): squares[square] = [[] as Array[Transform3D],[] as Array[Color]]
				squares[square][0].append(typed_trees[j])
				squares[square][1].append(typed_colors[j])
			var order := squares.keys()
			order.sort()
			for square in order:
				var square_trees: Array[Transform3D] = squares[square][0]
				var square_colors: Array[Color] = squares[square][1]
				_batches(root, forests, forest_tiles[i], square_trees, square_colors, "%02d_%d_%d" % [i+1,square.x,square.y])
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
	# Coal: two lumps on every Coal cell, from their own generator so nothing above moves on a map that gains coal.
	if coal_scene != null and cells.find(6) >= 0:
		var coal_rng := RandomNumberGenerator.new()
		coal_rng.seed = seed_+2
		var lumps: Array[Transform3D] = []
		var lump_colors: Array[Color] = []
		var at := cells.find(6)
		while at >= 0:
			var centre := Vector3(at%500+0.5-250, 0, at/500+0.5-250)
			for j in range(2):
				var lb := Basis(Vector3.UP, coal_rng.randf_range(0, TAU)).scaled(Vector3(coal_rng.randf_range(0.7, 1.1), coal_rng.randf_range(0.6, 1.35), coal_rng.randf_range(0.7, 1.1)))
				lumps.append(Transform3D(lb, centre + Vector3(coal_rng.randf_range(-0.3, 0.3), 0, coal_rng.randf_range(-0.3, 0.3))))
				var shade := coal_rng.randf_range(0.75, 1.2)
				lump_colors.append(Color(shade, shade, shade))
			at = cells.find(6, at+1)
		_scatter(root, "CoalDeposits", coal_scene, lumps, lump_colors)
	var sunk: bool = shore.get("basin") != null and shore.get("surface") != null
	if sunk:
		var water := Node3D.new()
		water.name = "Water"
		root.add_child(water)
		water.owner = root
		for part in [["Bed", shore["basin"], shore.get("ground_material")], ["Surface", shore["surface"], null]]:
			var node := MeshInstance3D.new()
			node.name = part[0]
			node.mesh = part[1]
			node.material_override = part[2]
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			water.add_child(node)
			node.owner = root
	_shore(root, cells, seed_+3, shore, sculpted, forest_chunk, sunk)
	if sculpted != null: sculpted.add_to(root, cells, landscape, self)
	return root

# Reeds and rocks in the first water cells out from land, lily pads a little further, all in drifts rather than
# evenly. Only Water cells are dressed, which nothing walks on or builds on. From its own generator, so nothing
# else moves on a map that gains a shore.
func _shore(root: Node3D, cells: PackedByteArray, seed_: int, shore: Dictionary, sculpted, chunk: int, sunk: bool) -> void:
	var reeds: Array = shore.get("reeds", [])
	var stones: Array = shore.get("rocks", [])
	var lilies: Array = shore.get("lilies", [])
	if reeds.is_empty() and stones.is_empty() and lilies.is_empty(): return
	# Cells out from the nearest land, up to 6.
	var out := PackedByteArray()
	out.resize(250000)
	var edge: Array[int] = []
	for i in range(250000):
		out[i] = 0 if cells[i] != 1 else 255
		if cells[i] != 1: continue
		var x := i%500
		var z := i/500
		if (x > 0 and cells[i-1] != 1) or (x < 499 and cells[i+1] != 1) or (z > 0 and cells[i-500] != 1) or (z < 499 and cells[i+500] != 1):
			out[i] = 1
			edge.append(i)
	var head := 0
	while head < edge.size():
		var i := edge[head]; head += 1
		if out[i] >= 6: continue
		for j in [i-1,i+1,i-500,i+500]:
			if j < 0 or j >= 250000 or absi(j%500-i%500) > 1 or out[j] != 255: continue
			out[j] = out[i]+1
			edge.append(j)
	# Where the drawn shore runs, so each piece stands on the bank, on the bed or on the water as it should.
	var ShoreField = load("res://scripts/tools/shore_field.gd")
	var field = ShoreField.new(cells)
	var level: float = ShoreField.WATER_LEVEL if sunk else 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var drifts := FastNoiseLite.new()
	drifts.seed = seed_
	drifts.frequency = 0.09
	var placed := {}
	for z in range(500):
		for x in range(500):
			var d := int(out[z*500+x])
			if d == 0 or d > 6: continue
			if sculpted != null and sculpted.covers(x, z): continue
			var reed_drift := drifts.get_noise_2d(x, z)
			var lily_drift := drifts.get_noise_2d(x*1.7+300.0, z*1.7-120.0)
			var centre := Vector3(x+0.5-250, 0, z+0.5-250)
			if not reeds.is_empty() and d <= 2 and reed_drift > 0.02:
				for j in range(2 if d == 1 else 1):
					if rng.randf() > 0.75: continue
					var basis := Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3.ONE*rng.randf_range(0.75, 1.25)*(1.0 if d == 1 else 0.8))
					var at := centre+Vector3(rng.randf_range(-0.45, 0.45), 0, rng.randf_range(-0.45, 0.45))
					var tint := Color.WHITE*rng.randf_range(0.8, 1.1)
					# Rooted in the bed; none in water deeper than the reeds could stand in.
					var into: float = field.shore(at.x+250.0, at.z+250.0)
					if into > 1.6: continue
					at.y = (ShoreField.bed(into) if sunk else 0.0)-0.03
					_shore_place(placed, reeds[rng.randi_range(0, reeds.size()-1)], Transform3D(basis, at), tint, chunk)
			if not stones.is_empty() and d == 1 and rng.randf() < 0.07:
				var basis := Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3.ONE*rng.randf_range(0.45, 1.0))
				var at := centre+Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
				var tint := Color.WHITE*rng.randf_range(0.8, 1.1)
				at.y = (maxf(ShoreField.bed(field.shore(at.x+250.0, at.z+250.0)), level-0.25) if sunk else 0.0)-0.08
				_shore_place(placed, stones[rng.randi_range(0, stones.size()-1)], Transform3D(basis, at), tint, chunk)
			if not lilies.is_empty() and d >= 2 and d <= 5 and lily_drift > 0.22 and rng.randf() < 0.3:
				var basis := Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3.ONE*rng.randf_range(0.9, 1.5))
				var at := centre+Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4))
				var tint := Color.WHITE*rng.randf_range(0.85, 1.1)
				# Afloat, and only where the drawn water is wide enough to hold the whole cluster.
				if field.shore(at.x+250.0, at.z+250.0) < 1.3: continue
				at.y = level+0.025
				_shore_place(placed, lilies[rng.randi_range(0, lilies.size()-1)], Transform3D(basis, at), tint, chunk)
	if placed.is_empty(): return
	var group := Node3D.new()
	group.name = "Shore"
	root.add_child(group)
	group.owner = root
	for scene in placed:
		var squares: Array = placed[scene].keys()
		squares.sort()
		for square in squares:
			var transforms: Array[Transform3D] = placed[scene][square][0]
			var colors: Array[Color] = placed[scene][square][1]
			_batches(root, group, scene, transforms, colors, "_%s_%d_%d" % [scene.resource_path.get_file().get_basename(),square.x,square.y])

func _shore_place(placed: Dictionary, scene: PackedScene, transform: Transform3D, tint: Color, chunk: int) -> void:
	var square := Vector2i.ZERO if chunk <= 0 else Vector2i(floori((transform.origin.x+250.0)/chunk),floori((transform.origin.z+250.0)/chunk))
	if not placed.has(scene): placed[scene] = {}
	if not placed[scene].has(square): placed[scene][square] = [[] as Array[Transform3D],[] as Array[Color]]
	placed[scene][square][0].append(transform)
	placed[scene][square][1].append(tint)
