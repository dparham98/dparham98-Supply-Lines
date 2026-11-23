extends SceneTree
# Headless (docs/VEHICLE_REPAIR.md): Infantry repair friendly vehicles as they do buildings, paid by a Depot or
# deployed Cargo truck whose range covers both; not people, not enemy vehicles, not out of range. Right-click and
# the Repair card both order it.
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func spawn(id: String, point: Vector3, team := "player") -> Node3D:
	var unit = load("res://scenes/gameplay/"+id+".tscn").instantiate()
	unit.team = team
	game.get_node("Entities/Units").add_child(unit)
	unit.set_process(false)
	unit._stop_route()
	for cell in unit._claimed.duplicate(): unit._release(cell)
	unit.grid_position = game.ground.nearest_actor_cell(game.ground.get_tile_at_position(point),unit.mobility_layer(),unit._owner_key())
	unit.global_position = game.ground.tile_to_world(unit.grid_position)
	unit._claim(unit.grid_position)
	return unit
func step(units: Array, seconds: float) -> void:
	for i in range(ceili(seconds*60)):
		for unit in units: unit._process(1.0/60)
func run() -> void:
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	game.set_process(false)
	for group in ["units","depots","mines","energy_generators","production_buildings"]:
		for node in get_nodes_in_group(group): node.set_process(false); node.set("is_selected",false)
	var depot = game.depot
	var rules: EngineeringRules = load("res://assets/economy/engineering_rules.tres")
	var near: Vector3 = depot.global_position+Vector3(10,0,10)
	var worker = spawn("infantry",near)
	var tank = spawn("tank",near+Vector3(4,0,0))
	if not check(EngineeringWork.is_vehicle(tank) and not EngineeringWork.is_vehicle(worker),"A Tank is a vehicle and Infantry is not"): return
	# A damaged Tank in the Depot's range is repaired from the Depot, at the building rate.
	tank.health = tank.max_health-50
	depot.energy = 500
	depot.iron = 500
	worker.command_repair(tank)
	if not check(worker.order == "repair" and worker.repair_payer == depot,"Infantry should repair the Tank from the Depot: order %s, payer %s" % [worker.order,worker.repair_payer]): return
	step([worker],8.0)
	if not check(tank.health == tank.max_health and worker.order == "idle","The Tank should be repaired: %d / %d, '%s'" % [tank.health,tank.max_health,worker.state]): return
	var ticks := ceili(50.0/rules.repair_hp)
	if not check(depot.energy == 500-ticks*rules.repair_energy and depot.iron == 500-ticks*rules.repair_iron,"Repair cost %d E and %d I" % [500-depot.energy,500-depot.iron]): return
	# A Tank that drives off is followed.
	tank.health = tank.max_health-20
	worker.command_repair(tank)
	tank.global_position += Vector3(0,0,10)
	step([worker],12.0)
	if not check(tank.health == tank.max_health,"The worker should follow the Tank to repair it: %d, '%s'" % [tank.health,worker.state]): return
	# Not people, not an enemy's vehicle, not itself.
	var other = spawn("infantry",near+Vector3(-3,0,0))
	other.health = other.max_health-10
	worker.command_repair(other)
	if not check(worker.order != "repair","Infantry are not repaired like vehicles"): return
	var enemy_tank = spawn("tank",near+Vector3(0,0,-4),"hostile")
	enemy_tank.health = enemy_tank.max_health-30
	worker.command_repair(enemy_tank)
	if not check(worker.order != "repair","An enemy vehicle is not repaired"): return
	# Out of every stockpile's range nothing pays, so nothing is repaired.
	var away: Vector3 = depot.global_position+Vector3(0,0,1)*(SupplySource.radius(depot)+40.0)
	var lone_worker = spawn("infantry",away)
	var lone_tank = spawn("tank",away+Vector3(4,0,0))
	lone_tank.health = lone_tank.max_health-30
	lone_worker.command_repair(lone_tank)
	step([lone_worker],3.0)
	if not check(lone_tank.health == lone_tank.max_health-30,"A vehicle out of range should not be repaired: '%s'" % lone_worker.state): return
	# A deployed Cargo truck pays for a vehicle in its range.
	var truck = spawn("cargo_vehicle",away+Vector3(-5,0,0))
	truck.deploy_supplies()
	step([truck],3.0)
	if not check(truck.supplies_available(),"The truck did not deploy"): return
	# Iron only: the truck pays the energy by burning coal from its tank (docs/MOBILE_SUPPLY.md).
	truck.stockpile.set_amount(&"energy",0)
	truck.stockpile.set_amount(&"iron",50)
	var truck_iron: int = truck.stockpile.amount(&"iron")
	lone_worker.command_repair(lone_tank)
	if not check(lone_worker.repair_payer == truck,"The deployed truck should pay: %s" % [lone_worker.repair_payer]): return
	step([lone_worker],6.0)
	if not check(lone_tank.health == lone_tank.max_health and truck.stockpile.amount(&"iron") < truck_iron,"The truck should pay to repair the Tank: %d, iron %d" % [lone_tank.health,truck.stockpile.amount(&"iron")]): return
	# Right-click on a damaged vehicle orders repair; the Repair card picks it too.
	tank.health = tank.max_health-10
	worker.order = "idle"
	worker.set_selected(true)
	game.issue_map_order(tank.global_position,1.5,false)
	if not check(worker.order == "repair" and worker.order_target == tank,"Right-click on a damaged Tank should order repair: %s" % worker.order): return
	worker.order = "idle"
	game.pending_unit_command = "repair"
	game.issue_map_order(tank.global_position,1.5,true)
	if not check(worker.order == "repair" and worker.order_target == tank,"The Repair card should take a damaged Tank: %s" % worker.order): return
	print("VEHICLE_REPAIR_TEST_PASSED")
	quit(0)
