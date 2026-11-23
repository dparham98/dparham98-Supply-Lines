extends Node
## The enemy player (docs/ENEMY_AI.md). It plays its side with the same orders the player gives: workers gather
## iron, wood and coal for its Depot and put up a Generator, Barracks, Coal Mine and Tank Factory from plans; its
## buildings keep producing; its army defends the base and, from `first_wave_seconds`, attacks in waves that grow.
## It sees by the same fog of war as the player (docs/FOG_OF_WAR.md): the map, its own things, and what its units see
## or have seen. It remembers the other side's buildings it has seen, and scouts the start sites it has not.
@export var team := "enemy"
@export var opponent := "player"
## Seconds between decisions.
@export_range(0.2,5,0.1) var think_seconds := 1.0
## What it builds, in order. Each waits for the one before to be finished.
@export var build_order: Array[StringName] = [&"generator",&"barracks",&"coal_mine",&"tank_factory",&"generator"]
## Infantry kept on gathering and building; the Barracks makes these before anything else.
@export_range(0,20) var workers_wanted := 4
## What each building makes, in turn, once there are workers enough.
@export var barracks_mix: Array[StringName] = [&"scout",&"infantry",&"grenadier",&"infantry",&"grenadier"]
@export var factory_mix: Array[StringName] = [&"tank",&"motorcycle",&"tank",&"drone",&"ubermech"]
## Units queued at once in each building.
@export_range(1,5) var queue_depth := 2
## No wave goes before this many seconds of play, nor with fewer units than `first_wave_size`. Each later wave
## waits for `wave_growth` more units than the last one had.
@export_range(0,3600,10) var first_wave_seconds := 480.0
@export_range(1,50) var first_wave_size := 6
@export_range(1,20) var wave_growth := 2
## Enemies seen this close to one of its buildings draw the army home.
@export_range(0,200,1) var defend_radius := 60.0
## Where the army waits: this far from the Depot toward the middle of the map.
@export_range(0,100,1) var rally_distance := 24.0
## Gathering reaches this far from the Depot, and coal mines are planned no further away.
@export_range(10,250,1) var reach := 90.0
## Stock it gathers toward before it turns the workers to iron: wood for its Generators, coal for vehicle fuel.
@export_range(0,2000,10) var wood_wanted := 120
@export_range(0,2000,10) var coal_wanted := 150
## Iron enough that every worker not on coal turns to wood while the Generators lack it.
@export_range(0,5000,10) var iron_plenty := 250

var elapsed := 0.0
var waves_sent := 0
var last_wave := 0
var workers: Array[Node3D] = []
var army: Array[Node3D] = []
var wave: Array[Node3D] = []
var scout: Node3D
## The plan it is putting up now, and which step of `build_order` that is.
var plan: Node3D
var build_step := 0
## The other side's buildings and sites it has seen: instance id -> where.
var known := {}
var defeated := false
var _left := 0.0
var _mix_at := {}
var _home: Node3D
var _home_at: Variant = null
@onready var game = get_tree().get_first_node_in_group("skirmish")
@onready var ground = get_tree().get_first_node_in_group("terrain_grid")
@onready var network = game.get_node("DepotNetwork")

func _process(delta: float) -> void:
	elapsed += delta
	_left -= delta
	if _left > 0.0 or defeated: return
	_left = think_seconds
	think()

## One decision round. Also called by tests.
func think() -> void:
	var depot := home()
	var units := own_units()
	remember()
	if depot == null:
		_redeploy(units)
		if units.is_empty() and own_buildings().is_empty(): _beaten()
		return
	_sort(units)
	build(depot)
	gather(depot)
	produce(depot)
	fight(depot)

# --- What it knows -------------------------------------------------------------------------------------------------

func fog() -> Node:
	return game.fog_of_war() if game.has_method("fog_of_war") else null
## Whether it sees `point` now. With no fog on the map it sees everything.
func sees(point: Vector3) -> bool:
	var f := fog()
	return f == null or f.visible_to(team,point)
func explored(point: Vector3) -> bool:
	var f := fog()
	return f == null or f.explored_by(team,point)
## Its home Depot: the one it has had, while that stands and is its own; else the nearest of its others to it.
func home() -> Node3D:
	if _own_depot(_home): return _home
	var from: Vector3 = _home_at if _home_at != null else Vector3.ZERO
	var best: Node3D
	for depot in get_tree().get_nodes_in_group("depots"):
		if not _own_depot(depot): continue
		if _home_at == null or best == null or depot.global_position.distance_to(from) < best.global_position.distance_to(from): best = depot
		if _home_at == null: break
	_home = best
	if best != null: _home_at = best.global_position
	return best
