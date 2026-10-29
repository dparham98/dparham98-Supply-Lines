extends SceneTree
# Shift-queued orders: ordering, replacement, Stop, completion rules, fuel pause, markers.
var game: Node3D
var hud: CanvasLayer
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func step(unit: Node3D, seconds: float) -> void:
	for i in range(ceili(seconds*60)): unit._process(1.0/60)
func run_until(unit: Node3D, condition: Callable, seconds: float) -> bool:
	for i in range(ceili(seconds*60)):
		unit._process(1.0/60)
		if condition.call(): return true
	return false
func spawn(path: String, offset: Vector3) -> Node3D:
	var unit = load(path).instantiate()
	unit.position = game.depot.global_position+offset
	game.get_node("Entities/Units").add_child(unit)
	unit.set_process(false)
	return unit
func screen(point: Vector3) -> Vector2:
	return game.get_viewport().get_camera_3d().unproject_position(point)
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game); await process_frame
	game.set_process(false)
	hud = game.get_node("Interface"); hud.set_process(false)
	for group in ["units","depots"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	var rig = game.get_node("CameraRig"); rig.set_process(false)
	var depot = game.depot
	rig.focus_position(depot.global_position,55)
	for frame in range(180): rig.advance_camera(1.0/60)
	var markers = game.get_node("WaypointMarkers")
	markers.set_process(false)
	var worker = game.get_node("Entities/Units/Infantry")
	for node in get_nodes_in_group("units"): node.set_selected(node == worker)
	var start: Vector3 = worker.global_position
	var a: Vector3 = start+Vector3(6,0,-4)
	var b: Vector3 = start+Vector3(10,0,-8)
	var c: Vector3 = start+Vector3(4,0,-10)
	# Queuing on an idle unit starts at once; later entries wait their turn.
	worker.queue_order({kind = "move", point = a})
	worker.queue_order({kind = "move", point = b})
	if not check(worker.order == "move" and worker.move_goal == a and worker.order_queue.size() == 1,"Idle queue did not start the first order"): return
	# Shift-right-click goes through the real input path into the queue.
	game.issue_order(screen(c),true)
	if not check(worker.order_queue.size() == 2 and worker.move_goal == a and "queued" in game.message,"Shift right-click did not queue"): return
	markers._process(0)
	if not check(markers.visible_count() == 3 and markers.markers[0].get_node("Order").text == "1" and markers.markers[2].get_node("Order").text == "3","Waypoint markers wrong: %d" % markers.visible_count()): return
	if not check(run_until(worker,func(): return worker.move_goal == b,20),"Second order did not start after the first"): return
	if not check(worker.global_position.distance_to(a) < 2.5,"First move not reached before the second started"): return
	if not check(run_until(worker,func(): return worker.order == "idle" and worker.order_queue.is_empty(),40) and worker.global_position.distance_to(worker.move_goal) < 1.5,"Queue did not finish at the last waypoint"): return
	markers._process(0)
	if not check(markers.visible_count() == 0,"Markers shown for an idle unit"): return
	# A plain order replaces the queue; Stop clears it.
	worker.queue_order({kind = "move", point = a}); worker.queue_order({kind = "move", point = b})
	game.issue_order(screen(c))
	if not check(worker.order_queue.is_empty() and worker.order != "idle" and worker.move_goal != b,"Plain order did not replace the queue"): return
	worker.queue_order({kind = "move", point = a})
	hud.stop_units()
	if not check(worker.order_queue.is_empty() and worker.order == "idle","Stop did not clear the queue"): return
	markers._process(0)
	if not check(markers.visible_count() == 0,"Markers left after Stop"): return
	# Attack finishes when the target dies, then the next order runs.
	var hostile = game.get_node("Entities/Units/Hostile")
	worker.queue_order({kind = "attack", target = hostile})
	worker.queue_order({kind = "move", point = a})
	if not check(worker.order == "attack","Queued attack did not start"): return
	hostile.take_damage(hostile.health+100); await process_frame
	step(worker,0.1)
	if not check(worker.order == "move" and worker.move_goal == a,"Order after a finished attack did not start"): return
	hud.stop_units()
	# Entries whose target is gone are skipped.
	var gone = spawn("res://scenes/gameplay/hostile.tscn",Vector3(40,0,0))
	worker.queue_order({kind = "move", point = worker.global_position+Vector3(1,0,0)})
	worker.order_queue.append({kind = "attack", target = gone})
	worker.order_queue.append({kind = "move", point = b})
	gone.free()
	if not check(run_until(worker,func(): return worker.move_goal == b,10),"Freed target was not skipped"): return
	hud.stop_units()
	# Gather never finishes, so orders queued behind it wait.
	var pile = game.get_node("Entities/Resources/TestingCoalPile")
	worker.queue_order({kind = "gather", target = pile})
	worker.queue_order({kind = "move", point = a})
	step(worker,8)
	if not check(worker.order in ["gather","return"] and worker.order_queue.size() == 1,"Gather did not hold the queue"): return
	hud.stop_units(); worker.cargo = 0
	# Card orders with Shift queue and stay armed for more targets.
	game.pending_unit_command = "move"
	game.issue_card_order(screen(a),true)
	game.issue_card_order(screen(b),true)
	if not check(game.pending_unit_command == "move" and worker.order == "move" and worker.order_queue.size() == 1,"Shift card order did not queue or stay armed"): return
	game.issue_card_order(screen(c))
	if not check(game.pending_unit_command.is_empty() and worker.order_queue.is_empty(),"Plain card order did not replace the queue and disarm"): return
	hud.stop_units()
	# Out of fuel pauses the queue without dropping it.
	var tank = spawn("res://scenes/gameplay/tank.tscn",Vector3(14,0,14))
	depot.coal = 0
	tank.fuel = 0.5
	tank.queue_order({kind = "move", point = tank.global_position+Vector3(-12,0,0)})
	tank.queue_order({kind = "move", point = tank.global_position+Vector3(-12,0,6)})
	step(tank,4)
	if not check(tank.out_of_fuel and tank.order == "move" and tank.order_queue.size() == 1,"Out of fuel dropped the queue"): return
	depot.coal = 100
	if not check(run_until(tank,func(): return tank.order_queue.is_empty(),30),"Queue did not resume after refuelling"): return
	# Assigning a supply route clears a cargo vehicle's queue.
	var truck = spawn("res://scenes/gameplay/cargo_vehicle.tscn",Vector3(-14,0,10))
	truck.queue_order({kind = "move", point = truck.global_position+Vector3(-4,0,0)})
	truck.queue_order({kind = "move", point = truck.global_position+Vector3(-8,0,0)})
	var second = load("res://scenes/gameplay/depot.tscn").instantiate()
	second.name = "QueueTestDepot"; second.team = "player"
	second.position = depot.global_position+Vector3(60,0,0)
	game.get_node("Entities/Buildings").add_child(second); second.set_process(false)
	if not check(truck.start_supply_route(depot,second,10,0,false) and truck.order_queue.is_empty(),"Supply route kept the move queue: %s" % truck.route_error): return
	# An idle Cargo vehicle refuels once per frame, at the configured rate.
	truck.cancel_supply_route(); truck._stop_route(); truck.order = "idle"; truck.order_queue.clear()
	truck.global_position = depot.global_position+Vector3(-10,0,8)
	truck.fuel = 0; depot.coal = 100
	step(truck,1)
	if not check(truck.fuel <= truck.fuel_rules.refuel_coal_per_second+1 and truck.fuel >= truck.fuel_rules.refuel_coal_per_second-1,"Cargo refuel rate %.1f/s, expected %.1f" % [truck.fuel,truck.fuel_rules.refuel_coal_per_second]): return
	print("COMMAND_QUEUE_TEST_PASSED")
	quit(0)
