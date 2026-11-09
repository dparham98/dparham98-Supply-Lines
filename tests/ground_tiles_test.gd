extends SceneTree
# Headless: the terrain material carries the eight ground tiles as texture arrays (docs/GROUND_TILES.md),
# and the gameplay terrain data they are drawn over is untouched by them.
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func run() -> void:
	var material: ShaderMaterial = load("res://assets/materials/terrain/terrain_surface.tres")
	for parameter in ["tile_albedo","tile_normal"]:
		var array = material.get_shader_parameter(parameter)
		if not check(array is TextureLayered and array.get_layers() == 8 and array.get_width() == 512 and array.get_height() == 512,parameter+" should be eight 512 px layers"): return
		if not check(array.has_mipmaps(),parameter+" needs mipmaps or the ground shimmers when zoomed out"): return
	var code := material.shader.code
	for name in ["tile_metres","feature_share","surface_tint"]:
		if not check(code.contains("uniform float "+name),"Shader lost "+name): return
	if not check(code.contains("uniform float tile_metres = 4.0;"),"Tile size changed from 4 m"): return
	var terrain = load("res://scenes/maps/terrain.tscn").instantiate()
	root.add_child(terrain)
	await process_frame
	var ground = terrain.get_node("Ground")
	if not check(ground.material_override == material,"Ground should use the terrain material saved in terrain.tscn"): return
	if not check(ground.grid_size == Vector2i(500,500) and is_equal_approx(ground.tile_size,1.0),"Gameplay grid changed"): return
	print("GROUND_TILES_TEST_PASSED"); quit()
