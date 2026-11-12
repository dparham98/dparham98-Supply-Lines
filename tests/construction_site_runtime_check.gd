extends SceneTree
# Rendered: the fenced construction sites (docs/CONSTRUCTION_SITE_MODEL.md). Shots of each footprint size in the
# skirmish: a Generator site waiting for materials, an Iron Mine site with its materials on, a Barracks site
# a third built, then nearly up with its clutter cleared, a Tank Factory site half built and a Depot site. Pictures only; judge them
# by eye.
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
	var best := Vector3.INF
	for dz in range(-40,41,2):
		for dx in range(-40,41,2):
			var point: Vector3 = near+Vector3(dx,0,dz)
			if point.distance_to(near) >= best.distance_to(near): continue
			var start: Vector2i = network.footprint_start(point,spec.size)
			if not network.plan_terrain_valid(start,spec.size,kind) or network.plan_overlaps(start,spec.size): continue
			if kind == &"iron_mine" and not network.can_place_mine(point,game.depot): continue
			if kind != &"iron_mine" and not network.can_place_size(point,game.depot,spec.size): continue
			best = point
	return best
func shot(at: Vector3, distance: float, name: String) -> void:
	rig.focus_position(at,distance)
	for frame in range(150): rig.advance_camera(1.0/60)
	for frame in range(8): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(TestOutput.path(name+".png"))
func place(kind: StringName, near: Vector3) -> Node3D:
	var point := site(kind,near)
	if point == Vector3.INF: return null
	var plan = network.queue_plan(point,kind)
	if plan != null: plan.set_process(false)
	return plan
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
	depot.storage_capacity = 20000
	depot.energy = 9000; depot.iron = 9000
	rig = game.get_node("CameraRig")
	rig.set_process(false)
	rig.min_zoom = 4.0
	var generator := place(&"generator",depot.global_position+Vector3(14,0,4))
	if not check(generator != null,"No generator site"): return
	generator.refresh_state()
	await shot(generator.global_position,12,"site_3x3_waiting")
	var mine := place(&"iron_mine",depot.global_position+Vector3(-8,0,24))
	if not check(mine != null,"No mine site"): return
	mine.receive(&"iron",mine.spec.iron)
	mine.refresh_state()
	await shot(mine.global_position,10,"site_2x2_ready")
	var barracks := place(&"barracks",depot.global_position+Vector3(-18,0,-6))
	if not check(barracks != null,"No barracks site"): return
	barracks.receive(&"iron",barracks.spec.iron)
	while barracks.progress_fraction() < 0.33: barracks.work(null,5)
	await shot(barracks.global_position,18,"site_6x6_building")
	while barracks.progress_fraction() < 0.8: barracks.work(null,5)
	await shot(barracks.global_position,18,"site_6x6_nearly_up")
	var factory := place(&"tank_factory",depot.global_position+Vector3(22,0,-22))
	if not check(factory != null,"No tank factory site"): return
	factory.receive(&"iron",factory.spec.iron)
	while factory.progress_fraction() < 0.5: factory.work(null,5)
	await shot(factory.global_position,22,"site_8x8_building")
	var new_depot := place(&"depot",depot.global_position+Vector3(0,0,-34))
	if not check(new_depot != null,"No depot site"): return
	new_depot.refresh_state()
	await shot(new_depot.global_position,26,"site_10x10_waiting")
	await shot(depot.global_position+Vector3(-4,0,6),48,"site_overview")
	print("CONSTRUCTION_SITE_RUNTIME_CHECK_PASSED"); quit(TestOutput.exit_code())
