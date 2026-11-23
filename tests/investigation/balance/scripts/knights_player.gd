extends "res://scripts/ai/enemy_player.gd"
## BALANCE PROTOTYPE: an AI for the Knights under the proposed economy (Farms, Houses, housing), built on the Cyborg
## AI's scouting, defence and waves. Each Keep runs its own small economy; it founds more Keeps by hand.
const Supply = preload("res://balance/knight_supply.gd")
@export var farms_wanted := 8
@export var foresters_wanted := 14
@export var chapterhouses_wanted := 3
## Farms a Keep has before its second Chapterhouse goes up.
@export var second_hall_farms := 3
@export var keeps_wanted := 2
## It founds the next Keep after this many seconds, or sooner if a Keep runs out of room.
@export var expand_at := 300.0
@export var outpost_farms := 6
@export var outpost_foresters := 10
@export var outpost_halls := 2
@export var knight_mix: Array[StringName] = [&"round_table_marine",&"round_table_marine",&"questing_marine",&"round_table_marine",&"grail_sentinel"]
## Every this many units from the mix, an Azure Dragon instead; 0 for none.
@export var dragon_every := 0
@export var hound_scout := true
@export var early_workers := 6
## Stands in for the proposed Supply Balloon: home sends an outpost 100 Food and 50 Wood at a time (20 Wood a trip),
## landing after `balloon_seconds`, while home has plenty and the outpost is short.
@export var balloon := false
@export var balloon_seconds := 20.0
var shipments: Array = []
var balloons_sent := 0
var _last_ship := -100.0
var plans := {}
var farmers := {}
var keep_plan: Node3D
var founding := false
var founders: Array[Node3D] = []
var keeps_founded: Array = []
var no_room := 0
var _made := 0
var first_army_at := -1.0
func _ready() -> void:
	# The army waits outside the Keep's range, off the ground its buildings go on.
	rally_distance = 36.0
func think() -> void:
	var depot := home()
	var units := own_units()
	remember()
	if depot == null:
		defeated = true
		return
	_sort(units)
	wants = {}
	for keep in own_keeps(): economy(keep,keep == depot)
	found_keep(depot)
	_balloons(depot)
	produce()
	fight(depot)
	_medics()
func own_keeps() -> Array[Node3D]:
	var result: Array[Node3D] = []
	var depot := home()
	if depot != null: result.append(depot)
	for node in get_tree().get_nodes_in_group("keeps"):
		if node != depot and _own_depot(node): result.append(node)
	return result
func _nearest_keep(point: Vector3) -> Node3D:
	var best: Node3D
	for keep in own_keeps():
		if best == null or keep.global_position.distance_to(point) < best.global_position.distance_to(point): best = keep
	return best
func _sort(units: Array[Node3D]) -> void:
	var alive := func(unit) -> bool: return is_instance_valid(unit) and units.has(unit)
	workers = workers.filter(alive)
	army = army.filter(alive)
	wave = wave.filter(alive)
	founders = founders.filter(alive)
	if not alive.call(scout): scout = null
	for unit in units:
		if workers.has(unit) or army.has(unit) or unit == scout: continue
		var id = unit.unit_stats.unit_id if unit.unit_stats != null else &""
		if id == &"forester_maiden":
			workers.append(unit)
			_bases[unit.get_instance_id()] = _nearest_keep(unit.global_position)
		elif id == &"warhound" and scout == null and hound_scout: scout = unit
		else:
			army.append(unit)
			if first_army_at < 0: first_army_at = elapsed
func _at(keep: Node3D, nodes: Array) -> Array:
	var reach: float = SupplySource.radius(keep)+2.0
	return nodes.filter(func(node): return node.global_position.distance_to(keep.global_position) <= reach)
func farms() -> Array:
	return get_tree().get_nodes_in_group("farms").filter(func(f): return f.team == team and f.health > 0 and not f.is_queued_for_deletion())
func halls() -> Array:
	return get_tree().get_nodes_in_group("production_buildings").filter(func(b): return b.team == team and b.health > 0 and b.stats.building_id == &"chapterhouse")
