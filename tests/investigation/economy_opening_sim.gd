extends SceneTree
## INVESTIGATION TOOL, NOT A TEST. It asserts nothing and CI does not run it (the runner only takes
## tests/*_test.gd). It plays scripted openings on the balanced map with the game's own unit orders and prints
## when each step happened, for docs/ECONOMY_REPORT.md. It changes no project file.
##
## Run with a fixed time step so game time does not depend on the machine:
##   godot --headless --fixed-fps 30 --path . --script res://tests/investigation/economy_opening_sim.gd -- --opening=rates
##
## --opening=rates   one Infantry: iron a minute from the starter mine, then wood a minute from the nearest trees
## --opening=truck   the starter Cargo truck to the safe expansion and back: seconds and coal
## --opening=doc     the opening in docs/BALANCED_MAP.md: Depot truck to the safe expansion, then build up at home
## --opening=cheap   what today's prices reward: Depot plans beside the mine for their free Infantry
## --full-tanks=on   leave FuelRules.testing_full_tanks on, as shipped (default off: new vehicles start empty)
## --minutes=N       how long doc and cheap run (default 12)
## --depots=N        how many extra Depots cheap builds (default 3)
## --debug=on        print every unit's order with each stock line
##
## The balanced map already has the Depot iron grant and the testing coal pile off.
const SCENE := "res://scenes/maps/balanced_skirmish.tscn"
var game: Node3D
var ground: Node3D
var network: Node
var depot: Node3D
var worker: Node3D
var truck: Node3D
var mine: Node3D
var t := 0.0
var step_seconds := 0.0
var done := false
## Everything delivered to each stockpile so far, {instance id: {kind: amount}}.
var delivered := {}
func _on_delivered(target: Node3D, kind: StringName, amount: int) -> void:
	var id := target.get_instance_id()
	if not delivered.has(id): delivered[id] = {}
	delivered[id][kind] = delivered[id].get(kind,0)+amount
func tally(target: Node3D, kind: StringName) -> int:
	return delivered.get(target.get_instance_id(),{}).get(kind,0)

func _initialize() -> void: call_deferred("run")
func _process(delta: float) -> bool:
	t += delta
	step_seconds = delta
	return false

func clock(seconds: float) -> String:
	return "%d:%02d" % [int(seconds)/60,int(seconds)%60]
func stock(node: Node3D) -> String:
	return "E%d I%d W%d C%d" % [node.energy,node.iron,node.wood,node.coal]
func mark(text: String) -> void:
	print("[%s] %s" % [clock(t),text])
func until(cond: Callable, limit := 900.0) -> bool:
	var end := t+limit
	while t < end:
		if cond.call(): return true
		await process_frame
	return false
func wait(seconds: float) -> void:
	var end := t+seconds
	while t < end: await process_frame
func arg(name: String, fallback: String) -> String:
	for entry in OS.get_cmdline_user_args():
		if entry.begins_with("--%s=" % name): return entry.get_slice("=",1)
	return fallback
func player_units() -> Array:
	return get_nodes_in_group("units").filter(func(u): return u.team == "player" and u.health > 0)
func infantry() -> Array:
	return player_units().filter(func(u): return u.can_gather and not u.is_depot_truck and not u.is_cargo_vehicle)
func depots() -> Array:
	return get_nodes_in_group("depots").filter(func(d): return d.team == "player")
func newest(before: Array, group: String) -> Node3D:
	for node in get_nodes_in_group(group):
		if not before.has(node) and node.get("team") == "player": return node
	return null
func fresh_of(before: Array, now: Array) -> Node3D:
	for node in now:
		if not before.has(node): return node
	return null
func alive(node) -> bool:
	return is_instance_valid(node) and not node.is_queued_for_deletion()

