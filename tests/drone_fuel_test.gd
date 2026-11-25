extends SceneTree
# Headless (item 10 of docs/BALANCE_IMPLEMENTATION_HANDOFF.md, docs/FUEL_BATCH.md): a Drone burns 0.1 coal a second
# while in the air, moving or not, about five minutes on its 30 tank. Out of coal it lands where it is and takes no
# move. A coal crate beside it refuels it as any vehicle is refuelled, and it takes off again.
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func step(unit: Node3D, seconds: float) -> void:
	for i in range(ceili(seconds*30)): unit._process(1.0/30)
func run() -> void:
	var rules: FuelRules = load("res://assets/economy/fuel_drone.tres")
	if not check(rules.consumes_fuel and is_equal_approx(rules.coal_per_second_airborne,0.1) and is_equal_approx(rules.reserve_capacity/rules.coal_per_second_airborne,300.0),"A Drone should burn 0.1 coal a second, 300 s on a 30 tank"): return
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	for i in range(3): await process_frame
	game.set_process(false)
	for group in ["units","depots","mines"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	var depot = game.depot
	# Far from every Depot, so nothing refuels it.
	var far: Vector3 = depot.global_position+Vector3(-90,0,40)
	var drone = load("res://scenes/gameplay/drone.tscn").instantiate()
	drone.position = far
	game.get_node("Entities/Units").add_child(drone)
	drone.set_process(false)
	await process_frame
	if not check(drone.fuel_active() and is_equal_approx(drone.fuel,30),"The Drone should start with 30 coal, has %.1f" % drone.fuel): return
	var flying: float = drone.get_node("Visuals").position.y
	# Hovering burns too.
	step(drone,10.0)
	if not check(absf(drone.fuel-29.0) < 0.05 and not drone.landed,"Hovering 10 s should burn 1 coal, has %.2f" % drone.fuel): return
	# Moving burns by the second, not by the metre.
	drone.command_move(far+Vector3(30,0,0))
	step(drone,2.0)
	if not check(absf(drone.fuel-28.8) < 0.05,"Flying 2 s should burn 0.2 coal, has %.2f" % drone.fuel): return
	# Out of coal: it lands where it is.
	drone.fuel = 0.15
	step(drone,2.0)
	var down_at: Vector3 = drone.global_position
	if not check(drone.landed and drone.out_of_fuel and drone.fuel == 0 and drone.state.contains("landed"),"Out of coal the Drone should land (landed=%s, state=%s)" % [drone.landed,drone.state]): return
	step(drone,3.0)
	if not check(drone.get_node("Visuals").position.y < 1.0,"The landed Drone should sit on the ground, at %.1f" % drone.get_node("Visuals").position.y): return
	drone.command_move(far+Vector3(-30,0,0))
	step(drone,3.0)
	if not check(drone.global_position.distance_to(down_at) < 0.01 and drone.landed,"A landed Drone should not move"): return
	if not check(drone.fuel_summary().contains("landed"),"The fuel line should say it has landed: %s" % drone.fuel_summary()): return
	# A coal crate beside it refuels it, and it takes off.
	var crate := CrateYard.spawn(self,game.ground.get_tile_at_position(drone.global_position+Vector3(2,0,0)),&"coal",25,"player")
	drone.command_stop() if drone.has_method("command_stop") else drone._stop_route()
	drone.order = "idle"
	step(drone,8.0)
	if not check(drone.fuel > 5 and not drone.landed and not drone.out_of_fuel and crate.amount < 25,"A coal crate beside it should refuel the Drone and it should take off (fuel=%.1f, landed=%s, crate=%d)" % [drone.fuel,drone.landed,crate.amount]): return
	step(drone,6.0)
	if not check(drone.get_node("Visuals").position.y > flying-0.5,"Refuelled, it should climb back to %.1f m, at %.1f" % [flying,drone.get_node("Visuals").position.y]): return
	print("DRONE_FUEL_TEST_PASSED")
	quit(0)