func economy(keep: Node3D, is_home: bool) -> void:
	var key: int = keep.get_instance_id()
	var mine: Array = workers.filter(func(unit): return base_of(unit) == keep and not founders.has(unit))
	var fields: Array = _at(keep,farms())
	var local_halls: Array = _at(keep,halls())
	var want_farms := farms_wanted if is_home else outpost_farms
	var want_workers := foresters_wanted if is_home else outpost_foresters
	var want_halls := chapterhouses_wanted if is_home else outpost_halls
	var target_farms := 2 if mine.size() <= 4 else mini(want_farms,mine.size()-2)
	if mine.size() <= 2 and not is_home: target_farms = 1
	var cap: int = Supply.cap(get_tree(),team)
	var used: int = Supply.used(get_tree(),team)
	var plan = plans.get(key)
	if not is_instance_valid(plan) or plan.finished:
		plans.erase(key)
		plan = null
		var house_planned: bool = plans.values().any(func(other): return is_instance_valid(other) and other.kind == &"house")
		var kind: StringName = &""
		if Supply.enabled and cap-used <= 3 and not house_planned and keep.wood >= 40: kind = &"house"
		elif fields.size() < mini(2,target_farms) and keep.wood >= 30: kind = &"farm"
		elif local_halls.is_empty() and want_halls > 0 and fields.size() >= 2 and keep.food >= 40 and keep.wood >= 30 and keep.iron >= 40: kind = &"chapterhouse"
		elif fields.size() < target_farms and keep.wood >= 30: kind = &"farm"
		elif not local_halls.is_empty() and local_halls.size() < want_halls and fields.size() >= second_hall_farms and keep.food >= 105 and keep.wood >= 30 and keep.iron >= 65: kind = &"chapterhouse"
		if kind != &"":
			var spec: Dictionary = network.plan_spec(kind)
			var point = building_site(keep,spec.size)
			if point != null:
				plan = network.queue_plan(point,kind,keep,true,false,team)
				if plan != null: plans[key] = plan
			else: no_room += 1
	if is_instance_valid(plan):
		var building: bool = mine.any(func(unit): return unit.order == "construct" and unit.order_target == plan)
		if not building:
			var best: Node3D
			var best_score := INF
			for unit in mine:
				if unit.order == "construct": continue
				var score: float = unit.global_position.distance_to(plan.global_position)+(1000.0 if farmers.values().has(unit) else 0.0)
				if score < best_score: best = unit; best_score = score
			if best != null: best.command_construct(plan)
	# One farmer to a farm.
	for id in farmers.keys():
		var farm = instance_from_id(id)
		var worker = farmers[id]
		if farm == null or not is_instance_valid(farm) or farm.is_queued_for_deletion() or farm.health <= 0 or not is_instance_valid(worker) or not workers.has(worker): farmers.erase(id)
	for farm in fields:
		if farmers.has(farm.get_instance_id()): continue
		var best: Node3D
		for unit in mine:
			if unit.order in ["construct","repair"] or farmers.values().has(unit): continue
			if best == null or unit.global_position.distance_to(farm.global_position) < best.global_position.distance_to(farm.global_position): best = unit
		if best != null: farmers[farm.get_instance_id()] = best
	for farm in fields:
		var worker = farmers.get(farm.get_instance_id())
		if worker == null or worker.order in ["construct","repair"]: continue
		if not (worker.order in ["gather","return"] and worker.source == farm): worker.command_gather(farm)
	# The rest cut wood and mine iron.
	var free: Array = mine.filter(func(unit): return not farmers.values().has(unit) and not unit.order in ["construct","repair"])
	var want_wood := 1
	if keep.wood >= 200: want_wood = 0
	elif keep.wood < 40 and free.size() >= 3: want_wood = 2
	var iron := _nearest_mine(keep.global_position,&"iron")
	if iron != null and iron.global_position.distance_to(keep.global_position) > 45.0: iron = null
	if iron == null or keep.iron >= 600: want_wood = maxi(want_wood,1)
	var on_wood := 0
	for unit in free:
		if _working(unit) == &"wood":
			if on_wood < want_wood: on_wood += 1
			elif iron != null: unit.command_gather(iron)
	for unit in free:
		if on_wood >= want_wood: break
		if _working(unit) == &"wood": continue
		var tree := forest_at(keep.global_position)
		if tree != null: unit.command_gather(tree); on_wood += 1
	for unit in free:
		if _working(unit) == &"":
			if iron != null: unit.command_gather(iron)
			else:
				var tree := forest_at(keep.global_position)
				if tree != null: unit.command_gather(tree)
	if mine.size()+keep.pending.count("forester_maiden") < want_workers and keep.food >= 45 and keep.queue < keep.queue_limit and Supply.room(get_tree(),team,&"forester_maiden"): keep.request_forester()
func forest_at(point: Vector3) -> Node3D:
	var centre = ground.get_tile_at_position(point)
	if centre == null: return null
	for r in range(6,int(reach/ground.tile_size)):
		for dx in range(-r,r+1):
			for dz in [-r,r]:
				for cell in [Vector2i(centre.x+dx,centre.y+dz),Vector2i(centre.x+dz,centre.y+dx)]:
					if ground.forest_amount(cell) > 0: return ground.forest_source(cell)
	return null