## Nearest valid footprint for a plan to `near`, optionally inside `cover`'s range, at least `min_d` away.
func find_site(kind: StringName, near: Vector3, cover: Node3D, min_d := 0.0, max_d := 45.0) -> Vector3:
	var spec: Dictionary = network.plan_spec(kind)
	var size: Vector2i = spec.size
	var centre: Vector2i = ground.get_tile_at_position(near)
	var best := Vector3.INF
	var best_d := INF
	var span := ceili(max_d)
	for z in range(centre.y-span,centre.y+span+1):
		for x in range(centre.x-span,centre.x+span+1):
			var cell := Vector2i(x,z)
			if not ground.is_tile_in_bounds(cell): continue
			var point: Vector3 = ground.tile_to_world(cell)
			var d := point.distance_to(near)
			if d < min_d or d > max_d or d >= best_d: continue
			var start: Vector2i = cell-size/2
			if not network.plan_terrain_valid(start,size,kind) or network.plan_overlaps(start,size): continue
			if cover != null and not network.can_place_size(point,cover,size): continue
			best = point; best_d = d
	return best
## Forest cells with open ground beside them, nearest to a point first.
func forest_near(point: Vector3, radius: float) -> Array[Vector2i]:
	var centre: Vector2i = ground.get_tile_at_position(point)
	var span := ceili(radius)
	var result: Array[Vector2i] = []
	for z in range(centre.y-span,centre.y+span+1):
		for x in range(centre.x-span,centre.x+span+1):
			var cell := Vector2i(x,z)
			if not ground.is_tile_in_bounds(cell) or ground.get_terrain(cell) != 3: continue
			if ground.tile_to_world(cell).distance_to(point) > radius: continue
			for step in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)]:
				if ground.is_tile_in_bounds(cell+step) and ground.get_terrain(cell+step) in [0,2]:
					result.append(cell); break
	result.sort_custom(func(a,b): return ground.tile_to_world(a).distance_squared_to(point) < ground.tile_to_world(b).distance_squared_to(point))
	return result
## Keeps a worker felling the forest nearest `home` until `stop` says so.
func cut_wood(unit: Node3D, home: Node3D, stop: Callable) -> void:
	var bad := {}
	while alive(unit) and not stop.call():
		var target := Vector2i(-1,-1)
		for cell in forest_near(home.global_position,70.0):
			if not bad.has(cell): target = cell; break
		if target.x < 0: return
		unit.command_gather(ground.forest_source(target))
		# A worker keeps its last drop-off; a player would right-click the Depot that needs the wood.
		unit.return_depot = home; unit.return_explicit = true
		while alive(unit) and not stop.call():
			await process_frame
			if unit.state.ends_with("unreachable"): bad[target] = true; break
			if unit.order == "idle": break
## The fewest forest cells to fell from `from` until a worker can stand within reach of a coal cell of `field`.
## Returns the forest cells in walking order and the coal cell reached.
func corridor(from: Vector2i, field: Dictionary, reach: float) -> Dictionary:
	var size: Vector2i = ground.grid_size
	var cost := {}
	var back := {}
	var near_coal := {}
	var span := ceili(reach)
	for coal in field.cells:
		if ground.coal_amount(coal) <= 0: continue
		for z in range(coal.y-span,coal.y+span+1):
			for x in range(coal.x-span,coal.x+span+1):
				var cell := Vector2i(x,z)
				if ground.is_tile_in_bounds(cell) and Vector2(cell-coal).length() <= reach+0.0001 and not near_coal.has(cell): near_coal[cell] = coal
	# Fewest forest cells first, then the shortest walk: cost is 10,000 a forest cell plus one a step.
	var open_set: Array = [[0,from]]
	cost[from] = 0
	var goal := Vector2i(-1,-1)
	while not open_set.is_empty():
		var entry: Array = open_set.pop_front()
		var cell: Vector2i = entry[1]
		if entry[0] > cost[cell]: continue
		if near_coal.has(cell): goal = cell; break
		for step in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)]:
			var next: Vector2i = cell+step
			if next.x < 0 or next.y < 0 or next.x >= size.x or next.y >= size.y or absi(next.x-from.x) > 90 or absi(next.y-from.y) > 90: continue
			var kind: int = ground.get_terrain(next)
			var extra := 1 if kind in [0,2] else (10001 if kind == 3 else -1)
			if extra < 0 or (extra == 1 and not ground.can_traverse(next,MobilityRules.Layer.GROUND,"")): continue
			var total: int = cost[cell]+extra
			if cost.has(next) and cost[next] <= total: continue
			cost[next] = total
			back[next] = cell
			var item := [total,next]
			open_set.insert(open_set.bsearch_custom(item,func(a,b): return a[0] < b[0]),item)
	if goal.x < 0: return {}
	var cells: Array[Vector2i] = []
	var at := goal
	while at != from:
		if ground.get_terrain(at) == 3: cells.push_front(at)
		at = back[at]
	return {cells = cells, coal = near_coal[goal]}
