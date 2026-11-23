extends SceneTree
# Balance investigation arena (not a test). Runs a list of battles from a JSON spec on a flattened patch of the
# First Contact map, with the game's own unit scenes, orders and combat code, at a fixed step.
#   ARENA_SPEC=/path/spec.json ARENA_OUT=/path/out.jsonl godot --headless --fixed-fps 30 --path . --script res://balance/arena.gd
const A := "player"
const B := "enemy"
const STEP_FRAMES := 6          # controllers think every 0.2 s
const BIG := ["tank","ubermech","azure_dragon"]
var game: Node3D
var ground: Node
var UA: Script
var keep_children: Array = []
var dealt := {A: 0, B: 0}       # damage taken by each side's units that have died
var deaths: Array = []
var now := 0.0
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var specs: Array = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("ARENA_SPEC")))
	var out := FileAccess.open(OS.get_environment("ARENA_OUT"),FileAccess.WRITE)
	UA = load("res://scripts/gameplay/unit_agent.gd")
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	for i in range(3): await process_frame
	ground = game.get_node("Terrain/Ground")
	for group in ["units","selectable_buildings","depots"]:
		for node in get_nodes_in_group(group): node.queue_free()
	for node in game.get_node("Entities/Resources").get_children(): node.queue_free()
	for i in range(3): await process_frame
	game.set_process(false)
	game.get_node("Interface").process_mode = Node.PROCESS_MODE_DISABLED
	for z in range(150,350):
		for x in range(20,480):
			var cell := Vector2i(x,z)
			var tile: Dictionary = ground.tiles[z*500+x]
			tile.occupied_by = null
			ground._open_cell(cell)
	keep_children = game.get_children()
	for spec in specs:
		var reps: int = spec.get("reps",1)
		for rep in range(reps):
			var result: Dictionary = await battle(spec)
			result["rep"] = rep
			out.store_line(JSON.stringify(result))
			out.flush()
			print("%s #%d -> %s in %.1fs  A %s  B %s" % [spec.name,rep,result.winner,result.time,result.a_alive,result.b_alive])
	out.close()
	print("ARENA_DONE")
	quit()

func spawn(side: String, group: Dictionary, front_x: float, dir: float, row_offset: float) -> float:
	var id: String = group.unit
	var n: int = group.n
	var gap: float = group.get("gap",4.0 if id in BIG else 2.0)
	var width: int = int(group.get("width",clampi(ceili(sqrt(n)*1.6),1,16)))
	var members: Array = []
	var scene: PackedScene = load("res://scenes/gameplay/%s.tscn" % id)
	var rows := ceili(float(n)/width)
	for i in range(n):
		var row := i/width
		var col := i%width
		var in_row := mini(width,n-row*width)
		var unit = scene.instantiate()
		unit.team = side
		if group.has("stats"):
			unit.unit_stats = unit.unit_stats.duplicate()
			for key in group.stats: unit.unit_stats.set(key,group.stats[key])
		if group.has("props"):
			for key in group.props: unit.set(key,group.props[key])
		unit.position = Vector3(front_x-dir*(row_offset+row*gap),0,(col-(in_row-1)*0.5)*gap+group.get("z",0.0))
		if "start_fuelled" in unit: unit.start_fuelled = true
		game.get_node("Entities/Units").add_child(unit,true)
		if group.has("roof") and unit.has_node("CloseDefense"):
			for key in group.roof: unit.get_node("CloseDefense").set(key,group.roof[key])
		if group.get("no_roof",false) and unit.has_node("CloseDefense"): unit.get_node("CloseDefense").set_process(false)
		if group.has("second"):
			for entry in (group.second if group.second is Array else [group.second]):
				var weapon = load("res://balance/second_weapon.gd").new()
				for key in entry: weapon.set(key,entry[key])
				unit.add_child(weapon)
		unit.died.connect(_on_died.bind(side,id))
		unit.set_meta("spawn",unit.position)
		unit.set_meta("moved",0.0)
		unit.set_meta("last",unit.position)
		members.append(unit)
	group["members"] = members
	group["side"] = side
	return row_offset+rows*gap+1.0
func _on_died(unit: Node3D, side: String, id: String) -> void:
	dealt[side] += unit.damage_taken
	deaths.append([snappedf(now,0.1),side,id])
func alive(members: Array) -> Array:
	return members.filter(func(u): return is_instance_valid(u) and not u.is_queued_for_deletion() and u.health > 0)
func side_units(groups: Array, side: String) -> Array:
	var result: Array = []
	for group in groups:
		if group.side == side: result.append_array(alive(group.members))
	return result
func nearest(from: Vector3, units: Array) -> Node3D:
	var best: Node3D
	var best_d := INF
	for unit in units:
		var d := from.distance_squared_to(unit.global_position)
		if d < best_d: best = unit; best_d = d
	return best