## Founds the next Keep beside the nearest free iron mine on its side: two workers from home carry 50 iron and 50
## wood onto the site from what is nearest it, and build it.
func found_keep(depot: Node3D) -> void:
	if founding and (not is_instance_valid(keep_plan) or keep_plan.finished):
		founding = false
		keep_plan = null
		for unit in founders: _bases[unit.get_instance_id()] = _nearest_keep(unit.global_position)
		founders.clear()
		keeps_founded.append(elapsed)
	if founding:
		_run_founders()
		return
	if own_keeps().size() >= keeps_wanted: return
	if elapsed < expand_at and no_room == 0: return
	var site = expansion_spot(depot,null)
	if site == null: return
	var pool: Array = workers.filter(func(unit): return base_of(unit) == depot and not farmers.values().has(unit) and unit.order != "construct")
	if pool.size() < 2: return
	keep_plan = network.queue_plan(site,&"keep",null,false,false,team)
	if keep_plan == null: return
	founding = true
	pool.sort_custom(func(a,b): return a.global_position.distance_to(site) < b.global_position.distance_to(site))
	founders.assign(pool.slice(0,2))
func _run_founders() -> void:
	var mine := _nearest_mine(keep_plan.global_position,&"iron")
	var jobs: Array[StringName] = [&"iron",&"wood"]
	for i in range(founders.size()):
		var unit: Node3D = founders[i]
		if unit.cargo > 0 and not unit.cargo_kind in jobs: unit.cargo = 0
		var want: StringName = jobs[i%2]
		if keep_plan.shortfall(want) <= 0: want = jobs[(i+1)%2]
		if keep_plan.shortfall(want) <= 0:
			if unit.order != "construct": unit.command_construct(keep_plan)
			continue
		if unit.cargo >= unit.carry_capacity or (unit.cargo > 0 and unit.cargo_kind != want):
			if unit.order != "construct": unit.command_construct(keep_plan)
		elif unit.order in ["idle","return"] or (unit.order == "construct" and unit.cargo == 0) or (unit.order == "gather" and (not is_instance_valid(unit.source) or unit.source.resource_kind != want)):
			var source: Node3D = mine if want == &"iron" else forest_at(keep_plan.global_position)
			if source != null: unit.command_gather(source)
func produce(depot: Node3D = null) -> void:
	for hall in halls():
		if hall.queue >= queue_depth or not hall.source_friendly(): continue
		var id := _next_knight()
		var stats: UnitStats = _stats(hall,id)
		if stats == null: continue
		var source: Node3D = hall.assigned_depot
		var local: int = workers.filter(func(unit): return base_of(unit) == source).size()
		var reserve := 45 if local < early_workers else 0
		if source.food-stats.food_cost < reserve or source.iron < stats.iron_cost: continue
		if not Supply.room(get_tree(),team,id): continue
		if hall.request_unit(id): _made += 1
	var keep := home()
	if keep != null and hound_scout and scout == null and not keep.pending.has("warhound") and elapsed > 90.0 and keep.food >= 75 and keep.iron >= 5 and Supply.room(get_tree(),team,&"warhound"): keep.request_warhound()
func _next_knight() -> StringName:
	if dragon_every > 0 and _made%dragon_every == dragon_every-1: return &"azure_dragon"
	return knight_mix[_made%knight_mix.size()]
## Grail Sentinels heal the most hurt friend near them.
func _medics() -> void:
	for unit in army:
		if unit.unit_stats.unit_id != &"grail_sentinel": continue
		if unit.order == "heal" and is_instance_valid(unit.order_target) and unit.order_target.health < unit.order_target.max_health: continue
		var best: Node3D
		var worst := 0.9
		for friend in army:
			if friend == unit or friend.fuel_rules != null or friend.health >= friend.max_health: continue
			if friend.global_position.distance_to(unit.global_position) > 22.0: continue
			var share: float = float(friend.health)/friend.max_health
			if share < worst: worst = share; best = friend
		if best != null: unit.command_heal(best)

func _balloons(depot: Node3D) -> void:
	for shipment in shipments.duplicate():
		if elapsed < shipment.at: continue
		shipments.erase(shipment)
		if _own_depot(shipment.to):
			shipment.to.stockpile.deposit(&"food",shipment.food)
			shipment.to.stockpile.deposit(&"wood",shipment.wood)
	if not balloon or elapsed-_last_ship < 30.0: return
	for keep in own_keeps():
		if keep == depot or keep.food >= 150 or depot.food < 250 or depot.wood < 90: continue
		if shipments.any(func(shipment): return shipment.to == keep): continue
		depot.stockpile.withdraw(&"food",100)
		depot.stockpile.withdraw(&"wood",70)
		shipments.append({at = elapsed+balloon_seconds, to = keep, food = 100, wood = 50})
		balloons_sent += 1
		_last_ship = elapsed
		return
