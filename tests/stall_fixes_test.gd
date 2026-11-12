extends SceneTree
# Headless: four stalls in worker and truck behaviour (docs/STALL_FIXES.md), on the balanced map.
# 1. A builder standing on a plan's footprint steps off before it builds, instead of blocking its own site.
# 2. A worker whose drop-off the player did not choose delivers to the nearest stockpile on each trip; a
#    stockpile the player chose stays its drop-off.
# 3. Unload at a Depot also moves a Cargo vehicle's loose cargo, as far as it fits.
# 4. A worker sent to coal behind uncut forest fells the trees in its way and carries on through the field.
const SCENE := "res://scenes/maps/balanced_skirmish.tscn"
const CoalApproach := preload("res://scripts/terrain/coal_approach.gd")
const Approach := preload("res://scripts/units/interaction_approach.gd")
var game: Node3D
var ground: Node3D
var network: Node
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
## Runs the given nodes for up to `seconds` of game time, until `done`.
func step(nodes: Array, seconds: float, done: Callable) -> bool:
	for i in range(ceili(seconds*60)):
		for node in nodes:
			if is_instance_valid(node): node._process(1.0/60)
		if done.call(): return true
	return false
func still(node: Node) -> void:
	node.set_process(false)
## The nearest valid footprint for a plan of this kind to `near`, at least `least` metres from it.
func site(kind: StringName, near: Vector3, least: float, cover: Node3D = null) -> Vector3:
	var spec: Dictionary = network.plan_spec(kind)
	var centre: Vector2i = ground.get_tile_at_position(near)
	var best := Vector3.INF
	for z in range(centre.y-40,centre.y+41):
		for x in range(centre.x-40,centre.x+41):
			var point: Vector3 = ground.tile_to_world(Vector2i(x,z))
			var d := point.distance_to(near)
			if d < least or (best != Vector3.INF and d >= best.distance_to(near)): continue
			var start: Vector2i = Vector2i(x,z)-spec.size/2
			if not network.plan_terrain_valid(start,spec.size,kind) or network.plan_overlaps(start,spec.size): continue
			if cover != null and not network.can_place_size(point,cover,spec.size): continue
			best = point
	return best
func free_cell(near: Vector3, least: float) -> Vector3:
	var centre: Vector2i = ground.get_tile_at_position(near)
	var best := Vector3.INF
	for z in range(centre.y-12,centre.y+13):
		for x in range(centre.x-12,centre.x+13):
			var point: Vector3 = ground.tile_to_world(Vector2i(x,z))
			var d := point.distance_to(near)
			if d < least or not ground.can_traverse(Vector2i(x,z)) or (best != Vector3.INF and d >= best.distance_to(near)): continue
			best = point
	return best
func new_truck(point: Vector3) -> Node3D:
	var truck: Node3D = load("res://scenes/gameplay/cargo_vehicle.tscn").instantiate()
	truck.position = point
	game.get_node("Entities/Units").add_child(truck)
	still(truck)
	return truck
## Founds a Depot and returns it with the Infantry it brings.
func found(point: Vector3, energy: int) -> Array:
	var before := get_nodes_in_group("units")
	var depot: Node3D = network.establish(point,energy,0)
	await process_frame
	await process_frame
	var settler: Node3D
	for unit in get_nodes_in_group("units"):
		if not before.has(unit): settler = unit
	if is_instance_valid(depot): still(depot)
	if is_instance_valid(settler): still(settler)
	return [depot,settler]

