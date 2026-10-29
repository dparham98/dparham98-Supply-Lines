extends SceneTree
# UI phase B: structured selection panels for units, vehicles, Depots, production, generators and mines.
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
func shown(path: String) -> bool:
	return hud.info.get_node(path).visible
func stat(key: String) -> String:
	var grid = hud.info.get_node("Stats")
	for i in range(1,7):
		if grid.get_node("K%d" % i).visible and grid.get_node("K%d" % i).text == key: return grid.get_node("V%d" % i).text
	return ""
func run() -> void:
	root.size = Vector2i(1280,900)
	await fixture("res://scenes/maps/resource_skirmish.tscn")
	var depot = game.depot
	var info = hud.info
	# Depot: icon, state line, storage split by resource, production only while queued.
	depot.stockpile.set_amount(&"coal",100)
	select(null,depot)
	if not check(info.get_node("Head/Icon").texture != null and "territory" in info.get_node("Head/Text/State").text,"Depot header wrong"): return
	if not check(shown("Storage") and info.get_node("Storage/Head/Label").text == "Storage" and info.get_node("Storage/Head/Value").text == "%s / %s" % [hud.grouped(depot.stockpile.total()),hud.grouped(depot.stockpile.capacity)],"Depot storage header wrong"): return
	var segments = info.get_node("Storage/Track/Segments")
	if not check(segments.get_node("Coal").visible and is_equal_approx(segments.get_node("Coal").size_flags_stretch_ratio,100) and not segments.get_node("Wood").visible and info.get_node("Storage/Legend/Coal/Amount").text == "Coal 100","Storage segments or legend wrong"): return
	if not check(not shown("Production"),"Production shown with an empty queue"): return
	depot.energy = 1000; depot.iron = 1000
	if not check(depot.request_cargo() and depot.request_cargo(),"Cargo production refused"): return
	depot.progress = depot.print_seconds*0.5
	hud._process(0)
	if not check(shown("Production") and info.get_node("Production/Head/Label").text == "Producing · Cargo vehicle" and "1 more queued" in info.get_node("Production/Head/Value").text and is_equal_approx(info.get_node("Production/Bar").value,0.5),"Depot production section wrong"): return
	depot.queue = 0; depot.pending.clear(); depot.progress = 0
	# Infantry: cargo bar with value, plain stats, notes keep the nearest Depot.
	var worker = game.get_node("Entities/Units/Infantry")
	worker.cargo = 4; worker.cargo_kind = &"iron"
	select(worker)
	if not check(hud.bars.get_node("CargoValue").text == "4 / 10 iron" and stat("Range") == "5.0" and stat("Cost") != "" and "Nearest Depot" in info.get_node("Details").text,"Infantry panel wrong"): return
	if not check(not shown("Storage") and info.get_node("Stats").visible,"Infantry shows storage or lacks stats"): return
	worker.cargo = 0
	# Tank: fuel value, stats incl. heavy-target pairs, abilities line, unboxed.
	var tank = spawn("res://scenes/gameplay/tank.tscn",Vector3(14,0,14))
	tank.fuel = 10
	select(tank)
	if not check(hud.bars.get_node("FuelValue").text == "10 / 60" and hud.bars.get_node("FuelLabel").text == "Fuel" and stat("Vs buildings") != "" and stat("Splash") != "","Tank bars or stats wrong"): return
	if not check(shown("Abilities") and "Fires while moving" in info.get_node("Abilities").text and "LOW FUEL" in info.get_node("Details").text,"Tank abilities or fuel note wrong"): return
	for i in range(1,7):
		var value: Label = info.get_node("Stats/V%d" % i)
		if not check(not value.has_theme_stylebox_override("normal"),"Stat values must not be boxed"): return
	# Cargo vehicle: storage titled Cargo, separate tank fuel, route line while routed.
	var truck = spawn("res://scenes/gameplay/cargo_vehicle.tscn",Vector3(-14,0,10))
	truck.carried_coal = 30; truck.carried_energy = 10
	select(truck)
	if not check(shown("Storage") and info.get_node("Storage/Head/Label").text == "Cargo" and info.get_node("Storage/Head/Value").text == "40 / 100" and not hud.bars.get_node("Cargo").visible,"Cargo vehicle storage wrong"): return
	if not check(hud.bars.get_node("FuelLabel").text == "Tank fuel" and hud.bars.get_node("Fuel").visible,"Cargo vehicle tank fuel not separate"): return
	var outpost = load("res://scenes/gameplay/depot.tscn").instantiate()
	outpost.name = "PanelOutpost"; outpost.team = "player"
	outpost.position = depot.global_position+Vector3(60,0,0)
	game.get_node("Entities/Buildings").add_child(outpost); outpost.set_process(false)
	if not check(truck.start_supply_route(depot,outpost,10,0,true),"Route assignment failed"): return
	hud._process(0)
	if not check(shown("Route") and info.get_node("Route/From").text == "Depot" and info.get_node("Route/To").text == "PanelOutpost" and "repeating" in info.get_node("Head/Text/State").text,"Cargo route line wrong"): return
	truck.cancel_supply_route()
	# Generator, mine and production building get their own sections.
	var generator = get_first_node_in_group("energy_generators")
	if generator != null:
		select(null,generator)
		if not check(stat("Output") != "" and stat("Mode") != "","Generator stats missing"): return
	var mine = get_first_node_in_group("mines")
	if mine != null:
		select(null,mine)
		if not check(shown("Production") and info.get_node("Production/Head/Label").text == "Iron reserves","Mine reserves missing"): return
	# Train: round-trip tick on the fuel bar and an amber warning line.
	await fixture("res://scenes/maps/rail_exercise.tscn")
	game.vehicle_fuel_required = true
	var train = game.get_node("Entities/Units/Train")
	train.fuel = 0
	if not check(train.start_supply_route(game.depot,game.get_node("Entities/Buildings/EastDepot"),1,0,false),"Train route failed"): return
	select(train)
	var needed: float = train.estimated_round_trip_fuel()
	if needed > 0:
		var tick: ColorRect = hud.bars.get_node("Fuel/Need")
		if not check(tick.visible and is_equal_approx(tick.anchor_left,clampf(needed/train.fuel_rules.reserve_capacity,0,1)) and "Round trip needs about" in hud.info.get_node("Details").text,"Round-trip tick or note missing"): return
	if not check(hud.info.get_node("Warning").visible and hud.info.get_node("Warning").text == train.fuel_warning,"Train warning line missing"): return
	print("SELECTION_PANELS_TEST_PASSED")
	quit(0)
