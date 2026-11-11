extends SceneTree
# Builds the sculpted landscape of assets/terrain/landscape_settings.tres from terrain_cells.bin
# (docs/LANDSCAPE_LOOKDEV.md): the field texture, the ground and water meshes, and the cut-outs that stop the flat
# ground and the old mountains drawing inside the region. Run after changing the map cells, the region or the shape
# settings, then press Rebuild terrain scenery on terrain.tscn:
#   godot --headless --path . --script res://scripts/tools/build_landscape.gd
const SETTINGS := "res://assets/terrain/landscape_settings.tres"
const FIELDS := "res://assets/textures/terrain/landscape_fields.res"
const GROUND_DIR := "res://assets/models/terrain/landscape_ground"
const WATER_MESH := "res://assets/models/terrain/landscape_water.res"
const GROUND_MATERIAL := "res://assets/materials/terrain/landscape_ground.tres"
const WATER_MATERIAL := "res://assets/materials/terrain/landscape_water.tres"
const FLAT_MATERIAL := "res://assets/materials/terrain/terrain_surface.tres"
const MASSIF_MATERIAL := "res://assets/materials/terrain/mountain_massif.tres"

func _initialize() -> void:
	var settings: LandscapeSettings = load(SETTINGS)
	var cells := FileAccess.get_file_as_bytes("res://assets/maps/terrain_cells.bin")
	if settings == null or cells.size() != 250000:
		push_error("Landscape settings or map cells missing"); quit(1); return
	var builder = load("res://scripts/tools/landscape_builder.gd").new()
	builder.setup(cells,settings)
	# Saved as a resource, not a PNG: the importer's alpha handling would change the colour channels.
	if ResourceSaver.save(ImageTexture.create_from_image(builder.build_fields_image()),FIELDS,ResourceSaver.FLAG_COMPRESS) != OK:
		push_error("Could not save the landscape fields"); quit(1); return
	# One file per ground square. Squares left over from a larger region are removed.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(GROUND_DIR))
	for old in DirAccess.get_files_at(GROUND_DIR):
		if old.ends_with(".res"): DirAccess.remove_absolute(ProjectSettings.globalize_path(GROUND_DIR.path_join(old)))
	var tiles: Array[Mesh] = []
	var triangles := 0
	for ground: ArrayMesh in builder.build_ground_tiles():
		ground.surface_set_material(0,load(GROUND_MATERIAL))
		var path := GROUND_DIR.path_join("ground_%02d.res" % tiles.size())
		if ResourceSaver.save(ground,path,ResourceSaver.FLAG_COMPRESS) != OK:
			push_error("Could not save " + path); quit(1); return
		ground.take_over_path(path)
		tiles.append(ground)
		triangles += ground.get_faces().size()/3
	var water: ArrayMesh = builder.build_water_mesh()
	water.surface_set_material(0,load(WATER_MATERIAL))
	if ResourceSaver.save(water,WATER_MESH,ResourceSaver.FLAG_COMPRESS) != OK:
		push_error("Could not save the landscape water"); quit(1); return
	var region := Rect2(settings.region)
	var flat: ShaderMaterial = load(FLAT_MATERIAL)
	flat.set_shader_parameter("landscape_region",Vector4(region.position.x,region.position.y,region.end.x,region.end.y)/500.0)
	var massif: ShaderMaterial = load(MASSIF_MATERIAL)
	massif.set_shader_parameter("landscape_region",Vector4(region.position.x,region.position.y,region.end.x,region.end.y)-Vector4.ONE*250.0)
	if ResourceSaver.save(flat,FLAT_MATERIAL) != OK or ResourceSaver.save(massif,MASSIF_MATERIAL) != OK:
		push_error("Could not save the cut-outs"); quit(1); return
	settings.ground_tiles = tiles
	water.take_over_path(WATER_MESH)
	settings.water_mesh = water
	if ResourceSaver.save(settings,SETTINGS) != OK:
		push_error("Could not save the landscape settings"); quit(1); return
	print("LANDSCAPE_BUILT ground %d triangles in %d squares, water %d triangles" % [triangles,tiles.size(),water.get_faces().size()/3])
	quit()
