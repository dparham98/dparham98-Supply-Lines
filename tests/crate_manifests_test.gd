extends SceneTree
# Crate manifests (docs/CRATE_MANIFESTS.md): what a vehicle loads, crates made as they are loaded,
# repeat trips, shortages, the Load page and the Depot Make crates tile.
const TRUCK := "res://scenes/gameplay/cargo_vehicle.tscn"
var game: Node3D
var hud: CanvasLayer
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func select(unit: Node3D, building: Node3D = null) -> void:
	game.selected_building = building
	for node in get_nodes_in_group("units"): node.set_selected(node == unit)
	hud._process(0)
func spawn(offset: Vector3) -> Node3D:
	var unit = load(TRUCK).instantiate()
	unit.position = game.depot.global_position+offset
	game.get_node("Entities/Units").add_child(unit)
	unit.set_process(false)
	return unit
func run_until(unit: Node3D, condition: Callable, seconds: float) -> bool:
	for i in range(ceili(seconds*60)):
		unit._process(1.0/60)
		if condition.call(): return true
	return false
func aboard(unit: Node3D, kind: StringName) -> int:
	var count := 0
	for crate in unit.crates:
		if crate.kind == kind: count += 1
	return count
func clear_crates() -> void:
	for crate in get_nodes_in_group("supply_crates"): crate.free()
