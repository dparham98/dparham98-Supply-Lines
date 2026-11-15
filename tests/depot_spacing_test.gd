extends SceneTree
# Headless: a new Depot must stand at least DepotRules.min_depot_spacing (70 m) from every other friendly
# Depot and Depot plan (docs/ECONOMY_REPORT.md step 6), whether planned, built or deployed from a truck.
# Authored Depots are not checked.
const SCENE := "res://scenes/maps/balanced_skirmish.tscn"
var game: Node3D
var ground: Node3D
var network: Node
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
## A point whose Depot footprint is clear, between `least` and `most` metres from `from`, or INF.
func depot_site(from: Vector3, least: float, most: float) -> Vector3:
	var size := Vector2i(10,10)
	var centre: Vector2i = ground.get_tile_at_position(from)
	var reach := ceili(most)
	for r in range(ceili(least),reach+1,2):
		for step in range(0,360,10):
			var point: Vector3 = from+Vector3(cos(deg_to_rad(step)),0,sin(deg_to_rad(step)))*r
			var cell = ground.get_tile_at_position(point)
			if cell == null: continue
			var start: Vector2i = cell-size/2
			if network.plan_terrain_valid(start,size,&"depot") and not network.plan_overlaps(start,size): return point
	return Vector3.INF
func run() -> void:
	game = load(SCENE).instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	game.set_process(false)
	ground = game.ground
	network = game.get_node("DepotNetwork")
	var main: Node3D = game.depot
	var spacing: float = network.depot_rules().min_depot_spacing
	if not check(spacing == 70.0,"Spacing should be 70 m, is %.1f" % spacing): return
	# Plans.
	var close := depot_site(main.global_position,40,60)
	var far := depot_site(main.global_position,75,110)
	if not check(close != Vector3.INF and far != Vector3.INF,"No test sites near the main Depot"): return
	if not check(not network.depot_spacing_ok(close) and network.depot_spacing_ok(far),"40-60 m should be too close and 75 m+ far enough"): return
	if not check(network.queue_plan(close,&"depot") == null,"A Depot plan inside 70 m was accepted"): return
	var plan: Node3D = network.queue_plan(far,&"depot")
	if not check(plan != null,"A Depot plan 75 m+ away was refused"): return
	# Another plan close to that plan is refused too; a Generator plan there is not affected.
	var beside_plan := depot_site(plan.global_position,20,40)
	if not check(beside_plan != Vector3.INF and network.queue_plan(beside_plan,&"depot") == null,"A Depot plan inside 70 m of another Depot plan was accepted"): return
	if not check(network.queue_plan(beside_plan,&"generator") != null,"Spacing should not affect other buildings"): return
	# Completing the plan ignores the plan itself.
	if not check(network.depot_spacing_ok(plan.global_position,"player",plan),"A plan should not block itself"): return
	plan.queue_free()
	await process_frame
	# A Depot truck cannot deploy inside 70 m, and can beyond it.
	var truck: Node3D = network.truck_scene.instantiate()
	truck.position = close
	game.get_node("Entities/Units").add_child(truck)
	truck.set_process(false)
	await process_frame
	if not check(not network.can_deploy_at(truck,truck.global_position) and not network.deploy_truck(truck,truck.global_position),"A Depot truck deployed inside 70 m"): return
	if not check(is_instance_valid(truck) and not truck.is_queued_for_deletion(),"A refused deploy should keep the truck"): return
	if not check(network.can_deploy_at(truck,far),"A Depot truck should be able to deploy 75 m+ away"): return
	var before := get_nodes_in_group("depots").size()
	if not check(network.deploy_truck(truck,far),"Deploy 75 m+ away failed"): return
	await process_frame
	if not check(get_nodes_in_group("depots").size() == before+1,"No new Depot after deploying"): return
	# The new Depot now pushes the rule outward from itself as well.
	if not check(not network.depot_spacing_ok(far+Vector3(30,0,0)),"The deployed Depot should hold its own 70 m"): return
	# Off restores the old rule.
	network.depot_rules().min_depot_spacing = 0.0
	if not check(network.depot_spacing_ok(close),"Spacing 0 should turn the rule off"): return
	network.depot_rules().min_depot_spacing = spacing
	print("DEPOT_SPACING_TEST_PASSED")
	quit()
