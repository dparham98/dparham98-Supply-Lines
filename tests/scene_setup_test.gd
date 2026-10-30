extends SceneTree
const TestOutput = preload("res://tests/test_output.gd")
const OUTPUT = "camera_work/"
# rebuild_scenery() overwrites this tracked generated scene; the test restores its exact bytes.
const LANDMARKS = "res://scenes/maps/terrain_landmarks.tscn"
func _initialize() -> void: call_deferred("check_scenes")
func clear_scripts(n: Node) -> void:
	for child in n.get_children(): clear_scripts(child)
	n.set_script(null)
func restore_landmarks(original: PackedByteArray) -> bool:
	var handle := FileAccess.open(LANDMARKS, FileAccess.WRITE)
	if handle == null or not handle.store_buffer(original):
		printerr("LANDMARKS_RESTORE_FAILED: cannot write " + LANDMARKS); quit(1); return false
	handle.close()
	if FileAccess.get_file_as_bytes(LANDMARKS) != original:
		printerr("LANDMARKS_RESTORE_FAILED: contents differ after restore"); quit(1); return false
	return true
func check_scenes() -> void:
	var world := load("res://scenes/maps/supply_lines_world.tscn").instantiate() as Node3D
	# All visuals exist before adding the scene to the tree or running _ready().
	assert(world.get_node("Terrain/Ground").tiles.is_empty())
	assert(world.get_node("Terrain/Ground").mesh != null)
	assert(world.get_node("Terrain/Ground").material_override != null)
	assert(world.get_node("Terrain/Landmarks/Forests/Trunk").multimesh.instance_count == 1646)
	assert(world.get_node("Terrain/Landmarks/Mountains/Rock").multimesh.instance_count == 1300)
	assert(world.get_node("Terrain/Landmarks/OreDeposits/OreRock").multimesh.instance_count == 867)
	assert(world.has_node("Lighting/Sun"))
	assert(world.has_node("Interface/Legend/Contents/TerrainInfo"))
	assert(world.has_node("Entities/Units/Infantry/Visuals/Model/Body"))
	assert(world.has_node("Entities/Buildings/Headquarters/Visuals/Model/Body"))
	var unit := load("res://scenes/units/infantry.tscn").instantiate() as Node3D
	var slot := unit.get_node("Visuals")
	assert(slot.refresh_action.is_valid())
	slot.model_scene = load("res://scenes/models/enemy_placeholder.tscn")
	slot.refresh_model()
	assert(slot.get_node("Model").scene_file_path == "res://scenes/models/enemy_placeholder.tscn")
	unit.free()
	# A single-mesh scene is accepted as a replacement terrain prop.
	var baker = load("res://scripts/tools/terrain_baker.gd").new()
	var custom: Node3D = baker.build(load("res://scenes/models/infantry_placeholder.tscn"), load("res://scenes/terrain/mountain.tscn"), load("res://scenes/terrain/ore_deposit.tscn"))
	assert(custom.get_node("Forests/Body").multimesh.mesh is BoxMesh)
	assert(custom.get_node("Forests/Body").multimesh.instance_count == 1646)
	var baked_mesh: MultiMesh = custom.get_node("Forests/Body").multimesh
	assert(baked_mesh.buffer.size() == baked_mesh.instance_count*16)
	assert(baked_mesh.duplicate().buffer == baked_mesh.buffer)
	assert(not is_zero_approx(baked_mesh.buffer[3]) or not is_zero_approx(baked_mesh.buffer[11]))
	assert(baked_mesh.buffer[15] > 0)
	custom.free()
	var fixture := Node3D.new()
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = "CustomRock"
	mesh_node.mesh = BoxMesh.new()
	var painted := StandardMaterial3D.new()
	painted.albedo_color = Color.MAGENTA
	mesh_node.set_surface_override_material(0, painted)
	fixture.add_child(mesh_node)
	mesh_node.owner = fixture
	var fixture_scene := PackedScene.new()
	assert(fixture_scene.pack(fixture) == OK)
	fixture.free()
	var overridden: Node3D = baker.build(fixture_scene, load("res://scenes/terrain/mountain.tscn"), load("res://scenes/terrain/ore_deposit.tscn"))
	assert(overridden.get_node("Forests/CustomRock").multimesh.mesh.surface_get_material(0).albedo_color == Color.MAGENTA)
	overridden.free()
	var terrain := load("res://scenes/maps/terrain.tscn").instantiate() as Node3D
	assert(terrain.rebuild_action.is_valid())
	var original_landmarks := FileAccess.get_file_as_bytes(LANDMARKS)
	assert(not original_landmarks.is_empty())
	terrain.rebuild_scenery()
	assert(terrain.get_node("Landmarks").scene_file_path == "res://scenes/maps/terrain_landmarks.tscn")
	assert(terrain.get_node("Landmarks/Forests/Trunk").multimesh.instance_count == 1646)
	var rebuilt_mesh: MultiMesh = terrain.get_node("Landmarks/Forests/Trunk").multimesh
	var rebuilt_buffers_valid: bool = rebuilt_mesh.buffer.size() == rebuilt_mesh.instance_count*16 and rebuilt_mesh.duplicate().buffer == rebuilt_mesh.buffer
	terrain.free()
	if not restore_landmarks(original_landmarks): return
	assert(rebuilt_buffers_valid)
	# Static render proves visibility does not depend on runtime generation.
	clear_scripts(world)
	root.add_child(world)
	var camera := world.get_node("CameraRig/YawPivot/PitchPivot/Camera") as Camera3D
	root.size = Vector2i(1280, 960)
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		TestOutput.save_png(self, root.get_texture().get_image(), OUTPUT + "static_scene_preview.png")
	if not TestOutput.write_text(self, OUTPUT + "scene_setup_results.json", JSON.stringify({"editor_visuals_persist_without_ready": true, "unit_model_slot_swapped": true, "terrain_prefab_slot_swapped": true, "rebuild_button_saved_and_reloaded": true, "static_rendered": DisplayServer.get_name() != "headless"}, "\t")): return
	world.queue_free()
	await process_frame
	print("SCENE_SETUP_CHECKS_PASSED")
	quit(TestOutput.exit_code())