func stock(energy: int, iron: int, wood: int, coal: int) -> void:
	var depot = game.depot
	for kind in ResourceStockpile.KINDS: depot.stockpile.set_amount(kind,0)
	depot.energy = energy; depot.iron = iron; depot.wood = wood; depot.coal = coal
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game); await process_frame
	game.set_process(false)
	hud = game.get_node("Interface"); hud.set_process(false)
	for group in ["units","depots"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	var depot = game.depot
	# A manifest is a plan: it holds no more than the vehicle carries and takes no stock.
	var truck = spawn(Vector3(-12,0,12))
	stock(0,100,100,100)
	if not check(truck.manifest_add(&"iron") and truck.manifest_add(&"iron") and truck.manifest_add(&"wood") and truck.manifest_add(&"coal"),"Manifest refused free slots"): return
	if not check(not truck.manifest_add(&"iron") and not truck.manifest_fill(&"iron") and truck.manifest_total() == 4,"Manifest went past the vehicle capacity"): return
	if not check(truck.manifest_text() == "2 iron · 1 wood · 1 coal","Manifest text wrong"): return
	if not check(depot.iron == 100 and get_nodes_in_group("supply_crates").is_empty(),"Setting a manifest took stock"): return
	# Loading makes the crates from stock; nothing waits on the map.
	truck.command_load(depot)
	if not check(run_until(truck,func(): return truck.order == "idle",40),"Truck did not finish loading"): return
	if not check(aboard(truck,&"iron") == 2 and aboard(truck,&"wood") == 1 and aboard(truck,&"coal") == 1,"Manifest not loaded"): return
	if not check(depot.iron == 50 and depot.wood == 75 and depot.coal == 75 and depot.energy == 0,"Wrong stock taken for the manifest"): return
	if not check(get_nodes_in_group("supply_crates").is_empty(),"Loading left crates on the map"): return
	# Crates already aboard count: a partly unloaded crate is topped up around, not doubled.
	truck.crates.clear()
	truck.crates.append({kind = &"iron", amount = 10})
	truck._sync_reserved()
	truck.manifest = {&"iron": 2, &"wood": 2}
	stock(0,100,100,0)
	if not check(truck.load_crates(depot,depot.global_position) == 3 and truck.crates.size() == 4 and depot.iron == 75 and depot.wood == 50,"Top-up loaded the wrong crates"): return
	# Crates set down beside the stop go first.
	truck.crates.clear(); truck._sync_reserved()
	truck.manifest = {&"iron": 2}
	stock(0,25,0,0)
	var beside = CrateYard.pack(depot,&"iron")
	stock(0,25,0,0)
	if not check(truck.load_crates(depot,depot.global_position) == 2 and depot.iron == 0 and beside.is_queued_for_deletion(),"Crates beside the stop were not used first"): return
	beside.free()
	# A shortage leaves the slot empty. Only full crates are made and the mix does not change.
	truck.crates.clear(); truck._sync_reserved()
	truck.manifest = {&"iron": 2, &"coal": 2}
	stock(0,60,40,20)
	if not check(truck.load_crates(depot,depot.global_position) == 2 and aboard(truck,&"iron") == 2 and aboard(truck,&"coal") == 0 and aboard(truck,&"wood") == 0,"Shortage changed the mix"): return
	if not check(depot.iron == 10 and depot.wood == 40 and depot.coal == 20,"Shortage took stock it should not"): return
	# With no manifest a Depot only gives up crates set down beside it, never its stock.
	truck.crates.clear(); truck._sync_reserved()
	truck.manifest.clear()
	stock(0,100,0,0)
	if not check(truck.load_crates(depot,depot.global_position) == 0 and depot.iron == 100 and truck.crates.is_empty(),"No manifest still took stock"): return
	# A Train-sized mix.
	var long_haul = spawn(Vector3(-14,0,16))
	long_haul.stockpile.resize(300)
	long_haul.manifest = {&"iron": 6, &"wood": 4, &"coal": 2}
	stock(0,500,500,500)
	if not check(long_haul.crate_slots() == 12 and long_haul.load_crates(depot,depot.global_position) == 12 and aboard(long_haul,&"iron") == 6 and aboard(long_haul,&"wood") == 4 and aboard(long_haul,&"coal") == 2,"Twelve-slot mixed load wrong"): return
	if not check(depot.iron == 350 and depot.wood == 400 and depot.coal == 450,"Twelve-slot mixed load took the wrong stock"): return
	long_haul.free()
	# Repeat trips carry the same mix each time and leave unlisted resources alone.
	var outpost = spawn(Vector3(-20,0,20))
	outpost.deployed = true
	truck.free()
	truck = spawn(Vector3(-12,0,12))
	truck.manifest = {&"iron": 2, &"wood": 2}
	truck.trips = "repeat"
	truck.auto_refuel = false
	stock(100,300,300,300)
	truck.command_load(depot)
	if not check(run_until(truck,func(): return truck.order == "idle",40) and truck.crates.size() == 4 and depot.iron == 250 and depot.wood == 250,"First repeat load wrong"): return
	truck.command_unload(outpost)
	if not check(run_until(truck,func(): return truck.crates.is_empty(),60),"Repeat unload did not finish"): return
	if not check(run_until(truck,func(): return truck.crates.size() == 4,60),"Repeat trip did not load again"): return
	if not check(depot.iron == 200 and depot.wood == 200 and depot.coal == 300 and depot.energy == 100 and truck.manifest_total() == 4,"Repeat trip changed the mix or took unlisted stock: %s" % [[depot.energy,depot.iron,depot.wood,depot.coal,truck.manifest_total()]]): return
	# Repeat waits only when it can load nothing at all.
	truck.crates.clear(); truck._sync_reserved()
	truck.order_queue.clear()
	stock(0,0,0,0)
	truck.command_load(depot)
	if not check(run_until(truck,func(): return truck.state.begins_with("Waiting for stock"),40) and truck.order == "load","Repeat did not wait for stock"): return
	depot.iron = 25
	if not check(run_until(truck,func(): return truck.crates.size() == 1,20),"Repeat did not resume when stock arrived"): return
	# "All available" stops once the stop can no longer fill anything on the manifest.
	truck.trips = "all"
	truck.order_queue.clear(); truck.order = "idle"
	truck.crates.clear(); truck._sync_reserved()
	stock(0,0,0,0)
	if not check(not truck.pickup_possible(depot,depot.global_position),"Empty stop looked loadable"): return
	depot.wood = 25
	if not check(truck.pickup_possible(depot,depot.global_position),"Stocked stop looked empty"): return
	truck.trips = "once"
	# The Load page edits the manifest of every selected vehicle.
	select(truck)
	truck.manifest.clear()
	hud.card.get_node("Load").pressed.emit(); hud._process(0)
	var pips = hud.manifest_panel.get_node("Pips")
	if not check(game.pending_unit_command == "load" and hud.pick.visible and hud.load_tiles.visible and hud.manifest_panel.visible and not hud.pick.get_node("Prompt").visible and not hud.card.visible,"Load page not shown"): return
	hud.edit_manifest(&"iron"); hud.edit_manifest(&"iron"); hud.edit_manifest(&"wood"); hud._process(0)
	if not check(truck.manifest == {&"iron": 2, &"wood": 1} and hud.manifest_panel.get_node("Head/Value").text == "3 / 4 crates","Manifest tiles wrong"): return
	if not check(pips.get_node("Pip0").visible and pips.get_node("Pip3").visible and not pips.get_node("Pip4").visible and pips.get_node("Pip0/Fill").visible and not pips.get_node("Pip3/Fill").visible,"Manifest pips wrong"): return
	hud.edit_manifest(&"coal",true); hud._process(0)
	if not check(truck.manifest[&"coal"] == 1 and hud.manifest_panel.get_node("Head/Value").text == "4 / 4 crates","Shift fill wrong"): return
	hud.edit_manifest(&"iron"); hud._process(0)
	if not check("full" in game.message and truck.manifest_total() == 4,"Full manifest not explained"): return
	hud.load_tiles.get_node("Clear").pressed.emit(); hud._process(0)
	if not check(truck.manifest.is_empty() and hud.manifest_panel.get_node("Head/Value").text == "0 / 4 crates","Clear did not empty the manifest"): return
	if not check(is_equal_approx(hud.get_node("Bottom").size.y,272) and hud.context.size.x <= 250.5,"Load page broke the fixed HUD size"): return
	game.cancel_armed(); hud._process(0)
	if not check(not hud.manifest_panel.visible and hud.card.visible and not hud.pick.visible,"Load page stayed open after cancelling"): return
	truck.manifest[&"iron"] = 1; select(truck)
	if not check("Manifest: 1 iron" in hud.info.get_node("Details").text,"Vehicle panel does not show its manifest"): return
	# The Depot card makes full crates (tests/truck_worksites_test.gd); the old panel controls are gone.
	select(null,depot)
	if not check(hud.card.get_node("MakeCrates").visible and not hud.card.has_node("EmptyCrate") and not hud.manifest_panel.visible,"Depot card wrong"): return
	clear_crates()
	if not check(not hud.has_node("Bottom/Body/Row/Context/Shipment") and not hud.has_node("Bottom/Body/Row/Context/Manifest/Pack"),"Old crate panel still present"): return
	print("CRATE_MANIFESTS_TEST_PASSED")
	quit(0)