## Fells a corridor into the coal field nearest `home`, then digs. Reports when coal is first reached.
func open_coal(unit: Node3D, home: Node3D, label: String) -> void:
	var field := {}
	for candidate in ground.coal_fields:
		if field.is_empty() or candidate.center.distance_to(home.global_position) < field.center.distance_to(home.global_position): field = candidate
	var way := corridor(ground.get_tile_at_position(unit.global_position),field,unit.interaction_range)
	if way.is_empty(): mark("%s: no corridor to coal found" % label); return
	var begin := t
	mark("%s: felling %d forest cells toward coal" % [label,way.cells.size()])
	for cell in way.cells:
		unit.command_gather(ground.forest_source(cell))
		if not await until(func(): return not alive(unit) or (ground.get_terrain(cell) != 3 and unit.order == "idle") or unit.state.ends_with("unreachable"),600.0):
			mark("%s: stuck felling %s (%s)" % [label,cell,unit.state]); return
		if not alive(unit) or unit.state.ends_with("unreachable"): mark("%s: forest cell %s unreachable" % [label,cell]); return
	mark("%s: corridor open after %.0f s of felling (%.1f s a cell), digging coal · %s %s" % [label,t-begin,(t-begin)/way.cells.size(),home.name,stock(home)])
	unit.command_gather(ground.coal_source(way.coal))
	var first := -1.0
	var extra := 0
	var goal := 150
	while alive(unit) and home.coal < goal and t < begin+1500.0:
		await process_frame
		if first < 0.0 and home.coal > 0:
			first = t
			mark("%s: first coal delivered to %s" % [label,home.name])
		if unit.state.ends_with("unreachable"):
			# The corridor reached one cell from a distance; the dug-out cell is an island behind uncut forest.
			var more := corridor(ground.get_tile_at_position(unit.global_position),field,unit.interaction_range)
			if more.is_empty(): mark("%s: no way on into the field" % label); return
			mark("%s: next coal cell out of reach with %d coal dug; felling %d more forest cells" % [label,home.coal,more.cells.size()])
			for cell in more.cells:
				unit.command_gather(ground.forest_source(cell))
				await until(func(): return not alive(unit) or (ground.get_terrain(cell) != 3 and unit.order == "idle") or unit.state.ends_with("unreachable"),600.0)
			extra += more.cells.size()
			unit.command_gather(ground.coal_source(more.coal))
	if first >= 0.0: mark("%s: %d coal at %s, %.0f s after the first load (%.1f a minute for one Infantry, with %d more forest cells felled on the way)" % [label,home.coal,home.name,t-first,(home.coal-10)*60.0/maxf(1.0,t-first),extra])
## Moves a unit off a plan's footprint, where it would block its own build.
func step_clear(unit: Node3D, plan: Node3D) -> void:
	var here = ground.get_tile_at_position(unit.global_position)
	var keep: Rect2i = plan.footprint().grow(1)
	if here == null or not keep.has_point(here): return
	var best := Vector2i(-1,-1)
	for z in range(keep.position.y-3,keep.end.y+3):
		for x in range(keep.position.x-3,keep.end.x+3):
			var cell := Vector2i(x,z)
			if keep.has_point(cell) or not ground.can_traverse(cell,MobilityRules.Layer.GROUND,unit._owner_key()): continue
			if best.x < 0 or cell.distance_squared_to(here) < best.distance_squared_to(here): best = cell
	if best.x < 0: return
	unit.command_move(ground.tile_to_world(best))
	await until(func(): return unit.order == "idle",20.0)
