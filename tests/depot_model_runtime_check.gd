extends SceneTree
# Rendered: the Depot uses the authored warehouse model (docs/DEPOT_MODEL.md). It stands on the ground,
# stays inside its footprint, keeps the rail row south of it clear, and is pickable. Saves depot_model.
const Bounds = preload("res://scripts/units/selection_bounds.gd")
const TestOutput = preload("res://tests/test_output.gd")
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	game.set_process(false)
	for unit in get_nodes_in_group("units"): unit.set_process(false)
	var depot: Node3D = game.depot
	if not check(depot.get_node("Visuals/Model").scene_file_path == "res://scenes/models/depot_model.tscn","Depot still uses the prototype model"): return
	var meshes := Bounds.meshes(depot)
	if not check(meshes.size() > 30,"Depot model meshes missing: %d" % meshes.size()): return
	var low := Vector3(INF,INF,INF)
	var high := -low
	for mesh in meshes:
		for i in range(8):
			var p: Vector3 = depot.global_transform.affine_inverse()*(mesh.global_transform*mesh.get_aabb().get_endpoint(i))
			low = low.min(p); high = high.max(p)
	if not check(absf(low.y) < 0.05 and high.y > 5.5 and high.y < 7.0,"Depot not on the ground or wrong height: %.2f..%.2f" % [low.y,high.y]): return
	var half := Vector2(depot.footprint)*0.5
	if not check(low.x >= -half.x and high.x <= half.x and low.z >= -half.y and high.z <= half.y,"Model leaves its footprint: %s..%s, half %s" % [low,high,half]): return
	if not check(high.x-low.x > 15.5 and high.z-low.z > 8.5,"Model is not at world scale 0.6: %s..%s" % [low,high]): return
	var rig = game.get_node("CameraRig")
	rig.set_process(false)
	rig.focus_position(depot.global_position+Vector3(0,0,3),32)
	for frame in range(180): rig.advance_camera(1.0/60)
	var screen: Vector2 = rig.camera.unproject_position(depot.global_position+Vector3(0,3,0))
	if not check(Bounds.hit_distance(depot,rig.camera,screen) < INF,"Depot model not pickable at its centre"): return
	for frame in range(8): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(TestOutput.path("depot_model.png"))
	print("DEPOT_MODEL_RUNTIME_CHECK_PASSED"); quit(TestOutput.exit_code())
