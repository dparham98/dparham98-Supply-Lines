extends Node
## The enemy player (docs/ENEMY_AI.md). It plays its side with the same orders the player gives: workers gather
## iron, wood and coal for its Depot and put up a Generator, Barracks, Coal Mine, Tank Factory and Temple of Science
## from plans; its buildings keep producing; its army defends the base and, from `first_wave_seconds`, attacks in
## waves that grow. It expands: Depot Trucks set up Depots by other iron mines, where workers of their own gather,
## and track joins each to home with a train hauling the iron back. Once the Temple has researched Mining Trains,
## track runs to another mine and a train mines it. Workers repair what is damaged.
## It sees by the same fog of war as the player (docs/FOG_OF_WAR.md): the map, its own things, and what its units see
## or have seen. It remembers the other side's buildings it has seen, and scouts the start sites it has not.
@export var team := "enemy"
@export var opponent := "player"
## Seconds between decisions.
@export_range(0.2,5,0.1) var think_seconds := 1.0
## What it builds at home, in order. Each waits for the one before to be finished.
## Two Barracks before tech (docs/BALANCE_IMPLEMENTATION_HANDOFF.md, item 5): tech first lost to it. The Temple of
## Science comes after the Tank Factory, for Mining Trains and Minelaying; the Foundry goes last, for attack and armour
## upgrades (docs/UPGRADES.md).
@export var build_order: Array[StringName] = [&"generator",&"barracks",&"generator",&"barracks",&"generator",&"coal_mine",&"tank_factory",&"temple_of_science",&"generator",&"foundry"]
## Once `build_order` is done, it keeps adding Generators, up to this many in all, while it holds `iron_plenty`.
## Energy, not iron, is what holds it back once it has expanded.
@export_range(0,20) var generators_wanted := 6
@export_group("Expansion")
## Depots it sets up beside other iron mines, one at a time, each by a Depot Truck from home.
@export_range(0,6) var expansions_wanted := 2
## The first Depot Truck waits until this many steps of `build_order` are done.
@export_range(0,20) var expand_after := 3
## Mines further than this from home are not expanded to, nor mined by train.
@export_range(30,400,5) var expand_reach := 170.0
## Workers kept gathering iron at each expansion, on top of `workers_wanted` at home.
@export_range(0,10) var expansion_workers := 2
## Track joins each expansion to home, and a train hauls its iron home.
@export var haul_trains := true
## The Temple researches Mining Trains; then track runs from home to another mine and a train mines it.
@export var mining_trains := true
## Haul trains wait while home holds this much iron or has less room than `haul_room`: a Depot's stock shares one
## store, and a home full of iron leaves its Generators no room to bank energy.
@export_range(0,5000,50) var haul_iron_cap := 800
@export_range(0,2000,50) var haul_room := 400
## Microseconds a frame spent looking for track, so a long search does not hold the frame up.
@export_range(500,20000,100) var link_usec := 2000
@export_group("Repair")
## Own buildings below this share of their health are repaired, when no enemy is near them.
@export_range(0.0,1.0,0.05) var repair_below := 0.75
## Workers repairing at once.
@export_range(0,10) var repairers := 2
@export_group("Mines")
## Once it has a Derailer, the Temple researches Minelaying (after Mining Trains), and Derailers waiting at the rally
## point lay mines across the way the other side would come (docs/MINES.md).
@export var minelaying := true
## Its own mines it keeps laid at once.
@export_range(0,30) var mines_wanted := 6
## How far out from home, toward the other side, the row of mines goes (metres).
@export_range(10,200,1) var mine_distance := 45.0
## Metres between mines along the row.
@export_range(1,20,0.5) var mine_spacing := 5.0
@export_group("Upgrades")
## It researches attack and armour upgrades (docs/UPGRADES.md) at its Foundry, or the Knights at their Forge, level
## by level across `upgrade_lines`, once its army has `upgrades_army` units.
@export var upgrades := true
@export var upgrade_lines: Array[StringName] = [&"infantry_weapons",&"vehicle_weapons",&"infantry_armour",&"vehicle_armour"]
@export_range(0,100) var upgrades_army := 6
@export_group("")
## Infantry kept on gathering and building; the Barracks makes these before anything else.
@export_range(0,20) var workers_wanted := 6
## What each building makes, in turn, once there are workers enough.
@export var barracks_mix: Array[StringName] = [&"scout",&"infantry",&"grenadier",&"infantry",&"grenadier"]
@export var factory_mix: Array[StringName] = [&"tank",&"motorcycle",&"tank",&"drone",&"ubermech"]
## A Drone is unarmed and outruns the army, so it is kept over the centre of the ground units it goes with,
## moved back whenever it strays further than this (metres).
@export_range(1,30) var drone_escort_radius := 6.0
## Units queued at once in each building.
@export_range(1,5) var queue_depth := 3
## No wave goes before this many seconds of play, nor with fewer units than `first_wave_size`. Each later wave
## waits for `wave_growth` more units than the last one had.
@export_range(0,3600,10) var first_wave_seconds := 480.0
@export_range(1,50) var first_wave_size := 6
@export_range(1,20) var wave_growth := 2
## Enemies seen this close to one of its buildings draw the army home.
@export_range(0,200,1) var defend_radius := 60.0
## Where the army waits: this far from the Depot toward the middle of the map. Kept inside the Depot's range, so
## its vehicles refuel while they wait.
@export_range(0,100,1) var rally_distance := 18.0
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
## Where the Depot Truck out now is to set up the next expansion, or null.
var expansion_site: Variant = null
## Track laid by purpose: {from, to, purpose ("haul" or "mine"), pieces}.
var links: Array[Dictionary] = []
## The mine its mining train works, once the research is done and track reaches it.
var mining_mine: Node3D
## What it is saving for this round: {truck, train, research, rail} -> true or the iron. Units for the army leave
## the Depot what these need.
var wants := {}
var _left := 0.0
var _mix_at := {}
var _home: Node3D
var _home_at: Variant = null
## Worker instance id -> the Depot it gathers for.
var _bases := {}
## The track search under way: {job, from, to, purpose}, or empty.
var _search := {}
## Pairs it found no track for, so it does not search for them again: "from id:to id" -> true.
var _no_path := {}
## Derailer instance id -> the point it was sent to lay a mine; points it could not reach, so it does not try again.
var _laying := {}
var _bad_mine_spots: Array[Vector3] = []
## Where its row of mines faces, fixed the first time it knows of somewhere to attack, so the row stays put.
var _mine_toward: Variant = null
@onready var game = get_tree().get_first_node_in_group("skirmish")
@onready var ground = get_tree().get_first_node_in_group("terrain_grid")
@onready var network = game.get_node("DepotNetwork")
@onready var rails = game.get_node_or_null("RailNetwork")

