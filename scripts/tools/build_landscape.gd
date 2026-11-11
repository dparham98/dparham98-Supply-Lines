extends SceneTree
# Builds the sculpted landscape of assets/terrain/landscape_settings.tres from terrain_cells.bin
# (docs/LANDSCAPE_LOOKDEV.md): the field texture, the ground and water meshes, and the cut-outs that stop the flat
# ground and the old mountains drawing inside the region. Run after changing the map cells, the region or the shape
# settings, then press Rebuild terrain scenery on terrain.tscn:
#   godot --headless --path . --script res://scripts/tools/build_landscape.gd
const SETTINGS := "res://assets/terrain/landscape_settings.tres"
const FIELDS := "res://assets/textures/terrain/landscape_fields.res"
const GROUND_MESH := "res://assets/models/terrain/landscape_ground.res"
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
	var ground: ArrayMesh = builder.build_ground_mesh()
	ground.surface_set_material(0,load(GROUND_MATERIAL))
	var water: ArrayMesh = builder.build_water_mesh()
	water.surface_set_material(0,load(WATER_MATERIAL))
	if ResourceSaver.save(ground,GROUND_MESH,ResourceSaver.FLAG_COMPRESS) != OK or ResourceSaver.save(water,WATER_MESH,ResourceSaver.FLAG_COMPRESS) != OK:
		push_error("Could not save the landscape meshes"); quit(1); return
	var region := Rect2(settings.region)
	var flat: ShaderMaterial = load(FLAT_MATERIAL)
	flat.set_shader_parameter("landscape_region",Vector4(region.position.x,region.position.y,region.end.x,region.end.y)/500.0)
	var massif: ShaderMaterial = load(MASSIF_MATERIAL)
	massif.set_shader_parameter("landscape_region",Vector4(region.position.x,region.position.y,region.end.x,region.end.y)-Vector4.ONE*250.0)
	if ResourceSaver.save(flat,FLAT_MATERIAL) != OK or ResourceSaver.save(massif,MASSIF_MATERIAL) != OK:
		push_error("Could not save the cut-outs"); quit(1); return
	if settings.ground_mesh == null or settings.water_mesh == null:
		settings.ground_mesh = load(GROUND_MESH)
		settings.water_mesh = load(WATER_MESH)
		ResourceSaver.save(settings,SETTINGS)
	print("LANDSCAPE_BUILT ground %d triangles, water %d triangles" % [ground.get_faces().size()/3,water.get_faces().size()/3])
	quit()
