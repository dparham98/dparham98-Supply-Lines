extends SceneTree
# Rendered check: the Cargo vehicle's authored truck renders in the skirmish and is picked by selection
# bounds; a second shot shows it deployed with the lid and ramp open and the cargo indicator raised.
# Saves truck_road and truck_open.
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
	var truck = load("res://scenes/gameplay/cargo_vehicle.tscn").instantiate()
	truck.position = game.depot.global_position+Vector3(-8,0,10)
	game.get_node("Entities/Units").add_child(truck); truck.set_process(false)
	for frame in range(3): await process_frame
	var model = truck.get_node("Visuals/Model")
	if not check(model.scene_file_path == "res://scenes/models/cargo_truck_model.tscn","Cargo vehicle still uses the placeholder"): return
	var rig = game.get_node("CameraRig")
	rig.set_process(false)
	rig.focus_position(truck.global_position+Vector3(0,0,-1),14)
	for frame in range(180): rig.advance_camera(1.0/60)
	var screen: Vector2 = rig.camera.unproject_position(truck.selection_point())
	if not check(Bounds.hit_distance(truck,rig.camera,screen) < INF,"Truck model not pickable at its selection point"): return
	await shot("truck_road")
	for crate in [{kind = &"iron", amount = 25},{kind = &"iron", amount = 25}]: truck.crates.append(crate)
	truck._sync_reserved()
	truck.deploy_supplies()
	for i in range(150):
		truck._process(1.0/60); model._process(1.0/60)
	for frame in range(3): await process_frame
	if not check(truck.deployed and model.lid_angle() > 0.9 and model.ramp_angle() < -2.0,"Deployed truck should stand open: lid %.2f ramp %.2f" % [model.lid_angle(),model.ramp_angle()]): return
	await shot("truck_open")
	print("CARGO_TRUCK_MODEL_RUNTIME_CHECK_PASSED"); quit(TestOutput.exit_code())
