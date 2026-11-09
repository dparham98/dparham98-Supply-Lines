extends SceneTree
# Depot Truck production (docs/DEPOT_MODEL.md): 14 seconds of tractor exit and trailer assembly, a blocked
# side that waits, cancel with refund, and the real truck replacing the model on the same spot.
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func trucks() -> Array:
	return get_nodes_in_group("units").filter(func(unit): return unit.is_depot_truck)
func run() -> void:
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	game.set_process(false)
	var network = game.get_node("DepotNetwork")
	var start: Vector2i = game.ground.find_buildable_footprint(Vector2i(220,170),Vector2i(30,30))+Vector2i(10,10)
	var site: Vector3 = game.ground.tile_to_world(start+Vector2i(5,5))
	# A Depot heading east on open ground, so its truck side is clear.
	var depot: Node3D = network.establish(site,3000,3000)
	depot.set_process(false)
	depot.storage_capacity = 20000
	var model: Node3D = depot.get_node("Visuals/Model")
	var cells: Array[Vector2i] = depot.truck_side_cells()
	if not check(cells.size() >= 45,"Truck side should cover about 15 by 3 tiles: %d" % cells.size()): return
	var other_units := trucks().size()
	var energy: int = depot.energy
	var iron: int = depot.iron
	if not check(depot.request_truck() and depot.energy < energy,"Truck order refused"): return
	if not check(absf(depot.current_seconds()-14.17) < 0.05,"A truck should take both clips: %.2f" % depot.current_seconds()): return
	# Blocked: progress waits and the tractor stays home.
	game.ground.set_tile_feature(cells[10],"occupied_by","blocker")
	depot._process(1.0)
	if not check(depot.progress == 0.0 and depot.truck_cells.is_empty() and depot.get_node("Progress").text.begins_with("Exit blocked"),"Blocked side should wait"): return
	game.ground.set_tile_feature(cells[10],"occupied_by",null)
	# Tractor exit, then assembly on the side.
	depot._process(1.0)
	if not check(depot.progress > 0.9 and depot.truck_cells == cells and model.tractor.visible and not model.assembly.visible,"Exit should start and reserve the side"): return
	if not check(not game.ground.can_traverse(cells[10]),"Reserved side should block units"): return
	var parked_at: Vector3 = model.assembly.global_position
	depot._process(5.3)
	var tractor_end: Vector3 = model.tractor.global_position
	var assembly_chassis: Vector3 = model.assembly.get_node("Rig/warehouse_root/warehouse_power_unit").global_position
	if not check(tractor_end.distance_to(assembly_chassis) < 0.05,"Assembly chassis should meet the tractor: %s %s" % [tractor_end,assembly_chassis]): return
	depot._process(1.0)
	if not check(not model.tractor.visible and model.assembly.visible and trucks().size() == other_units,"Assembly should replace the tractor"): return
	var deck: Node3D = model.assembly.get_node("Rig/warehouse_root/warehouse_deck")
	if not check(deck.scale[deck.scale.min_axis_index()] < 0.99,"Trailer should be part-built: %s" % deck.scale): return
	# Cancel plays backwards, refunds and leaves the tractor home.
	var seen_back: float = depot.progress
	if not check(depot.can_cancel() and depot.cancel_current() and depot.cancelling and not depot.can_cancel(),"Cancel should start"): return
	depot._process(0.5)
	if not check(depot.progress < seen_back and depot.queue == 1,"Cancel should run backwards"): return
	for i in range(20): depot._process(0.5)
	if not check(depot.queue == 0 and not depot.cancelling and depot.energy == energy and depot.iron == iron,"Cancel should refund: %d/%d" % [depot.energy,depot.iron]): return
	if not check(depot.truck_cells.is_empty() and game.ground.can_traverse(cells[10]) and model.tractor.visible and not model.assembly.visible,"Cancel should leave the tractor home and the side free"): return
	# Full build: a real truck on the same spot, and no tractor left.
	if not check(depot.request_truck() and depot.request_truck(),"Queue two trucks"): return
	depot._process(0.1)
	depot._process(depot.current_seconds()+0.1)
	if not check(trucks().size() == other_units+1 and depot.queue == 1 and depot.truck_cells.is_empty(),"Truck should be delivered"): return
	var made: Node3D = trucks().filter(func(unit): return unit.global_position.distance_to(parked_at) < 0.1).front()
	if not check(made != null and is_equal_approx(made.get_node("Visuals").rotation.y,depot.get_node("Visuals").rotation.y),"Truck should stand where it was built"): return
	if not check(not model.tractor.visible and not model.assembly.visible,"Depot should have no tractor after delivery"): return
	# The truck is parked on the side, so the next one waits until it leaves, then a tractor appears.
	depot._process(0.5)
	if not check(depot.progress == 0.0 and depot.get_node("Progress").text.begins_with("Exit blocked"),"Next truck should wait for the side"): return
	made.free()
	depot._process(0.5)
	if not check(depot.progress > 0.4 and model.tractor.visible,"A new tractor should appear"): return
	# Other jobs keep the short time.
	depot.cancel_current()
	for i in range(30): depot._process(0.5)
	if not check(depot.queue == 0 and depot.request_cargo() and is_equal_approx(depot.current_seconds(),depot.print_seconds),"Cargo should stay at the short time"): return
	if not check(depot.cancel_current() and depot.queue == 0,"Cargo cancel should be immediate"): return
	print("DEPOT_TRUCK_PRODUCTION_TEST_PASSED"); quit()