func _process(delta: float) -> void:
	elapsed += delta
	_left -= delta
	if not _search.is_empty() and not _search.job.done: rails.advance_link(_search.job,link_usec)
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
	wants = {}
	build(depot)
	expand(depot)
	rail(depot)
	research()
	run_trains(depot)
	gather(depot)
	repair()
	produce(depot)
	lay_mines(depot)
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
		if id == &"infantry" and workers.size() < workers_total(): workers.append(unit); _assign_base(unit)
		elif id == &"scout" and scout == null: scout = unit
		else: army.append(unit)
## Its expansions within `expand_reach` of home: the ones track joins to home. A Depot it captured further away is
## left to stand alone.
func outposts(depot: Node3D) -> Array[Node3D]:
	return expansions().filter(func(outpost): return outpost.global_position.distance_to(depot.global_position) <= expand_reach)
## Its Depots other than home.
func expansions() -> Array[Node3D]:
	var result: Array[Node3D] = []
	var depot := home()
	for node in get_tree().get_nodes_in_group("depots"):
		if node != depot and _own_depot(node): result.append(node)
	return result
## Workers it keeps: `workers_wanted` at home and `expansion_workers` at each expansion.
func workers_total() -> int:
	return workers_wanted+expansion_workers*expansions().size()
## The Depot a worker gathers for: the one it was given while that stands, else home.
func base_of(unit: Node3D) -> Node3D:
	var depot = _bases.get(unit.get_instance_id())
	return depot if _own_depot(depot) else home()
func _workers_at(depot: Node3D) -> Array[Node3D]:
	return workers.filter(func(unit): return base_of(unit) == depot)
