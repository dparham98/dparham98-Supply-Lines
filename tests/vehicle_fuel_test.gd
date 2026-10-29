extends SceneTree
# Vehicle fuel (economy stage 5): consumption, idle, exhaustion, refuelling, recovery and separation.
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func step(unit: Node3D, seconds: float) -> void:
	for i in range(ceili(seconds*60)): unit._process(1.0/60)
func fixture(path: String) -> void:
	if is_instance_valid(game): game.free()
	game = load(path).instantiate()
	root.add_child(game); await process_frame
	game.set_process(false)
	for group in ["units","depots","mines"]:
		for node in get_nodes_in_group(group): node.set_process(false)
func spawn(id: String, point: Vector3, fuelled := true) -> Node3D:
	var unit = load("res://scenes/gameplay/"+id+".tscn").instantiate()
	unit.start_fuelled = fuelled
	unit.position = point
	game.get_node("Entities/Units").add_child(unit)
	unit.set_process(false)
	return unit
func place(unit: Node3D, point: Vector3) -> void:
	unit._stop_route()
	for cell in unit._claimed.duplicate(): unit._release(cell)
	unit.grid_position = game.ground.nearest_actor_cell(game.ground.get_tile_at_position(point),unit.mobility_layer(),unit._owner_key())
	unit.global_position = game.ground.tile_to_world(unit.grid_position)
	unit._claim(unit.grid_position)