func _own_depot(depot) -> bool:
	return is_instance_valid(depot) and depot.team == team and depot.health > 0 and not depot.is_queued_for_deletion()
func own_units() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.team == team and unit.health > 0 and not unit.is_queued_for_deletion(): result.append(unit)
	return result
func own_buildings() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for building in get_tree().get_nodes_in_group("selectable_buildings"):
		if building.get("team") == team and building.get("health") != null and building.health > 0: result.append(building)
	return result
## Remembers the other side's buildings and sites when it sees them, and forgets one when it sees it is gone.
func remember() -> void:
	for group in ["selectable_buildings","construction_plans"]:
		for node in get_tree().get_nodes_in_group(group):
			if node.get("team") != opponent or node.is_queued_for_deletion(): continue
			if node.get("health") != null and node.health <= 0: continue
			if sees(node.global_position): known[node.get_instance_id()] = node.global_position
	for id in known.keys():
		var node = instance_from_id(id)
		var gone: bool = node == null or not is_instance_valid(node) or node.is_queued_for_deletion() or (node.get("health") != null and node.health <= 0)
		if gone and sees(known[id]): known.erase(id)
## Its units by job: workers gather and build, one Scout scouts, the rest are the army.
func _sort(units: Array[Node3D]) -> void:
	# Units killed since the last round are freed: check that first, before looking them up.
	var alive := func(unit) -> bool: return is_instance_valid(unit) and units.has(unit)
	workers = workers.filter(alive)
	army = army.filter(alive)
	wave = wave.filter(alive)
	if not alive.call(scout): scout = null
	for unit in units:
		if workers.has(unit) or army.has(unit) or unit == scout: continue
		if unit.is_depot_truck or unit.is_cargo_vehicle: continue
		var id = unit.unit_stats.unit_id if unit.unit_stats != null else &""
		if id == &"infantry" and workers.size() < workers_wanted: workers.append(unit)
		elif id == &"scout" and scout == null: scout = unit
		else: army.append(unit)
func _cargo_truck() -> Node3D:
	for unit in own_units():
		if unit.is_cargo_vehicle and not unit.is_in_group("rail_trains"): return unit
	return null
func _idle(unit: Node3D) -> bool:
	return unit.order == "idle" or unit.order == ""

# --- Building -------------------------------------------------------------------------------------------------------

## Puts up `build_order` one plan at a time: places the plan, sends the Cargo truck for its iron, and sets up to two
## workers on it.
func build(depot: Node3D) -> void:
	_park_truck(depot)
	if not is_instance_valid(plan) or plan.finished:
		plan = null
		if build_step >= build_order.size(): return
		var kind: StringName = build_order[build_step]
		var spec: Dictionary = network.plan_spec(kind)
		if spec.is_empty(): build_step += 1; return
		if depot.iron < spec.iron or depot.energy < spec.energy: return
		var point = coal_site(depot) if kind == &"coal_mine" else building_site(depot,spec.size)
		if point == null: build_step += 1; return
		var mine: bool = network.is_mine_kind(kind)
		plan = network.queue_plan(point,kind,null if mine else depot,not mine,true,team)
		if plan == null: build_step += 1; return
		plan.tree_exiting.connect(_plan_gone.bind(plan))
	var truck := _cargo_truck()
	if truck != null and plan.shortfall(&"iron") > 0 and _idle(truck) and truck.get("fetch_plan") == null: truck.command_fetch(plan)
	# Builders go once the iron is on site; a mine out in the woods gets one early, to fell its way in.
	var builders := workers.filter(func(unit): return unit.order == "construct" and unit.order_target == plan).size()
	var room := 2 if plan.materials_covered() else (1 if network.is_mine_kind(plan.kind) else 0)
	for unit in workers:
		if builders >= room: break
		if unit.order == "construct": continue
		if unit.cargo > 0 and unit.cargo_kind != &"iron": continue
		unit.command_construct(plan)
		builders += 1
## An idle Cargo truck away from home drives back beside the Depot, out of the way: a truck left in a lane felled to
## a mine walls the workers in.
func _park_truck(depot: Node3D) -> void:
	var truck := _cargo_truck()
	if truck == null or not _idle(truck) or truck.get("fetch_plan") != null: return
	var spot := depot.global_position+Vector3(-10.0*signf(depot.global_position.x),0,4)
	if truck.global_position.distance_to(spot) > 8.0: truck.command_move(spot)
