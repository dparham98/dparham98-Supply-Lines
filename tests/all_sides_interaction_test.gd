extends SceneTree
const Approach = preload("res://scripts/units/interaction_approach.gd")
const DIRECTIONS = [Vector2i(1,0),Vector2i(1,1),Vector2i(0,1),Vector2i(-1,1),Vector2i(-1,0),Vector2i(-1,-1),Vector2i(0,-1),Vector2i(1,-1)]
var game: Node3D
var ground: Node3D
var actors: Array[Node3D] = []
var blocked: Array[Vector2i] = []
var center: Vector2i
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> bool:
	if ok: return true
	push_error(message); quit(1); return false
func worker_at(cell: Vector2i) -> Node3D:
	var unit = load("res://scenes/gameplay/infantry.tscn").instantiate()
	unit.position = ground.tile_to_world(cell)
	game.get_node("Entities/Units").add_child(unit)
	unit.set_process(false)
	actors.append(unit)
	return unit
func clear_workers() -> void:
	for unit in actors: unit.free()
	actors.clear()
func block(cell: Vector2i) -> void:
	if ground.can_traverse(cell):
		ground.set_tile_feature(cell,"occupied_by","all_side_test")
		blocked.append(cell)
func unblock() -> void:
	for cell in blocked:
		if ground.tiles[cell.y*500+cell.x].occupied_by == "all_side_test": ground.set_tile_feature(cell,"occupied_by",null)
	blocked.clear()
func same_side(unit: Node3D, target: Node3D, direction: Vector2i) -> bool:
	var offset := unit.global_position-target.global_position
	return (direction.x == 0 or offset.x*direction.x > 0) and (direction.y == 0 or offset.z*direction.y > 0)
func ownership_valid(unit: Node3D) -> bool:
	for cell in unit._claimed:
		if not unit._is_ours(cell): return false
	return true
func wood_stand() -> Node3D:
	var source = load("res://scenes/gameplay/wood_site.tscn").instantiate()
	source.position = ground.tile_to_world(center)
	game.get_node("Entities/Resources").add_child(source)
	return source