func run() -> void:
	await fixture("res://scenes/maps/resource_skirmish.tscn")
	var depot = game.depot
	depot.coal = 0
	var pile = game.get_node("Entities/Resources/TestingCoalPile")
	if not check(game.vehicle_fuel_required and pile.resource_kind == &"coal" and pile.remaining == 200 and depot.coal == 0,"Skirmish fuel switch or testing coal pile wrong"): return
	# The starting Infantry can carry the testing coal into the Depot stockpile.
	var worker = game.get_node("Entities/Units/Infantry")
	worker.command_gather(pile)
	for i in range(60*40):
		worker._process(1.0/60)
		if depot.coal > 0: break
	if not check(depot.coal == worker.carry_capacity and pile.remaining+depot.coal+worker.cargo == 200,"Testing coal pile unreachable or delivery lost coal"): return
	worker._stop_route(); worker.order = "idle"; worker.source = null
	depot.coal = 0
	var tank = spawn("tank",depot.global_position+Vector3(14,0,14))
	if not check(tank.fuel_active() and is_equal_approx(tank.fuel,60) and not tank.fuel_low(),"Authored vehicle did not start fuelled"): return
	var drone = spawn("drone",depot.global_position+Vector3(-14,0,14))
	if not check(not drone.fuel_active() and drone.fuel == 0,"Drone fuel should stay deferred"): return
	# Ground vehicles burn nothing while idle.
	step(tank,5)
	if not check(is_equal_approx(tank.fuel,60),"Idle vehicle burned fuel"): return
	# Consumption follows distance moved at the editable per-unit rate.
	var start: Vector3 = tank.global_position
	var travelled := 0.0
	tank.command_move(start+Vector3(10,0,0))
	for i in range(600):
		var before: Vector3 = tank.global_position
		tank._process(1.0/60)
		travelled += before.distance_to(tank.global_position)
		if tank.order == "idle": break
	if not check(travelled > 5 and absf((60-tank.fuel)-travelled*tank.fuel_rules.coal_per_movement_unit) < 0.01,"Fuel burn %.3f does not match %.2f units moved" % [60-tank.fuel,travelled]): return
	# Exhaustion stops the vehicle in place with its order paused.
	tank.fuel = 1
	tank.command_move(tank.global_position+Vector3(-12,0,0))
	step(tank,4)
	var stranded: Vector3 = tank.global_position
	if not check(tank.fuel == 0 and tank.out_of_fuel and tank.order == "move" and tank.state.begins_with("Out of fuel"),"Vehicle did not stop out of fuel with its order kept"): return
	step(tank,2)
	if not check(tank.global_position == stranded and tank.fuel == 0,"Empty vehicle kept moving"): return
	# A limited source refuels from whole coal units and the paused order resumes.
	depot.coal = 3
	step(tank,0.25)
	if not check(depot.coal == 2 and is_equal_approx(tank.fuel,1) and tank.out_of_fuel and tank.global_position == stranded,"Refuel rate or pause wrong"): return
	step(tank,0.5)
	if not check(depot.coal == 0 and tank.fuel <= 3 and tank.fuel > 2 and not tank.out_of_fuel and tank.global_position != stranded,"Order did not resume on the partial tank"): return
	# Auto-refuel off keeps stockpile coal untouched.
	place(tank,depot.global_position+Vector3(14,0,14)); tank.order = "idle"
	tank.fuel = 10; tank.auto_refuel = false; depot.coal = 50
	step(tank,2)
	if not check(depot.coal == 50 and is_equal_approx(tank.fuel,10),"Auto-refuel off still refuelled"): return
	tank.auto_refuel = true
	# One source only: a pinned Depot is never topped up from a nearby deployed truck.
	var truck = spawn("cargo_vehicle",depot.global_position+Vector3(14,0,10))
	truck.fuel = 30
	if not check(truck.deploy_supplies(),"Truck could not deploy"): return
	step(truck,2.1)
	if not check(truck.supplies_available() and is_equal_approx(truck.fuel,30),"Truck deployment changed its fuel"): return
	truck.carried_coal = 40
	depot.coal = 2
	tank.set_fuel_source(depot)
	step(tank,2)
	if not check(depot.coal == 0 and truck.coal == 40 and is_equal_approx(tank.fuel,12),"Pinned refuel borrowed from a second source"): return
	step(tank,1)
	if not check(truck.coal == 40 and is_equal_approx(tank.fuel,12),"Empty pinned source fell back to another source"): return
	tank.set_fuel_source(null)
	step(tank,1)
	if not check(truck.coal+tank.fuel == 52 and truck.coal < 40,"Unpinned refuel did not use the remaining source"): return
	# Deployed truck coal stays separate from its own tank: it never refuels itself, and
	# construction cannot spend tank fuel.
	truck.fuel = 5; truck.stockpile.withdraw(&"coal",truck.coal)
	step(truck,1)
	if not check(is_equal_approx(truck.fuel,5) and not truck.spend_local(1,0) and is_equal_approx(truck.fuel,5),"Truck refuelled from itself or spent its tank"): return
	# Stranded recovery: a deployed truck refuels a vehicle without it moving.
	var far: Vector3 = depot.global_position+Vector3(60,0,0)
	place(tank,far); tank.fuel = 0; tank.out_of_fuel = true; tank.order = "idle"
	var held: Vector3 = tank.global_position
	step(tank,1)
	if not check(tank.fuel == 0 and depot.global_position.distance_to(held) > depot.rules.construction_radius,"Stranded tank refuelled out of range"): return
	truck.pack_supplies(); step(truck,2.1)
	place(truck,held+Vector3(4,0,0))
	if not check(truck.deploy_supplies(),"Rescue truck could not deploy"): return
	step(truck,2.1)
	truck.carried_coal = 20
	step(tank,2)
	if not check(tank.global_position == held and is_equal_approx(tank.fuel,10) and truck.coal == 10,"Deployed truck did not rescue the stranded tank in place"): return
	# Captured sources are unavailable.
	truck.team = "enemy"
	step(tank,1)
	if not check(is_equal_approx(tank.fuel,10) and truck.coal == 10,"Refuelled from an enemy source"): return
	truck.team = "player"
	# HUD readout and toggle.
	tank.fuel = 5; tank.auto_refuel = false
	tank.set_selected(true)
	var hud = game.get_node("Interface")
	hud._process(0)
	if not check(tank.fuel_low() and hud.card.get_node("ToggleRefuel").visible and "LOW FUEL" in hud.info.get_node("Details").text and "Auto-refuel off" in hud.info.get_node("Details").text,"HUD fuel readout or toggle missing"): return
	hud.card.get_node("ToggleRefuel").pressed.emit()
	if not check(tank.auto_refuel,"Auto-refuel toggle did not apply"): return
	tank.set_selected(false)
	# Newly produced vehicles start empty, then refuel when stopped at the Depot.
	depot.energy = 1000; depot.iron = 500; depot.coal = 100
	var before_units := get_nodes_in_group("mobile_supplies").size()
	if not check(depot.request_cargo(),"Cargo production refused"): return
	depot._process(depot.print_seconds+0.1)
	var produced = get_nodes_in_group("mobile_supplies")[-1]
	if not check(get_nodes_in_group("mobile_supplies").size() == before_units+1 and produced.fuel == 0,"Produced vehicle did not start empty"): return
	produced.set_process(false)
	step(produced,7)
	if not check(produced.fuel >= produced.fuel_rules.reserve_capacity-1 and depot.coal+produced.fuel == 100,"Produced vehicle did not refuel at its Depot"): return
	# Exercise scenes from earlier batches keep fuel off.
	await fixture("res://scenes/maps/rail_exercise.tscn")
	var train = game.get_node("Entities/Units/Train")
	if not check(not game.vehicle_fuel_required and not train.fuel_active() and train.fuel == 0,"Earlier exercise scene requires fuel"): return
	# Train round-trip check warns but allows the route.
	game.vehicle_fuel_required = true
	train.fuel = 0
	var destination = game.get_node("Entities/Buildings/EastDepot")
	if not check(train.start_supply_route(game.depot,destination,1,0,true) and train.route_active,"Low-fuel train route was refused"): return
	var needed: float = train.estimated_round_trip_fuel()
	if not check(needed > 0 and "Round trip needs" in train.fuel_warning and "Train fuel warning" in game.message,"Round-trip fuel warning missing"): return
	train.fuel = train.fuel_rules.reserve_capacity
	train.check_round_trip_fuel()
	if not check(needed > train.fuel or train.fuel_warning.is_empty(),"Warning shown for a sufficient tank"): return
	print("VEHICLE_FUEL_TEST_PASSED")
	quit(0)
