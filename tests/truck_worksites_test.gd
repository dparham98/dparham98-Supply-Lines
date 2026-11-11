extends SceneTree
# Truck worksites (docs/TRUCK_WORKSITES.md): Fetch brings a build site exactly what it lacks, the
# Worksite page places a building for the selected trucks, and the Depot makes full crates.
const TRUCK := "res://scenes/gameplay/cargo_vehicle.tscn"
var game: Node3D
var hud: CanvasLayer
var network: Node
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
	unit.auto_refuel = false
	return unit
## Steps every given truck until the condition holds.
func run_until(units: Array, condition: Callable, seconds: float) -> bool:
	for i in range(ceili(seconds*60)):
		for unit in units: unit._process(1.0/60)
		if condition.call(): return true
	return false
func clear_world() -> void:
	for group in ["supply_crates","material_piles","construction_plans"]:
		for node in get_nodes_in_group(group): node.free()
## A plan of this kind on valid land near the Depot, with its iron cost set for the test.
func place(kind: StringName, iron: int) -> Node3D:
	for offset in [Vector3(22,0,0),Vector3(-22,0,0),Vector3(0,0,22),Vector3(0,0,-22),Vector3(22,0,22),Vector3(-22,0,-22)]:
		var plan = network.queue_plan(game.depot.global_position+offset,kind)
		if plan != null:
			plan.spec.iron = iron
			plan.set_process(false)
			return plan
	return null
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game); await process_frame
	game.set_process(false)
	hud = game.get_node("Interface"); hud.set_process(false)
	network = game.get_node("DepotNetwork")
	for group in ["units","depots"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	var depot = game.depot
	clear_world()
	# Fetch loads exactly what the site lacks: 45 iron is a full crate and a 20-unit crate.
	var truck = spawn(Vector3(-12,0,12))
	depot.iron = 200
	var plan := place(&"generator",45)
	if not check(plan != null,"No room for a test plan"): return
	truck.command_fetch(plan)
	if not check(truck.order == "load" and truck.fetch_load == {&"iron": 45} and truck.fetch_claim == {&"iron": 45},"Fetch did not plan an exact load: %s" % [truck.fetch_load]): return
	if not check(run_until([truck],func(): return truck.crates.size() == 2,40),"Fetch did not load"): return
	if not check(truck.crate_units(&"iron") == 45 and depot.iron == 155,"Fetch loaded the wrong amount: %d aboard, %d left" % [truck.crate_units(&"iron"),depot.iron]): return
	if not check(run_until([truck],func(): return truck.order == "idle" and truck.order_queue.is_empty(),60),"Fetch did not finish"): return
	if not check(plan.on_site(&"iron") == 45 and plan.materials_covered() and truck.crates.is_empty() and depot.iron == 155,"Fetch delivered the wrong amount: %d on site" % plan.on_site(&"iron")): return
	if not check(truck.fetch_plan == null and truck.fetch_claim.is_empty() and truck.fetch_load.is_empty(),"Fetch did not end cleanly"): return
	# A site bigger than a truckload takes more than one trip.
	clear_world()
	depot.iron = 300
	plan = place(&"generator",130)
	truck.command_fetch(plan)
	if not check(run_until([truck],func(): return plan.materials_covered() and truck.order == "idle" and truck.order_queue.is_empty(),180),"Two-trip fetch did not finish: "+truck.state): return
	if not check(plan.on_site(&"iron") == 130 and depot.iron == 170 and truck.crates.is_empty(),"Two-trip fetch took the wrong stock"): return
	# Two trucks on one site split it and bring no more than it needs.
	clear_world()
	var second = spawn(Vector3(-16,0,14))
	depot.iron = 300
	plan = place(&"generator",150)
	truck.command_fetch(plan)
	second.command_fetch(plan)
	if not check(truck.fetch_claim == {&"iron": 100} and second.fetch_claim == {&"iron": 50},"Trucks did not split the site: %s %s" % [truck.fetch_claim,second.fetch_claim]): return
	if not check(run_until([truck,second],func(): return plan.materials_covered() and truck.order == "idle" and second.order == "idle" and truck.order_queue.is_empty() and second.order_queue.is_empty(),180),"Split fetch did not finish"): return
	if not check(plan.on_site(&"iron") == 150 and depot.iron == 150 and truck.crates.is_empty() and second.crates.is_empty(),"Split fetch over-delivered: %d on site, %d left" % [plan.on_site(&"iron"),depot.iron]): return
	second.free()
	# Materials already aboard go straight to the site; the rest stays aboard.
	clear_world()
	truck.crates.clear()
	truck.crates.append({kind = &"iron", amount = 25})
	truck.crates.append({kind = &"energy", amount = 25})
	truck._sync_reserved()
	depot.iron = 80
	plan = place(&"generator",20)
	truck.command_fetch(plan)
	if not check(truck.order == "unload" and truck.fetch_claim == {&"iron": 20},"Fetch did not deliver what was aboard first"): return
	if not check(run_until([truck],func(): return truck.order == "idle" and truck.order_queue.is_empty(),60),"Aboard delivery did not finish"): return
	if not check(plan.on_site(&"iron") == 20 and depot.iron == 80 and truck.crate_units(&"iron") == 5 and truck.crate_units(&"energy") == 25,"Aboard delivery wrong"): return
	truck.crates.clear(); truck._sync_reserved()
	# With no stock anywhere, Fetch waits and starts when stock arrives.
	clear_world()
	depot.iron = 0
	for other in get_nodes_in_group("mobile_supplies"):
		if other != truck: other.stockpile.set_amount(&"iron",0)
	plan = place(&"generator",20)
	truck.command_fetch(plan)
	if not check(truck.order == "fetch" and truck.state.begins_with("Waiting for iron"),"Fetch did not wait for stock: "+truck.state): return
	depot.iron = 40
	if not check(run_until([truck],func(): return plan.materials_covered(),60) and depot.iron == 20,"Fetch did not resume when stock arrived"): return
	# Another order ends the fetch, so its claim no longer holds back other trucks.
	clear_world()
	depot.iron = 100
	plan = place(&"generator",40)
	truck.command_fetch(plan)
	truck.run_order({kind = "move", point = depot.global_position+Vector3(-20,0,20)})
	if not check(truck.fetch_plan == null and truck.fetch_claim.is_empty() and not truck.fetching(plan),"A move order kept the fetch"): return
	truck.order_queue.clear(); truck._stop_route(); truck.order = "idle"
	# The Worksite page: place a building and the selected trucks fetch for it.
	clear_world()
	truck.global_position = depot.global_position+Vector3(-12,0,12)
	select(truck)
	var tile: Button = hud.card.get_node("Worksite")
	if not check(tile.visible and hud.hotkey_text(tile) == "W","Worksite tile missing"): return
	tile.pressed.emit(); hud._process(0)
	if not check(hud.worksite_open and hud.build_menu.visible and not hud.card.visible and not hud.build_menu.get_node("Actions/Rail").visible and not hud.build_menu.get_node("Actions/Pin").visible,"Worksite page not shown"): return
	if not check(hud.build_menu.get_node("Bank").text == "DELIVERS: EXACT MATERIALS","Worksite page text wrong"): return
	hud.build_menu.get_node("Actions/Generator").pressed.emit()
	if not check(game.global_plan_kind == &"generator","Worksite tile did not arm placement"): return
	var site: Node3D
	for offset in [Vector3(22,0,0),Vector3(-22,0,0),Vector3(0,0,22),Vector3(0,0,-22)]:
		site = game.place_global_plan(depot.global_position+offset,true)
		if site != null: break
	if not check(site != null and truck.fetch_plan == site and game.global_plan_kind == &"generator","Shift worksite did not place, fetch and stay armed"): return
	var queued: Node3D
	for offset in [Vector3(-22,0,0),Vector3(0,0,22),Vector3(0,0,-22),Vector3(22,0,22)]:
		queued = game.place_global_plan(depot.global_position+offset,false)
		if queued != null: break
	if not check(queued != null and truck.order_queue.any(func(e): return e.kind == "fetch" and e.target == queued),"Second worksite was not queued"): return
	hud._process(0)
	if not check(game.global_plan_kind.is_empty() and not hud.worksite_open and hud.card.visible,"Worksite page did not close after placing"): return
	# The global page still lays plans for nobody, with Pin and Rail back.
	hud.open_global_build(); hud._process(0)
	if not check(not hud.worksite_open and hud.build_menu.get_node("Actions/Rail").visible and hud.build_menu.get_node("Actions/Pin").visible,"Global build page lost Rail or Pin"): return
	hud.close_build()
	truck.order_queue.clear(); truck._clear_fetch(); truck.order = "idle"
	clear_world()
	# Trains have no Worksite tile.
	select(truck)
	truck.add_to_group("rail_trains"); hud._process(0)
	if not check(not hud.card.get_node("Worksite").visible,"Train shows Worksite"): return
	truck.remove_from_group("rail_trains")
	# The Depot makes full crates of any kind and no empty ones.
	for kind in ResourceStockpile.KINDS: depot.stockpile.set_amount(kind,0)
	depot.iron = 150; depot.wood = 25
	select(null,depot)
	if not check(hud.card.get_node("MakeCrates").visible and not hud.card.has_node("EmptyCrate") and hud.hotkey_text(hud.card.get_node("MakeCrates")) == "K","Make crates tile wrong"): return
	hud.card.get_node("MakeCrates").pressed.emit(); hud._process(0)
	if not check(hud.crate_page_open and hud.pick.visible and hud.load_tiles.visible and not hud.load_tiles.get_node("Clear").visible and not hud.manifest_panel.visible and not hud.card.visible,"Crate page not shown"): return
	if not check(hud.load_tiles.get_node("Coal").disabled and not hud.load_tiles.get_node("Iron").disabled,"Crate tiles did not follow stock"): return
	hud.load_tiles.get_node("Iron").pressed.emit()
	var beside: Array[Node3D] = CrateYard.beside(depot)
	if not check(beside.size() == 1 and beside[0].amount == 25 and beside[0].resource_kind == &"iron" and depot.iron == 125,"Iron crate not made"): return
	if not check(hud.make_crates(&"iron",true) == 5 and depot.iron == 0 and CrateYard.count_beside(depot,&"iron") == 6,"Shift did not make five crates"): return
	if not check(hud.make_crates(&"coal") == 0 and "needs" in game.message,"Short stock was not explained"): return
	game.cancel_armed(); hud._process(0)
	if not check(not hud.crate_page_open and not hud.pick.visible and hud.card.visible,"Crate page stayed open"): return
	# The Load page still edits manifests and shows Clear after the crate page.
	clear_world()
	select(truck)
	hud.card.get_node("Load").pressed.emit(); hud._process(0)
	if not check(hud.load_tiles.get_node("Clear").visible and hud.manifest_panel.visible and not hud.load_tiles.get_node("Coal").disabled,"Load page broken after the crate page"): return
	game.cancel_armed()
	print("TRUCK_WORKSITES_TEST_PASSED")
	quit(0)
