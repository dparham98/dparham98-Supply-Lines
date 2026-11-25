extends "res://scripts/ai/enemy_player.gd"
## The Knights AI (docs/KNIGHTS_AI.md): Farms, Houses and Chapterhouses round each Keep, on the Cyborg AI's scouting,
## defence and waves (scripts/ai/enemy_player.gd). Each Keep runs its own small economy; it founds a second Keep by
## hand. Ported from the balance investigation's prototype (branch claude/game-balance-knights-cyborg-52c0aa).
## Its opening: both Foresters build and work a Farm; the Keep trains Foresters without a pause to 14; 8 Farms and
## the first Chapterhouse by about 2:00; three Chapterhouses by about 3:30; Houses ahead of need; a second Keep at
## 5:00; the first wave at 8:00.
const Supply = preload("res://scripts/economy/knight_housing.gd")
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
## The army, in turn: 10 Round Table Marines to 3 Questing Marines to 3 Grail Sentinels.
@export var knight_mix: Array[StringName] = [&"round_table_marine",&"round_table_marine",&"questing_marine",&"round_table_marine",&"grail_sentinel",&"round_table_marine",&"round_table_marine",&"questing_marine",&"round_table_marine",&"grail_sentinel",&"round_table_marine",&"round_table_marine",&"questing_marine",&"round_table_marine",&"grail_sentinel",&"round_table_marine"]
## Every this many units from the mix, an Azure Dragon instead; 0 for none.
@export var dragon_every := 0
@export var hound_scout := true
@export var early_workers := 6
var plans := {}
var farmers := {}
var keep_plan: Node3D
## Keeps with no room left for another Chapterhouse, by instance id.
var _hall_waits := {}
var founding := false
var founders: Array[Node3D] = []
var keeps_founded: Array = []
var no_room := 0
var _made := 0
var first_army_at := -1.0
## Iron and wood a Keep holds before its workers stop bringing more; past this the store only fills and turns
## away its Farmers' Food.
@export var iron_enough := 600
@export var wood_enough := 300
## Housing free below which it plans a House.
@export var house_headroom := 3
## Once home has all its Chapterhouses (or no room for more), a Forge goes up there for Arms and Mail
## (docs/UPGRADES.md). While it saves for a level, the Chapterhouses leave home that Food and Iron.
@export var forge_wanted := true
@export_group("Rail")
## Once it has a second Keep, it puts up a Wainwright, joins each Keep to home with track and runs a train hauling
## iron home from each (docs/KNIGHTS_RAIL.md). The trains burn coal, so home also gets a Coal Mine and a Forester
## works it while home holds less than `train_coal_wanted`.
@export var rail_wanted := true
@export_range(0,1000,10) var train_coal_wanted := 60
@export_group("")
## Its Coal Mine plan, and the Forester that builds it and then works it.
var coal_plan: Node3D
var coal_hand: Node3D
@export_group("Spells")
## Grail Sentinels cast Slow on a clump of the other side's units and Mist over a group of friends under fire from
## beyond Mist's sight (docs/MIST_AND_SLOW.md). The Forge researches Slow after level 1 of Arms and Mail.
@export var spells := true
## Reserve a Sentinel keeps for healing after a cast.
@export_range(0,200,5) var spell_keep := 40
## The other side's units within Slow's radius of a point before it is slowed.
@export_range(1,20) var slow_clump := 3
## Friends within Mist's radius of a Sentinel before it covers them.
@export_range(1,20) var mist_group := 4
@export_group("")
## Its casts still running: {kind, point, until}, so two Sentinels don't cast on the same spot.
var _casts: Array = []
func _ready() -> void:
	# The army waits outside the Keep's range, off the ground its buildings go on.
	rally_distance = 36.0
	upgrade_lines = [&"arms",&"mail"]
	# Its trains haul; mining trains need a Temple, which the Knights don't have.
	mining_trains = false
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
	research()
	rail_economy(depot)
	produce()
	fight(depot)
	_medics()
	_spells()
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
## Whether it has a Forge standing or planned.
func has_forge() -> bool:
	for node in get_tree().get_nodes_in_group("research_buildings"):
		if node.team == team and node.health > 0 and node.stats.building_id == &"forge": return true
	return plans.values().any(func(other): return is_instance_valid(other) and other.kind == &"forge")
