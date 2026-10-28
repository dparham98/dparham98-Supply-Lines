extends SceneTree
var normal_economy_rules: Resource
func _initialize() -> void:
	# Economy regressions use normal inventories regardless of sandbox iron grants.
	normal_economy_rules = load("res://assets/economy/depot_rules.tres")
	normal_economy_rules.testing_starting_iron = -1
	call_deferred("run")
func run() -> void:
	var game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	for unit in get_nodes_in_group("units"): unit.set_process(false)
	for depot in get_nodes_in_group("depots"): depot.set_process(false)
	var network = game.get_node("DepotNetwork")
	var first = game.depot
	assert(first.energy == 500 and first.iron == 0)
	assert(not first.request_infantry())
	first.iron = 100
	assert(not first.request_infantry())
	assert(first.request_cargo())
	assert(first.energy == 400 and first.iron == 80)
	# Find a valid nearby footprint through the same placement gate used by input.
	var point := Vector3.ZERO
	for x in range(-25,26,10):
		for z in range(-25,26,10):
			var candidate: Vector3 = first.global_position+Vector3(x,0,z)
			if network.can_place(candidate,first): point = candidate
	assert(point != Vector3.ZERO)
	assert(not network.construct(first.global_position))
	assert(first.energy == 400 and first.iron == 80)
	assert(network.construct(point))
	var second = network.selected
	second.set_process(false)
	assert(second.energy == 0 and second.iron == 0)
	assert(first.energy == 380 and first.iron == 60)
	assert(not second.request_infantry())
	# An overlapping rich neighbour must never silently pay for the selected Depot.
	assert(not network.construct(first.global_position+Vector3(20,0,20)))
	assert(first.energy == 380 and first.iron == 60)
	network.select_depot(first)
	assert(first.get_node("Territory").visible and not second.get_node("Territory").visible)
	assert(first.request_truck())
	assert(first.energy == 230 and first.iron == 30)
	# Complete both prepaid jobs through the original printer exit logic.
	first._process(3.1)
	first._process(3.1)
	var printed_truck: Node3D
	for unit in get_nodes_in_group("units"):
		unit.set_process(false)
		if unit.is_depot_truck: printed_truck = unit
	assert(printed_truck != null and first.queue == 0)
	printed_truck.set_selected(true)
	# Occupied footprint fails and retains truck reservation.
	var old_position: Vector3 = printed_truck.global_position
	printed_truck.global_position = old_position
	assert(not network.deploy_selected_truck())
	assert(is_instance_valid(printed_truck) and printed_truck._claimed.size() == 1)
	printed_truck.global_position = old_position
	printed_truck.set_selected(false)
	# Capture is uncontested proximity, resets when contested, retains inventory.
	var worker = game.get_node("Entities/Units/Infantry")
	var enemy = game.get_node("Entities/Units/Hostile")
	worker.global_position = second.global_position+Vector3(9,0,0)
	enemy.global_position = second.global_position+Vector3(-9,0,0)
	second.update_capture(20)
	assert(second.team == "player" and second.capture_progress == 0)
	worker.global_position = first.global_position+Vector3(0,0,20)
	second.energy = 77
	second.queue = 1
	second.pending.append("cargo")
	second.update_capture(4)
	assert(second.team == "player" and second.capture_progress == 4)
	second.update_capture(4)
	assert(second.team == "enemy" and second.energy == 77 and second.queue == 0)
	network.select_depot(second)
	assert(not second.get_node("Territory").visible and not network.owned_selected())
	enemy.global_position = first.global_position+Vector3(0,0,-40)
	worker.global_position = second.global_position+Vector3(9,0,0)
	second.update_capture(8)
	assert(second.team == "player" and second.energy == 77)
	# Deliver only to explicit friendly recipient, leaving neighbouring balance intact.
	worker.global_position = second.global_position+Vector3(6,0,0)
	worker.cargo = 10
	worker.command_return(second)
	worker._return_cargo()
	assert(second.iron == 10 and first.iron == 30 and worker.cargo == 0)
	# Deploy a truck outside all territory on a valid footprint.
	var truck = network.truck_scene.instantiate()
	var start = game.ground.find_buildable_footprint(Vector2i(220,170),Vector2i(8,8))
	truck.position = game.ground.tile_to_world(start+Vector2i(4,4))
	game.get_node("Entities/Units").add_child(truck)
	truck.set_process(false)
	truck.set_selected(true)
	assert(network.deploy_selected_truck())
	var third = network.selected
	third.set_process(false)
	assert(third.energy == 100 and third.iron == 0 and not truck.is_in_group("units"))
	assert(not network.can_place(third.global_position,first))
	# No tick transfers resources.
	first._process(0.1)
	third._process(0.1)
	assert(third.energy == 100 and third.iron == 0)
	print("DEPOT_CHECKS_PASSED")
	quit()