## A finished plan moves on to the next step; one that is lost (cancelled, destroyed) is tried again.
func _plan_gone(gone: Node3D) -> void:
	if gone.finished: build_step += 1
	if plan == gone: plan = null
## A spot in the Depot's range for a building of `size`, with room round it to walk, off the way to its home mine.
func building_site(depot: Node3D, size: Vector2i) -> Variant:
	var centre := depot.global_position
	var mine := _nearest_mine(centre,&"iron")
	var radius: float = SupplySource.radius(depot)
	var middle := signf(-centre.x) if absf(centre.x) > 1.0 else 1.0
	var margin := Vector2i(2,2)
	for r in range(10,int(radius)+1,2):
		for step in range(24):
			# Toward the middle of the map first, then round both ways.
			var turn := (step+1)/2*(1 if step%2 == 0 else -1)*TAU/24
			var point := centre+Vector3(cos(turn)*middle,0,sin(turn))*r
			var start: Vector2i = network.footprint_start(point,size)
			if start.x < 0 or not network.range_covers_footprint(depot,start,size): continue
			if not ground.is_footprint_valid(start-margin,size+margin*2): continue
			if not network.plan_terrain_valid(start,size,&"barracks") or network.plan_overlaps(start-margin,size+margin*2): continue
			if mine != null and _off_way(point,centre,mine.global_position) < maxf(size.x,size.y)*0.5+4.0: continue
			return ground.tile_to_world(start+size/2)
	return null
## How far `point` is from the way between two places.
func _off_way(point: Vector3, from: Vector3, to: Vector3) -> float:
	var a := Vector2(from.x,from.z); var b := Vector2(to.x,to.z); var p := Vector2(point.x,point.z)
	var t := clampf((p-a).dot(b-a)/maxf((b-a).length_squared(),0.001),0.0,1.0)
	return p.distance_to(a+(b-a)*t)
## A 2 x 2 footprint on the nearest coal seam that has no mine and no plan, within `reach`.
func coal_site(depot: Node3D) -> Variant:
	var size: Vector2i = network.engineering_rules.mine_footprint
	var best: Variant = null
	var best_distance := reach
	for field in ground.coal_fields:
		var cells: Array = field.get("cells",[])
		if cells.is_empty(): continue
		var centre: Vector3 = field.get("center",ground.tile_to_world(cells[0]))
		if depot.global_position.distance_to(centre) > best_distance+20.0: continue
		var taken := false
		for cell in cells:
			if ground.coal_mine_at(cell) != null: taken = true; break
		if taken: continue
		for cell in cells:
			var point: Vector3 = ground.tile_to_world(cell+size/2)
			var distance := depot.global_position.distance_to(point)
			if distance >= best_distance: continue
			if not network.plan_terrain_valid(cell,size,&"coal_mine") or network.plan_overlaps(cell,size): continue
			best = point; best_distance = distance
	return best

# --- Gathering ------------------------------------------------------------------------------------------------------

## Shares the workers out by need each round: iron while the next building is short of it, one on wood while the
## Generators want fuel, one on coal once it has a coal mine; the rest on iron. Builders are left building.
func gather(depot: Node3D) -> void:
	var free: Array[Node3D] = workers.filter(func(unit): return unit.order != "construct")
	var coal := _nearest_mine(depot.global_position,&"coal")
	var iron := _nearest_mine(depot.global_position,&"iron")
	var wanted := {&"coal":0,&"wood":0}
	var short: bool = depot.iron < _iron_needed()
	if coal != null and depot.coal < coal_wanted and (free.size() > 1 or not short): wanted[&"coal"] = 1
	if depot.wood < wood_wanted and (free.size() > wanted[&"coal"]+1 or not short): wanted[&"wood"] = 1
	# With iron to spare the Generators are what hold production back: the rest cut wood.
	if depot.iron >= iron_plenty and depot.wood < wood_wanted: wanted[&"wood"] = free.size()-wanted[&"coal"]
	if iron == null: wanted[&"wood"] = free.size()-wanted[&"coal"]
	wanted[&"iron"] = free.size()-wanted[&"coal"]-wanted[&"wood"]
	var on := {&"coal":0,&"wood":0,&"iron":0}
	var spare: Array[Node3D] = []
	for unit in free:
		var kind := _working(unit)
		if kind == &"": spare.append(unit); continue
		if on.get(kind,0) >= wanted.get(kind,0): spare.append(unit); continue
		on[kind] = on.get(kind,0)+1
	for unit in spare:
		var source: Node3D
		if on[&"coal"] < wanted[&"coal"]: source = coal; on[&"coal"] += 1
		elif on[&"wood"] < wanted[&"wood"]: source = forest_near(depot); on[&"wood"] += 1
		if source == null: source = iron
		if source != null and _working(unit) != source.resource_kind: unit.command_gather(source)