## A new worker goes to the Depot most short of workers, the nearest of those equally short.
func _assign_base(unit: Node3D) -> void:
	var best: Node3D
	var best_short := -INF
	for depot in [home()]+expansions():
		var short: int = (workers_wanted if depot == home() else expansion_workers)-_workers_at(depot).size()
		if short > best_short or (short == best_short and depot.global_position.distance_to(unit.global_position) < best.global_position.distance_to(unit.global_position)):
			best = depot; best_short = short
	_bases[unit.get_instance_id()] = best
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
		var kind := next_building()
		if kind == &"": return
		var spec: Dictionary = network.plan_spec(kind)
		if spec.is_empty(): build_step += 1; return
		if depot.iron < spec.iron or depot.energy < spec.energy: return
		# Buildings go up at home; a Generator with no room left there goes up at an expansion.
		var payer := depot
		var point = coal_site(depot) if kind == &"coal_mine" else building_site(depot,spec.size)
		if point == null and kind == &"generator":
			for outpost in expansions():
				if outpost.global_position.distance_to(depot.global_position) > expand_reach: continue
				point = building_site(outpost,spec.size)
				if point != null: payer = outpost; break
		if point == null: build_step += 1; return
		var mine: bool = network.is_mine_kind(kind)
		# A site it cannot see yet is planned as the player plans a Cargo truck's Worksite, which needs no sight:
		# the truck drives out to it with the iron (docs/HUD_POLISH.md, Plans need sight).
		var size: Vector2i = spec.size
		var seen: bool = network.in_sight(network.footprint_start(point,size),size,team)
		plan = network.queue_plan(point,kind,null if mine else payer,not mine,seen,team)
		if plan == null: build_step += 1; return
		plan.tree_exiting.connect(_plan_gone.bind(plan))
	# Track laid across the site after it was planned (the other side's, say) would leave it waiting for good: it is
	# given up and planned again elsewhere. Iron already on the site stays there as piles (docs/ENEMY_AI.md).
	if track_on(plan):
		_given_up = plan
		plan = null
		_given_up.cancel()
		return
	var truck := _cargo_truck()
	# Only the Cargo truck takes iron out to a site: one that is lost (shot on the way, say) is replaced, or the site
	# would wait for its iron for good (docs/ENEMY_AI.md).
	if truck == null and plan.shortfall(&"iron") > 0: _replace_truck(depot)
	if truck != null and plan.shortfall(&"iron") > 0 and _idle(truck) and truck.get("fetch_plan") == null: truck.command_fetch(plan)
	# Builders go once the iron is on site; a mine out in the woods gets one early, to fell its way in.
	var home_workers := _workers_at(depot)
	var builders := home_workers.filter(func(unit): return unit.order == "construct" and unit.order_target == plan).size()
	var room := 2 if plan.materials_covered() else (1 if network.is_mine_kind(plan.kind) else 0)
	for unit in home_workers:
		if builders >= room: break
		if unit.order in ["construct","repair"]: continue
		if unit.cargo > 0 and unit.cargo_kind != &"iron": continue
		unit.command_construct(plan)
		builders += 1
## Prints a Cargo truck at home when none is on its way, saving up for it first (held_back).
func _replace_truck(depot: Node3D) -> void:
	if depot.pending.has("cargo"): return
	if depot.request_cargo(): return
	wants["cargo"] = true
## What it builds next: the next step of `build_order`, then more Generators while iron piles up; &"" for none.
func next_building() -> StringName:
	if build_step < build_order.size(): return build_order[build_step]
	var depot := home()
	if depot == null or depot.iron < iron_plenty: return &""
	var generators := get_tree().get_nodes_in_group("energy_generators").filter(func(node): return node.get("team") == team and node.get("health") != null and node.health > 0).size()
	return &"generator" if generators < generators_wanted else &""
## An idle Cargo truck away from home drives back beside the Depot, out of the way: a truck left in a lane felled to
## a mine walls the workers in.
func _park_truck(depot: Node3D) -> void:
	var truck := _cargo_truck()
	if truck == null or not _idle(truck) or truck.get("fetch_plan") != null: return
	var spot := depot.global_position+Vector3(-10.0*signf(depot.global_position.x),0,4)
	if truck.global_position.distance_to(spot) > 8.0: truck.command_move(spot)
## A finished plan moves on to the next step; one that is lost (cancelled, destroyed) is tried again.
var _given_up: Node3D
func _plan_gone(gone: Node3D) -> void:
	if gone.finished and gone != _given_up: build_step += 1
	if plan == gone: plan = null
## Whether any track lies on the plan's footprint.
func track_on(site: Node3D) -> bool:
	var ground = game.ground
	for z in range(site.start.y,site.start.y+site.spec.size.y):
		for x in range(site.start.x,site.start.x+site.spec.size.x):
			var cell := Vector2i(x,z)
			if ground.is_tile_in_bounds(cell) and ground.tiles[z*ground.grid_size.x+x].has("rail"): return true
	return false
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

