extends "res://tests/crate_containers_test.gd"
# Independent audit regressions: target lifetime, yard boundaries and explicit unpack/refill.
const MAP := "res://scenes/maps/resource_skirmish.tscn"
const TRUCK := "res://scenes/gameplay/cargo_vehicle.tscn"
func field_crate() -> Node3D:
	var cell = CrateYard.free_cell(self,game.depot.global_position+Vector3(-20,0,15))
	return CrateYard.spawn(self,cell,&"iron",25,"player")
func outpost() -> Node3D:
	var node = load("res://scenes/gameplay/depot.tscn").instantiate()
	node.position = game.depot.global_position+Vector3(40,0,0)
	game.get_node("Entities/Buildings").add_child(node)
	node.set_process(false)
	return node
func block_yard(owner_node: Node3D) -> void:
	var ground = game.ground
	var center: Vector2i = ground.get_tile_at_position(owner_node.global_position)
	var radius := CrateYard.beside_radius(owner_node)
	for dz in range(-10,11):
		for dx in range(-10,11):
			var cell := center+Vector2i(dx,dz)
			if ground.can_traverse(cell) and ground.tile_to_world(cell).distance_to(owner_node.global_position) <= radius:
				ground.set_tile_feature(cell,"occupied_by","test_yard_block")
func run() -> void:
	await fixture(MAP)
	var crate = field_crate()
	var point: Vector3 = crate.global_position
	var first = spawn(TRUCK,Vector3(-19,0,15))
	var second = spawn(TRUCK,Vector3(-18,0,15))
	first.command_load(crate)
	second.load_crates(crate,point)
	await process_frame # Flush the real queue_free, not a mock target.
	first._crate_job(3)
	first._crate_job(3)
	if not check(first.order == "idle" and second.crate_units() == 25 and first.crates.is_empty(),"Competing pickup did not finish safely with resources on one truck"): return
	crate = field_crate(); point = crate.global_position
	first.order = "move"
	first.queue_order({kind = "load",target = crate,point = point})
	# A single remaining slot keeps the second truck from taking unrelated crates.
	second.load_crates(crate,point)
	await process_frame
	first.order = "idle"; first._start_next_order()
	first._crate_job(3)
	if not check(first.order == "idle" and second.crate_units() == 50,"Queued freed-crate stop did not use its saved point"): return
	var destination = outpost()
	second.command_unload(destination)
	destination.take_damage(destination.health)
	await process_frame
	second._crate_job(3)
	if not check(second.order == "idle" and second.crate_units() == 50 and second.stockpile.reserved == 50 and second.state.contains("stop lost"),"Destroyed active endpoint did not cancel and retain cargo"): return
	destination = outpost()
	second.order = "move"
	second.queue_order({kind = "unload",target = destination,point = destination.global_position})
	destination.take_damage(destination.health)
	await process_frame
	second.order = "idle"; second._start_next_order()
	if not check(second.order == "idle" and second.crate_units() == 50,"Destroyed queued Depot was reinterpreted as a ground drop"): return
	# A live reference already queued for deletion must also be safe before the frame flush.
	crate = field_crate(); first.command_load(crate)
	second.load_crates(crate,crate.global_position)
	first._crate_job(3)
	if not check(first.order == "idle" and second.crate_units() == 75,"Same-frame pickup duplicated cargo or kept a dead crate stop"): return
	# A remembered pickup endpoint can also disappear after loading, before delivery.
	var pickup = outpost()
	pickup.iron = 25; CrateYard.pack(pickup,&"iron")
	first.trips = "repeat"
	first.command_load(pickup)
	if not check(run_until(first,func(): return first.order == "idle",40) and first.crate_units() == 25,"Repeat fixture failed to load at its Depot"): return
	pickup.take_damage(pickup.health)
	await process_frame
	first.command_unload(game.depot)
	if not check(run_until(first,func(): return first.order == "idle",40) and first.crates.is_empty() and first.order_queue.is_empty(),"Repeat trip returned to a destroyed pickup Depot"): return
	await fixture(MAP)
	game.depot.iron = 100
	for i in range(3): CrateYard.pack(game.depot,&"iron")
	game.depot.stockpile.refill = true
	game.depot.stockpile.set_target(&"iron",3)
	select(null,game.depot)
	hud.unpack_pip(0,true)
	if not check(CrateYard.count_beside(game.depot,&"iron") == 2 and game.depot.stockpile.refill_targets[&"iron"] == 2,"Unpacking one crate decremented the Refill target twice"): return
	# Simulate pickup and require the remaining target to be restored.
	CrateYard.beside(game.depot)[0].queue_free()
	game.depot.iron = 100
	CrateYard.restock(game.depot)
	if not check(CrateYard.count_beside(game.depot,&"iron") == 2 and game.depot.iron == 75,"Refill did not replace the next picked-up crate"): return
	# Both owner types must reject a full yard without withdrawing loose stock.
	for mobile in [false,true]:
		await fixture(MAP)
		var owner_node: Node3D = spawn(TRUCK,Vector3(-16,0,14)) if mobile else game.depot
		owner_node.stockpile.set_amount(&"iron",100)
		block_yard(owner_node)
		var before: int = owner_node.stockpile.amount(&"iron")
		if not check(CrateYard.pack(owner_node,&"iron") == null and CrateYard.pack_empty(owner_node) == null,"Packing escaped a blocked yard radius"): return
		owner_node.stockpile.refill = true; owner_node.stockpile.set_target(&"iron",1)
		for i in range(4): CrateYard.restock(owner_node)
		if not check(owner_node.stockpile.amount(&"iron") == before and get_nodes_in_group("supply_crates").is_empty(),"Refill drained a blocked yard into out-of-range crates"): return
	print("CRATE_LIFECYCLE_TEST_PASSED")
	quit(0)
