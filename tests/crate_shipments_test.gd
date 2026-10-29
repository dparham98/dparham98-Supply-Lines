extends SceneTree
# Phase E crate shipments: reservation, prepare and keep stocked, Load/Unload, trips, HUD tiles.
var game: Node3D
var hud: CanvasLayer
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func fixture(path: String) -> void:
	if is_instance_valid(game): game.free()
	game = load(path).instantiate()
	root.add_child(game); await process_frame
	game.set_process(false)
	hud = game.get_node("Interface"); hud.set_process(false)
	for group in ["units","depots"]:
		for node in get_nodes_in_group(group): node.set_process(false)
func select(unit: Node3D, building: Node3D = null) -> void:
	game.selected_building = building
	for node in get_nodes_in_group("units"): node.set_selected(node == unit)
	hud._process(0)
func spawn(path: String, offset: Vector3) -> Node3D:
	var unit = load(path).instantiate()
	unit.position = game.depot.global_position+offset
	game.get_node("Entities/Units").add_child(unit)
	unit.set_process(false)
	return unit
func run_until(unit: Node3D, condition: Callable, seconds: float) -> bool:
	for i in range(ceili(seconds*60)):
		unit._process(1.0/60)
		if condition.call(): return true
	return false
func run() -> void:
	root.size = Vector2i(1280,900)
	await fixture("res://scenes/maps/resource_skirmish.tscn")
	var depot = game.depot
	var stock: ResourceStockpile = depot.stockpile
	# Reservation: crated units count toward storage but can't be spent, withdrawn or set away.
	depot.iron = 100
	if not check(stock.pack(&"iron") and stock.pack(&"iron") and stock.crated(&"iron") == 50 and depot.iron == 50 and stock.amount(&"iron") == 100,"Packing iron wrong"): return
	if not check(stock.withdraw(&"iron",80) == 50 and stock.amount(&"iron") == 50 and stock.crate_count(&"iron") == 2,"Withdraw reached into crates"): return
	if not check(not stock.spend({&"iron":1}) and depot.iron == 0,"Spend reached into crates"): return
	depot.iron = 0
	if not check(stock.amount(&"iron") == 50,"Setting spendable iron destroyed crates"): return
	if not check(not stock.pack(&"iron"),"Packed a crate without 25 loose units"): return
	# Generators and refuelling ignore crated fuel.
	depot.wood = 0; depot.coal = 0
	depot.wood = 25; stock.pack(&"wood")
	var generator = load("res://scenes/gameplay/energy_generator.tscn").instantiate()
	generator.assigned_depot = depot
	if not check(generator.choose_fuel() == &"","Generator chose crated wood"): return
	generator.free()
	depot.coal = 25; stock.pack(&"coal")
	var tank = spawn("res://scenes/gameplay/tank.tscn",Vector3(14,0,14))
	if not check(not tank.can_refuel_from(depot),"Refuelling from crated coal"): return
	stock.unpack(&"wood"); stock.unpack(&"coal")
	if not check(stock.available(&"wood") == 25 and stock.available(&"coal") == 25,"Unpack did not return loose units"): return
	# Prepare shipment panel on a selected Depot.
	depot.iron = 200
	select(null,depot)
	var panel = hud.shipment
	if not check(panel.visible and panel.get_node("Rows/Iron/Count").text == "Iron 2","Shipment panel missing or wrong"): return
	panel.get_node("Rows/Iron/Plus").pressed.emit(); hud._process(0)
	if not check(stock.crate_count(&"iron") == 3 and panel.get_node("Rows/Iron/Count").text == "Iron 3","Plus did not pack a crate"): return
	panel.get_node("Rows/Iron/Minus").pressed.emit(); hud._process(0)
	if not check(stock.crate_count(&"iron") == 2,"Minus did not unpack a crate"): return
	if not check(hud.info.get_node("Storage/Track/Segments/IronCrated").visible and "2▢" in hud.info.get_node("Storage/Legend/Iron/Amount").text,"Crated storage not shown lighter"): return
	# Keep stocked repacks up to the recorded counts.
	panel.get_node("KeepStocked").toggled.emit(true)
	if not check(stock.keep_stocked and stock.stock_targets[&"iron"] == 2,"Keep stocked did not record targets"): return
	stock.take_crate(); stock.take_crate()
	depot._process(0.01)
	if not check(stock.crate_count(&"iron") == 2,"Keep stocked did not repack"): return
	panel.get_node("KeepStocked").toggled.emit(false)
	if not check(is_equal_approx(hud.get_node("Bottom").size.y,260),"Shipment panel broke the fixed HUD height"): return
	# Load at the Depot, Shift-Unload at an outpost: whole crates, oldest first.
	stock.unpack(&"iron"); stock.unpack(&"iron")
	depot.iron = 100; depot.coal = 50
	for kind in [&"iron",&"iron",&"iron",&"iron",&"coal",&"coal"]: stock.pack(kind)
	var outpost = load("res://scenes/gameplay/depot.tscn").instantiate()
	outpost.name = "CrateOutpost"; outpost.team = "player"
	outpost.position = depot.global_position+Vector3(40,0,0)
	game.get_node("Entities/Buildings").add_child(outpost); outpost.set_process(false)
	var outpost_iron: int = outpost.stockpile.amount(&"iron")
	var truck = spawn("res://scenes/gameplay/cargo_vehicle.tscn",Vector3(-12,0,10))
	game.give_order(truck,{kind = "load", target = depot},false)
	game.give_order(truck,{kind = "unload", target = outpost},true)
	if not check(truck.order == "load" and truck.order_queue.size() == 1 and truck.shipment_pair() == [depot,outpost],"Load/Unload not queued"): return
	if not check(run_until(truck,func(): return truck.order == "load" and truck.stockpile.crate_count() > 0 or truck.order == "unload",20),"Truck never loaded"): return
	if not check(truck.stockpile.crate_count() == 4 and truck.stockpile.crate_count(&"iron") == 4 and stock.crate_count() == 2,"Load did not take the 4 oldest crates"): return
	if not check(run_until(truck,func(): return truck.order == "idle" and truck.order_queue.is_empty(),40),"Unload never finished"): return
	if not check(truck.stockpile.total() == 0 and outpost.stockpile.amount(&"iron") == outpost_iron+100 and outpost.stockpile.crate_count() == 0 and outpost.iron == outpost_iron+100,"Unload did not unpack 100 iron"): return
	# Trips: all available returns for the remaining crates, then stops.
	truck.trips = "all"
	game.give_order(truck,{kind = "load", target = depot},false)
	game.give_order(truck,{kind = "unload", target = outpost},true)
	if not check(run_until(truck,func(): return truck.order == "idle" and truck.order_queue.is_empty() and stock.crate_count() == 0 and truck.stockpile.total() == 0,80),"All-available trips did not empty the pickup"): return
	if not check(outpost.coal >= 50,"Coal crates not delivered"): return
	# Trips: repeat waits at the pickup for new crates.
	truck.trips = "repeat"
	game.give_order(truck,{kind = "load", target = depot},false)
	game.give_order(truck,{kind = "unload", target = outpost},true)
	if not check(run_until(truck,func(): return truck.state.begins_with("Waiting for crates"),40),"Repeat did not wait for crates"): return
	depot.wood = 25; stock.pack(&"wood")
	var outpost_wood: int = outpost.wood
	if not check(run_until(truck,func(): return outpost.wood == outpost_wood+25,60),"Repeat did not deliver a newly packed crate"): return
	hud.stop_units()
	truck.set_selected(true); hud.stop_units(); truck.set_selected(false)
	truck.trips = "once"
	# A full destination keeps whole crates that don't fit.
	depot.iron = 50; stock.pack(&"iron"); stock.pack(&"iron")
	game.give_order(truck,{kind = "load", target = depot},false)
	run_until(truck,func(): return truck.stockpile.crate_count() == 2,30)
	outpost.stockpile.set_amount(&"energy",outpost.stockpile.amount(&"energy")+outpost.stockpile.space()-30)
	game.give_order(truck,{kind = "unload", target = outpost},false)
	if not check(run_until(truck,func(): return truck.order == "idle",40) and truck.stockpile.crate_count() == 1 and "retained" in truck.state,"Partial unload did not keep the crate that doesn't fit"): return
	outpost.stockpile.set_amount(&"energy",0)
	# Right-click on a Depot: unload while carrying crates, otherwise load.
	truck.command_return(outpost)
	if not check(truck.order == "unload","Right-click with crates did not unload"): return
	run_until(truck,func(): return truck.order == "idle",30)
	truck.command_return(depot)
	if not check(truck.order == "load","Right-click when empty did not load"): return
	truck.cancel_supply_route()
	# HUD: cargo tiles on their slots, Trips cycles, a distant-stop list while Load is armed.
	select(truck)
	for id in ["Move","Stop","DeployCargo","ToggleRefuel","Load","Unload","Trips"]:
		if not check(hud.card.get_node(id).visible,"Cargo tile %s missing" % id): return
	if not check(not hud.has_node("Bottom/Body/Row/Commands/Supply") and not hud.has_node("Bottom/Body/Header/Pages"),"Route panel or tabs still present"): return
	if not check(hud.card.get_node("Load").position == Vector2(0,50) and hud.card.get_node("Trips").position == Vector2(100,50),"Cargo tiles not on their slots"): return
	hud.card.get_node("Trips").pressed.emit(); hud._process(0)
	if not check(truck.trips == "all" and hud.label_of(hud.card.get_node("Trips")) == "Trips: all available","Trips tile did not cycle"): return
	truck.trips = "once"
	hud.card.get_node("Load").pressed.emit(); hud._process(0)
	var target: OptionButton = hud.shipment_target
	if not check(game.pending_unit_command == "load" and target.visible and target.item_count == 1+hud.shipment_stops.size() and hud.shipment_stops.has(outpost),"Distant stop list missing"): return
	target.item_selected.emit(hud.shipment_stops.find(outpost)+1)
	if not check(truck.order == "load" and truck.job_target == outpost and game.pending_unit_command.is_empty(),"Distant stop did not order Load"): return
	truck.cancel_supply_route()
	if not check(is_equal_approx(hud.get_node("Bottom").size.y,260),"Cargo HUD broke the fixed height"): return
	# Trains: Depots only, and the round-trip warning covers a Load/Unload pair.
	await fixture("res://scenes/maps/rail_exercise.tscn")
	game.vehicle_fuel_required = true
	var train = game.get_node("Entities/Units/Train")
	var east = game.get_node("Entities/Buildings/EastDepot")
	train.fuel = 0
	var deployed = spawn("res://scenes/gameplay/cargo_vehicle.tscn",Vector3(-10,0,8))
	deployed.deployed = true
	if not check(not train.shipment_endpoint(deployed) and train.shipment_endpoint(east),"Train accepted a deployed truck as a stop"): return
	game.give_order(train,{kind = "load", target = game.depot},false)
	game.give_order(train,{kind = "unload", target = east},true)
	train._process(1.0/60)
	if not check(train.trip_endpoints() == [game.depot,east] and not train.fuel_warning.is_empty(),"Train round-trip warning missing for a crate trip"): return
	print("CRATE_SHIPMENTS_TEST_PASSED")
	quit(0)