## Shares the home workers out by need each round: iron while the next building is short of it, one on wood while
## the Generators want fuel, one on coal once it has a coal mine; the rest on iron. Builders and repairers are left
## at it. Each expansion's workers gather iron at the mine nearest their Depot.
func gather(depot: Node3D) -> void:
	for outpost in expansions():
		var mine := _nearest_mine(outpost.global_position,&"iron")
		if mine == null: continue
		for unit in _workers_at(outpost):
			if unit.order in ["construct","repair"]: continue
			if _working(unit) != &"iron" or (unit.order == "gather" and unit.get("source") != mine): unit.command_gather(mine)
	var free: Array[Node3D] = _workers_at(depot).filter(func(unit): return not unit.order in ["construct","repair"])
	var coal := _nearest_mine(depot.global_position,&"coal")
	var iron := _nearest_mine(depot.global_position,&"iron")
	var wanted := {&"coal":0,&"wood":0}
	var short: bool = depot.iron < _iron_needed()
	if coal != null and depot.coal < coal_wanted and (free.size() > 1 or not short): wanted[&"coal"] = 1
	if depot.wood < wood_wanted and (free.size() > wanted[&"coal"]+1 or not short): wanted[&"wood"] = 1
	# With iron to spare the Generators are what hold production back: the rest cut wood.
	# Two stay on iron while a site is up: a worker carrying wood is not sent to build.
	var keep := 2 if is_instance_valid(plan) else 0
	if (depot.iron >= iron_plenty and depot.wood < wood_wanted) or (depot.iron >= haul_iron_cap and depot.wood < wood_wanted*2): wanted[&"wood"] = maxi(0,free.size()-wanted[&"coal"]-keep)
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
## Energy kept back from production: what the site being built has still to pay as it goes up, or the next
## building's, so the army does not starve the builders.
func _energy_held() -> int:
	if is_instance_valid(plan): return maxi(0,int(plan.spec.get("energy",0))-plan.energy_paid)
	var kind := next_building()
	return network.plan_spec(kind).get("energy",0) if kind != &"" else 0
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

# --- Expansion ------------------------------------------------------------------------------------------------------

## Sets up Depots by other iron mines, one at a time: a Depot Truck from home drives to a site beside the mine and
## deploys. The next waits until the last is joined to home by track, when `haul_trains` is on.
func expand(depot: Node3D) -> void:
	var truck := _depot_truck()
	if truck != null:
		if truck.order == "deploy": return
		# New vehicles start with empty tanks and fill at the Depot while they stand: it leaves once full.
		if not fuelled(truck): return
		if expansion_site == null or not network.can_deploy_at(truck,expansion_site): expansion_site = expansion_spot(depot,truck)
		if expansion_site != null: truck.command_deploy_at(expansion_site)
		return
	if outposts(depot).size() >= expansions_wanted or build_step < expand_after or depot.pending.has("truck"): return
	if haul_trains and outposts(depot).any(func(outpost): return not linked(depot,outpost) and not _no_path.has(_pair(depot,outpost))): return
	expansion_site = expansion_spot(depot,null)
	if expansion_site == null: return
	wants.truck = true
	if depot.energy >= depot.rules.truck_energy_cost and depot.iron-_iron_held() >= depot.rules.truck_iron_cost: depot.request_truck()
## Whether a vehicle has the fuel to go out: full, or it uses none. One standing in a Depot's range with coal
## fills up by itself (docs/FUEL_BATCH.md).
func fuelled(unit: Node3D) -> bool:
	if not unit.has_method("fuel_active") or not unit.fuel_active(): return true
	return unit.fuel >= unit.fuel_target()-1.0
func _depot_truck() -> Node3D:
	for unit in own_units():
		if unit.is_depot_truck: return unit
	return null
## Where a Depot may stand beside the nearest iron mine on its own side within `expand_reach` that no Depot of its
## own stands by and the other side is not known to hold: the free spot nearest the mine, toward home. With a truck,
## the truck's own deploy check decides; without one, the same footprint and spacing rules. Null when none.
func expansion_spot(depot: Node3D, truck: Node3D) -> Variant:
	var spacing: float = network.depot_rules().min_depot_spacing()
	for mine in _iron_mines(depot.global_position,expand_reach):
		if mine.global_position.distance_to(depot.global_position) < spacing: continue
		if not _own_side(mine.global_position,depot) or _held_by_opponent(mine.global_position): continue
		if get_tree().get_nodes_in_group("depots").any(func(node): return node.team == team and node.global_position.distance_to(mine.global_position) < 30.0): continue
		var toward: Vector3 = (depot.global_position-mine.global_position).normalized()
		for r in range(8,26,2):
			for step in range(16):
				var turn := (step+1)/2*(1 if step%2 == 0 else -1)*TAU/16
				var point: Vector3 = mine.global_position+toward.rotated(Vector3.UP,turn)*r
				var ok: bool = network.can_deploy_at(truck,point) if truck != null else network.can_place(point,null,true,team)
				if ok: return point
	return null
