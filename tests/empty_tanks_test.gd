extends SceneTree
# Headless: on the balanced map, vehicles made in play start with an empty tank (economy report step 5,
# docs/BALANCED_MAP.md): a Depot truck and a Cargo vehicle printed at the Depot, a Tank from a Tank factory,
# and a vehicle spawned from the playtest panel. The authored starter Cargo truck still starts full.
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func new_units(before: Array) -> Array:
	return get_nodes_in_group("units").filter(func(unit): return not before.has(unit))
func run() -> void:
	game = load("res://scenes/maps/balanced_skirmish.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	game.set_process(false)
	for node in get_nodes_in_group("units"): node.set_process(false)
	var depot: Node3D = game.depot
	var starter: Array = get_nodes_in_group("units").filter(func(unit): return unit.get("is_cargo_vehicle") == true and unit.team == "player")
	if not check(starter.size() == 1 and starter[0].fuel_active() and starter[0].fuel >= starter[0].fuel_rules.reserve_capacity,"The authored starter Cargo truck should start full"): return
	# Printed at the Depot.
	depot.coal = 0
	depot.energy = 2000-depot.stockpile.total()+depot.energy
	depot.iron = 500
	var before: Array = get_nodes_in_group("units")
	if not check(depot.request_truck() and depot.request_cargo(),"The Depot should take a truck and a cargo order"): return
	for frame in range(60*30):
		depot._process(1.0/60)
		if new_units(before).size() >= 2: break
	var made: Array = new_units(before)
	if not check(made.size() == 2,"The Depot should have printed two vehicles, printed %d" % made.size()): return
	for unit in made:
		if not check(unit.fuel_active() and unit.fuel == 0,"%s should start with an empty tank, has %.1f" % [unit.name,unit.fuel]): return
	# Built at a Tank factory.
	var network = game.get_node("DepotNetwork")
	var spec: Dictionary = network.plan_spec(&"tank_factory")
	var point := Vector3.INF
	for radius in range(12,34,2):
		for offset in [Vector3(radius,0,0),Vector3(-radius,0,0),Vector3(0,0,radius),Vector3(0,0,-radius)]:
			var start: Vector2i = network.footprint_start(depot.global_position+offset,spec.size)
			if point == Vector3.INF and network.plan_terrain_valid(start,spec.size,&"tank_factory") and not network.plan_overlaps(start,spec.size) and network.can_place_size(depot.global_position+offset,depot,spec.size): point = depot.global_position+offset
	if not check(point != Vector3.INF,"No site for a Tank factory"): return
	var plan = network.queue_plan(point,&"tank_factory",depot)
	if not check(plan != null,"The Tank factory plan was refused"): return
	plan.set_process(false)
	depot.iron = 500
	var factory = plan.complete_from_stock()
	if not check(factory != null,"The Tank factory was not built"): return
	await process_frame
	factory.set_process(false)
	depot.iron = 500
	before = get_nodes_in_group("units")
	if not check(factory.request_unit(&"tank"),"The factory should take a Tank order"): return
	for frame in range(60*60):
		factory._process(1.0/60)
		if not new_units(before).is_empty(): break
	made = new_units(before)
	if not check(made.size() == 1 and made[0].fuel_active() and made[0].fuel == 0,"The factory Tank should start with an empty tank"): return
	# Spawned from the playtest panel.
	var panel = game.get_node("Interface/PlaytestPanel")
	var index := -1
	for i in range(panel.spawn_scenes.size()):
		if panel.spawn_scenes[i].resource_path.ends_with("tank.tscn"): index = i
	if not check(index >= 0,"The playtest panel should offer a Tank"): return
	panel.get_node("Body/Spawn/Unit").select(index)
	var spawned: Node3D = panel.spawn_at(depot.global_position+Vector3(30,0,30))
	if not check(spawned != null and spawned.fuel_active() and spawned.fuel == 0,"A playtest Tank should start empty on this map"): return
	print("EMPTY_TANKS_TEST_PASSED")
	quit()
