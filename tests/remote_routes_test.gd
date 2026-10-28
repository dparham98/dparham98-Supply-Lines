extends SceneTree
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func fixture(path: String) -> void:
	if is_instance_valid(game):
		game.free()
		await process_frame
	game = load(path).instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	for group in ["units","depots"]:
		for node in get_nodes_in_group(group): node.set_process(false)
func step(unit: Node3D, seconds: float) -> void:
	for i in range(ceili(seconds*60)): unit._process(1.0/60)
func total(source: Node3D, target: Node3D, unit: Node3D, kind: StringName) -> int:
	return source.stockpile.amount(kind)+target.stockpile.amount(kind)+unit.stockpile.amount(kind)
func run() -> void:
	await fixture("res://scenes/maps/supply_routes.tscn")
	var source = game.depot
	var destination = game.get_node("Entities/Buildings/Outpost")
	var neutral = game.get_node("Entities/Buildings/NeutralDepot")
	var anchor = game.get_node("Entities/Units/CargoVehicle")
	var ground = game.ground
	var near_cell: Vector2i = ground.nearest_actor_cell(ground.get_tile_at_position(source.global_position+Vector3(7,0,7)),0)
	var remote := Vector3.INF
	for dx in [-80,-60,60,80]:
		for dz in [-60,0,60]:
			var candidate: Vector3 = source.global_position+Vector3(dx,0,dz)
			var cell = ground.get_tile_at_position(candidate)
			if cell == null or not ground.is_tile_valid(cell): continue
			if candidate.distance_to(source.global_position) <= source.rules.construction_radius or candidate.distance_to(destination.global_position) <= destination.rules.construction_radius: continue
			if not ground.actor_path(cell,near_cell,0,"").is_empty(): remote = candidate; break
		if remote != Vector3.INF: break
	if not check(remote != Vector3.INF,"No reachable remote truck fixture"): return
	var truck = load("res://scenes/gameplay/cargo_vehicle.tscn").instantiate()
	truck.position = remote
	game.get_node("Entities/Units").add_child(truck)
	truck.set_process(false)
	if not check(truck.global_position.distance_to(source.global_position) > source.rules.construction_radius and truck.global_position.distance_to(destination.global_position) > destination.rules.construction_radius,"Truck starts in endpoint territory"): return
	source.energy = 200; source.iron = 100; source.wood = 40; source.coal = 30
	destination.energy = 0; destination.iron = 0; destination.wood = 0; destination.coal = 0
	var held_position: Vector3 = truck.global_position
	if not check(truck.start_supply_route(source,destination,10,5,false,3,2),"Remote ground route rejected"): return
	if not check(truck.global_position == held_position and source.energy == 200 and truck.stockpile.total() == 0,"Assignment teleported or transferred cargo"): return
	if not check(not truck.start_supply_route(source,neutral,10,0,false) and not truck.start_supply_route(source,source,10,0,false) and not truck.start_supply_route(source,game.get_node("Entities/Units/Infantry"),10,0,false),"Invalid endpoint accepted"): return
	if not check(not truck.start_supply_route(source,destination,101,0,false) and not truck.start_supply_route(source,destination,-1,1,false) and not truck.start_supply_route(source,destination,0,0,false),"Invalid amounts accepted"): return
	if not check(truck.route_active and truck.origin_depot == source and truck.destination_depot == destination and truck.requested_energy == 10,"Rejected request mutated accepted route"): return
	for i in range(300*60):
		truck._process(1.0/60)
		if not check(total(source,destination,truck,&"energy") == 200 and total(source,destination,truck,&"iron") == 100 and total(source,destination,truck,&"wood") == 40 and total(source,destination,truck,&"coal") == 30,"Remote route lost/duplicated inventory"): return
		if not truck.route_active: break
	if not check(not truck.route_active and destination.energy == 10 and destination.iron == 5 and destination.wood == 3 and destination.coal == 2,"Remote truck failed to approach, load, travel and deliver"): return
	# Unavailable actors/endpoints reject new requests without disturbing held cargo.
	truck.carried_energy = 4
	destination.health = 0
	if not check(not truck.start_supply_route(source,destination,1,0,false) and truck.carried_energy == 4,"Dead Depot accepted or discarded cargo"): return
	destination.health = destination.max_health
	truck.health = 0
	if not check(not truck.start_supply_route(source,destination,1,0,false),"Dead vehicle accepted new route"): return
	truck.health = truck.max_health
	if not check(truck.start_supply_route(source,destination,1,0,false),"Held-cargo route rejected"): return
	destination.queue_free()
	await process_frame
	if not check(truck.route_paused and truck.carried_energy == 4 and not truck.resume_supply_route(),"Freed endpoint failed to pause and retain cargo"): return
	await fixture("res://scenes/maps/rail_exercise.tscn")
	source = game.depot
	destination = game.get_node("Entities/Buildings/EastDepot")
	var train = game.get_node("Entities/Units/Train")
	var rails = game.get_node("RailNetwork")
	destination.energy = 0; destination.iron = 0; destination.wood = 0; destination.coal = 0
	# An isolated train outside both territories may receive the same route.
	var isolated = load("res://scenes/gameplay/train.tscn").instantiate()
	isolated.position = remote
	game.get_node("Entities/Units").add_child(isolated)
	isolated.set_process(false)
	if not check(isolated.global_position.distance_to(source.global_position) > source.rules.construction_radius and isolated.global_position.distance_to(destination.global_position) > destination.rules.construction_radius,"Isolated train is within endpoint territory"): return
	var isolated_point: Vector3 = isolated.global_position
	if not check(isolated.start_supply_route(source,destination,1,0,false),"Out-of-range train assignment rejected"): return
	step(isolated,3)
	if not check(isolated.waiting_for_rail and isolated.global_position == isolated_point and isolated.stockpile.total() == 0,"Isolated train escaped rails or loaded remotely"): return
	isolated.cancel_supply_route()
	isolated.free()
	var gap := Vector2i(435,406)
	var payer = rails.segments[gap].assigned_depot
	rails.segments[gap].free()
	var source_energy: int = source.energy
	var train_start: Vector3 = train.global_position
	if not check(train.start_supply_route(source,destination,12,8,false),"Disconnected train assignment rejected"): return
	step(train,5)
	if not check(train.route_active and train.waiting_for_rail and not train.route_paused and train.global_position == train_start and source.energy == source_energy and train.stockpile.total() == 0,"Waiting train moved, loaded, or lost assignment"): return
	# Manual pause remains latched after track is connected.
	train.pause_supply_route()
	var replacement = rails.segment_scene.instantiate()
	replacement.assigned_depot = payer; replacement.position = game.ground.tile_to_world(gap)
	game.add_child(replacement)
	step(train,3)
	if not check(train.route_paused and source.energy == source_energy,"Repair auto-resumed manually paused pending route"): return
	if not check(train.resume_supply_route(),"Connected pending route could not resume"): return
	step(train,20)
	if not check(not train.route_active and destination.energy == 12 and destination.iron == 8,"Queued train route failed after explicit resume"): return
	# A fresh waiting assignment starts automatically on initial connection.
	rails.segments[gap].free()
	train.carried_coal = 3
	if not check(train.start_supply_route(source,destination,1,0,false),"Waiting assignment with held cargo rejected"): return
	step(train,3)
	if not check(train.waiting_for_rail and train.carried_coal == 3,"Waiting assignment lost held cargo"): return
	replacement = rails.segment_scene.instantiate()
	replacement.assigned_depot = payer; replacement.position = game.ground.tile_to_world(gap)
	game.add_child(replacement)
	step(train,20)
	if not check(not train.waiting_for_rail and not train.route_active and destination.coal == 3,"Initial rail connection did not auto-start held-cargo delivery"): return
	# An interrupted executing route still requires explicit repair/resume.
	if not check(train.start_supply_route(source,destination,5,0,true),"Connected repeat assignment rejected"): return
	rails.segments[gap].free()
	if not check(train.route_paused and not train.waiting_for_rail and not train.resume_supply_route(),"Active rail cut converted to auto-start wait"): return
	replacement = rails.segment_scene.instantiate()
	replacement.assigned_depot = payer; replacement.position = game.ground.tile_to_world(gap)
	game.add_child(replacement)
	step(train,2)
	if not check(train.route_paused and train.resume_supply_route(),"Repaired active route resumed implicitly or refused Resume"): return
	train.cancel_supply_route()
	if not check(not train.waiting_for_rail and not train.route_active,"Cancel kept queued train state"): return
	await fixture("res://scenes/maps/remote_routes_exercise.tscn")
	var exercise_train = game.get_node("Entities/Units/Train")
	var distant = game.get_node("Entities/Buildings/RemoteDepot")
	if not check(game.get_node("RailNetwork").segments.size() == 30 and not game.get_node("RailNetwork").segments.has(gap),"Remote route exercise gap is not open"): return
	if not check(distant.global_position.distance_to(exercise_train.global_position) > distant.rules.construction_radius and exercise_train.start_supply_route(game.depot,distant,1,0,false) and exercise_train.waiting_for_rail,"Remote exercise did not support distant Depot assignment"): return
	print("REMOTE_ROUTES_CHECKS_PASSED")
	quit()