## Iron mines with iron left within `limit` of `point`, nearest first.
func _iron_mines(point: Vector3, limit: float) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for mine in get_tree().get_nodes_in_group("mines"):
		if mine.resource_kind != &"iron" or mine.health <= 0 or mine.remaining <= 0: continue
		if mine.global_position.distance_to(point) <= limit: result.append(mine)
	result.sort_custom(func(a,b): return a.global_position.distance_to(point) < b.global_position.distance_to(point))
	return result
## Whether `point` is on home's half of the map, east or west of the middle.
func _own_side(point: Vector3, depot: Node3D) -> bool:
	return signf(point.x) == signf(depot.global_position.x) and absf(point.x) > 15.0
## Whether it remembers one of the other side's buildings near `point`.
func _held_by_opponent(point: Vector3) -> bool:
	for id in known:
		if known[id].distance_to(point) < 60.0: return true
	return false

# --- Rail -----------------------------------------------------------------------------------------------------------

## Joins each expansion to home with track and, once Mining Trains is researched, home to a mine for a mining train.
## One search at a time, worked on a little each frame; found track is laid once home has its iron.
func rail(depot: Node3D) -> void:
	if rails == null: return
	if not _search.is_empty():
		if not _search.job.done: return
		if not is_instance_valid(_search.from) or not is_instance_valid(_search.to) or not _search.from.is_inside_tree() or not _search.to.is_inside_tree():
			_search = {}
			return
		var path: Array = _search.job.found.get("path",[])
		if path.is_empty():
			_no_path[_pair(_search.from,_search.to)] = true
			_search = {}
			return
		# A piece the laid track's own cells find blocked (rail_router.gd, forbidden), or ground that changed since
		# the search: search again without those moves rather than lay broken track. Five tries, then no path.
		var unfit: Dictionary = rails.unfit_moves(path)
		if not unfit.is_empty():
			var forbidden: Dictionary = _search.get("forbidden",{})
			forbidden.merge(unfit)
			var tries: int = _search.get("tries",0)+1
			if tries > 5: _no_path[_pair(_search.from,_search.to)] = true; _search = {}; return
			_search = {job = rails.begin_link(_search.from,_search.to,forbidden), from = _search.from, to = _search.to, purpose = _search.purpose, forbidden = forbidden, tries = tries}
			return
		var cost: int = rails.link_cost(path)
		wants.rail = cost
		if depot.iron-_iron_held() < cost or depot.energy < rails.rules.rail_energy_cost*path.size(): return
		var laid: Array[Node3D] = rails.lay_link(path,depot)
		if not laid.is_empty(): links.append({from = _search.from, to = _search.to, purpose = _search.purpose, pieces = laid})
		_search = {}
		return
	if haul_trains:
		for outpost in outposts(depot):
			if linked(depot,outpost) or _no_path.has(_pair(depot,outpost)): continue
			if depot.iron-_iron_held() < 40: return
			_begin_search(depot,outpost,"haul")
			return
	if mining_trains and Research.has(game,team,Research.MINING_TRAINS):
		# A mine track can't reach is dropped for the next.
		if mining_mine == null or not _mine_ok(mining_mine) or _no_path.has(_pair(depot,mining_mine)): mining_mine = mining_target(depot)
		if mining_mine == null or mine_linked(depot,mining_mine) or _no_path.has(_pair(depot,mining_mine)): return
		if depot.iron-_iron_held() < 40: return
		_begin_search(depot,mining_mine,"mine")
func _begin_search(from: Node3D, to: Node3D, purpose: String) -> void:
	_search = {job = rails.begin_link(from,to), from = from, to = to, purpose = purpose}
func _pair(a: Node3D, b: Node3D) -> String:
	return "%d:%d" % [a.get_instance_id(),b.get_instance_id()]
func _mine_ok(mine) -> bool:
	return is_instance_valid(mine) and mine.is_inside_tree() and mine.health > 0 and mine.remaining > 0