func centroid(units: Array) -> Vector3:
	var total := Vector3.ZERO
	for unit in units: total += unit.global_position
	return total/maxf(1.0,units.size())

func battle(spec: Dictionary) -> Dictionary:
	UA.sim_require_sight = spec.get("sight",false)
	game.vehicle_fuel_required = spec.get("fuel",false)
	dealt = {A: 0, B: 0}
	deaths = []
	now = 0.0
	var dist: float = spec.get("dist",70.0)
	var groups: Array = []
	var offset := 0.0
	for group in spec.a:
		var g: Dictionary = group.duplicate(true)
		offset = spawn(A,g,-dist*0.5+spec.get("ax",0.0),1.0,offset)
		groups.append(g)
	offset = 0.0
	for group in spec.b:
		var g: Dictionary = group.duplicate(true)
		offset = spawn(B,g,dist*0.5+spec.get("bx",0.0),-1.0,offset)
		groups.append(g)
	for i in range(2): await process_frame
	var start := {A: {}, B: {}}
	var hp0 := {A: 0, B: 0}
	for group in groups:
		start[group.side][group.unit] = start[group.side].get(group.unit,0)+group.members.size()
		for unit in group.members: hp0[group.side] += unit.max_health
	var limit: float = spec.get("limit",240.0)
	var winner := "draw"
	var first_contact := -1.0
	while now < limit:
		for i in range(STEP_FRAMES): await process_frame
		now += STEP_FRAMES/30.0
		var units_a := side_units(groups,A)
		var units_b := side_units(groups,B)
		if first_contact < 0:
			for unit in units_a+units_b:
				if unit.damage_taken > 0: first_contact = now; break
		# Sides whose armed units are all dead have lost (unarmed spotters and medics don't hold the field).
		var armed_a := units_a.filter(func(u): return u._attack_enabled)
		var armed_b := units_b.filter(func(u): return u._attack_enabled)
		if armed_a.is_empty() or armed_b.is_empty():
			winner = "b" if armed_a.is_empty() and not armed_b.is_empty() else ("a" if armed_b.is_empty() and not armed_a.is_empty() else "draw")
			break
		for group in groups:
			var mine: Array = alive(group.members)
			var foes: Array = units_b if group.side == A else units_a
			var friends: Array = units_a if group.side == A else units_b
			for unit in mine:
				unit.set_meta("moved",unit.get_meta("moved")+unit.global_position.distance_to(unit.get_meta("last")))
				unit.set_meta("last",unit.global_position)
			match group.get("ctrl","amove"):
				"amove": _amove(mine,foes)
				"kite": _kite(group,mine,foes)
				"hold": pass
				"follow": _follow(group,mine,friends)
				"medic": _medic(mine,friends,foes)
				"mech": _mech(group,mine,foes)
	var units_a := side_units(groups,A)
	var units_b := side_units(groups,B)
	var result := {"name": spec.name, "winner": winner, "time": snappedf(now,0.1), "contact": snappedf(first_contact,0.1),
		"a_start": start[A], "b_start": start[B], "a_alive": _count(units_a), "b_alive": _count(units_b),
		"a_hp": _hp(units_a), "b_hp": _hp(units_b), "a_hp0": hp0[A], "b_hp0": hp0[B],
		"a_taken": dealt[A]+_taken(units_a), "b_taken": dealt[B]+_taken(units_b), "deaths": deaths.duplicate(),
		"a_moved": _moved(groups,A), "b_moved": _moved(groups,B), "a_fuel": _fuel(units_a)}
	for unit in get_nodes_in_group("units"): unit.queue_free()
	for child in game.get_children():
		if not keep_children.has(child): child.queue_free()
	for i in range(4): await process_frame
	return result
func _count(units: Array) -> Dictionary:
	var result := {}
	for unit in units:
		var id := str(unit.unit_stats.unit_id)
		result[id] = result.get(id,0)+1
	return result
func _hp(units: Array) -> int:
	var total := 0
	for unit in units: total += unit.health
	return total
func _taken(units: Array) -> int:
	var total := 0
	for unit in units: total += unit.damage_taken
	return total
func _moved(groups: Array, side: String) -> float:
	var most := 0.0
	for group in groups:
		if group.side != side: continue
		for unit in alive(group.members): most = maxf(most,unit.get_meta("moved"))
	return snappedf(most,0.1)
func _fuel(units: Array) -> float:
	var total := 0.0
	for unit in units:
		if unit.fuel_rules != null: total += unit.fuel
	return snappedf(total,0.1)

