extends SceneTree
# Crate containers (docs/CRATE_CONTAINERS.md): crates are map objects beside a Depot or anywhere on
# open ground. Packing, the HUD panel, keep stocked, worker delivery and gathering, Load on a crate,
# Unload onto a Depot or the ground, trips, overlay and Trains.
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
func crates_of(kind: StringName) -> int:
	return CrateYard.count_beside(game.depot,kind)
## Clears crates now (queue_free waits for the frame).
func clear_crates() -> void:
	for crate in get_nodes_in_group("supply_crates"): crate.free()
func run() -> void:
	root.size = Vector2i(1280,900)
	await fixture("res://scenes/maps/resource_skirmish.tscn")
	var depot = game.depot
	var stock: ResourceStockpile = depot.stockpile
	var ground = game.ground
	# Packing takes 25 loose units out of storage and sets a crate down beside the Depot.
	depot.iron = 100
	var crate = CrateYard.pack(depot,&"iron")
	if not check(crate != null and crate.amount == 25 and crate.resource_kind == &"iron" and depot.iron == 75 and stock.total() == stock.amount(&"energy")+75+stock.amount(&"wood")+stock.amount(&"coal"),"Packing did not move 25 iron out of storage"): return
	var cell = ground.get_tile_at_position(crate.global_position)
	if not check(not depot.cells.has(cell) and crate.global_position.distance_to(depot.global_position) <= CrateYard.BESIDE_RADIUS and ground.can_traverse(cell),"Crate not on open land beside the Depot"): return
	if not check(crate.is_in_group("resources") and crate.is_in_group("supply_crates"),"Crate groups wrong"): return
	depot.wood = 10
	if not check(CrateYard.pack(depot,&"wood") == null and depot.wood == 10,"Packed a crate without 25 loose units"): return
	var empty = CrateYard.pack_empty(depot)
	if not check(empty != null and empty.amount == 0 and not empty.is_in_group("resources") and ground.get_tile_at_position(empty.global_position) != cell,"Empty crate missing or stacked on another crate"): return
	# Crates are not Depot storage: generators and refuelling can't use them.
	depot.wood = 0; depot.coal = 0
	depot.wood = 25; CrateYard.pack(depot,&"wood")
	var generator = load("res://scenes/gameplay/energy_generator.tscn").instantiate()
	generator.assigned_depot = depot
	if not check(generator.choose_fuel() == &"","Generator used wood in a crate"): return
	generator.free()
	depot.coal = 25; CrateYard.pack(depot,&"coal")
	var tank = spawn("res://scenes/gameplay/tank.tscn",Vector3(14,0,14))
	if not check(not tank.can_refuel_from(depot),"Refuelled from coal in a crate"): return
	if not check(CrateYard.unpack(depot,&"wood") == 25 and depot.wood == 25 and crates_of(&"wood") == 0,"Unpack did not return the crate to storage"): return
	CrateYard.unpack(depot,&"coal")
	# The Depot panel counts crates beside it; + packs onto the map, − unpacks, + Empty adds one.
	depot.iron = 200
	select(null,depot)
	var panel = hud.shipment
	if not check(panel.visible and panel.get_node("Rows/Iron/Count").text == "Iron 1" and panel.get_node("Head/Label").text == "Crates beside" and "1 empty" in panel.get_node("Head/Value").text,"Crate panel missing or wrong"): return
	panel.get_node("Rows/Iron/Plus").pressed.emit(); hud._process(0)
	if not check(crates_of(&"iron") == 2 and depot.iron == 175 and panel.get_node("Rows/Iron/Count").text == "Iron 2","Plus did not pack a crate onto the map"): return
	panel.get_node("Rows/Iron/Minus").pressed.emit(); hud._process(0)
	for node in get_nodes_in_group("supply_crates"):
		if node.is_queued_for_deletion(): node.free()
	if not check(crates_of(&"iron") == 1 and depot.iron == 200,"Minus did not unpack a crate into storage"): return
	panel.get_node("Foot/EmptyCrate").pressed.emit(); hud._process(0)
	if not check("2 empty" in panel.get_node("Head/Value").text,"+ Empty did not add an empty crate"): return
	var segments = hud.info.get_node("Storage/Track/Segments")
	if not check(not segments.has_node("IronCrated") and not segments.get_node("Crates").visible and hud.info.get_node("Storage/Legend/Iron/Amount").text == "Iron 200","Depot storage still mixes in crates"): return
	# Keep stocked repacks crates beside the Depot as they're taken.
	panel.get_node("Foot/KeepStocked").toggled.emit(true)
	if not check(stock.keep_stocked and stock.stock_targets[&"iron"] == 1,"Keep stocked did not record targets"): return
	for node in CrateYard.beside(depot):
		if node.resource_kind == &"iron": node.free()
	depot._process(0.01)
	if not check(crates_of(&"iron") == 1 and depot.iron == 175,"Keep stocked did not repack"): return
	panel.get_node("Foot/KeepStocked").toggled.emit(false)
	if not check(is_equal_approx(hud.get_node("Bottom").size.y,260),"Crate panel broke the fixed HUD height"): return
	clear_crates()
	# Workers deliver into a crate and, when it fills, into the next crate beside it.
	var field := ground.get_tile_at_position(depot.global_position+Vector3(-16,0,14)) as Vector2i
	var bin = CrateYard.spawn(self,field,&"",0,"player")
	var bin2 = CrateYard.spawn(self,field+Vector2i(1,0),&"",0,"player")
	var worker = spawn("res://scenes/gameplay/infantry.tscn",Vector3(-12,0,12))
	worker.cargo_kind = &"wood"; worker.cargo = 10
	worker.command_return(bin)
	if not check(run_until(worker,func(): return worker.cargo == 0,20) and bin.amount == 10 and bin.resource_kind == &"wood","Worker did not deliver into the crate"): return
	bin.receive(&"wood",10)
	worker.cargo_kind = &"wood"; worker.cargo = 10
	worker.command_return(bin)
	if not check(run_until(worker,func(): return worker.cargo == 0,20) and bin.amount == 25 and bin2.amount == 5,"Overflow did not go to the next crate"): return
	worker.cargo_kind = &"iron"; worker.cargo = 5
	worker.command_return(bin)
	run_until(worker,func(): return worker.state.begins_with("Crate full"),10)
	if not check(worker.cargo == 5 and bin.amount == 25 and bin2.resource_kind == &"wood","Crate accepted a second resource"): return
	worker.cargo = 0
	# Workers gather from a crate like a pile; the emptied crate stays.
	worker.command_gather(bin2)
	if not check(run_until(worker,func(): return bin2.amount == 0,20) and is_instance_valid(bin2) and bin2.material_kind.is_empty(),"Gathering did not empty the crate"): return
	worker._stop_route(); worker.order = "idle"; worker.source = null; worker.cargo = 0
	# Load on a crate takes it and the filled crates next to it, up to 4 slots.
	clear_crates()
	for i in range(5): CrateYard.spawn(self,field+Vector2i(i,0),&"iron",25,"player")
	CrateYard.spawn(self,field+Vector2i(0,1),&"",0,"player")
	var truck = spawn("res://scenes/gameplay/cargo_vehicle.tscn",Vector3(-12,0,8))
	var first = CrateYard.crates_near(self,ground.tile_to_world(field),0.5)[0]
	game.give_order(truck,{kind = "load", target = first, point = first.global_position},false)
	if not check(truck.order == "load" and truck.job_target == first,"Load on a crate not ordered"): return
	if not check(run_until(truck,func(): return truck.order == "idle",30) and truck.crates.size() == 4 and truck.crate_units(&"iron") == 100 and truck.stockpile.reserved == 100 and truck.stockpile.space() == 0,"Load did not take 4 crates"): return
	for node in get_nodes_in_group("supply_crates"):
		if node.is_queued_for_deletion(): node.free()
	if not check(get_nodes_in_group("supply_crates").size() == 2,"Loaded crates still on the map, or the empty one was taken"): return
	# Unload on open ground sets the crates down on free tiles around the point.
	var drop: Vector3 = ground.tile_to_world(CrateYard.free_cell(self,depot.global_position+Vector3(-26,0,2)))
	if not check(not truck.stop_valid("unload",null,depot.global_position),"Unload accepted a point inside the Depot"): return
	game.give_order(truck,{kind = "unload", point = drop},false)
	if not check(run_until(truck,func(): return truck.order == "idle",40) and truck.crates.is_empty() and truck.stockpile.reserved == 0,"Ground unload did not empty the truck"): return
	var dropped := CrateYard.crates_near(self,drop,4.0)
	if not check(dropped.size() == 4,"Crates not set down around the point"): return
	var used := {}
	for node in dropped:
		var c = ground.get_tile_at_position(node.global_position)
		if not check(not used.has(c),"Two crates on one tile"): return
		used[c] = true
	# Load beside a Depot, Shift-Unload into an outpost: unpacked into its storage.
	clear_crates()
	var outpost = load("res://scenes/gameplay/depot.tscn").instantiate()
	outpost.name = "CrateOutpost"; outpost.team = "player"
	outpost.position = depot.global_position+Vector3(40,0,0)
	game.get_node("Entities/Buildings").add_child(outpost); outpost.set_process(false)
	var outpost_iron: int = outpost.iron
	depot.iron = 100; depot.coal = 50
	for kind in [&"iron",&"iron",&"iron",&"iron",&"coal",&"coal"]: CrateYard.pack(depot,kind)
	game.give_order(truck,{kind = "load", target = depot, point = depot.global_position},false)
	game.give_order(truck,{kind = "unload", target = outpost, point = outpost.global_position},true)
	if not check(truck.shipment_pair() == [depot,outpost] and truck.shipment_stops().size() == 2,"Load/Unload pair not queued"): return
	if not check(run_until(truck,func(): return truck.order == "unload",30) and truck.crates.size() == 4,"Truck did not load beside the Depot"): return
	if not check(run_until(truck,func(): return truck.order == "idle" and truck.order_queue.is_empty(),40) and outpost.iron+outpost.coal >= outpost_iron+100,"Unload did not unpack into the outpost"): return
	# Trips: all available returns for the rest, then stops.
	truck.trips = "all"
	game.give_order(truck,{kind = "load", target = depot, point = depot.global_position},false)
	game.give_order(truck,{kind = "unload", target = outpost, point = outpost.global_position},true)
	if not check(run_until(truck,func(): return truck.order == "idle" and truck.order_queue.is_empty() and CrateYard.beside(depot).is_empty() and truck.crates.is_empty(),80),"All-available trips did not empty the pickup"): return
	# Trips: repeat waits at the pickup for new crates.
	truck.trips = "repeat"
	game.give_order(truck,{kind = "load", target = depot, point = depot.global_position},false)
	game.give_order(truck,{kind = "unload", target = outpost, point = outpost.global_position},true)
	if not check(run_until(truck,func(): return truck.state.begins_with("Waiting for crates"),40),"Repeat did not wait for crates"): return
	depot.wood = 25; CrateYard.pack(depot,&"wood")
	var outpost_wood: int = outpost.wood
	if not check(run_until(truck,func(): return outpost.wood == outpost_wood+25,60),"Repeat did not deliver a newly packed crate"): return
	truck.set_selected(true); hud.stop_units(); truck.set_selected(false)
	truck.trips = "once"
	# A full destination keeps what doesn't fit, partly unpacked.
	depot.iron = 50; CrateYard.pack(depot,&"iron"); CrateYard.pack(depot,&"iron")
	game.give_order(truck,{kind = "load", target = depot, point = depot.global_position},false)
	run_until(truck,func(): return truck.crates.size() == 2,30)
	outpost.stockpile.set_amount(&"energy",outpost.stockpile.amount(&"energy")+outpost.stockpile.space()-30)
	var aboard: int = truck.crate_units()
	game.give_order(truck,{kind = "unload", target = outpost, point = outpost.global_position},false)
	if not check(run_until(truck,func(): return truck.order == "idle",40) and truck.crates.size() == 1 and truck.crate_units() > 0 and truck.crate_units() <= aboard-30 and "retained" in truck.state,"Partial unload did not keep the rest aboard"): return
	outpost.stockpile.set_amount(&"energy",0)
	# Right-click: a crate loads; a Depot unloads while carrying crates, otherwise loads.
	truck.command_return(outpost)
	if not check(truck.order == "unload","Right-click with crates did not unload"): return
	run_until(truck,func(): return truck.order == "idle",30)
	var lone = CrateYard.spawn(self,field,&"coal",25,"player")
	truck.command_return(lone)
	if not check(truck.order == "load" and truck.job_target == lone,"Right-click on a crate did not load"): return
	run_until(truck,func(): return truck.order == "idle",30)
	# HUD: crates aboard, a separate Crates segment, and the overlay's crate pips.
	select(truck)
	if not check(hud.info.get_node("Storage/Head/Label").text == "Cargo · 1/4 crates" and segments.get_node("Crates").visible and "Coal 25" in hud.info.get_node("Details").text,"Crates aboard not shown"): return
	var overlay = hud.get_node("MapOverlay")
	var pips: Array = overlay.status_for(truck).pips
	if not check(pips.size() == 4 and pips[0] == overlay.RESOURCE_COLORS[&"coal"] and pips[1].a == 0,"Truck crate pips wrong"): return
	var marker = CrateYard.spawn(self,field+Vector2i(0,3),&"wood",10,"player")
	var status: Dictionary = overlay.status_for(marker)
	if not check(is_equal_approx(status.crate.ratio,0.4) and overlay.hud_name(marker) == "Wood crate","Crate overlay wrong"): return
	if not check(is_equal_approx(hud.get_node("Bottom").size.y,260),"Cargo HUD broke the fixed height"): return
	for id in ["Move","Stop","DeployCargo","ToggleRefuel","Load","Unload","Trips"]:
		if not check(hud.card.get_node(id).visible,"Cargo tile %s missing" % id): return
	hud.card.get_node("Load").pressed.emit(); hud._process(0)
	if not check(game.pending_unit_command == "load" and hud.shipment_target.visible and hud.shipment_stops.has(outpost),"Distant stop list missing"): return
	hud.shipment_target.item_selected.emit(hud.shipment_stops.find(outpost)+1)
	if not check(truck.order == "load" and truck.job_target == outpost,"Distant stop did not order Load"): return
	truck.set_selected(true); hud.stop_units(); truck.set_selected(false)
	# Trains: Depots only, and the round-trip warning covers a Load/Unload pair.
	await fixture("res://scenes/maps/rail_exercise.tscn")
	game.vehicle_fuel_required = true
	var train = game.get_node("Entities/Units/Train")
	var east = game.get_node("Entities/Buildings/EastDepot")
	train.fuel = 0
	var deployed = spawn("res://scenes/gameplay/cargo_vehicle.tscn",Vector3(-10,0,8))
	deployed.deployed = true
	if not check(not train.shipment_endpoint(deployed) and train.shipment_endpoint(east),"Train accepted a deployed truck as a stop"): return
	var stray = CrateYard.spawn(self,game.ground.get_tile_at_position(game.depot.global_position+Vector3(-14,0,-14)),&"iron",25,"player")
	if not check(not train.stop_valid("load",stray,stray.global_position) and not train.stop_valid("unload",null,stray.global_position),"Train accepted a crate or ground stop"): return
	game.give_order(train,{kind = "load", target = game.depot, point = game.depot.global_position},false)
	game.give_order(train,{kind = "unload", target = east, point = east.global_position},true)
	train._process(1.0/60)
	if not check(train.trip_endpoints() == [game.depot,east] and not train.fuel_warning.is_empty(),"Train round-trip warning missing for a crate trip"): return
	print("CRATE_CONTAINERS_TEST_PASSED")
	quit(0)