## Brings iron from `src` to a plan by hand and builds it. Used when no truck is spared for the site.
func haul_and_build(unit: Node3D, plan: Node3D, src: Node3D) -> void:
	var id := plan.get_instance_id()
	var live := func() -> Node3D:
		var node := instance_from_id(id) as Node3D
		return node if alive(node) and not node.finished else null
	while live.call() != null and alive(unit):
		if plan.shortfall(&"iron") > 0 and not (unit.cargo > 0 and unit.cargo_kind == &"iron"):
			unit.command_gather(src)
			await until(func(): return live.call() == null or (unit.cargo >= mini(unit.carry_capacity,live.call().shortfall(&"iron")) and unit.cargo_kind == &"iron"),300.0)
		if live.call() == null: break
		await step_clear(unit,plan)
		unit.command_construct(plan)
		await until(func(): return live.call() == null or (unit.cargo == 0 and unit.state.begins_with("Waiting for")),300.0)
## A truck fetches the plan's materials and a worker builds it. Returns the finished building.
func fetch_and_build(kind: StringName, point: Vector3, builder: Node3D, lorry: Node3D, group: String) -> Node3D:
	var before := get_nodes_in_group(group)
	var plan: Node3D = network.queue_plan(point,kind)
	if plan == null: mark("%s plan refused at %s" % [kind,point]); return null
	var begin := t
	lorry.order_queue.clear()
	lorry.run_order({kind = "fetch", target = plan})
	var id := plan.get_instance_id()
	var title: String = plan.spec.title
	if not await until(func(): return not alive(instance_from_id(id)) or instance_from_id(id).materials_covered(),300.0): mark("%s: materials never arrived (%s)" % [kind,lorry.state]); return null
	mark("%s: materials on site %.0f s after the plan" % [title,t-begin])
	await step_clear(builder,plan)
	builder.command_construct(plan)
	if not await until(func(): return newest(before,group) != null,300.0): mark("%s: never finished (%s)" % [kind,builder.state]); return null
	return newest(before,group)
func sample() -> void:
	var parts: Array[String] = []
	for local in depots(): parts.append("%s %s" % [local.name,stock(local)])
	var fuels: Array[String] = []
	for unit in player_units():
		if unit.fuel_rules != null and unit.fuel_active(): fuels.append("%s %.0f" % [unit.name,unit.fuel])
	print("    stock @%s | %s | Infantry %d | fuel: %s" % [clock(t)," | ".join(parts),infantry().size(),", ".join(fuels)])
	if arg("debug","") == "on":
		for unit in player_units(): print("      %s: %s / %s · cargo %d %s" % [unit.name,unit.order,unit.state,unit.cargo,unit.cargo_kind])
		for plan in get_nodes_in_group("construction_plans"): print("      plan %s: %s · %s" % [plan.spec.title,plan.state,plan.site_text()])
func sampler(every: float) -> void:
	while not done:
		await wait(every)
		if not done: sample()

func run() -> void:
	FuelRules.testing_full_tanks = arg("full-tanks","off") == "on"
	game = load(SCENE).instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	ground = game.ground
	network = game.get_node("DepotNetwork")
	depot = game.depot
	worker = game.get_node("Entities/Units/Infantry")
	truck = game.get_node("Entities/Units/StarterTruck")
	mine = game.get_node("Entities/Buildings/IronMine")
	game.resources_delivered.connect(_on_delivered)
	t = 0.0
	var opening := arg("opening","rates")
	var limit := float(arg("minutes","12"))*60.0
	print("ECONOMY OPENING SIMULATION · opening=%s · step %.4f s · testing_full_tanks=%s · iron grant=%s" % [opening,step_seconds,FuelRules.testing_full_tanks,depot.testing_iron_granted()])
	mark("start: %s %s · Infantry %d · truck fuel %.0f" % [depot.name,stock(depot),infantry().size(),truck.fuel])
	match opening:
		"rates": await rates()
		"truck": await truck_trip()
		"doc": await doc_opening(limit)
		"cheap": await cheap_opening(limit)
		_: print("Unknown opening")
	done = true
	print("ECONOMY_OPENING_SIM_DONE")
	quit()