## Whether it has a building of `id` standing, or planned at one of its Keeps.
func has_building(id: StringName) -> bool:
	if own_buildings().any(func(node): return node.get("stats") != null and node.stats.get("building_id") == id): return true
	return plans.values().any(func(other): return is_instance_valid(other) and other.kind == id)
func economy(keep: Node3D, is_home: bool) -> void:
	var key: int = keep.get_instance_id()
	var mine: Array = workers.filter(func(unit): return base_of(unit) == keep and not founders.has(unit) and unit != coal_hand)
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
		if cap-used <= house_headroom and not house_planned and keep.wood >= 40: kind = &"house"
		elif fields.size() < mini(2,target_farms) and keep.wood >= 30: kind = &"farm"
		elif local_halls.is_empty() and want_halls > 0 and fields.size() >= 2 and keep.food >= 40 and keep.wood >= 30 and keep.iron >= 40: kind = &"chapterhouse"
		# With 10 x 10 Farms a Keep's land runs out at about eight; its Chapterhouses go up before the last Farms take
		# the room (docs/KNIGHTS_AI.md).
		elif not local_halls.is_empty() and local_halls.size() < want_halls and fields.size() >= second_hall_farms and keep.food >= 105 and keep.wood >= 30 and keep.iron >= 65 and not _hall_waits.get(key,false): kind = &"chapterhouse"
		elif is_home and forge_wanted and upgrades and not local_halls.is_empty() and (local_halls.size() >= want_halls or _hall_waits.get(key,false)) and not has_forge() and keep.wood >= 60 and keep.iron >= 80: kind = &"forge"
		# The Wainwright goes up at whichever Keep has room first, once there is a second Keep to join.
		elif rail_wanted and own_keeps().size() >= 2 and not has_building(&"wainwright") and keep.wood >= 60 and keep.iron >= 60: kind = &"wainwright"
		elif fields.size() < target_farms and keep.wood >= 30: kind = &"farm"
		if kind != &"":
			var spec: Dictionary = network.plan_spec(kind)
			var point = building_site(keep,spec.size)
			if point != null:
				plan = network.queue_plan(point,kind,keep,true,false,team)
				if plan != null: plans[key] = plan
			else:
				no_room += 1
				# No room for another Chapterhouse here: Farms may have the rest of the land.
				if kind == &"chapterhouse": _hall_waits[key] = true
	if is_instance_valid(plan):
		var building: bool = mine.any(func(unit): return unit.order == "construct" and unit.order_target == plan)
		if not building:
			var best: Node3D
			var best_score := INF
			for unit in mine:
				if unit.order == "construct" or unit.farmer: continue
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
		# A Farmer whose Farm was lost takes an empty one first (docs/KNIGHTS_ECONOMY.md).
		var best: Node3D
		for unit in mine:
			if not unit.farmer or farmers.values().has(unit) or (is_instance_valid(unit.farm) and unit.farm.health > 0): continue
			if best == null or unit.global_position.distance_to(farm.global_position) < best.global_position.distance_to(farm.global_position): best = unit
		if best == null:
			for unit in mine:
				if unit.farmer or unit.order in ["construct","repair"] or farmers.values().has(unit): continue
				if best == null or unit.global_position.distance_to(farm.global_position) < best.global_position.distance_to(farm.global_position): best = unit
		if best != null: farmers[farm.get_instance_id()] = best
	for farm in fields:
		var worker = farmers.get(farm.get_instance_id())
		if worker == null or worker.order in ["construct","repair"]: continue
		if not (worker.order in ["gather","return"] and worker.source == farm): worker.command_gather(farm)
	# The rest cut wood and mine iron.
	var free: Array = mine.filter(func(unit): return not unit.farmer and not farmers.values().has(unit) and not unit.order in ["construct","repair"])
	var want_wood := 1
	if keep.wood >= 200: want_wood = 0
	elif keep.wood < 40 and free.size() >= 3: want_wood = 2
	var iron := _nearest_mine(keep.global_position,&"iron")
	if iron != null and iron.global_position.distance_to(keep.global_position) > 45.0: iron = null
	if iron == null or keep.iron >= 600: want_wood = maxi(want_wood,1)
	# A Keep that holds enough iron and wood stops taking more, so its store keeps room for its Farmers' Food.
	if keep.iron >= iron_enough:
		# Its iron miners cut wood instead.
		iron = null
		want_wood = free.size()
	if keep.wood >= wood_enough:
		want_wood = 0
		for unit in free:
			if _working(unit) == &"wood" or (_working(unit) == &"iron" and iron == null):
				unit._stop_route(); unit.order = "idle"; unit.state = "Idle · the Keep has enough"
		return _train_foresters(keep,mine,want_workers)
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
	_train_foresters(keep,mine,want_workers)