## Whether one line of its track reaches both Depots' rings.
func linked(a: Node3D, b: Node3D) -> bool:
	if rails == null: return false
	var all_lines: Dictionary = rails.lines()
	for from in rails.loading_pieces(a,team):
		var line = all_lines.get(from.get_instance_id())
		for to in rails.loading_pieces(b,team):
			if is_same(all_lines.get(to.get_instance_id()),line): return true
	return false
## Whether one line of its track reaches the Depot's ring and the mine's.
func mine_linked(depot: Node3D, mine: Node3D) -> bool:
	if rails == null: return false
	var all_lines: Dictionary = rails.lines()
	for from in rails.loading_pieces(depot,team):
		var line = all_lines.get(from.get_instance_id())
		for stop in rails.mine_stops(mine,team):
			if is_same(all_lines.get(stop.piece.get_instance_id()),line): return true
	return false
## The mine for a mining train: the nearest iron mine on its side at least 40 m from home, so the train has a run,
## that no expansion of its own works.
func mining_target(depot: Node3D) -> Node3D:
	for mine in _iron_mines(depot.global_position,expand_reach):
		if mine.global_position.distance_to(depot.global_position) < 40.0 or _no_path.has(_pair(depot,mine)): continue
		if not _own_side(mine.global_position,depot) or _held_by_opponent(mine.global_position): continue
		if expansions().any(func(outpost): return outpost.global_position.distance_to(mine.global_position) < 30.0): continue
		return mine
	return null
## Researches Mining Trains at its Temple once it can pay.
## The research it wants, in order: Mining Trains, Minelaying once it has a Derailer, then (once the army is big
## enough) the upgrade lines, level 1 of each, then level 2 of each, then level 3.
func research_wanted() -> Array[StringName]:
	var ids: Array[StringName] = []
	if mining_trains: ids.append(Research.MINING_TRAINS)
	if minelaying and army.any(func(unit): return _is_derailer(unit)): ids.append(Research.MINELAYING)
	if upgrades and army.size() >= upgrades_army:
		for n in range(1,Upgrades.LEVELS+1):
			for line in upgrade_lines: ids.append(Upgrades.research_id(line,n))
	return ids
## Starts the first research it wants that is neither done nor under way, at a building of its own that offers it
## and is free, saving for it meanwhile (`wants.research`, energy or food then iron). One thing at a time is saved for.
func research() -> void:
	for id in research_wanted():
		if Research.has(game,team,id) or Research.underway(game,team,id) != null: continue
		for building in get_tree().get_nodes_in_group("research_buildings"):
			if building.team != team or building.health <= 0 or building.researching != null: continue
			var entry = building.research_by_id(id)
			if entry == null: continue
			wants.research = Vector2i(entry.energy_cost+entry.food_cost,entry.iron_cost)
			if building.research_blocker(id).is_empty(): building.request_research(id)
			return
## Gives each of its trains a job: hauling iron home from an expansion its track reaches that no train serves,
## else mining its mine. Buys a train at home for a job no train has.
func run_trains(depot: Node3D) -> void:
	if rails == null: return
	var trains: Array[Node3D] = own_units().filter(func(unit): return unit.is_in_group("rail_trains"))
	var full := home_full(depot)
	var jobs: Array = []
	for outpost in outposts(depot):
		if linked(depot,outpost) and not trains.any(func(train): return train.route_active and train.origin_depot == outpost): jobs.append(outpost)
	if not full and _mine_ok(mining_mine) and Research.has(game,team,Research.MINING_TRAINS) and mine_linked(depot,mining_mine) and not trains.any(func(train): return train.is_mining()):
		jobs.append(mining_mine)
	# Hauling pauses while home is full enough, and resumes once it has room.
	# A mining train stops and is set to work again once there is room.
	for train in trains:
		if full and train.is_mining(): train.stop_mining(); continue
		if not train.route_active or train.destination_depot != depot: continue
		if full and not train.route_paused: train.pause_supply_route()
		elif not full and train.route_paused: train.resume_supply_route()
	for train in trains:
		if jobs.is_empty(): return
		if train.derailed or train.route_active or train.is_mining() or not _idle(train): continue
		for job in jobs:
			if job.is_in_group("depots"):
				if rails.line_to_depot(train.piece,train.along,job,team,0.0,train.lane).is_empty(): continue
				train.start_supply_route(job,depot,0,train.stockpile.capacity,true)
			else:
				if not train.mine_blocker(job).is_empty(): continue
				train.command_mine(job)
			jobs.erase(job)
			break
	if jobs.is_empty() or depot.pending.has("train"): return
	if trains.any(func(train): return _idle(train) and not train.route_active and not train.is_mining() and not train.derailed): return
	var line: Node3D = _line_piece(depot,jobs[0])
	if line == null: return
	wants.train = true
	if depot.energy >= rails.rules.cargo_energy_cost and depot.iron-_iron_held() >= rails.rules.cargo_iron_cost: depot.request_train(line)
