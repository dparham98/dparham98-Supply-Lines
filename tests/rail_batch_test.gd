extends SceneTree
var game: Node3D
var rails: Node
var source: Node3D
var destination: Node3D
var train: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func load_fixture() -> void:
	game = load("res://scenes/maps/rail_exercise.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	for group in ["units","depots"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	rails = game.get_node("RailNetwork")
	source = game.depot
	destination = game.get_node("Entities/Buildings/EastDepot")
	train = game.get_node("Entities/Units/Train")
	destination.energy = 0; destination.iron = 0; destination.wood = 0
func step(seconds: float) -> void:
	for i in range(ceili(seconds*60)): train._process(1.0/60)
func restore_rail(cell: Vector2i, payer: Node3D) -> void:
	var node = rails.segment_scene.instantiate()
	node.assigned_depot = payer; node.position = game.ground.tile_to_world(cell)
	game.add_child(node)
func run() -> void:
	await load_fixture()
	if not check(rails.segments.size() == 31 and train.is_in_group("rail_trains") and train.move_speed == 8,"Rail fixture or train config incorrect"): return
	step(5)
	if not check(source.energy == 500 and source.iron == 500 and destination.iron == 0,"Idle train automatically transferred resources"): return
	var depots = game.get_node("DepotNetwork")
	depots.select_depot(source)
	var extra: Vector3 = source.global_position+Vector3(0,0,10)
	var extra_cell = game.ground.get_tile_at_position(extra)
	if not check(rails.build(extra) and source.iron == 498 and destination.iron == 0,"Rail did not spend selected local Depot only"): return
	if not check(not rails.build(extra) and source.iron == 498,"Duplicate rail charged resources"): return
	if not check(game.ground.is_tile_valid(extra_cell) and not game.ground.is_footprint_valid(extra_cell,Vector2i.ONE),"Rail should allow ground crossing and block building footprints"): return
	if not check(rails.path(Vector2i(420,406),extra_cell,"player","",false).is_empty(),"Disconnected rail accepted as connected"): return
	var overlap := extra+Vector3(1,0,0)
	source.iron = 0; destination.iron = 999
	if not check(not rails.build(overlap) and destination.iron == 999,"Rail borrowed from overlapping territory"): return
	source.iron = 498; destination.iron = 0
	if not check(not rails.build(source.global_position+Vector3(40,0,0)),"Out-of-territory rail built"): return
	train.free()
	if not check(source.request_train() and source.energy == 350 and source.iron == 468,"Train production payment incorrect"): return
	source._process(3.1)
	for node in get_nodes_in_group("rail_trains"): train = node; node.set_process(false)
	if not check(source.queue == 0 and rails.friendly(train.grid_position,"player") and game.units_printed == 0,"Paid train did not spawn on friendly rails"): return
	if not check(not train.start_supply_route(source,destination,301,0,false) and not train.start_supply_route(source,source,10,0,false),"Invalid train route accepted"): return
	if not check(train.start_supply_route(source,destination,60,40,false,20),"Connected train route rejected"): return
	step(2.1)
	if not check(train.carried_energy == 60 and train.carried_iron == 40 and train.carried_wood == 20 and source.energy == 290 and source.iron == 428 and source.wood == 80,"Train loading failed exact local debit"): return
	var gap := Vector2i(435,406)
	var payer = rails.segments[gap].assigned_depot
	rails.segments[gap].free()
	if not check(train.route_paused and train.carried_iron == 40 and not train.resume_supply_route(),"Cut track failed to pause and retain cargo"): return
	step(5)
	if not check(destination.iron == 0,"Disconnected train delivered without track"): return
	restore_rail(gap,payer)
	if not check(train.route_paused and train.resume_supply_route(),"Reconnected track resumed automatically or explicit resume failed"): return
	destination.team = "enemy"; destination.ownership_changed.emit()
	if not check(train.route_paused and not train.resume_supply_route(),"Captured endpoint did not pause route"): return
	destination.team = "player"; destination.ownership_changed.emit()
	if not check(train.route_paused and train.resume_supply_route(),"Friendly recapture should require explicit resume"): return
	step(12)
	if not check(not train.route_active and destination.energy == 60 and destination.iron == 40 and destination.wood == 20 and train.carried_iron == 0,"Train did not complete connected delivery"): return
	# Manual orders must never put a train onto ordinary open land.
	train.command_move(train.global_position+Vector3(0,0,3))
	step(2)
	if not check(rails.friendly(game.ground.get_tile_at_position(train.global_position),"player"),"Train escaped rails on Move"): return
	source.energy = 5; source.iron = 7; source.wood = 3
	if not check(train.start_supply_route(source,destination,60,40,false,20),"Partial load route rejected"): return
	step(20)
	if not check(source.energy == 0 and source.iron == 0 and source.wood == 0 and destination.energy == 65 and destination.iron == 47 and destination.wood == 23,"Partial loading/conservation incorrect"): return
	# Ordinary ground traffic blocks rail movement, without invalidating the friendly graph.
	game.ground.set_tile_feature(Vector2i(430,406),"occupied_by","rail_traffic_test")
	if not check(not train._plan(Vector2i(420,406)) and not rails.path(train.grid_position,Vector2i(420,406),"player",train._owner_key(),false).is_empty(),"Train ignored ground traffic or lost topology"): return
	game.ground.set_tile_feature(Vector2i(430,406),"occupied_by",null)
	source.energy = 10; source.iron = 10; source.wood = 6
	var total_e: int = source.energy+destination.energy
	var total_i: int = source.iron+destination.iron
	var total_w: int = source.wood+destination.wood
	if not check(train.start_supply_route(source,destination,2,3,true,1),"Explicit repeating train route rejected"): return
	step(45)
	if not check(train.route_active and destination.energy >= 69 and destination.iron >= 53 and source.energy+destination.energy+train.carried_energy == total_e and source.iron+destination.iron+train.carried_iron == total_i and source.wood+destination.wood+train.carried_wood == total_w,"Repeat route failed cargo conservation"): return
	var prior_iron: int = destination.iron
	# Cancellation retains cargo; death loses it without crediting either endpoint.
	train.carried_energy = 4; train.carried_iron = 6; train.carried_wood = 2
	train.cancel_supply_route()
	if not check(train.carried_iron == 6,"Cancel lost train cargo"): return
	var cell: Vector2i = train.grid_position
	train.take_damage(train.health)
	if not check(destination.iron == prior_iron and game.ground.is_tile_valid(cell),"Train death refunded cargo or kept reservation"): return
	await process_frame
	game.free()
	await load_fixture()
	train.free()
	var removed: Array[Vector2i] = []
	for point in rails.segments.keys():
		if game.ground.tile_to_world(point).distance_to(source.global_position) <= source.dropoff_range:
			removed.append(point); rails.segments[point].free()
	if not check(source.request_train(),"Train queue rejected without an exit"): return
	var paid_energy: int = source.energy
	source._process(3.1)
	if not check(source.queue == 1 and get_nodes_in_group("rail_trains").is_empty() and source.energy == paid_energy,"Missing rails lost prepaid queue job"): return
	restore_rail(removed[0],source)
	source._process(0.1)
	if not check(source.queue == 0 and get_nodes_in_group("rail_trains").size() == 1 and source.energy == paid_energy,"Train queue did not retry rail exit safely"): return
	print("RAIL_BATCH_CHECKS_PASSED")
	quit()