# --- Rail -----------------------------------------------------------------------------------------------------------

## With a Wainwright standing: track from home to each other Keep, trains hauling their iron home (the Cyborg AI's
## rail and run_trains, with Keeps for Depots), and coal at home for the trains.
func rail_economy(depot: Node3D) -> void:
	if not rail_wanted or rails == null or own_keeps().size() < 2 or not KnightRail.has_wainwright(depot,team): return
	rail(depot)
	run_trains(depot)
	_coal(depot)
## No build order holds iron back: each Keep's plans pay as they are placed.
func _iron_held() -> int:
	return 0
func _buy_train(depot: Node3D, line: Node3D) -> void:
	var r := Supply.rules()
	if depot.food >= r.train_food_cost and depot.wood >= r.train_wood_cost and depot.iron >= r.train_iron_cost: depot.request_train(line)
## One home Forester carries iron out to a Coal Mine site near home and builds it, then gathers coal while home
## holds less than `train_coal_wanted` (up to twice that), and goes back to the Keep's own work after.
func _coal(depot: Node3D) -> void:
	if coal_hand != null and (not is_instance_valid(coal_hand) or not workers.has(coal_hand)): coal_hand = null
	var coal := _nearest_mine(depot.global_position,&"coal")
	if coal != null: coal_plan = null
	elif not is_instance_valid(coal_plan) or coal_plan.finished:
		coal_plan = null
		var site = coal_site(depot)
		if site == null: return
		coal_plan = network.queue_plan(site,&"coal_mine",depot,true,false,team)
		if coal_plan == null: return
	if coal != null and depot.coal >= train_coal_wanted*2:
		if coal_hand != null and coal_hand.order == "gather" and is_instance_valid(coal_hand.source) and coal_hand.source.resource_kind == &"coal": coal_hand._stop_route(); coal_hand.order = "idle"
		coal_hand = null
		return
	if coal != null and depot.coal >= train_coal_wanted and coal_hand == null: return
	if coal_hand == null:
		var best: Node3D
		for unit in workers:
			if base_of(unit) != depot or unit.farmer or farmers.values().has(unit) or founders.has(unit) or unit.order in ["construct","repair"]: continue
			var at: Vector3 = coal.global_position if coal != null else coal_plan.global_position
			if best == null or unit.global_position.distance_to(at) < best.global_position.distance_to(at): best = unit
		coal_hand = best
		if coal_hand == null: return
	if coal != null:
		if not (coal_hand.order in ["gather","return"] and coal_hand.source == coal): coal_hand.command_gather(coal)
		return
	# The site needs its iron carried out: the Forester mines it, then builds.
	if coal_hand.cargo > 0 and coal_hand.cargo_kind != &"iron": coal_hand.cargo = 0
	if coal_plan.shortfall(&"iron") <= 0 or coal_hand.cargo >= mini(coal_hand.carry_capacity,coal_plan.shortfall(&"iron")):
		if coal_hand.order != "construct": coal_hand.command_construct(coal_plan)
	elif coal_hand.order != "gather" or not is_instance_valid(coal_hand.source) or coal_hand.source.resource_kind != &"iron":
		var iron := _nearest_mine(depot.global_position,&"iron")
		if iron != null: coal_hand.command_gather(iron)
