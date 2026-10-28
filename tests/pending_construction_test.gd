extends SceneTree
var game: Node3D
var network: Node
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> bool:
	if ok: return true
	push_error(message); quit(1); return false
func site(kind: StringName, near: Vector3, inside: bool = true) -> Vector3:
	var spec: Dictionary = network.plan_spec(kind)
	for radius in range(10,100,4):
		for offset in [Vector3(radius,0,0),Vector3(-radius,0,0),Vector3(0,0,radius),Vector3(0,0,-radius)]:
			var point: Vector3 = near+offset
			var start: Vector2i = network.footprint_start(point,spec.size)
			if network.plan_terrain_valid(start,spec.size,kind) and not network.plan_overlaps(start,spec.size):
				if network.can_place_size(point,game.depot,spec.size) == inside: return point
	return Vector3.INF
func run() -> void:
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	for i in range(3): await process_frame
	network = game.get_node("DepotNetwork")
	game.set_process(false)
	for unit in get_nodes_in_group("units"): unit.set_process(false)
	for depot in get_nodes_in_group("depots"): depot.set_process(false)
	var depot = game.depot
	depot.energy = 0; depot.iron = 0
	var position := site(&"generator",depot.global_position)
	if not check(position != Vector3.INF,"No test footprint"): return
	var spec: Dictionary = network.plan_spec(&"generator")
	var plan = network.queue_plan(position,&"generator")
	if not check(plan != null,"Failed to place plan without funds"): return
	plan.set_process(false)
	if not check(plan.try_complete() == null and depot.energy == 0 and depot.iron == 0,"Unfunded plan spent resources"): return
	if not check(network.plan_terrain_valid(plan.start,spec.size,&"generator"),"Unpaid plan blocked occupancy"): return
	if not check(network.queue_plan(position,&"generator") == null,"Duplicate overlapping plan accepted"): return
	if not check(network.queue_plan(depot.global_position,&"generator") == null,"Plan accepted existing building footprint"): return
	if not check(network.queue_plan(Vector3(-249,0,-249),&"iron_mine") == null,"Mine accepted non-ore terrain"): return
	depot.energy = spec.energy; depot.iron = spec.iron
	var blocker: Vector2i = plan.start
	game.ground.set_tile_feature(blocker,"occupied_by","pending_test_blocker")
	if not check(plan.try_complete() == null and depot.energy == spec.energy,"Blocked footprint spent resources"): return
	game.ground.set_tile_feature(blocker,"occupied_by",null)
	var building = plan.try_complete()
	if not check(building != null and depot.energy == 0 and depot.iron == 0,"Plan did not pay exact cost once"): return
	building.set_process(false)
	if not check(building.assigned_depot == depot and plan.try_complete() == null,"Plan duplicated completion or lost assigned payer"): return
	var remote := site(&"barracks",depot.global_position,false)
	var waiting = network.queue_plan(remote,&"barracks")
	if not check(waiting != null,"No remote plan"): return
	waiting.set_process(false)
	depot.energy = 500; depot.iron = 500
	if not check(waiting.try_complete() == null and depot.energy == 500,"Out-of-range plan spent funds"): return
	# Establish coverage after planning, without selecting a builder.
	var old_selected = network.selected
	var new_point := remote+Vector3(15,0,0)
	var new_depot = network.establish(new_point,0,0)
	new_depot.set_process(false)
	new_depot.energy = 1000; new_depot.iron = 500
	var completed = waiting.try_complete()
	if not check(completed != null and completed.assigned_depot == new_depot and network.selected == new_depot,"New coverage failed to complete remote plan"): return
	completed.set_process(false)
	# Pin to an unfunded Depot; never silently use a different one.
	depot.energy = 0
	var pinned_point := site(&"generator",new_depot.global_position)
	var pinned = network.queue_plan(pinned_point,&"generator",depot)
	if not check(pinned != null,"Pinned plan not created"): return
	pinned.set_process(false)
	var balance: int = new_depot.energy
	if not check(pinned.try_complete() == null and new_depot.energy == balance,"Pinned plan silently switched payer"): return
	pinned.cancel()
	if not check(pinned.finished and pinned.try_complete() == null and new_depot.energy == balance,"Cancellation charged or built a plan"): return
	depot.energy = 500
	# Capture and destruction suspend pinned plans rather than spending from another Depot.
	var capture_point := site(&"generator",depot.global_position)
	var captured = network.queue_plan(capture_point,&"generator",depot)
	captured.set_process(false)
	depot.team = "enemy"
	if not check(captured.try_complete() == null and depot.energy == 500,"Enemy Depot funded a plan"): return
	depot.team = "player"
	depot.health = 0
	if not check(captured.try_complete() == null,"Destroyed Depot funded a plan"): return
	depot.health = depot.max_health
	captured.cancel()
	# Two insufficient stockpiles never combine; other pending plan cancellation is free.
	var split_point := site(&"tank_factory",new_depot.global_position)
	var split = network.queue_plan(split_point,&"tank_factory")
	split.set_process(false)
	depot.energy = 199; new_depot.energy = 199
	if not check(split.try_complete() == null,"Construction pooled insufficient stockpiles"): return
	split.cancel()
	# Creation validity for every menu kind and no reservation or payment on cancellation.
	for kind in [&"depot",&"barracks",&"tank_factory",&"rail"]:
		var point := site(kind,depot.global_position)
		var queued = network.queue_plan(point,kind)
		if not check(queued != null,"Failed to create plan for "+str(kind)): return
		queued.cancel()
	# Complete each building factory through the same paid background path.
	for kind in [&"depot",&"barracks",&"tank_factory",&"rail"]:
		depot.energy = 1000; depot.iron = 500
		var point := site(kind,depot.global_position)
		var queued = network.queue_plan(point,kind,depot)
		if not check(queued != null,"No completion site for "+str(kind)): return
		queued.set_process(false)
		var cost: int = queued.spec.energy
		var built = queued.try_complete()
		if not check(built != null and depot.energy == 1000-cost,"Failed paid completion for "+str(kind)): return
		if kind == &"rail":
			if not check(game.get_node("RailNetwork").friendly(built.cell,"player"),"Planned rail did not register"): return
		elif kind == &"depot":
			built.try_construction_infantry()
			if not check(built.construction_infantry_spawned,"New planned Depot lost its establishment Infantry"): return
		else:
			if not check(built.assigned_depot == depot,"Production lost its operating Depot"): return
		built.set_process(false)
	# Rebuild the shared mine without consuming its preserved reserves.
	var mine = game.get_node("Entities/Buildings/IronMine")
	var mine_point: Vector3 = mine.global_position
	var reserves: int = mine.remaining
	mine.take_damage(mine.max_health)
	await process_frame
	depot.energy = 1000; depot.iron = 500
	var mine_plan = network.queue_plan(mine_point,&"iron_mine",depot)
	if not check(mine_plan != null,"Mine plan rejected empty ore footprint"): return
	var rebuilt = mine_plan.try_complete()
	if not check(rebuilt != null and rebuilt.remaining == reserves and rebuilt.team == "neutral","Planned mine changed reserves/shared ownership"): return
	# A freed pinned reference must wait safely instead of switching or crashing.
	var lost_point := site(&"generator",depot.global_position)
	var lost = network.queue_plan(lost_point,&"generator",depot)
	if not check(lost != null,"No lost-source plan site"): return
	lost.set_process(false)
	depot.queue_free()
	await process_frame
	if not check(lost.try_complete() == null,"Freed pinned Depot funded a plan"): return
	lost.cancel()
	print("PENDING_CONSTRUCTION_CHECKS_PASSED")
	quit()