func run() -> void:
	game = load(SCENE).instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	still(game)
	for group in ["units","depots","mines"]:
		for node in get_nodes_in_group(group): still(node)
	ground = game.ground
	network = game.get_node("DepotNetwork")
	var depot: Node3D = game.depot
	var worker: Node3D = game.get_node("Entities/Units/Infantry")
	var mine: Node3D = game.get_node("Entities/Buildings/IronMine")
	depot.energy = 1000

	# ---- 1. A builder on the footprint steps off and then builds.
	var spec: Dictionary = network.plan_spec(&"generator")
	var point := site(&"generator",depot.global_position,10.0,depot)
	if not check(point != Vector3.INF,"No Generator site near the start"): return
	var plan: Node3D = network.queue_plan(point,&"generator")
	if not check(plan != null,"Generator plan refused"): return
	still(plan)
	if not check(plan.receive(&"iron",spec.iron) == spec.iron and plan.materials_covered(),"Site did not take its iron"): return
	# The worker walks onto the unbuilt site, as nothing stops it doing, and is then told to build.
	for cell in worker._claimed.duplicate(): worker._release(cell)
	worker.global_position = plan.global_position
	worker._stop_route()
	var on_site: Vector2i = ground.get_tile_at_position(worker.global_position)
	if not check(plan.footprint().has_point(on_site) and not network.plan_terrain_valid(plan.start,spec.size,&"generator"),"The worker should stand on the footprint and block it"): return
	var generators := get_nodes_in_group("energy_generators").size()
	var energy: int = depot.energy
	worker.command_construct(plan)
	worker._process(1.0/60)
	if not check(worker.state == "Stepping off the build site" and not worker._route.is_empty(),"A builder on the footprint should step off first, state '%s'" % worker.state): return
	var built := step([worker],30.0,func(): return get_nodes_in_group("energy_generators").size() > generators)
	if not check(built,"The Generator was never built: builder state '%s'" % worker.state): return
	var off_site: Vector2i = ground.get_tile_at_position(worker.global_position)
	if not check(not Rect2i(plan.start,spec.size).has_point(off_site) and worker.order == "idle","The builder should end beside the building, not on it"): return
	if not check(depot.energy == energy-spec.energy,"The build should charge its energy once: %d" % (energy-depot.energy)): return
	for generator in get_nodes_in_group("energy_generators"): still(generator)

	# ---- 2. The nearest drop-off each trip, unless the player chose one.
	worker.command_gather(mine)
	if not check(step([worker],90.0,func(): return depot.iron >= 10),"First iron never reached the Depot: '%s'" % worker.state): return
	if not check(worker.return_depot == depot and not worker.return_explicit,"The first load should go to the only Depot, unpinned"): return
	var beside := site(&"depot",mine.global_position,11.0)
	if not check(beside != Vector3.INF and beside.distance_to(mine.global_position) < depot.global_position.distance_to(mine.global_position)-5.0,"No Depot site beside the mine"): return
	var founded: Array = await found(beside,0)
	var near_depot: Node3D = founded[0]
	if not check(is_instance_valid(near_depot) and near_depot.iron == 0,"Second Depot not founded"): return
	var far_iron: int = depot.iron
	if not check(step([worker],90.0,func(): return near_depot.iron >= 20),"The worker kept its old drop-off: near Depot %d iron, far Depot %d (state '%s')" % [near_depot.iron,depot.iron,worker.state]): return
	if not check(depot.iron <= far_iron+worker.carry_capacity,"At most the load already on its way may still go to the far Depot: %d more" % (depot.iron-far_iron)): return
	if not check(worker.return_depot == near_depot and not worker.return_explicit,"The nearer Depot should now be the drop-off, still unpinned"): return
	# A right-click on a Depot pins it: later trips go there although another is nearer.
	worker.command_return(depot)
	worker.command_gather(mine)
	far_iron = depot.iron
	var near_iron: int = near_depot.iron
	if not check(step([worker],120.0,func(): return depot.iron >= far_iron+20),"A pinned drop-off was not kept: far Depot %d more, near Depot %d more" % [depot.iron-far_iron,near_depot.iron-near_iron]): return
	if not check(near_depot.iron <= near_iron+worker.carry_capacity and worker.return_explicit and worker.return_depot == depot,"Pinned deliveries leaked to the nearer Depot"): return
	worker.command_move(worker.global_position)

	# ---- 3. Unload at a Depot also empties loose cargo.
	var truck := new_truck(free_cell(depot.global_position,7.0))
	truck.stockpile.deposit(&"iron",40)
	truck.stockpile.deposit(&"coal",15)
	truck.crates.append({kind = &"wood", amount = 25})
	truck._sync_reserved()
	var iron: int = depot.iron
	var coal: int = depot.coal
	var wood: int = depot.wood
	truck.command_unload(depot)
	if not check(step([truck],30.0,func(): return truck.order == "idle"),"Unload never finished: '%s'" % truck.state): return
	if not check(depot.iron == iron+40 and depot.coal == coal+15 and depot.wood == wood+25,"Depot should gain 40 iron, 15 coal and a 25 wood crate: %d / %d / %d" % [depot.iron-iron,depot.coal-coal,depot.wood-wood]): return
	if not check(truck.stockpile.total() == 0 and truck.crates.is_empty() and truck.loose_unloaded == 55,"Truck should be empty with 55 loose units moved: %d aboard, %d counted" % [truck.stockpile.total(),truck.loose_unloaded]): return
	if not check(truck.state.contains("1 crate") and truck.state.contains("55 loose"),"State should say what was unloaded: '%s'" % truck.state): return
	# Only what fits goes in; the rest stays aboard. A right-click with loose cargo alone unloads.
	near_depot.storage_capacity = near_depot.stockpile.total()+30
	near_iron = near_depot.iron
	truck.stockpile.deposit(&"iron",50)
	truck.command_return(near_depot)
	if not check(truck.order == "unload","Right-clicking a Depot with loose cargo aboard should unload, not load: %s" % truck.order): return
	if not check(step([truck],60.0,func(): return truck.order == "idle"),"Partial unload never finished: '%s'" % truck.state): return
	if not check(near_depot.iron == near_iron+30 and truck.stockpile.amount(&"iron") == 20 and truck.state.contains("20 loose retained"),"30 of 50 should fit and 20 stay aboard: Depot +%d, truck %d, '%s'" % [near_depot.iron-near_iron,truck.stockpile.amount(&"iron"),truck.state]): return
	near_depot.storage_capacity = 2000
	# The use it is for: a truck deployed beside the mine takes a worker's loads, then carries them home.
	truck.stockpile.withdraw(&"iron",20)
	var parked := new_truck(free_cell(mine.global_position,5.0))
	if not check(parked.deploy_supplies() and step([parked],5.0,func(): return parked.supplies_available()),"Truck would not deploy beside the mine"): return
	worker.command_return(parked)
	worker.command_gather(mine)
	if not check(step([worker,parked],90.0,func(): return parked.stockpile.amount(&"iron") >= 20),"The worker did not load the deployed truck: %d iron aboard, '%s'" % [parked.stockpile.amount(&"iron"),worker.state]): return
	worker.command_move(worker.global_position)
	var aboard: int = parked.stockpile.amount(&"iron")
	iron = depot.iron
	parked.command_unload(depot)
	if not check(step([parked],60.0,func(): return parked.order == "idle" and parked.stockpile.total() == 0),"The truck did not bring the loose iron home: '%s'" % parked.state): return
	if not check(depot.iron == iron+aboard,"Iron was created or lost on the way: Depot +%d, truck had %d" % [depot.iron-iron,aboard]): return

	# ---- 4. Coal behind uncut forest: the worker cuts its own way in and through the field.
	var expansion: Vector3 = game.get_node("Sites/SafeExpansionA").position
	founded = await found(expansion,100)
	var second: Node3D = founded[0]
	var settler: Node3D = founded[1]
	if not check(is_instance_valid(second) and is_instance_valid(settler),"No Depot and Infantry at the safe expansion"): return
	var field := {}
	var far_field := {}
	for candidate in ground.coal_fields:
		if field.is_empty() or candidate.center.distance_to(expansion) < field.center.distance_to(expansion): field = candidate
		if far_field.is_empty() or candidate.center.distance_to(expansion) > far_field.center.distance_to(expansion): far_field = candidate
	var total: int = ground.coal_field_remaining(field)
	var standing := 0
	for cell in field.cells: standing += Approach.candidates(ground,ground.coal_source(cell),settler.interaction_range,MobilityRules.Layer.GROUND,"").size()
	if not check(standing == 0,"The field should start enclosed by forest"): return
	var here: Vector2i = ground.get_tile_at_position(settler.global_position)
	var asked: Vector2i = field.cells[0]
	var way: Dictionary = CoalApproach.way(ground,here,asked,settler.interaction_range,MobilityRules.Layer.GROUND,settler._owner_key())
	if not check(not way.is_empty() and way.fell.size() >= 1 and field.cells.has(way.coal),"No way worked out into the field: %s" % [way]): return
	for cell in way.fell:
		if not check(ground.get_terrain(cell) == 3,"The way should only list Forest cells, not %s" % cell): return
	if not check(ground.cleared_forest.is_empty() and ground.coal_field_remaining(field) == total,"Working out a way must not change the ground"): return
	var planned: int = way.fell.size()
	var felled_before: int = ground.cleared_forest.size()
	settler.command_gather(ground.coal_source(asked))
	step([settler],3.0,func(): return is_instance_valid(settler._dig_source))
	if not check(is_instance_valid(settler._dig_source) and settler._dig_source.resource_kind == &"coal" and is_instance_valid(settler.source) and settler.source.resource_kind == &"wood","The worker should start on the first tree in its way, state '%s'" % settler.state): return
	if not check(settler.source.cell == way.fell[0],"It should fell the first cell of the planned way"): return
	if not check(step([settler],900.0,func(): return second.coal >= 10),"No coal reached the Depot: state '%s', %d trees felled" % [settler.state,ground.cleared_forest.size()-felled_before]): return
	var felled: int = ground.cleared_forest.size()-felled_before
	if not check(felled == planned,"It should fell exactly the planned %d trees before the first coal, not %d" % [planned,felled]): return
	if not check(second.wood == felled*ground.harvesting_rules.forest_wood_per_tile,"Every felled tree's wood should be in the Depot: %d wood for %d trees" % [second.wood,felled]): return
	# On through the field: past the first cell (50) without stopping at "Coal unreachable".
	var goal: int = ground.harvesting_rules.coal_per_tile*2+20
	if not check(step([settler],900.0,func(): return second.coal >= goal),"Digging stopped at %d coal: state '%s', order %s" % [second.coal,settler.state,settler.order]): return
	if not check(settler.order in ["gather","return"] and not settler.state.ends_with("unreachable"),"The worker should still be at work: %s / %s" % [settler.order,settler.state]): return
	var carried: int = settler.cargo if settler.cargo_kind == &"coal" else 0
	if not check(ground.coal_field_remaining(field)+second.coal+carried == total,"Coal was created or lost: %d left, %d delivered, %d carried of %d" % [ground.coal_field_remaining(field),second.coal,carried,total]): return
	# Another order drops the coal it was cutting towards.
	settler.command_move(settler.global_position)
	step([settler],5.0,func(): return settler.order == "idle")
	var other: Dictionary = {}
	for candidate in ground.coal_fields:
		if candidate != field and candidate != far_field and (other.is_empty() or candidate.center.distance_to(expansion) < other.center.distance_to(expansion)): other = candidate
	settler.cargo = 0
	settler.command_gather(ground.coal_source(other.cells[0]))
	step([settler],3.0,func(): return is_instance_valid(settler._dig_source))
	if not check(is_instance_valid(settler._dig_source),"A worker far from another enclosed field should set out to cut into it, state '%s'" % settler.state): return
	settler.command_move(settler.global_position)
	if not check(settler._dig_source == null and settler.source == null and settler.order == "move","A new order should drop the dig"): return
	# A field with no coal left has no way to work out.
	for cell in far_field.cells: ground.coal_reserves[cell] = 0
	if not check(CoalApproach.way(ground,here,far_field.cells[0],settler.interaction_range,MobilityRules.Layer.GROUND,settler._owner_key()).is_empty(),"An empty field should give no way"): return
	print("STALL_FIXES_TEST_PASSED")
	quit()