func _train_foresters(keep: Node3D, mine: Array, want_workers: int) -> void:
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
	var pool: Array = workers.filter(func(unit): return base_of(unit) == depot and not unit.farmer and not farmers.values().has(unit) and unit.order != "construct")
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
		# Home leaves what the Forge's next level needs.
		var hold: Vector2i = wants.get("research",Vector2i.ZERO) if source == home() else Vector2i.ZERO
		if source.food-stats.food_cost < maxi(reserve,hold.x) or source.iron-stats.iron_cost < hold.y: continue
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
		if unit.unit_stats.unit_id != &"grail_sentinel" or unit.order in ["mist","slow"]: continue
		if unit.order == "heal" and is_instance_valid(unit.order_target) and unit.order_target.health < unit.order_target.max_health: continue
		var best: Node3D
		var worst := 0.9
		for friend in army:
			if friend == unit or friend.fuel_rules != null or friend.health >= friend.max_health: continue
			if friend.global_position.distance_to(unit.global_position) > 22.0: continue
			var share: float = float(friend.health)/friend.max_health
			if share < worst: worst = share; best = friend
		if best != null: unit.command_heal(best)
## Slow after level 1 of each upgrade line, once the army is big enough.
func research_wanted() -> Array[StringName]:
	var ids := super()
	if not spells or army.size() < upgrades_army: return ids
	var at := 0
	for i in range(ids.size()):
		if upgrade_lines.any(func(line): return ids[i] == Upgrades.research_id(line,1)): at = i+1
	ids.insert(at,Research.SLOW)
	return ids

# --- Spells ---------------------------------------------------------------------------------------------------------

## Each Grail Sentinel with the other side's units it sees within reach of a cast tries Slow, then Mist.
func _spells() -> void:
	if not spells: return
	_casts = _casts.filter(func(cast): return cast.until > elapsed)
	var foes: Array = get_tree().get_nodes_in_group("units").filter(func(unit): return unit.team == opponent and unit.health > 0 and not unit.is_in_group("rail_trains") and sees(unit.global_position))
	if foes.is_empty(): return
	for unit in army:
		if unit.unit_stats.unit_id != &"grail_sentinel" or unit.spell_rules == null or unit.order in ["mist","slow"]: continue
		var near: Array = foes.filter(func(foe): return foe.global_position.distance_to(unit.global_position) <= unit.spell_rules.cast_range+10.0)
		if near.is_empty(): continue
		if not _try_slow(unit,near): _try_mist(unit,near)
func _cast_near(kind: String, point: Vector3, radius: float) -> bool:
	return _casts.any(func(cast): return cast.kind == kind and cast.point.distance_to(point) < radius)
func _cast(unit: Node3D, kind: String, point: Vector3, seconds: float) -> bool:
	unit.command_spell(kind,point)
	if unit.order != kind: return false
	_casts.append({kind = kind, point = point, until = elapsed+seconds})
	return true
## Slow on the point among `near` with the most of them within Slow's radius, at least `slow_clump`.
func _try_slow(unit: Node3D, near: Array) -> bool:
	if not unit.spell_blocker("slow").is_empty() or unit.med_reserve < unit.spell_cost("slow")+spell_keep: return false
	var r: float = unit.spell_rules.slow_radius
	var best: Node3D
	var best_count := 0
	for foe in near:
		var count: int = near.filter(func(other): return other.global_position.distance_to(foe.global_position) <= r).size()
		if count > best_count: best = foe; best_count = count
	if best == null or best_count < slow_clump or _cast_near("slow",best.global_position,r): return false
	return _cast(unit,"slow",best.global_position,unit.spell_rules.slow_seconds)
## Mist over the friends round the Sentinel, `mist_group` or more, while the other side's units in reach are all
## further off than Mist lets them see in: they lose sight of the friends and can't shoot them.
func _try_mist(unit: Node3D, near: Array) -> bool:
	if not unit.spell_blocker("mist").is_empty() or unit.med_reserve < unit.spell_cost("mist")+spell_keep: return false
	var r: float = unit.spell_rules.mist_radius
	var centre := Vector3.ZERO
	var friends := 0
	for friend in army:
		if friend.global_position.distance_to(unit.global_position) > r: continue
		centre += friend.global_position
		friends += 1
	if friends < mist_group: return false
	centre /= friends
	if near.any(func(foe): return foe.global_position.distance_to(centre) <= r+unit.spell_rules.mist_reveal): return false
	if _cast_near("mist",centre,r*2.0): return false
	return _cast(unit,"mist",centre,unit.spell_rules.mist_seconds)
