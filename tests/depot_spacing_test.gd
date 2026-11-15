extends SceneTree
# Headless: a new Depot must stand at least DepotRules.min_depot_spacing (70 m) from every other friendly
# Depot and Depot plan (docs/ECONOMY_REPORT.md step 6), whether planned, built or deployed from a truck.
# Authored and captured Depots are not checked. Sites held by deploy orders count; plans that lose their
# spacing stop and say why.
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
	# The rule measures from where a Depot actually stands once snapped to its footprint.
	var deployed: Node3D = null
	for depot in get_nodes_in_group("depots"):
		if depot != main and depot.team == "player" and Vector2(depot.global_position.x-far.x,depot.global_position.z-far.z).length() < 2.0: deployed = depot
	if not check(deployed != null and network.depot_centre(far).is_equal_approx(Vector2(deployed.global_position.x,deployed.global_position.z)),"depot_centre should be where the Depot stands"): return
	# The new Depot now pushes the rule outward from itself as well.
	if not check(not network.depot_spacing_ok(far+Vector3(30,0,0)),"The deployed Depot should hold its own 70 m"): return
	# A truck is checked against its own side's Depots.
	if not check(network.depot_spacing_ok(close,"hostile") and not network.depot_spacing_ok(close,"player"),"Spacing should count only the asking side's Depots"): return
	# A site a truck has been ordered to deploy on is held for it, as current order or queued.
	var open := Vector3.INF
	for r in range(150,400,10):
		var site := depot_site(main.global_position,r,r+8)
		if site != Vector3.INF and network.depot_spacing_ok(site) and network.depot_spacing_ok(site+Vector3(0,0,100)): open = site; break
	if not check(open != Vector3.INF,"No open site for the deploy-order check"): return
	var mover: Node3D = network.truck_scene.instantiate()
	mover.position = open+Vector3(0,0,100)
	game.get_node("Entities/Units").add_child(mover)
	mover.set_process(false)
	await process_frame
	mover.command_deploy_at(open)
	if not check(mover.order == "deploy" and not network.depot_spacing_ok(open+Vector3(20,0,0)),"A site a truck is heading to deploy on should be held"): return
	if not check(network.depot_spacing_ok(open,"player",mover),"A truck's own deploy site should not block it"): return
	mover.order = "idle"
	mover.order_queue.append({kind = "deploy", point = open, requires_target = false})
	if not check(not network.depot_spacing_ok(open+Vector3(20,0,0)),"A queued deploy site should be held"): return
	mover.order_queue.clear()
	if not check(network.depot_spacing_ok(open+Vector3(20,0,0)),"A dropped deploy order should free the site"): return
	# A plan that loses its spacing (here a Depot appears beside it without a check, as a capture does) stops
	# before taking any material, says why, and is not finished.
	var held: Node3D = network.queue_plan(open,&"depot")
	if not check(held != null,"A Depot plan at the open site was refused"): return
	held.set_process(false)
	var neighbour := depot_site(held.global_position,30,50)
	if not check(neighbour != Vector3.INF,"No site beside the plan"): return
	network.establish(neighbour,0,0)
	await process_frame
	var work_state: String = held.work(null,5)
	if not check(work_state.begins_with("Blocked") and network.spacing_reason() in work_state and held.added.is_empty(),"A plan too close should block before building: %s" % work_state): return
	if not check(held.complete_from_stock() == null and held.state.begins_with("Blocked") and network.finish_plan(held) == null,"A plan too close should not be finished"): return
	if not check(network.spacing_notice(close).contains(network.spacing_reason()),"Notices should name the rule"): return
	# Off restores the old rule.
	network.depot_rules().min_depot_spacing = 0.0
	if not check(network.depot_spacing_ok(close),"Spacing 0 should turn the rule off"): return
	network.depot_rules().min_depot_spacing = spacing
	print("DEPOT_SPACING_TEST_PASSED")
	quit()