## Whether home holds `haul_iron_cap` iron or has less room than `haul_room`: then trains stop bringing iron.
## With that much iron the home workers also cut wood for the Generators, up to twice `wood_wanted`.
func home_full(depot: Node3D) -> bool:
	return depot.iron >= haul_iron_cap or depot.stockpile.space() < haul_room
## The piece of home's line that reaches `target`, for a new train to start on.
func _line_piece(depot: Node3D, target: Node3D) -> Node3D:
	var all_lines: Dictionary = rails.lines()
	for piece in rails.depot_lines(depot):
		var line = all_lines.get(piece.get_instance_id())
		var ends: Array = rails.loading_pieces(target,team) if target.is_in_group("depots") else rails.mine_stops(target,team).map(func(stop): return stop.piece)
		if ends.any(func(other): return is_same(all_lines.get(other.get_instance_id()),line)): return piece
	return null

# --- Repair ---------------------------------------------------------------------------------------------------------

## Sends the nearest free worker to each own building that is damaged and has no enemy near, `repairers` at most.
func repair() -> void:
	var busy := workers.filter(func(unit): return unit.order == "repair").size()
	for building in own_buildings():
		if busy >= repairers: return
		if building.get("max_health") == null or building.health >= building.max_health*repair_below: continue
		if workers.any(func(unit): return unit.order == "repair" and unit.order_target == building): continue
		if _enemy_near(building.global_position,30.0): continue
		var best: Node3D
		for unit in workers:
			if unit.order in ["construct","repair"] or unit.global_position.distance_to(building.global_position) > 120.0: continue
			if best == null or unit.global_position.distance_to(building.global_position) < best.global_position.distance_to(building.global_position): best = unit
		if best == null: continue
		best.command_repair(building)
		if best.order == "repair": busy += 1
func _enemy_near(point: Vector3, radius: float) -> bool:
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.team == opponent and unit.health > 0 and sees(unit.global_position) and unit.global_position.distance_to(point) < radius: return true
	return false

## What the army's units leave in the Depot: energy and iron for the site being built and for what it is saving for
## this round (a Depot Truck, a train, track, research).
func held_back() -> Vector2i:
	var held := Vector2i(_energy_held(),_iron_held())
	var depot := home()
	if wants.get("truck",false) and depot != null: held += Vector2i(depot.rules.truck_energy_cost,depot.rules.truck_iron_cost)
	if wants.get("train",false) and rails != null: held += Vector2i(rails.rules.cargo_energy_cost,rails.rules.cargo_iron_cost)
	if wants.get("cargo",false): held += Vector2i(network.supply_rules.cargo_energy_cost,network.supply_rules.cargo_iron_cost)
	if wants.has("research"): held += wants.research
	held.y += int(wants.get("rail",0))
	return held

# --- Production -----------------------------------------------------------------------------------------------------

## Keeps every building's queue filled: workers first, then its mix in turn. Units other than workers leave the
## iron the next building needs.
func produce(depot: Node3D) -> void:
	var held := held_back()
	var buildings := get_tree().get_nodes_in_group("production_buildings").filter(func(node): return node.team == team and not node.stats.unit_scenes.is_empty() and node.source_friendly())
	var wanted := workers_total()-workers.size()
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
		if source.energy-stats.energy_cost < (0 if worker else held.x) or source.iron-stats.iron_cost < (0 if worker else held.y): continue
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

# --- Mines ----------------------------------------------------------------------------------------------------------

func _is_derailer(unit: Node3D) -> bool:
	return unit.has_method("can_carry_mines") and unit.has_ability(&"derail")
## Its own mines on the map.
func own_mines() -> Array:
	return get_tree().get_nodes_in_group("land_mines").filter(func(mine): return mine.team == team and not mine.is_queued_for_deletion())
