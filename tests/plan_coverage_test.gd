extends SceneTree
# Headless: a building plan whose centre is inside a Depot's range is paid from it, even when corners of its
# footprint stick out of the range (docs/DEPOT_RANGE.md). Every corner used to have to be inside, so with the
# 17.5 m range a Barracks beside a Depot waited for energy for ever. Outside every range the preview says so.
var game: Node3D
var network: Node
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
## A site for `kind` whose footprint centre is `least`..`most` m from `from`, with at least one corner
## farther than `corner_beyond` (or any corner when it is 0), or INF.
func site(kind: StringName, from: Vector3, least: float, most: float, corner_beyond := 0.0) -> Vector3:
	var spec: Dictionary = network.plan_spec(kind)
	for r in range(ceili(least),floori(most)+1):
		for step in range(0,360,5):
			var point: Vector3 = from+Vector3(cos(deg_to_rad(step)),0,sin(deg_to_rad(step)))*r
			var start: Vector2i = network.footprint_start(point,spec.size)
			if not network.plan_terrain_valid(start,spec.size,kind) or network.plan_overlaps(start,spec.size): continue
			var size: Vector2i = spec.size
			var centre: Vector3 = game.ground.tile_to_world(start)+Vector3(size.x*0.5-0.5,0,size.y*0.5-0.5)
			var d := Vector2(centre.x-from.x,centre.z-from.z).length()
			if d < least or d > most: continue
			var far_corner := 0.0
			for offset in [Vector2i.ZERO,Vector2i(size.x-1,0),Vector2i(0,size.y-1),size-Vector2i.ONE]:
				far_corner = maxf(far_corner,game.ground.tile_to_world(start+offset).distance_to(from))
			if far_corner > corner_beyond: return point
	return Vector3.INF
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/balanced_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	game.set_process(false)
	network = game.get_node("DepotNetwork")
	var depot: Node3D = game.depot
	var radius: float = SupplySource.radius(depot)
	if not check(is_equal_approx(radius,17.5),"The test expects the 17.5 m range"): return
	depot.energy = 2000
	# Centre inside, a corner outside: covered, and the plan gets its energy from the Depot.
	var inside := site(&"barracks",depot.global_position,8,radius-0.5,radius)
	if not check(inside != Vector3.INF,"No Barracks site with its centre in range and a corner out"): return
	var plan: Node3D = network.queue_plan(inside,&"barracks")
	if not check(plan != null,"The Barracks plan was refused"): return
	plan.set_process(false)
	if not check(network.source_covers_plan(depot,plan),"A Depot should cover a plan whose centre is in its range"): return
	if not check(plan.energy_payer(plan.energy_due(0)) == depot,"The plan should take its energy from the covering Depot"): return
	plan.refresh_state()
	if not check(not plan.state.begins_with("Waiting for energy"),"The plan should not wait for energy: "+plan.state): return
	# A worker's construction tick pays energy from the Depot.
	var before: int = depot.energy
	var iron := plan.materials().get(&"iron",0) as int
	plan.receive(&"iron",iron)
	var result: String = plan.work(null,5)
	if not check(result == "" and depot.energy < before and plan.energy_paid > 0,"A construction tick should pay energy from the Depot: %s, %d E paid" % [result,plan.energy_paid]): return
	plan.queue_free()
	await process_frame
	# Centre outside every range: not covered; the plan waits and says what it needs; the preview warns.
	var outside := site(&"barracks",depot.global_position,radius+4,radius+30)
	if not check(outside != Vector3.INF,"No Barracks site outside the range"): return
	var far_plan: Node3D = network.queue_plan(outside,&"barracks")
	if not check(far_plan != null,"A plan outside the range should still be placeable"): return
	far_plan.set_process(false)
	if not check(not network.source_covers_plan(depot,far_plan) and far_plan.energy_payer(far_plan.energy_due(0)) == null,"A plan outside the range should not be paid"): return
	far_plan.receive(&"iron",far_plan.materials().get(&"iron",0))
	far_plan.refresh_state()
	if not check(far_plan.state.contains("covers its centre"),"The waiting state should say what it needs: "+far_plan.state): return
	game.global_plan_kind = &"barracks"
	far_plan.queue_free()
	await process_frame
	network.update_global_preview(outside)
	var status: String = game.get_node("ConstructionPreview/Status").text
	if not check(status.contains("no Depot range covers it"),"The preview should warn outside every range: "+status): return
	network.update_global_preview(inside)
	status = game.get_node("ConstructionPreview/Status").text
	if not check(not status.contains("no Depot range"),"The preview should not warn inside a range: "+status): return
	game.global_plan_kind = &""
	print("PLAN_COVERAGE_TEST_PASSED")
	quit(0)
