extends SceneTree
# Rendered check: the Tank's authored model (assets/models/units/tank.glb) sits on the ground,
# faces -Z, keeps a one-tile-ish footprint, and is picked by selection bounds. Saves tank_model.
const TestOutput = preload("res://tests/test_output.gd")
const Bounds = preload("res://scripts/units/selection_bounds.gd")
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func shot(name: String) -> void:
	for frame in range(4): await process_frame
	root.get_texture().get_image().save_png(TestOutput.path(name+".png"))
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	game.set_process(false)
	for unit in get_nodes_in_group("units"): unit.set_process(false)
	var tank = load("res://scenes/gameplay/tank.tscn").instantiate()
	tank.position = game.depot.global_position+Vector3(-8,0,10)
	game.get_node("Entities/Units").add_child(tank); tank.set_process(false)
	for frame in range(3): await process_frame
	var model = tank.get_node("Visuals/Model")
	if not check(model.scene_file_path == "res://scenes/models/tank_model.tscn","Tank still uses the placeholder"): return
	var meshes := Bounds.meshes(tank)
	if not check(meshes.size() > 40,"Tank model meshes missing: %d" % meshes.size()): return
	var low := INF; var high := -INF; var front := INF; var back := -INF; var left := INF; var right := -INF
	for mesh in meshes:
		for i in range(8):
			var p: Vector3 = tank.global_transform.affine_inverse()*(mesh.global_transform*mesh.get_aabb().get_endpoint(i))
			low = minf(low,p.y); high = maxf(high,p.y); front = minf(front,p.z); back = maxf(back,p.z); left = minf(left,p.x); right = maxf(right,p.x)
	if not check(absf(low) < 0.05 and high < 2.2,"Tank not on the ground or too tall (%.2f..%.2f)" % [low,high]): return
	# The barrel points -Z: the model reaches further forward than back, and is wider than a tile but under three.
	if not check(front < -2.5 and back < 2.0 and right-left > 2.0 and right-left < 3.0,"Tank size or facing wrong: z %.2f..%.2f, x %.2f..%.2f" % [front,back,left,right]): return
	var rig = game.get_node("CameraRig")
	rig.set_process(false)
	rig.focus_position(tank.global_position+Vector3(0,0,-1),20)
	for frame in range(180): rig.advance_camera(1.0/60)
	var screen: Vector2 = rig.camera.unproject_position(tank.global_position+Vector3(0,0.6,0))
	if not check(Bounds.hit_distance(tank,rig.camera,screen) < INF,"Tank model not pickable at its centre"): return
	await shot("tank_model")
	print("TANK_MODEL_RUNTIME_CHECK_PASSED"); quit(TestOutput.exit_code())
