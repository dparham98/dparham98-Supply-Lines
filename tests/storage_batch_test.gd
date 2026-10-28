extends SceneTree
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func run() -> void:
	var a := ResourceStockpile.new(10)
	var b := ResourceStockpile.new(5)
	if not check(a.deposit(&"coal",8) == 8 and a.deposit(&"wood",8) == 2 and a.total() == 10,"Combined capacity failed"): return
	if not check(a.deposit(&"energy",1) == 0 and a.deposit(&"bad",1) == 0 and a.withdraw(&"coal",-2) == 0,"Invalid/overflow transfer accepted"): return
	if not check(not a.spend({&"coal":9,&"wood":1}) and a.amount(&"wood") == 2 and not a.spend({&"coal":-1}),"Failed atomic spend changed stock"): return
	if not check(ResourceStockpile.transfer(a,b,&"coal",8) == 5 and a.amount(&"coal") == 3 and b.total() == 5,"Partial transfer failed conservation"): return
	if not check(not b.resize(4) and b.capacity == 5 and b.total() == 5,"Capacity shrink destroyed stock"): return
	b.capacity = 1
	if not check(b.capacity == 5 and ResourceStockpile.transfer(b,b,&"coal",3) == 0,"Unsafe resize/self transfer accepted"): return
	var game = load("res://scenes/maps/storage_exercise.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	for group in ["units","depots"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	var source = game.depot
	var destination = game.get_node("Entities/Buildings/EastDepot")
	var train = game.get_node("Entities/Units/Train")
	if not check(source.coal == 100 and source.storage_capacity == 2000 and destination.stockpile.total() == 590 and destination.storage_capacity == 600,"Authored stock/capacity wrong"): return
	if not check(train.fuel == 0 and train.fuel_rules.reserve_capacity == 90,"Train fuel reserve missing"): return
	if not check(train.start_supply_route(source,destination,0,0,false,0,20),"Coal rail route rejected"): return
	for i in range(1200): train._process(1.0/60)
	if not check(source.coal == 80 and destination.coal == 10 and train.carried_coal == 10 and train.route_active and train.stage == "unloading","Full destination lost or overflowed coal"): return
	if not check(train.fuel == 0 and destination.stockpile.total() == 600,"Cargo coal leaked into fuel or overflowed capacity"): return
	destination.stockpile.withdraw(&"energy",10)
	for i in range(180): train._process(1.0/60)
	if not check(not train.route_active and destination.coal == 20 and train.carried_coal == 0 and source.coal+destination.coal == 100,"Delivery did not finish after freeing space"): return
	var worker = game.get_node("Entities/Units/Infantry")
	worker._stop_route()
	worker.global_position = destination.global_position+Vector3(0,0,6)
	worker.cargo_kind = &"coal"; worker.cargo = 10
	worker.command_return(destination)
	worker._return_cargo()
	if not check(worker.cargo == 10 and worker.order == "return","Infantry discarded cargo at full Depot"): return
	destination.stockpile.withdraw(&"energy",4)
	worker._return_cargo()
	if not check(worker.cargo == 6 and destination.coal == 24 and destination.stockpile.total() == 600,"Infantry partial deposit wrong"): return
	destination.stockpile.withdraw(&"energy",6)
	worker._return_cargo()
	if not check(worker.cargo == 0 and destination.coal == 30 and worker.order == "idle","Infantry remainder did not deliver"): return
	var truck = game.get_node("Entities/Units/CargoTruck")
	truck.carried_coal = 100
	truck.fuel = 7
	if not check(truck.stockpile.total() == 100 and truck.fuel == 7 and source.coal == 80,"Fuel reserve shares cargo capacity or steals source coal"): return
	truck.fuel = 1000
	if not check(truck.fuel == 30 and truck.carried_coal == 100,"Fuel capacity or cargo isolation failed"): return
	truck.cancel_supply_route()
	if not check(truck.carried_coal == 100,"Cancel discarded stored coal"): return
	worker.fuel = 20
	if not check(worker.fuel == 0 and worker.fuel_rules == null,"Infantry gained vehicle fuel"): return
	# Fueled generation respects full-cycle capacity; blocked time is never banked.
	var generator = load("res://scenes/gameplay/energy_generator.tscn").instantiate()
	var start = game.ground.find_buildable_footprint(Vector2i(430,415),Vector2i(3,3))
	generator.position = game.ground.tile_to_world(start+Vector2i.ONE)
	generator.assigned_depot = destination
	game.add_child(generator)
	generator.set_process(false)
	destination.stockpile.withdraw(&"energy",1); destination.stockpile.deposit(&"wood",1)
	generator._process(100)
	if not check(destination.stockpile.total() == 600 and generator.cycle_elapsed == 0 and destination.wood == 1,"Full Depot generator overflowed or consumed fuel"): return
	destination.stockpile.withdraw(&"energy",2)
	generator._process(1)
	if not check(destination.stockpile.total() == 598 and generator.cycle_elapsed == 0 and destination.wood == 1,"Generator started without room for full output"): return
	destination.stockpile.withdraw(&"energy",8)
	generator._process(2)
	if not check(destination.stockpile.total() == 599 and destination.wood == 0,"Generator did not consume one wood for bounded output"): return
	print("STORAGE_BATCH_CHECKS_PASSED")
	quit()