## Gather rates for one Infantry at the start: iron from the starter mine, then wood from the nearest trees.
func rates() -> void:
	worker.command_gather(mine)
	await until(func(): return depot.iron >= 10,120.0)
	var first := t
	mark("first iron load delivered")
	await until(func(): return depot.iron >= 110,600.0)
	mark("iron: 100 more delivered in %.1f s -> %.1f s a load of 10, %.1f iron a minute" % [t-first,(t-first)/10.0,6000.0/(t-first)])
	var wood_goal := 100
	cut_wood(worker,depot,func(): return depot.wood >= wood_goal+10)
	await until(func(): return depot.wood >= 10,300.0)
	first = t
	mark("first wood load delivered")
	await until(func(): return depot.wood >= wood_goal+10,900.0)
	mark("wood: 100 more delivered in %.1f s -> %.1f s a load of 10, %.1f wood a minute" % [t-first,(t-first)/10.0,6000.0/(t-first)])
## The starter Cargo truck to the safe expansion and back, empty: time and coal burned.
func truck_trip() -> void:
	var site: Vector3 = game.get_node("Sites/SafeExpansionA").position
	var home: Vector3 = truck.global_position
	var fuel: float = truck.fuel
	truck.command_move(site)
	await until(func(): return truck.order == "idle",300.0)
	mark("truck reached the safe expansion: %.1f s, %.1f coal, %.0f m straight-line" % [t,fuel-truck.fuel,home.distance_to(site)])
	var out := t
	truck.command_move(home)
	await until(func(): return truck.order == "idle",300.0)
	mark("truck home again: round trip %.1f s (return leg %.1f s), %.1f coal burned of %.0f" % [t,t-out,fuel-truck.fuel,fuel])
	var other: Vector3 = game.get_node("Sites/ExposedExpansionA").position
	var begin := t
	var tank: float = truck.fuel
	truck.command_move(other)
	await until(func(): return truck.order == "idle" or truck.out_of_fuel,300.0)
	mark("truck toward the exposed expansion: %.1f s, %.1f coal%s" % [t-begin,tank-truck.fuel," · OUT OF FUEL" if truck.out_of_fuel else ""])

