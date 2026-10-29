extends SceneTree
var game: Node3D
var vehicle: Node3D
var normal_economy_rules: Resource
func _initialize() -> void:
	# Economy regressions use normal inventories regardless of sandbox iron grants.
	normal_economy_rules = load("res://assets/economy/depot_rules.tres")
	normal_economy_rules.testing_starting_iron = -1
	call_deferred("run")
func step(seconds: float) -> void:
	for i in range(ceili(seconds*60)):
		vehicle._process(1.0/60)
func run() -> void:
	game = load("res://scenes/maps/supply_routes.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	for depot in get_nodes_in_group("depots"): depot.set_process(false)
	for unit in get_nodes_in_group("units"): unit.set_process(false)
	var first = game.depot
	var outpost = game.get_node("Entities/Buildings/Outpost")
	var neutral = game.get_node("Entities/Buildings/NeutralDepot")
	vehicle = game.get_node("Entities/Units/CargoVehicle")
	var network = game.get_node("DepotNetwork")
	assert(first.energy == 500 and first.iron == 200 and outpost.energy == 0)
	assert(neutral.team == "neutral")
	# Empty idle vehicles do not transfer anything without a route.
	step(5)
	assert(first.energy == 500 and first.iron == 200 and outpost.energy == 0)
	assert(not vehicle.start_supply_route(first,first,10,0,false))
	assert(not vehicle.start_supply_route(first,neutral,10,0,false))
	assert(not vehicle.start_supply_route(first,outpost,90,20,false))
	assert(not vehicle.start_supply_route(first,outpost,-1,1,false))
	assert(not vehicle.start_supply_route(first,outpost,0,0,false))
	# Complete an actual waypoint-following load/travel/unload loop. The HUD route panel was
	# replaced by crate containers (crate_containers_test); the route engine is still driven directly.
	assert(vehicle.start_supply_route(first,outpost,60,40,false))
	assert(vehicle.route_active and vehicle.origin_depot == first and vehicle.destination_depot == outpost)
	for i in range(180*60):
		step(1.0/60)
		assert(first.energy+outpost.energy+vehicle.carried_energy == 500)
		assert(first.iron+outpost.iron+vehicle.carried_iron == 200)
		if not vehicle.route_active: break
	assert(not vehicle.route_active and outpost.energy == 60 and outpost.iron == 40,"Delivery did not complete through existing pathing")
	assert(first.energy == 440 and first.iron == 160)
	# Build a local generator at the outpost: it needs bootstrap energy first.
	assert(vehicle.start_supply_route(first,outpost,60,0,false))
	for i in range(180*60):
		step(1.0/60)
		if not vehicle.route_active: break
	assert(outpost.energy == 120 and first.energy == 380)
	network.select_depot(outpost)
	var generator_point := Vector3.ZERO
	for x in range(-20,21,5):
		for z in range(-20,21,5):
			var candidate: Vector3 = outpost.global_position+Vector3(x,0,z)
			if network.can_place_size(candidate,outpost,network.supply_rules.generator_footprint): generator_point = candidate
	assert(generator_point != Vector3.ZERO)
	assert(network.update_preview(generator_point,true))
	assert(not network.construct_generator(outpost.global_position))
	assert(outpost.energy == 120 and outpost.iron == 40)
	assert(network.construct_generator(generator_point))
	var generator = get_nodes_in_group("energy_generators")[0]
	generator.set_process(false)
	assert(generator.assigned_depot == outpost and outpost.energy == 20 and outpost.iron == 20)
	outpost.wood = 40
	generator._process(1)
	assert(outpost.energy == 20 and outpost.wood == 40 and first.energy == 380)
	generator._process(1)
	assert(outpost.energy == 30 and outpost.wood == 39)
	generator._process(18)
	assert(outpost.energy == 120 and outpost.wood == 30 and outpost.request_cargo())
	outpost._process(3.1)
	assert(game.units_printed == 0 and outpost.queue == 0)
	# Capturing the assigned Depot never feeds its new owner.
	outpost.team = "enemy"
	outpost.ownership_changed.emit()
	var stored: int = outpost.energy
	generator._process(10)
	assert(outpost.energy == stored and not generator.active())
	outpost.team = "player"
	outpost.ownership_changed.emit()
	assert(generator.active())
	# Capture either endpoint during transit: latched pause and cargo conservation.
	assert(vehicle.start_supply_route(first,outpost,50,0,false))
	for i in range(180*60):
		step(1.0/60)
		if vehicle.carried_energy > 0: break
	assert(vehicle.carried_energy == 50)
	# Unreachable approach waits without paying out or losing loaded cargo.
	outpost.dropoff_range = 1.0
	vehicle._stop_route()
	stored = outpost.energy
	step(20)
	assert(vehicle.carried_energy == 50 and outpost.energy == stored and vehicle.state == "Route blocked · retrying")
	outpost.dropoff_range = 7.0
	outpost.team = "enemy"
	outpost.ownership_changed.emit()
	assert(vehicle.route_paused and not vehicle.resume_supply_route())
	var held_position: Vector3 = vehicle.global_position
	stored = outpost.energy
	step(10)
	assert(vehicle.global_position == held_position and vehicle.carried_energy == 50 and outpost.energy == stored)
	outpost.team = "player"
	outpost.ownership_changed.emit()
	step(2)
	assert(vehicle.route_paused and vehicle.carried_energy == 50)
	assert(vehicle.resume_supply_route())
	for i in range(180*60):
		step(1.0/60)
		if not vehicle.route_active: break
	assert(not vehicle.route_active and outpost.energy == stored+50)
	# Partial availability, depleted stock waiting, repeat and cancellation retaining cargo.
	first.energy = 7
	first.iron = 3
	assert(vehicle.start_supply_route(first,outpost,20,10,true))
	for i in range(180*60):
		step(1.0/60)
		if vehicle.carried_energy > 0: break
	assert(vehicle.carried_energy == 7 and vehicle.carried_iron == 3 and first.energy == 0 and first.iron == 0)
	vehicle.cancel_supply_route()
	step(2)
	assert(vehicle.carried_energy == 7 and vehicle.carried_iron == 3 and not vehicle.route_active)
	# Explicit new route sends held cargo to the chosen destination without another load.
	stored = outpost.energy
	assert(vehicle.start_supply_route(first,outpost,20,10,true))
	for i in range(180*60):
		step(1.0/60)
		if outpost.energy == stored+7: break
	assert(outpost.energy == stored+7 and vehicle.route_active and vehicle.stage == "loading")
	for i in range(180*60):
		step(1.0/60)
		if vehicle.state == "Waiting for source stock": break
	assert(vehicle.state == "Waiting for source stock" and vehicle.carried_energy == 0 and first.energy == 0)
	# Manual move cancels route, retaining any held cargo.
	vehicle.carried_energy = 9
	vehicle.command_move(vehicle.global_position+Vector3(3,0,0))
	assert(not vehicle.route_active and vehicle.carried_energy == 9)
	# Source capture also pauses. Endpoint removal is safe and does not credit anyone.
	assert(vehicle.start_supply_route(first,outpost,10,0,false))
	first.team = "enemy"
	first.ownership_changed.emit()
	assert(vehicle.route_paused)
	first.team = "player"
	first.ownership_changed.emit()
	assert(vehicle.resume_supply_route())
	# Cargo production uses the same prepaid local queue and creates its dedicated scene.
	first.energy = 100
	first.iron = 20
	assert(first.request_cargo())
	assert(first.energy == 0 and first.iron == 0 and first.queue == 1)
	first._process(3.1)
	assert(first.queue == 0)
	var cargo_count := 0
	for unit in get_nodes_in_group("units"):
		if unit.is_cargo_vehicle: cargo_count += 1
	assert(cargo_count == 3) # Includes the outpost cargo job replacing removed Depot Infantry.
	outpost.free()
	step(1)
	assert(vehicle.route_paused and vehicle.carried_energy == 9)
	vehicle.take_damage(1000)
	assert(vehicle.health == 0 and not vehicle.is_in_group("units"))
	print("SUPPLY_CHECKS_PASSED")
	quit()
