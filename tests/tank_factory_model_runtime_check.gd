extends SceneTree
# Rendered: the Tank Factory (docs/TANK_FACTORY_MODEL.md) at the game's camera and close up: a site going
# up, the finished plant, a Tank, a Motorcycle and a Drone each formed on the lift in their own shape, the Drone
# flying out of the roof, the Tank at the open door, and the collapse.
# Saves tank_factory_*.png. Also checks the finished Tank Factory is pickable on its roof. Pictures only;
# judge them by eye.
const Bounds = preload("res://scripts/units/selection_bounds.gd")
const TestOutput = preload("res://tests/test_output.gd")
var game: Node3D
var network: Node
var rig: Node
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func site(kind: StringName, near: Vector3) -> Vector3:
	var spec: Dictionary = network.plan_spec(kind)
	for radius in range(18,100,4):
		for offset in [Vector3(radius,0,0),Vector3(-radius,0,0),Vector3(0,0,radius),Vector3(0,0,-radius)]:
			var point: Vector3 = near+offset
			var start: Vector2i = network.footprint_start(point,spec.size)
			if network.plan_terrain_valid(start,spec.size,kind) and not network.plan_overlaps(start,spec.size) and network.can_place_size(point,game.depot,spec.size): return point
	return Vector3.INF
func shot(at: Vector3, distance: float, name: String) -> void:
	rig.focus_position(at,distance)
	for frame in range(150): rig.advance_camera(1.0/60)
	for frame in range(6): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(TestOutput.path(name+".png"))
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	network = game.get_node("DepotNetwork")
	game.set_process(false)
	for unit in get_nodes_in_group("units"): unit.set_process(false)
	for depot in get_nodes_in_group("depots"): depot.set_process(false)
	game.get_node("Interface").visible = false
	var depot = game.depot
	depot.storage_capacity = 10000
	depot.energy = 2000; depot.iron = 2000
	rig = game.get_node("CameraRig")
	rig.set_process(false)
	rig.min_zoom = 5.0      # close-ups below the player's zoom limit
	var point := site(&"tank_factory",depot.global_position)
	if not check(point != Vector3.INF,"No Tank Factory site"): return
	# A site 45% built, at the game's distance and close.
	var plan = network.queue_plan(point,&"tank_factory")
	plan.set_process(false)
	plan.added = {&"iron": int(plan.spec.iron*0.45)}; plan.energy_paid = int(plan.spec.energy*0.45)
	plan.refresh_label()
	var centre: Vector3 = plan.get_node("Visuals/Model").global_position
	await shot(centre,36,"tank_factory_site")
	await shot(centre+Vector3(0,0,1),15,"tank_factory_site_close")
	plan.added = {}; plan.energy_paid = 0
	var building: Node3D = plan.complete_from_stock()
	if not check(building != null,"Tank Factory plan did not complete"): return
	building.set_process(false)
	await process_frame
	var model: Node3D = building.get_node("Visuals/Model")
	await shot(building.global_position,36,"tank_factory_finished")
	var screen: Vector2 = rig.camera.unproject_position(building.global_position+Vector3(2.0,4.1,1.5))
	if not check(Bounds.hit_distance(building,rig.camera,screen) < INF,"Tank Factory not pickable on its roof"): return
	await shot(building.global_position+Vector3(0,0,1),15,"tank_factory_close")
	# Producing: each unit forms in its own shape under the weld seam while the crane brings plates; then the
	# finished Tank drives out of the open door.
	depot.energy = 9000; depot.iron = 9000
	var print_seconds: float = building.stats.print_seconds
	for id in ["motorcycle","drone"]:
		building.request_unit(StringName(id))
		building._process(print_seconds*0.45)
		await shot(building.global_position,13,"tank_factory_producing_%s" % id)
		if id == "drone":
			# It flies out of the roof well, up to its flying height.
			building._process(print_seconds*0.35)
			await shot(building.global_position,22,"tank_factory_drone_rising")
			building._process(print_seconds*0.15)
			await shot(building.global_position,30,"tank_factory_drone_out")
		building.pending.clear()
		building.progress = 0
		building._process(0.01)
		await process_frame
	building.request_unit(&"tank")
	building._process(print_seconds*0.45)
	await shot(building.global_position,13,"tank_factory_producing")
	building._process(print_seconds*0.25)
	await shot(building.global_position,13,"tank_factory_formed")
	building._process(print_seconds*0.29)
	await shot(building.global_position+Vector3(0,0,2.5),13,"tank_factory_door")
	# The collapse, part way and as a wreck.
	building.take_damage(building.max_health)
	model.player.advance(0.6)
	await shot(model.global_position+Vector3(0,0,1),18,"tank_factory_dying")
	model.player.advance(1.4)
	await shot(model.global_position+Vector3(0,0,1),18,"tank_factory_wreck")
	print("TANK_FACTORY_MODEL_RUNTIME_CHECK_PASSED"); quit(TestOutput.exit_code())
