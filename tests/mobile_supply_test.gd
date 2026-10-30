extends SceneTree
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func step(vehicle: Node3D, seconds: float) -> void:
	for i in range(ceili(seconds*60)): vehicle._process(1.0/60)
func near(unit: Node3D, target: Node3D, offset: Vector3) -> void:
	unit._stop_route()
	for cell in unit._claimed.duplicate(): unit._release(cell)
	unit.global_position = target.global_position+offset
	unit.grid_position = game.ground.get_tile_at_position(unit.global_position)
	unit._claim(unit.grid_position)
func run() -> void:
	game = load("res://scenes/maps/mobile_supply_exercise.tscn").instantiate()
	root.add_child(game); await process_frame
	game.set_process(false)
	for group in ["units","depots","mines"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	var truck = game.get_node("Entities/Units/MineSupply")
	var worker = game.get_node("Entities/Units/Infantry")
	var forest = game.get_node("Entities/Units/ForestSupply")
	var forester = game.get_node("Entities/Units/ForestInfantry")
	var train = game.get_node("Entities/Units/Train")
	var depot = game.depot
	var network = game.get_node("DepotNetwork")
	var initial_e: int = depot.energy
	var initial_i: int = depot.iron
	if not check(truck.energy == 75 and truck.iron == 25 and truck.storage_capacity == 100 and train.storage_capacity == 300,"Authored inventory wrong"): return
	if not check(is_equal_approx(truck.mobile_rules.supply_radius(),17.5) and is_equal_approx(train.mobile_rules.supply_radius(),17.5) and is_equal_approx(truck.dropoff_range,3.5) and is_equal_approx(train.dropoff_range,3.5),"Ranges are not half Depot"): return
	if not check(not truck.spend_local(1,1) and truck.deploy_supplies(),"Packed cargo spent resources or deploy refused"): return
	step(truck,1)
	if not check(not truck.supplies_available() and not truck.spend_local(1,1),"Deployment exposed stock early"): return
	step(truck,1.1)
	if not check(truck.supplies_available(),"Deployment did not complete"): return
	near(worker,truck,Vector3(7,0,0)); worker.set_selected(true)
	network.bind_builder(worker,truck)
	if not check(network.builder_valid() and network.construct_mine(Vector3(150,0,154)),"Infantry could not build mine from cargo stock"): return
	var mine = get_nodes_in_group("mines")[-1]
	mine.set_process(false)
	if not check(truck.stockpile.total() == 0 and depot.energy == initial_e and depot.iron == initial_i,"Mobile construction pooled Depot funds"): return
	if not check(not network.construct_mine(Vector3(148,0,154)) and depot.energy == initial_e,"Empty mobile payer borrowed nearby funds"): return
	# Exact range boundary and movement-triggered packing gate all construction.
	if not check(SupplySource.covers(truck,truck.global_position+Vector3(17.5,0,0),"player") and not SupplySource.covers(truck,truck.global_position+Vector3(17.51,0,0),"player"),"Supply boundary wrong"): return
	truck.carried_energy = 10; truck.carried_iron = 10
	near(worker,mine,Vector3(3,0,0)); mine.take_damage(30)
	worker.command_repair(mine,truck); worker._repair(1)
	if not check(mine.health == 980 and truck.energy == 8 and truck.iron == 9,"Mobile repair payment failed"): return
	# Build plans: a deployed Cargo truck pays from its own stock; rails need a Depot.
	truck.carried_energy = 40; truck.carried_iron = 40
	var site := Vector3.ZERO
	for x in range(-12,13,4):
		for z in range(-12,13,4):
			if site == Vector3.ZERO and network.can_place_size(truck.global_position+Vector3(x,0,z),truck,Vector2i(8,8)) and not network.plan_overlaps(network.footprint_start(truck.global_position+Vector3(x,0,z),Vector2i(8,8)),Vector2i(8,8)): site = truck.global_position+Vector3(x,0,z)
	if not check(site != Vector3.ZERO,"No Depot plan site beside the truck"): return
	var depots_before := get_nodes_in_group("depots").size()
	var plan = network.queue_plan(site,&"depot",truck,true)
	if not check(plan != null and plan.try_complete() != null and get_nodes_in_group("depots").size() == depots_before+1 and truck.energy == 20 and truck.iron == 20 and depot.energy == initial_e,"Deployed truck could not pay a Depot plan"): return
	for node in get_nodes_in_group("depots"): node.set_process(false)
	var rail_cell: Vector2i = game.ground.get_tile_at_position(truck.global_position+Vector3(3,0,3))
	var rail_plan = network.queue_plan(game.ground.tile_to_world(rail_cell),&"rail",truck,true)
	if rail_plan != null:
		if not check(rail_plan.try_complete() == null and truck.energy == 20,"A Cargo truck paid for rail"): return
		rail_plan.cancel()
	truck.carried_energy = 8; truck.carried_iron = 9
	var held: Vector3 = truck.global_position
	truck.command_move(held+Vector3(0,0,4))
	worker._repair(1); step(truck,1)
	if not check(not truck.supplies_available() and truck.global_position == held and mine.health == 980 and truck.energy == 8,"Packing allowed movement or spending early"): return
	# A packing truck can't pay a plan pinned to it.
	var packed_plan = network.queue_plan(site+Vector3(0,0,30),&"rail",truck,true)
	if packed_plan != null:
		if not check(packed_plan.try_complete() == null,"Packing truck paid a plan"): return
		packed_plan.cancel()
	step(truck,1.1)
	if not check(truck.supply_transition.is_empty() and not truck.deployed,"Packing did not finish"): return
	step(truck,2)
	if not check(truck.global_position != held,"Cargo movement did not resume after packing"): return
	truck._stop_route(); truck.order = "idle"
	# Remote forest harvest returns to the deployed truck, not a distant Depot.
	if not check(forest.deploy_supplies(),"Forest truck deploy refused"): return
	step(forest,2.1)
	forester.return_depot = forest; forester.return_explicit = true
	forester.command_gather(game.ground.forest_source(Vector2i(345,275)))
	for i in range(7200):
		forester._process(1.0/60)
		if forest.wood == 20: break
	if not check(forest.wood == 20 and forester.cargo == 0 and game.ground.get_terrain(Vector2i(345,275)) == 0,"Forest-to-mobile harvest loop failed"): return
	# Full/partial delivery retains the remainder; packed or hostile target never receives.
	forest.stockpile.deposit(&"energy",78)
	near(forester,forest,Vector3(2,0,0)); forester.cargo_kind = &"coal"; forester.cargo = 10
	forester.command_return(forest); forester._return_cargo()
	if not check(forest.coal == 2 and forester.cargo == 8 and forest.stockpile.total() == 100,"Partial mobile delivery lost resources"): return
	forest.pack_supplies(); forester._return_cargo()
	if not check(forester.cargo == 8,"Packed truck received materials"): return
	step(forest,2.1); forest.deploy_supplies(); step(forest,2.1)
	forest.stockpile.withdraw(&"energy",8); forest.team = "enemy"; forester._return_cargo()
	if not check(forester.cargo == 8,"Hostile truck received materials"): return
	forest.team = "player"; forester._return_cargo()
	if not check(forester.cargo == 0 and forest.coal == 10 and forest.fuel == 0,"Delivery/fuel separation failed"): return
	# Piles are physical resources, not spending wallets. Both teams can extract exactly once.
	forester.cargo_kind = &"wood"; forester.cargo = 10
	var pile = game.drop_material(forester)
	if not check(is_instance_valid(pile) and pile.remaining == 10 and forester.cargo == 0 and not pile.is_in_group("mobile_supplies") and not pile.has_method("spend_local"),"Material pile creation exposed a wallet"): return
	if not check(pile.extract(4,"enemy") == 4 and pile.extract(20,"player") == 6 and pile.extract(1,"enemy") == 0,"Pile sharing duplicated resources"): return
	await process_frame
	forester.cargo_kind = &"energy"; forester.cargo = 3
	if not check(game.drop_material(forester) == null and forester.cargo == 3,"Loose energy pile created"): return
	forester.cargo_kind = &"iron"; forester.cargo = 7
	var before: int = get_nodes_in_group("material_piles").size()
	forester.take_damage(forester.health)
	if not check(get_nodes_in_group("material_piles").size() == before+1 and get_nodes_in_group("material_piles")[-1].remaining == 7,"Infantry death lost physical material"): return
	await process_frame
	pile = get_nodes_in_group("material_piles")[-1]
	var collector = load("res://scenes/gameplay/infantry.tscn").instantiate()
	collector.team = "enemy"; collector.position = pile.global_position+Vector3(1,0,0)
	game.get_node("Entities/Units").add_child(collector); collector.set_process(false)
	forest.team = "enemy"; collector.return_depot = forest; collector.return_explicit = true
	collector.command_gather(pile)
	forest.stockpile.withdraw(&"energy",7)
	for i in range(3600):
		collector._process(1.0/60)
		if forest.iron == 7: break
	if not check(forest.iron == 7 and collector.cargo == 0,"Opposing Infantry could not collect and stockpile death pile"): return
	forest.team = "player"; collector.free()
	# Deploy pauses a route; it never resumes automatically or loses cargo.
	truck.carried_energy = 0; truck.carried_iron = 0
	if not check(truck.start_supply_route(depot,game.get_node("Entities/Buildings/EastDepot"),10,0,false),"Cargo route rejected"): return
	if not check(truck.deploy_supplies() and truck.route_paused,"Deployment did not pause route"): return
	step(truck,2.1)
	if not check(truck.supplies_available() and truck.route_paused and truck.resume_supply_route() and not truck.supplies_available(),"Explicit route resume failed packing contract"): return
	# Trains use the same deployed inventory without leaving friendly rail.
	train.carried_energy = 20; train.carried_iron = 20
	if not check(train.deploy_supplies(),"Train deploy rejected friendly rail"): return
	step(train,2.1)
	if not check(train.supplies_available() and train.spend_local(2,1) and train.energy == 18 and train.iron == 19,"Train mobile spending failed"): return
	near(worker,train,Vector3(0,0,3)); worker.cargo_kind = &"coal"; worker.cargo = 10
	worker.command_return(train); worker._return_cargo()
	if not check(train.coal == 10 and worker.cargo == 0 and train.fuel == 0,"Infantry train drop-off failed"): return
	held = train.global_position; train.command_move(held+Vector3(3,0,0)); step(train,1)
	if not check(train.global_position == held and not train.supplies_available(),"Train departed before packing"): return
	step(train,3)
	if not check(train.global_position != held and train.coal == 10,"Train movement/cargo failed after packing"): return
	# A train can fund structures from its larger inventory; operating funds stay Depot-bound.
	train._stop_route(); train.order = "idle"; train.deploy_supplies(); step(train,2.1)
	train.stockpile.withdraw(&"energy",train.energy); train.stockpile.withdraw(&"iron",train.iron)
	train.carried_energy = 200; train.carried_iron = 90
	near(worker,train,Vector3(0,0,4)); worker.set_selected(true)
	network.bind_builder(worker,train)
	var building_point := Vector3.ZERO
	for x in range(-12,13,3):
		for z in range(-12,13,3):
			var candidate: Vector3 = train.global_position+Vector3(x,0,z)
			if network.can_place_size(candidate,train,Vector2i(5,5)): building_point = candidate
	if not check(building_point != Vector3.ZERO and network.construct_production(building_point,&"barracks"),"Train could not fund production building construction"): return
	var building = get_nodes_in_group("production_buildings")[-1]; building.set_process(false)
	if not check(building.assigned_depot == null and not building.request_unit(&"infantry") and train.energy == 100 and train.iron == 45,"Mobile construction silently assigned operating funds"): return
	var nearest_depot: Node3D
	for candidate in get_nodes_in_group("depots"):
		if SupplySource.covers(candidate,building.global_position,"player"): nearest_depot = candidate
	if not check(is_instance_valid(nearest_depot) and building.assign_source(nearest_depot),"Mobile-built structure could not explicitly bind covering Depot"): return
	nearest_depot.energy = 100; nearest_depot.iron = 20
	if not check(building.source_friendly() and building.request_unit(&"infantry"),"Assigned Depot could not pay for Infantry"): return
	if not check(not building.assign_source(depot),"Production reassignment allowed a nonempty queue"): return
	building._process(building.stats.print_seconds+0.1)
	if not check(building.queue == 0,"Explicitly assigned mobile-built Barracks did not produce Infantry"): return
	var generator_point := Vector3.ZERO
	for x in range(-12,13,3):
		for z in range(-12,13,3):
			var candidate: Vector3 = train.global_position+Vector3(x,0,z)
			if network.can_place_size(candidate,train,Vector2i(3,3)): generator_point = candidate
	if not check(generator_point != Vector3.ZERO and network.construct_generator(generator_point),"Train-funded Generator construction failed"): return
	var generator = get_nodes_in_group("energy_generators")[-1]; generator.set_process(false)
	if not check(generator.assigned_depot == null and not generator.active() and train.energy == 0 and train.iron == 25,"Mobile Generator silently began operation"): return
	for candidate in get_nodes_in_group("depots"):
		if SupplySource.covers(candidate,generator.global_position,"player"): nearest_depot = candidate
	if not check(generator.assign_source(nearest_depot) and generator.source_valid(),"Generator explicit Depot assignment failed"): return
	nearest_depot.stockpile.deposit(&"wood",1)
	if not check(generator.active(),"Assigned Generator did not recognize local wood"): return
	# Loss of a latched mobile source pauses Infantry rather than using neighboring Depot money.
	worker.command_repair(mine,truck)
	mine.take_damage(20)
	truck.take_damage(truck.health)
	await process_frame
	var before_hp: int = mine.health
	worker._repair(1)
	if not check(mine.health == before_hp and worker.state.contains("payer lost"),"Lost mobile repair source fell back to another payer"): return
	if not check(not SupplySource.available(null,"player"),"Material pile was accepted as supply stock"): return
	game.queue_free(); await process_frame
	print("MOBILE_SUPPLY_CHECKS_PASSED"); quit()