## Iron kept back from production: what the site being built still lacks, less what the truck carries to it, or
## the next building's.
func _iron_held() -> int:
	if is_instance_valid(plan):
		var truck := _cargo_truck()
		var aboard: int = truck.cargo_units(&"iron") if truck != null and truck.get("fetch_plan") == plan else 0
		return maxi(0,plan.shortfall(&"iron")-aboard)
	if build_step >= build_order.size(): return 0
	return network.plan_spec(build_order[build_step]).get("iron",0)
## Iron the Depot should hold before it turns workers away from iron: the next building's, and a unit's.
func _iron_needed() -> int:
	var next: Dictionary = network.plan_spec(build_order[build_step]) if build_step < build_order.size() else {}
	return next.get("iron",0)+20
## What a worker is gathering, or "" when it is not.
func _working(unit: Node3D) -> StringName:
	if not unit.order in ["gather","return"]: return &""
	var source = unit.get("source")
	return source.resource_kind if is_instance_valid(source) else unit.cargo_kind
func _nearest_mine(point: Vector3, kind: StringName) -> Node3D:
	var best: Node3D
	var best_distance := reach
	for mine in get_tree().get_nodes_in_group("mines"):
		if mine.resource_kind != kind or mine.health <= 0 or mine.remaining <= 0: continue
		var distance := point.distance_to(mine.global_position)
		if distance < best_distance: best = mine; best_distance = distance
	return best
## The nearest Forest cell to the Depot, as a source to cut.
func forest_near(depot: Node3D) -> Node3D:
	var centre = ground.get_tile_at_position(depot.global_position)
	if centre == null: return null
	var cells := int(reach/ground.tile_size)
	for r in range(6,cells):
		for dx in range(-r,r+1):
			for dz in [-r,r]:
				for cell in [Vector2i(centre.x+dx,centre.y+dz),Vector2i(centre.x+dz,centre.y+dx)]:
					if ground.forest_amount(cell) > 0: return ground.forest_source(cell)
	return null

# --- Production -----------------------------------------------------------------------------------------------------

## Keeps every building's queue filled: workers first, then its mix in turn. Units other than workers leave the
## iron the next building needs.
func produce(depot: Node3D) -> void:
	var held := _iron_held()
	var buildings := get_tree().get_nodes_in_group("production_buildings").filter(func(node): return node.team == team and node.source_friendly())
	var wanted := workers_wanted-workers.size()
	for building in buildings:
		for scene in building.pending:
			if building.unit_stats_for(scene).unit_id == &"infantry": wanted -= 1
	for building in buildings:
		if building.queue >= queue_depth: continue
		var key: int = building.get_instance_id()
		var worker: bool = wanted > 0 and _makes(building,&"infantry")
		var id: StringName = &"infantry" if worker else _next_in_mix(building)
		if id == &"": continue
		var stats: UnitStats = _stats(building,id)
		var source: Node3D = building.assigned_depot
		if source.energy < stats.energy_cost or source.iron-stats.iron_cost < (0 if worker else held): continue
		if not building.request_unit(id): continue
		if worker: wanted -= 1
		else: _mix_at[key] = _mix_at.get(key,0)+1
## The next unit of the building's mix it makes, skipping a second Scout.
func _next_in_mix(building: Node3D) -> StringName:
	var mix: Array[StringName] = barracks_mix if _makes(building,&"infantry") else factory_mix
	var key: int = building.get_instance_id()
	for tries in range(mix.size()):
		var choice: StringName = mix[_mix_at.get(key,0)%mix.size()]
		if _makes(building,choice) and (choice != &"scout" or scout == null): return choice
		_mix_at[key] = _mix_at.get(key,0)+1
	return &""
func _makes(building: Node3D, id: StringName) -> bool:
	return _stats(building,id) != null
func _stats(building: Node3D, id: StringName) -> UnitStats:
	for scene in building.stats.unit_scenes:
		var stats: UnitStats = building.unit_stats_for(scene)
		if stats.unit_id == id: return stats
	return null

