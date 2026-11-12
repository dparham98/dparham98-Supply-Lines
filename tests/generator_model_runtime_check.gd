extends SceneTree
# Rendered: the Generator (docs/GENERATOR_MODEL.md) at the game's camera and close up: a site going up, the
# finished generator standing cold, running on fuel, and the collapse. Saves generator_*.png. Also checks the
# finished Generator is pickable on its boiler. Pictures only; judge them by eye.
const Bounds = preload("res://scripts/units/selection_bounds.gd")
const TestOutput = preload("res://tests/test_output.gd")
const Burst = preload("res://scripts/components/burst_effect.gd")
var game: Node3D
var network: Node
var rig: Node
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func site(kind: StringName, near: Vector3) -> Vector3:
	var spec: Dictionary = network.plan_spec(kind)
	for radius in range(12,100,4):
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
	rig.min_zoom = 4.0      # close-ups below the player's zoom limit
	var point := site(&"generator",depot.global_position)
	if not check(point != Vector3.INF,"No Generator site"): return
	# A site half built, at the game's distance and close.
	var plan = network.queue_plan(point,&"generator")
	plan.set_process(false)
	plan.added = {&"iron": int(plan.spec.iron*0.5)}; plan.energy_paid = int(plan.spec.energy*0.5)
	plan.refresh_label()
	var centre: Vector3 = plan.get_node("Visuals/Model").global_position
	await shot(centre,30,"generator_site")
	await shot(centre+Vector3(0,1,0),8,"generator_site_close")
	plan.added = {}; plan.energy_paid = 0
	var building: Node3D = plan.complete_from_stock()
	if not check(building != null,"Generator plan did not complete"): return
	building.set_process(false)
	await process_frame
	var model: Node3D = building.get_node("Visuals/Model")
	if not building.assigned_depot: building.assign_source(depot)
	# Cold: no fuel.
	depot.wood = 0; depot.coal = 0
	building._process(0.1)
	model.player.advance(0.5)
	await shot(building.global_position,30,"generator_cold")
	var screen: Vector2 = rig.camera.unproject_position(building.global_position+Vector3(-0.3,2.4,0.0))
	if not check(Bounds.hit_distance(building,rig.camera,screen) < INF,"Generator not pickable on its boiler"): return
	await shot(building.global_position+Vector3(0,1,0),8,"generator_cold_close")
	# Running on wood.
	depot.wood = 20
	building._process(0.1)
	model.player.advance(1.3)
	await shot(building.global_position,30,"generator_running")
	await shot(building.global_position+Vector3(0,1,0),8,"generator_running_close")
	# The collapse, part way and as a wreck.
	building.take_damage(building.max_health)
	var effects: Node = model.get_children().filter(func(n): return n.get_script() == Burst)[0]
	model.player.advance(0.55); effects.player.advance(0.55)
	await shot(model.global_position+Vector3(0,1,0),11,"generator_dying")
	model.player.advance(1.6); effects.player.advance(1.6)
	await shot(model.global_position+Vector3(0,0.5,0),11,"generator_wreck")
	print("GENERATOR_MODEL_RUNTIME_CHECK_PASSED"); quit(TestOutput.exit_code())