func run() -> void:
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	ground = game.ground
	for group in ["units","depots","resources","mines"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	var patch: Vector2i = ground.find_buildable_footprint(Vector2i(420,420),Vector2i(32,32))
	if not check(patch.x >= 0,"No clear map patch for all-side fixtures"): return
	center = patch+Vector2i(16,16)
	print("ALL_SIDES_FIXTURE_CENTER: ",ground.tile_to_world(center))
	var source := wood_stand()
	for direction in DIRECTIONS:
		var worker := worker_at(center+direction*10)
		worker.command_gather(source)
		for frame in range(3000):
			worker._process(1.0/60)
			if not check(ownership_valid(worker) and not source.cells.has(worker.grid_position),"Harvester entered occupied footprint or stole claim"): return
			if worker.cargo > 0: break
		if not check(worker.cargo == 5 and same_side(worker,source,direction) and worker.global_position.distance_to(source.global_position) <= worker.interaction_range+0.001,"Harvester failed its near-side approach: "+str(direction)): return
	var held := 0
	for worker in actors: held += worker.cargo
	if not check(source.remaining+held == source.amount and held == 40,"Eight-sided extraction violated conservation"): return
	clear_workers()
	source.free()
	# Repeat with an 8x8 Depot and full-size unit reservations.
	var depot = load("res://scenes/gameplay/depot.tscn").instantiate()
	depot.position = ground.tile_to_world(center)
	depot.initial_energy = 0; depot.initial_iron = 0
	game.get_node("Entities/Buildings").add_child(depot)
	depot.set_process(false)
	depot.iron = 0
	var index := 0
	for direction in DIRECTIONS:
		var worker := worker_at(center+direction*12)
		worker.cargo = 10
		worker.cargo_kind = [&"wood",&"iron",&"coal"][index%3]
		worker.command_return(depot)
		for frame in range(3000):
			worker._process(1.0/60)
			if not check(ownership_valid(worker) and not depot.cells.has(worker.grid_position),"Delivery entered Depot or stole claim"): return
			if worker.cargo == 0: break
		if not check(worker.cargo == 0 and same_side(worker,depot,direction) and worker.global_position.distance_to(depot.global_position) <= depot.dropoff_range+0.001,"Delivery failed its near-side approach: "+str(direction)): return
		index += 1
	if not check(depot.wood == 30 and depot.iron == 30 and depot.coal == 20,"Eight-sided delivery lost or duplicated resources"): return
	clear_workers()
	# Ground cargo uses the same approach search, retaining its timed transfers.
	depot.energy = 100
	for direction in DIRECTIONS:
		var truck = load("res://scenes/gameplay/cargo_vehicle.tscn").instantiate()
		truck.position = ground.tile_to_world(center+direction*12)
		game.get_node("Entities/Units").add_child(truck)
		truck.set_process(false); actors.append(truck)
		if not check(truck.start_supply_route(depot,game.depot,1,0,false),"Ground cargo loading request failed"): return
		for frame in range(3000):
			truck._process(1.0/60)
			if not check(ownership_valid(truck) and not depot.cells.has(truck.grid_position),"Truck entered Depot footprint"): return
			if truck.carried_energy > 0: break
		if not check(truck.carried_energy == 1 and same_side(truck,depot,direction),"Truck loaded through wrong/unreachable side: "+str(direction)): return
	if not check(depot.energy == 92,"Eight-sided truck loading lost/duplicated stock"): return
	clear_workers()
	depot.energy = 0
	for direction in DIRECTIONS:
		var truck = load("res://scenes/gameplay/cargo_vehicle.tscn").instantiate()
		truck.position = ground.tile_to_world(center+direction*12)
		truck.initial_energy = 3
		game.get_node("Entities/Units").add_child(truck)
		truck.set_process(false); actors.append(truck)
		if not check(truck.start_supply_route(game.depot,depot,1,0,false),"Ground cargo unloading request failed"): return
		for frame in range(3000):
			truck._process(1.0/60)
			if not check(ownership_valid(truck),"Unloading truck stole another claim"): return
			if not truck.route_active: break
		if not check(truck.carried_energy == 0 and not truck.route_active and same_side(truck,depot,direction),"Truck unloaded through wrong/unreachable side: "+str(direction)): return
	if not check(depot.energy == 24,"Eight-sided truck unloading lost/duplicated stock"): return
	clear_workers()
	# Converging workers must wait/replan rather than overwrite one another's claims.
	for n in range(4):
		var worker := worker_at(center+Vector2i(-12,n-2))
		worker.cargo = 5; worker.cargo_kind = &"wood"; worker.command_return(depot)
	for frame in range(3000):
		var complete := true
		var occupied: Dictionary = {}
		for worker in actors:
			worker._process(1.0/60)
			if not check(ownership_valid(worker) and not occupied.has(worker.grid_position),"Concurrent deliveries collided or overwrote reservations"): return
			occupied[worker.grid_position] = true
			if worker.cargo > 0: complete = false
		if complete: break
	for worker in actors:
		if not check(worker.cargo == 0,"Concurrent delivery stalled"): return
	if not check(depot.wood == 50,"Concurrent deliveries lost cargo"): return
	clear_workers()
	# Only a non-cardinal, formerly untested entrance remains open.
	var goal := center+Vector2i(-5,4)
	for cell in Approach.candidates(ground,depot,depot.dropoff_range,0,""):
		if cell != goal: block(cell)
	var worker := worker_at(center+Vector2i(-11,4))
	worker.cargo = 5; worker.cargo_kind = &"wood"
	worker.command_return(depot)
	if not check(not worker._route_near(depot,depot.dropoff_range),"Narrow entrance does not reproduce old direction failure"): return
	for frame in range(3000):
		worker._process(1.0/60)
		if worker.cargo == 0: break
	if not check(worker.cargo == 0 and worker.grid_position == goal and depot.wood == 55,"Off-axis-only Depot entrance unreachable"): return
	clear_workers(); unblock(); depot.free()
	# Closest legal standing cell is isolated; the further edge cell is reachable.
	source = wood_stand()
	var isolated := center+Vector2i(-3,0)
	var reachable := center+Vector2i(0,4)
	for cell in Approach.candidates(ground,source,4,0,""):
		if cell != isolated and cell != reachable: block(cell)
	for dx in range(-1,2):
		for dz in range(-1,2):
			if dx != 0 or dz != 0: block(isolated+Vector2i(dx,dz))
	worker = worker_at(center+Vector2i(-10,0))
	worker.command_gather(source)
	for frame in range(3000):
		worker._process(1.0/60)
		if worker.cargo > 0: break
	if not check(worker.cargo == 5 and worker.grid_position == reachable,"Failed reachable fallback / exact-radius resource approach"): return
	clear_workers(); unblock()
	# Fully sealed resource: no corner cutting, no extraction, then retry when opened.
	for cell in Approach.candidates(ground,source,4,0,""):
		if cell != isolated: block(cell)
	for dx in range(-1,2):
		for dz in range(-1,2):
			if dx != 0 or dz != 0: block(isolated+Vector2i(dx,dz))
	worker = worker_at(center+Vector2i(-10,0))
	worker.command_gather(source)
	var remaining: int = source.remaining
	for frame in range(600): worker._process(1.0/60)
	if not check(worker.cargo == 0 and source.remaining == remaining and worker.state.contains("unreachable"),"Sealed source extracted or corner-cut through obstacles"): return
	unblock()
	for frame in range(3000):
		worker._process(1.0/60)
		if worker.cargo > 0: break
	if not check(worker.cargo == 5 and source.remaining == remaining-5,"Harvest did not retry after an approach cleared"): return
	clear_workers(); source.free()
	# Deliberately finish 0.0005 units short of each waypoint at a variable frame rate.
	var precision_source := wood_stand()
	var precision_worker := worker_at(center+Vector2i(10,0))
	precision_worker.command_gather(precision_source)
	precision_worker._process(0.01)
	for frame in range(40):
		precision_worker._process((1.0-0.0005)/precision_worker.move_speed)
		if precision_worker._moving_to.x < 0:
			if not check(precision_worker.global_position == ground.tile_to_world(precision_worker.grid_position),"Completed waypoint retained sub-cell drift"): return
		if precision_worker.cargo > 0: break
	if not check(precision_worker.cargo > 0,"Fractional frame timing stranded a radius-boundary harvester"): return
	clear_workers(); precision_source.free()
	var guard_worker := worker_at(center+Vector2i(10,0))
	var hostile = load("res://scenes/gameplay/hostile.tscn").instantiate()
	hostile.position = ground.tile_to_world(center+Vector2i(12,0))
	game.get_node("Entities/Units").add_child(hostile)
	hostile.set_process(false)
	guard_worker.command_attack(hostile)
	hostile.free()
	guard_worker._process(1.0/60)
	if not check(guard_worker.order == "idle" and guard_worker.state == "Attack target lost","Freed combat target was not safely released"): return
	clear_workers()
	print("ALL_SIDES_INTERACTION_CHECKS_PASSED")
	quit()