# --- Fighting -------------------------------------------------------------------------------------------------------

## Defends what it holds, gathers the army at its rally point, and sends waves.
func fight(depot: Node3D) -> void:
	_scout()
	var threat := _threat()
	if threat != null:
		for unit in army:
			if wave.has(unit) and unit.global_position.distance_to(depot.global_position) > defend_radius*2.0: continue
			if unit.order == "attack": continue
			if unit.order == "attack_move" and unit.move_goal.distance_to(threat.global_position) < 15.0: continue
			unit.command_attack_move(threat.global_position)
		return
	# A wave presses on to the next target it knows of; one with nothing left to find, or down to its last unit,
	# comes home and joins the next.
	if not wave.is_empty():
		var target = wave_target(_centre(wave))
		if target == null or wave.size() <= 1: wave.clear()
		else:
			for unit in wave:
				if _idle(unit): unit.command_attack_move(target)
	var rally := rally_point(depot)
	for unit in army:
		if not wave.has(unit) and _idle(unit) and unit.global_position.distance_to(rally) > 14.0:
			unit.command_move(rally+Vector3(randf_range(-6,6),0,randf_range(-6,6)))
	if wave.is_empty() and elapsed >= first_wave_seconds and army.size() >= next_wave_size():
		var target = wave_target(rally)
		if target == null: return
		wave = army.duplicate()
		last_wave = wave.size(); waves_sent += 1
		for unit in wave: unit.command_attack_move(target)
## How many units the next wave needs.
func next_wave_size() -> int:
	return first_wave_size if waves_sent == 0 else maxi(first_wave_size,last_wave+wave_growth)
## The nearest of the other side's things it sees near its own buildings, or null.
func _threat() -> Node3D:
	var mine := own_buildings()
	var best: Node3D
	var best_distance := defend_radius
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.team != opponent or unit.health <= 0 or not sees(unit.global_position): continue
		for building in mine:
			var distance: float = unit.global_position.distance_to(building.global_position)
			if distance < best_distance: best = unit; best_distance = distance
	return best
func rally_point(depot: Node3D) -> Vector3:
	var middle := signf(-depot.global_position.x) if absf(depot.global_position.x) > 1.0 else 1.0
	return depot.global_position+Vector3(rally_distance*middle,0,0)
## Where a wave goes: the nearest of the other side's buildings it remembers, else the nearest start site it has
## not yet seen. Null when it knows of nothing to attack and has seen every start.
func wave_target(from: Vector3) -> Variant:
	var best: Variant = null
	var best_distance := INF
	for id in known:
		var distance := from.distance_to(known[id])
		if distance < best_distance: best = known[id]; best_distance = distance
	return best if best != null else unseen_start(from)
func unseen_start(from: Vector3) -> Variant:
	var sites := game.get_node_or_null("Sites")
	if sites == null: return null
	var best: Variant = null
	var best_distance := INF
	for site in sites.get_children():
		if not site is Node3D or explored(site.global_position): continue
		var distance := from.distance_to(site.global_position)
		if distance < best_distance: best = site.global_position; best_distance = distance
	return best
## The Scout looks at the start sites it has not seen, nearest first, then waits by the army.
func _scout() -> void:
	if scout == null or not _idle(scout): return
	var target = unseen_start(scout.global_position)
	if target != null: scout.command_move(target)
func _centre(units: Array[Node3D]) -> Vector3:
	var total := Vector3.ZERO
	for unit in units: total += unit.global_position
	return total/maxf(units.size(),1)

# --- Losing ---------------------------------------------------------------------------------------------------------

## A Depot Truck with no Depot left deploys where it stands, or as near as it can.
func _redeploy(units: Array[Node3D]) -> void:
	for unit in units:
		if not unit.is_depot_truck or unit.order == "deploy": continue
		var here = ground.get_tile_at_position(unit.global_position)
		if here == null: continue
		for r in range(0,12):
			for dx in range(-r,r+1):
				for dz in range(-r,r+1):
					if maxi(absi(dx),absi(dz)) != r: continue
					var point: Vector3 = ground.tile_to_world(here+Vector2i(dx,dz)*2)
					if network.can_deploy_at(unit,point): unit.command_deploy_at(point); return
## Nothing left: the player has won.
func _beaten() -> void:
	defeated = true
	if game.outcome.is_empty(): game.outcome = "VICTORY — the enemy has nothing left."
