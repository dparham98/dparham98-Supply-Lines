extends SceneTree
# Headless (docs/FUEL_BATCH.md, docs/MOBILE_SUPPLY.md): a deployed Cargo truck pays energy by burning coal at
# the Generator's rate (loose coal, coal crates aboard, then its tank) and hands the same coal to other
# vehicles' tanks; vehicles refuel from a coal crate beside them; inside a Depot's range vehicles move on the
# Depot's energy instead of fuel; energy cannot be crated.
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func spawn(id: String, point: Vector3) -> Node3D:
	var unit = load("res://scenes/gameplay/"+id+".tscn").instantiate()
	unit.team = "player"
	game.get_node("Entities/Units").add_child(unit)
	unit.set_process(false)
	place(unit,point)
	return unit
func place(unit: Node3D, point: Vector3) -> void:
	unit._stop_route()
	for cell in unit._claimed.duplicate(): unit._release(cell)
	unit.grid_position = game.ground.nearest_actor_cell(game.ground.get_tile_at_position(point),unit.mobility_layer(),unit._owner_key())
	unit.global_position = game.ground.tile_to_world(unit.grid_position)
	unit._claim(unit.grid_position)
func step(units: Array, seconds: float) -> void:
	for i in range(ceili(seconds*60)):
		for unit in units: unit._process(1.0/60)
func run() -> void:
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	game.set_process(false)
	for group in ["units","depots","mines"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	var depot = game.depot
	var burn: GeneratorRules = load("res://assets/economy/generator_rules.tres")
	if not check(game.vehicle_fuel_required,"This map should need fuel"): return
	# A truck deployed well outside the Depot's range, with no energy, 2 loose coal and a coal crate aboard.
	var away: Vector3 = depot.global_position+Vector3(0,0,1)*(SupplySource.radius(depot)+30.0)
	var truck = spawn("cargo_vehicle",away)
	truck.stockpile.set_amount(&"energy",0)
	truck.stockpile.set_amount(&"coal",2)
	truck.crates.append({kind = &"coal", amount = 3})
	truck._sync_reserved()
	truck.fuel = 10
	truck.deploy_supplies()
	step([truck],3.0)
	if not check(truck.supplies_available(),"The truck did not deploy"): return
	var rate: int = burn.coal_output
	if not check(truck.energy == (2+3+10)*rate,"Energy on hand should count its coal at %d E each: %d" % [rate,truck.energy]): return
	# Paying 2.5 coal's worth burns the 2 loose coal, then one from the crate; the rest is kept as credit.
	var due := rate*2+rate/2
	if not check(truck.spend_local(due,0),"The truck refused energy it can burn coal for"): return
	if not check(truck.coal == 0 and truck.crate_units(&"coal") == 2 and is_equal_approx(truck.fuel,10) and truck.energy_credit == rate-rate/2,"Burn order wrong: loose %d, crate %d, tank %.1f, credit %d" % [truck.coal,truck.crate_units(&"coal"),truck.fuel,truck.energy_credit]): return
	# Then the crate, then the tank, which it may empty.
	if not check(truck.spend_local(truck.energy,0) and truck.energy == 0 and truck.crate_units(&"coal") == 0 and truck.fuel < 1,"The truck should burn its crate and then its tank: energy %d, tank %.1f" % [truck.energy,truck.fuel]): return
	if not check(not truck.spend_local(1,0),"An empty truck paid energy"): return
	# A build site in its range is paid from its coal.
	truck.stockpile.set_amount(&"coal",4)
	var plan = game.get_node("DepotNetwork").queue_plan(truck.global_position+Vector3(0,0,7),&"generator")
	if not check(plan != null,"No generator plan beside the truck"): return
	var paid_by = plan.energy_payer(plan.spec.energy)
	if not check(paid_by == truck,"The deployed truck should pay a site in its range with coal: %s" % [paid_by]): return
	plan.queue_free()
	# Refuelling: a tank beside the deployed truck takes the truck's coal, then its tank.
	truck.stockpile.set_amount(&"coal",2)
	truck.fuel = 5
	var tank = spawn("tank",truck.global_position+Vector3(5,0,0))
	tank.fuel = 0
	tank.out_of_fuel = true
	step([tank,truck],4.0)
	if not check(truck.coal == 0 and truck.fuel < 5 and tank.fuel >= 6,"The tank should take the truck's coal and then its tank: truck coal %d tank %.1f, tank %.1f" % [truck.coal,truck.fuel,tank.fuel]): return
	# A coal crate on the ground refuels a stopped vehicle within 4 m, not one further off.
	var crate_cell: Vector2i = game.ground.nearest_actor_cell(game.ground.get_tile_at_position(away+Vector3(25,0,0)),0)
	var crate = CrateYard.spawn(self,crate_cell,&"coal",20,"player")
	var near = spawn("tank",crate.global_position+Vector3(2.5,0,0))
	var far = spawn("tank",crate.global_position+Vector3(-9,0,0))
	near.fuel = 0; far.fuel = 0
	if not check(near.can_refuel_from(crate) and not far.can_refuel_from(crate),"Crate refuel range wrong: near %.1f m, far %.1f m" % [near.global_position.distance_to(crate.global_position),far.global_position.distance_to(crate.global_position)]): return
	step([near,far],3.0)
	if not check(near.fuel >= 10 and crate.amount <= 10 and far.fuel == 0,"Refuel from the crate wrong: near %.1f, far %.1f, crate %d" % [near.fuel,far.fuel,crate.amount]): return
	# Depot power: inside the Depot's range a move takes the Depot's energy, not fuel.
	var mover = spawn("tank",depot.global_position+Vector3(8,0,8))
	mover.fuel = 20
	depot.energy = 100
	var start: Vector3 = mover.global_position
	mover.command_move(start+Vector3(10,0,0))
	step([mover],6.0)
	var moved := start.distance_to(mover.global_position)
	if not check(moved > 5 and is_equal_approx(mover.fuel,20) and depot.energy < 100,"In range the move should run on Depot energy: moved %.1f, fuel %.2f, energy %d" % [moved,mover.fuel,depot.energy]): return
	if not check(absi((100-depot.energy)-floori(moved*mover.fuel_rules.depot_energy_per_metre)) <= 1,"Depot energy spent %d for %.1f m" % [100-depot.energy,moved]): return
	if not check("running on" in mover.fuel_summary(),"The fuel line should say the Depot powers it: %s" % mover.fuel_summary()): return
	# A Depot with no energy powers nothing: the tank burns again.
	depot.energy = 0
	mover.command_move(start)
	step([mover],6.0)
	if not check(mover.fuel < 20,"With the Depot empty the tank should burn: %.2f" % mover.fuel): return
	# An empty tank still moves on Depot power.
	depot.energy = 100
	mover.fuel = 0
	mover.out_of_fuel = true
	mover.auto_refuel = false
	var here: Vector3 = mover.global_position
	mover.command_move(here+Vector3(6,0,0))
	step([mover],6.0)
	if not check(here.distance_to(mover.global_position) > 3,"An empty tank should move on Depot power"): return
	# Energy cannot be crated.
	if not check(CrateYard.pack(depot,&"energy") == null and not truck.manifest_add(&"energy") and not crate.accepts(&"energy"),"Energy should not go in a crate"): return
	print("TRUCK_FUEL_TEST_PASSED")
	quit(0)