## The opening docs/BALANCED_MAP.md describes: Depot truck first, to the safe expansion, then build up at home.
func doc_opening(limit: float) -> void:
	sampler(30.0)
	var safe: Vector3 = game.get_node("Sites/SafeExpansionA").position
	worker.command_gather(mine)
	await until(func(): return depot.iron >= depot.rules.truck_iron_cost,300.0)
	depot.request_truck()
	mark("Depot truck ordered (%d E / %d I) · %s" % [depot.rules.truck_energy_cost,depot.rules.truck_iron_cost,stock(depot)])
	expansion(safe)
	# Generator: the truck fetches 20 iron, the Infantry leaves the mine to build it, then cuts 40 wood.
	await until(func(): return depot.iron >= network.supply_rules.generator_iron_cost,300.0)
	var generator := await fetch_and_build(&"generator",find_site(&"generator",depot.global_position,depot,10.0),worker,truck,"energy_generators")
	mark("Generator built · %s" % stock(depot))
	var wood_goal: int = tally(depot,&"wood")+40
	await cut_wood(worker,depot,func(): return tally(depot,&"wood") >= wood_goal)
	mark("40 wood delivered; Generator %s · %s" % [generator.state if alive(generator) else "?",stock(depot)])
	# Barracks, then one Infantry from it.
	worker.command_gather(mine)
	await until(func(): return depot.iron >= 45 and depot.energy >= 100,600.0)
	var barracks := await fetch_and_build(&"barracks",find_site(&"barracks",depot.global_position,depot,12.0),worker,truck,"production_buildings")
	mark("Barracks built · %s" % stock(depot))
	worker.command_gather(mine)
	await until(func(): return depot.iron >= 20 and depot.energy >= 100,600.0)
	var before := infantry()
	barracks.request_unit(&"infantry")
	await until(func(): return infantry().size() > before.size(),120.0)
	var third := fresh_of(before,infantry())
	mark("Barracks Infantry out · %s" % stock(depot))
	# From here: the first Infantry mines, the Barracks Infantry cuts wood for the Generator.
	cut_wood(third,depot,func(): return done)
	# Tank Factory and a Tank, as iron and energy allow.
	await until(func(): return (depot.iron >= 65 and depot.energy >= 200) or t >= limit,900.0)
	if t < limit:
		var factory := await fetch_and_build(&"tank_factory",find_site(&"tank_factory",depot.global_position,depot,14.0),worker,truck,"production_buildings")
		mark("Tank Factory built · %s" % stock(depot))
		worker.command_gather(mine)
		await until(func(): return (depot.iron >= 35 and depot.energy >= 150) or t >= limit,900.0)
		if t < limit and alive(factory):
			var units := player_units()
			factory.request_unit(&"tank")
			await until(func(): return player_units().size() > units.size(),120.0)
			var tank := fresh_of(units,player_units())
			mark("Tank out with %.0f coal of %.0f · %s" % [tank.fuel,tank.fuel_rules.reserve_capacity,stock(depot)])
			await until(func(): return tank.fuel >= tank.fuel_rules.reserve_capacity-1 or t >= limit,900.0)
			mark("Tank fuel %.0f of %.0f" % [tank.fuel,tank.fuel_rules.reserve_capacity])
	await until(func(): return t >= limit,limit)
	sample()
## The Depot truck's side of the doc opening: second Depot, its Infantry into the coal, coal trucked home.
func expansion(site: Vector3) -> void:
	var units := player_units()
	await until(func(): return player_units().size() > units.size(),120.0)
	var depot_truck := fresh_of(units,player_units())
	mark("Depot truck built with %.0f coal aboard" % depot_truck.fuel)
	if depot_truck.fuel < 1:
		mark("Depot truck cannot move: no coal in the Depot and new vehicles start empty")
		return
	var existing := depots()
	var walkers := infantry()
	depot_truck.run_order({kind = "deploy", point = site})
	await until(func(): return depots().size() > existing.size(),300.0)
	var second := fresh_of(existing,depots())
	await until(func(): return infantry().size() > walkers.size(),60.0)
	var settler := fresh_of(walkers,infantry())
	mark("Second Depot down with its Infantry · %s %s" % [second.name,stock(second)])
	await open_coal(settler,second,"Expansion")
	# When a truckload of coal is ready the starter truck brings it home.
	await until(func(): return second.coal >= 100,900.0)
	mark("100 coal at the expansion · %s" % stock(second))
	await until(func(): return truck.order == "idle" and truck.order_queue.is_empty(),300.0)
	var tank: float = truck.fuel
	var begin := t
	truck.manifest = {&"coal": 4}
	truck.run_order({kind = "load", target = second, point = second.global_position, requires_target = true})
	truck.queue_order({kind = "unload", target = depot, point = depot.global_position})
	await until(func(): return depot.coal >= 100,600.0)
	mark("100 coal trucked home in %.0f s · truck fuel %.0f (was %.0f) · %s" % [t-begin,truck.fuel,tank,stock(depot)])