## Where its `n`-th mine goes: a row across the way from home toward what it would attack, `mine_distance` out (or
## half way, if that is nearer), spots `mine_spacing` apart from the middle outward. The way is fixed the first time
## it knows of somewhere (`_mine_toward`). Null while it knows of nowhere.
func mine_spot(depot: Node3D, n: int) -> Variant:
	if _mine_toward == null: _mine_toward = wave_target(depot.global_position)
	if _mine_toward == null: return null
	var way: Vector3 = _mine_toward-depot.global_position
	way.y = 0.0
	if way.length() < 2.0: return null
	var out := minf(mine_distance,way.length()*0.5)
	way = way.normalized()
	var across := Vector3(-way.z,0.0,way.x)
	var side: int = (n+1)/2*(1 if n%2 == 1 else -1)
	return depot.global_position+way*out+across*mine_spacing*side
## The first spot of the row with no mine of its own on it, none on the way and none it failed to reach.
func next_mine_spot(depot: Node3D) -> Variant:
	var taken: Array[Vector3] = []
	for mine in own_mines(): taken.append(mine.global_position)
	for point in _laying.values(): taken.append(point)
	taken.append_array(_bad_mine_spots)
	for n in range(mines_wanted*3):
		var spot = mine_spot(depot,n)
		if spot == null: return null
		if ground.get_tile_at_position(spot) == null: continue
		if taken.any(func(point): return Vector2(point.x-spot.x,point.z-spot.z).length() < mine_spacing*0.5): continue
		return spot
	return null
## Derailers with mines aboard and a full tank, waiting at home and not in a wave, lay them along the row until `mines_wanted` of its
## own are down. They load more at the rally point, inside the Depot's range (docs/MINES.md).
func lay_mines(depot: Node3D) -> void:
	for id in _laying.keys():
		var unit = instance_from_id(id)
		if unit == null or not is_instance_valid(unit) or unit.order != "lay_mine":
			if unit != null and is_instance_valid(unit) and str(unit.state).contains("unreachable"): _bad_mine_spots.append(_laying[id])
			_laying.erase(id)
	if not minelaying or not Research.has(game,team,Research.MINELAYING) or _threat() != null: return
	var down := own_mines().size()+_laying.size()
	# A Derailer idle at home buys mines until it is full (Buy mine, docs/MINES.md).
	for unit in army:
		if _is_derailer(unit) and _idle(unit) and not wave.has(unit):
			while unit.command_buy_mine(): pass
	for unit in army:
		if down >= mines_wanted: return
		# Only a full tank leaves: a Derailer with too little coal would stop at the edge of the Depot's range.
		if wave.has(unit) or not _is_derailer(unit) or unit.mines <= 0 or not _idle(unit) or not fuelled(unit): continue
		var spot = next_mine_spot(depot)
		if spot == null: return
		unit.command_lay_mine(spot)
		if unit.order != "lay_mine": continue
		_laying[unit.get_instance_id()] = spot
		down += 1

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
		_escort_drones(depot)
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
		# Vehicles low on fuel stay and fill up at the rally point, inside the Depot's range.
		wave = army.filter(func(unit): return not unit.has_method("fuel_low") or not unit.fuel_low())
		if wave.size() < next_wave_size(): wave.clear(); return
		last_wave = wave.size(); waves_sent += 1
		for unit in wave: unit.command_attack_move(target)
	_escort_drones(depot)
## Keeps each Drone over the centre of the ground units it goes with: the wave's if it is in the wave, else the
## rest of the army's. A Drone with no ground units to go with is left alone. One low on coal (it burns coal by the
## second in the air) leaves the wave and flies home to the rally point, inside the Depot's range, to refuel.
func _escort_drones(depot: Node3D = null) -> void:
	var home := is_instance_valid(depot)
	var rally := rally_point(depot) if home else Vector3.ZERO
	for drone in army:
		if not _is_drone(drone): continue
		if home and drone.has_method("fuel_low") and (drone.fuel_low() or drone.get("fuel_landed") == true):
			wave.erase(drone)
			if not drone.fuel_landed and drone.global_position.distance_to(rally) > 6.0 and (drone.order != "move" or drone.move_goal.distance_to(rally) > 6.0): drone.command_move(rally)
			continue
		var group: Array[Node3D] = (wave if wave.has(drone) else army.filter(func(unit): return not wave.has(unit))).filter(func(unit): return not _is_drone(unit))
		if group.is_empty(): continue
		var centre := _centre(group)
		if drone.global_position.distance_to(centre) > drone_escort_radius: drone.command_move(centre)
func _is_drone(unit: Node3D) -> bool:
	return unit.get("unit_stats") != null and unit.unit_stats.unit_id == &"drone"
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
