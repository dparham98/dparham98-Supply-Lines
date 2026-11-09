extends SceneTree
# Headless: the terrain material carries the twelve ground tiles as texture arrays (docs/GROUND_TILES.md),
# and the gameplay terrain data they are drawn over is untouched by them.
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func run() -> void:
	var material: ShaderMaterial = load("res://assets/materials/terrain/terrain_surface.tres")
	for parameter in ["tile_albedo","tile_normal"]:
		var array = material.get_shader_parameter(parameter)
		if not check(array is TextureLayered and array.get_layers() == 12 and array.get_width() == 512 and array.get_height() == 512,parameter+" should be twelve 512 px layers"): return
		if not check(array.has_mipmaps(),parameter+" needs mipmaps or the ground shimmers when zoomed out"): return
	var code := material.shader.code
	for name in ["tile_metres","feature_share","surface_tint"]:
		if not check(code.contains("uniform float "+name),"Shader lost "+name): return
	if not check(code.contains("uniform float tile_metres = 4.0;"),"Tile size changed from 4 m"): return
	var terrain = load("res://scenes/maps/terrain.tscn").instantiate()
	root.add_child(terrain)
	await process_frame
	var ground = terrain.get_node("Ground")
	if not check(ground.material_override.shader == material.shader and ground.material_override.get_shader_parameter("tile_albedo") == material.get_shader_parameter("tile_albedo"),"Ground should use the terrain material saved in terrain.tscn"): return
	if not check(ground.grid_size == Vector2i(500,500) and is_equal_approx(ground.tile_size,1.0),"Gameplay grid changed"): return
	# One patch of trees for each forest spot, in all four variants, inside the geometry budget.
	var forests: Node = terrain.get_node("Landmarks/Forests")
	var spots := 0
	if not check(forests.get_child_count() == 4,"Forests should have four tile variants"): return
	for batch in forests.get_children():
		spots += batch.multimesh.instance_count
		var mesh: Mesh = batch.multimesh.mesh
		if not check(mesh.resource_path.begins_with("res://assets/models/terrain/forest_tile_"),"Forest batch uses the wrong mesh: "+mesh.resource_path): return
		if not check(mesh.get_faces().size()/3 <= 800,"Forest tile over budget: %d triangles" % (mesh.get_faces().size()/3)): return
	if not check(spots == 1646,"Forest spots changed: %d" % spots): return
	print("GROUND_TILES_TEST_PASSED"); quit()