# Attack-move at the nearest foe, chasing it as it moves.
func _amove(mine: Array, foes: Array) -> void:
	for unit in mine:
		var foe := nearest(unit.global_position,foes)
		if foe == null: continue
		if unit.state == "Attack-moving · engaging": continue
		if unit.order == "idle" or (unit.order == "attack_move" and unit.move_goal.distance_to(foe.global_position) > 6.0 and int(now*5)%5 == 0):
			unit.command_attack_move(foe.global_position)
# Fall back from the nearest foe whenever it is inside `kite_at`, firing on the move if the unit can; stand when it
# is outside. `budget` is the metres it may fall back before it has to stand and fight.
func _kite(group: Dictionary, mine: Array, foes: Array) -> void:
	for unit in mine:
		var foe := nearest(unit.global_position,foes)
		if foe == null: continue
		var d: float = unit.global_position.distance_to(foe.global_position)
		var kite_at: float = group.get("kite_at",unit.attack_range-4.0)
		var resume: float = group.get("resume",kite_at+2.0)
		var budget: float = group.get("budget",1e9)
		var spent: float = unit.get_meta("kited",0.0)
		if unit.order == "move": unit.set_meta("kited",spent+unit.global_position.distance_to(unit.get_meta("klast",unit.global_position)))
		unit.set_meta("klast",unit.global_position)
		if d < kite_at and spent < budget:
			var away: Vector3 = unit.global_position-centroid(foes.filter(func(f): return f.global_position.distance_to(unit.global_position) < kite_at+10.0))
			away.y = 0
			away = away.normalized() if away.length() > 0.01 else Vector3.LEFT
			var goal: Vector3 = unit.global_position+away*30.0
			# Stay inside the flattened ground: slide along its edge.
			goal.x = clampf(goal.x,-225.0,225.0)
			goal.z = clampf(goal.z,-95.0,95.0)
			if unit.order != "move" or unit.move_goal.distance_to(goal) > 10.0: unit.command_move(goal)
		elif unit.order == "move" and (d >= resume or spent >= budget):
			unit._stop_route()
			unit.order = "idle"
		elif unit.order == "idle" and d > unit.attack_range+1.0 and group.get("advance",true):
			# Out of reach and not threatened: close to firing range again.
			unit.command_attack_move(foe.global_position)
		elif unit.order == "attack_move" and d < kite_at+1.0:
			unit._stop_route(); unit.order = "idle"
# Stay with the friendly fighting units (a spotter).
func _follow(group: Dictionary, mine: Array, friends: Array) -> void:
	var fighters: Array = friends.filter(func(u): return not mine.has(u))
	if fighters.is_empty(): return
	var centre := centroid(fighters)+Vector3(group.get("lead",0.0)*(1.0 if group.side == A else -1.0),0,0)
	for unit in mine:
		if unit.global_position.distance_to(centre) > 4.0 and (unit.order != "move" or unit.move_goal.distance_to(centre) > 4.0): unit.command_move(centre)
# Heal the most hurt friend in reach; otherwise keep up with the nearest fighter.
func _medic(mine: Array, friends: Array, foes: Array) -> void:
	if friends.filter(func(u): return not mine.has(u)).is_empty(): _amove(mine,foes); return
	for unit in mine:
		if unit.order == "heal" and is_instance_valid(unit.order_target) and unit.order_target.health < unit.order_target.max_health: continue
		var best: Node3D
		var worst := 1.0
		for friend in friends:
			if friend == unit or friend.fuel_rules != null or friend.health >= friend.max_health: continue
			if friend.global_position.distance_to(unit.global_position) > 24.0: continue
			var share: float = float(friend.health)/friend.max_health
			if share < worst: worst = share; best = friend
		if best != null: unit.command_heal(best); continue
		var fighters: Array = friends.filter(func(u): return not mine.has(u))
		var lead := nearest(unit.global_position,fighters)
		if lead != null and lead.global_position.distance_to(unit.global_position) > 7.0 and (unit.order != "move" or unit.move_goal.distance_to(lead.global_position) > 6.0): unit.command_move(lead.global_position)

# A two-weapon walker: closes to `near` on light foes (its laser) and holds at `far` from armoured ones (its missiles).
func _mech(group: Dictionary, mine: Array, foes: Array) -> void:
	var Second = load("res://balance/second_weapon.gd")
	for unit in mine:
		var foe := nearest(unit.global_position,foes)
		if foe == null: continue
		var d: float = unit.global_position.distance_to(foe.global_position)
		var want: float = group.get("far",30.0) if Second.is_heavy(foe) else group.get("near",15.0)
		if d > want:
			if unit.order != "move" or unit.move_goal.distance_to(foe.global_position) > 5.0: unit.command_move(foe.global_position)
		elif unit.order == "move":
			unit._stop_route(); unit.order = "idle"