## What today's prices reward: Depot plans inside the first Depot's range, beside the mine. Each costs
## 20 E / 20 I and brings a free Infantry, who builds the next one. Then a Generator, Barracks and Tank Factory
## at the first Depot, with the truck carrying iron across from the Depot beside the mine.
func cheap_opening(limit: float) -> void:
	sampler(30.0)
	var count := int(arg("depots","3"))
	var builder := worker
	var beside: Node3D
	for i in range(count):
		var point := find_site(&"depot",mine.global_position,depot,11.0,40.0)
		if point == Vector3.INF: mark("no room for another Depot inside %s's range" % depot.name); break
		var existing := depots()
		var before := infantry()
		var plan: Node3D = network.queue_plan(point,&"depot")
		if plan == null: mark("Depot plan refused"); break
		mark("Depot plan %d placed %.1f m from the mine, %.1f m from the first Depot" % [i+2,point.distance_to(mine.global_position),point.distance_to(depot.global_position)])
		await haul_and_build(builder,plan,mine)
		await until(func(): return infantry().size() > before.size(),60.0)
		var fresh := fresh_of(before,infantry())
		if beside == null: beside = fresh_of(existing,depots())
		mark("Depot %d built; Infantry now %d · first Depot %s" % [i+2,infantry().size(),stock(depot)])
		builder.command_gather(mine)
		if fresh == null: break
		builder = fresh
	var crew := infantry()
	for unit in crew: unit.command_gather(mine)
	# Mining with a Depot beside the mine: iron per Infantry.
	await wait(10.0)
	var iron := 0
	for local in depots(): iron += local.iron
	var begin := t
	await wait(60.0)
	var total := 0
	for local in depots(): total += local.iron
	mark("mining beside a Depot: %d Infantry delivered %d iron in %.0f s -> %.1f iron a minute each" % [crew.size(),total-iron,t-begin,(total-iron)*60.0/(t-begin)/crew.size()])
	if beside == null or crew.size() < 3: return
	# Generator at the first Depot (its energy pays). Two Infantry then cut wood for it; the rest mine.
	var generator := await fetch_and_build(&"generator",find_site(&"generator",depot.global_position,depot,10.0),crew[1],truck,"energy_generators")
	mark("Generator built · %s" % stock(depot))
	cut_wood(crew[1],depot,func(): return done)
	cut_wood(crew[2],depot,func(): return done)
	# The truck shuttles iron from the Depot beside the mine to the first Depot, four crates a trip.
	var shuttle := func():
		truck.order_queue.clear()
		truck.manifest = {&"iron": 4}
		truck.trips = "repeat"
		truck.run_order({kind = "load", target = beside, point = beside.global_position, requires_target = true})
		truck.queue_order({kind = "unload", target = depot, point = depot.global_position})
	shuttle.call()
	await until(func(): return depot.iron >= 45 and depot.energy >= 100,600.0)
	var barracks := await fetch_and_build(&"barracks",find_site(&"barracks",depot.global_position,depot,12.0),crew[0],truck,"production_buildings")
	mark("Barracks built · %s" % stock(depot))
	crew[0].command_gather(mine)
	shuttle.call()
	for n in range(2):
		await until(func(): return depot.iron >= 20 and depot.energy >= 100,600.0)
		var before := infantry()
		barracks.request_unit(&"infantry")
		await until(func(): return infantry().size() > before.size(),120.0)
		var recruit := fresh_of(before,infantry())
		mark("Barracks Infantry %d out; Infantry now %d · %s" % [n+1,infantry().size(),stock(depot)])
		if recruit != null: recruit.command_gather(mine)
	await until(func(): return (depot.iron >= 65 and depot.energy >= 200) or t >= limit,900.0)
	if t < limit:
		var factory := await fetch_and_build(&"tank_factory",find_site(&"tank_factory",depot.global_position,depot,14.0),crew[0],truck,"production_buildings")
		mark("Tank Factory built · %s" % stock(depot))
		crew[0].command_gather(mine)
		shuttle.call()
		await until(func(): return (depot.iron >= 35 and depot.energy >= 150) or t >= limit,900.0)
		if t < limit and alive(factory):
			var units := player_units()
			factory.request_unit(&"tank")
			await until(func(): return player_units().size() > units.size(),120.0)
			var tank := fresh_of(units,player_units())
			mark("Tank out with %.0f coal of %.0f%s · %s" % [tank.fuel,tank.fuel_rules.reserve_capacity," · it cannot move" if tank.fuel < 1 else "",stock(depot)])
	await until(func(): return t >= limit,limit)
	mark("Generator at the end: %s" % (generator.state if alive(generator) else "gone"))
	sample()
