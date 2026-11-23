extends SceneTree
# Balance investigation (not a test): an AI-against-AI match on Two Lakes with either faction on either side.
#   MATCH_SPEC=/path/spec.json MATCH_OUT=/path/out.json godot --headless --fixed-fps 30 --path . --script res://balance/match2.gd
# spec: {"name", "minutes", "west": {"faction": "cyborgs"|"knights", "ai": {...}, "stock": {...}}, "east": {...},
#        "rules": {"sight": bool, "supply": bool, "farm_per_beat": int}, "stats": {"tank": {...}}}
const Supply = preload("res://balance/knight_supply.gd")
var game: Node3D
var seen := {}
var lost := {"player": {}, "enemy": {}}
var lost_value := {"player": 0, "enemy": 0}
var made := {"player": {}, "enemy": {}}
var delivered := {"player": {}, "enemy": {}}
var first_loss := {"player": -1.0, "enemy": -1.0}
var elapsed := 0.0
var unit_rules := {}
func _initialize() -> void: call_deferred("run")
## Proposed rules that live on the unit scene, set as each unit is made (before its _ready).
func _on_unit(unit: Node) -> void:
	if unit.get("unit_stats") == null: return
	var id: StringName = unit.unit_stats.unit_id
	if id == &"grail_sentinel" and unit_rules.has("sentinel"):
		for key in unit_rules.sentinel: unit.set(key,unit_rules.sentinel[key])
	if id == &"ubermech" and unit_rules.has("ubermech_missile"):
		var weapon = load("res://balance/second_weapon.gd").new()
		for key in unit_rules.ubermech_missile: weapon.set(key,unit_rules.ubermech_missile[key])
		unit.add_child(weapon)
## Drones stay over their own army instead of flying ahead of it.
func _escort(ais: Dictionary) -> void:
	for team in ais:
		var ai: Node = ais[team]
		for group in [ai.wave,ai.army.filter(func(u): return not ai.wave.has(u))]:
			var fighters: Array = group.filter(func(u): return is_instance_valid(u) and u.unit_stats.unit_id != &"drone")
			if fighters.is_empty(): continue
			var centre := Vector3.ZERO
			for unit in fighters: centre += unit.global_position
			centre /= fighters.size()
			for unit in group:
				if is_instance_valid(unit) and unit.unit_stats.unit_id == &"drone" and unit.global_position.distance_to(centre) > 8.0: unit.command_move(centre)
func kind_of(unit: Node) -> String:
	if unit.is_in_group("rail_trains"): return "train"
	if unit.get("is_depot_truck") == true: return "depot_truck"
	if unit.get("is_cargo_vehicle") == true: return "cargo"
	return str(unit.unit_stats.unit_id) if unit.get("unit_stats") != null else "other"
func value_of(unit: Node) -> int:
	if unit.get("energy_cost") == null: return 0
	return int(unit.energy_cost)+int(unit.food_cost)+int(unit.iron_cost)*5
func apply(ai: Node, settings: Dictionary) -> void:
	for key in settings:
		var value = settings[key]
		if value is Array:
			var typed: Array[StringName] = []
			for entry in value: typed.append(StringName(entry))
			ai.set(key,typed)
		else: ai.set(key,value)
func _on_delivered(target: Node3D, kind: StringName, amount: int) -> void:
	var team = target.get("team")
	if team in delivered: delivered[team][str(kind)] = delivered[team].get(str(kind),0)+amount
func track() -> void:
	var live := {}
	for unit in get_nodes_in_group("units"):
		if unit.is_queued_for_deletion() or unit.health <= 0: continue
		var id: int = unit.get_instance_id()
		live[id] = true
		if not seen.has(id):
			seen[id] = [unit.team,kind_of(unit),value_of(unit)]
			if unit.team in made: made[unit.team][seen[id][1]] = made[unit.team].get(seen[id][1],0)+1
	for id in seen.keys():
		if live.has(id): continue
		var entry: Array = seen[id]
		seen.erase(id)
		if entry[1] == "depot_truck" or not entry[0] in lost: continue
		lost[entry[0]][entry[1]] = lost[entry[0]].get(entry[1],0)+1
		lost_value[entry[0]] += entry[2]
		if first_loss[entry[0]] < 0 and entry[1] != "cargo": first_loss[entry[0]] = elapsed
func snapshot(team: String, ai: Node) -> Dictionary:
	var units := {}
	var army_value := 0
	for unit in get_nodes_in_group("units"):
		if unit.team != team or unit.health <= 0 or unit.is_queued_for_deletion(): continue
		var kind := kind_of(unit)
		units[kind] = units.get(kind,0)+1
	for unit in ai.army:
		if is_instance_valid(unit): army_value += value_of(unit)
	var buildings := {}
	for node in get_nodes_in_group("selectable_buildings"):
		if node.get("team") != team or node.is_in_group("mines"): continue
		var title: String = "Keep" if node.is_in_group("keeps") else ("Depot" if node.is_in_group("depots") else (node.stats.display_name if node.is_in_group("production_buildings") else ("Generator" if node.is_in_group("energy_generators") else ("Farm" if node.is_in_group("farms") else ("House" if node.is_in_group("houses") else str(node.name))))))
		buildings[title] = buildings.get(title,0)+1
	var stock := {"energy": 0, "iron": 0, "wood": 0, "coal": 0, "food": 0}
	for depot in get_nodes_in_group("depots"):
		if depot.team != team: continue
		for kind in stock: stock[kind] += depot.stockpile.amount(StringName(kind))
	var per_depot: Array = []
	for depot in get_nodes_in_group("depots"):
		if depot.team == team: per_depot.append([str(depot.name),depot.stockpile.amount(&"food"),depot.stockpile.amount(&"wood"),depot.stockpile.amount(&"iron")])
	return {"units": units, "buildings": buildings, "stock": stock, "per_depot": per_depot, "workers": ai.workers.size(), "army": ai.army.size(), "army_value": army_value,
		"wave": ai.wave.size(), "waves_sent": ai.waves_sent, "supply": [Supply.used(self,team),Supply.cap(self,team)],
		"lost": lost[team].duplicate(), "lost_value": lost_value[team], "made": made[team].duplicate(), "delivered": delivered[team].duplicate()}
## Puts the Knights' start in place of `team`'s Cyborg start and gives it a Knights AI.
func knights_side(team: String, settings: Dictionary) -> Node:
	var old: Node3D
	for depot in get_nodes_in_group("depots"):
		if depot.team == team: old = depot
	var at: Vector3 = old.global_position
	var gone: Array = [old]
	for unit in get_nodes_in_group("units"):
		if unit.team == team: gone.append(unit)
	for node in gone:
		node.get_parent().remove_child(node)
		node.queue_free()
	var start: Node3D = load("res://scenes/maps/starts/knights_start.tscn").instantiate()
	var entities: Node = game.get_node("Entities")
	var keep: Node3D
	var side := 1.0 if team == "player" else -1.0
	for child in start.get_children():
		var offset: Vector3 = child.position
		offset.x *= side
		start.remove_child(child)
		child.owner = null
		if "team" in child: child.team = team
		var parent := "Buildings" if child.name == "Keep" else ("Resources" if str(child.name).begins_with("Starter") else "Units")
		if child.name != "Keep": child.name = "%s_%s" % [team,child.name]
		entities.get_node(parent).add_child(child)
		child.global_position = at+offset
		if child.is_in_group("keeps"): keep = child
	start.free()
	if team == "player":
		game.depot = keep
		game.get_node("DepotNetwork").select_depot(keep)
	var stock: Dictionary = settings.get("stock",{"food": 150, "wood": 100, "iron": 50})
	for kind in ["food","wood","iron","energy","coal"]: keep.stockpile.set_amount(StringName(kind),0)
	for kind in stock: keep.stockpile.set_amount(StringName(kind),int(stock[kind]))
	if settings.get("no_crate",true):
		for crate in get_nodes_in_group("supply_crates"):
			if crate.team == team: crate.queue_free()
	var old_ai: Node = game.get_node("PlayerAI" if team == "player" else "EnemyPlayer")
	var ai_name := str(old_ai.name)
	old_ai.name = "Old"+ai_name
	old_ai.queue_free()
	var ai := Node.new()
	ai.set_script(load("res://balance/knights_player.gd"))
	ai.name = ai_name
	ai.team = team
	ai.opponent = "enemy" if team == "player" else "player"
	game.add_child(ai)
	return ai
func run() -> void:
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("MATCH_SPEC")))
	var rules: Dictionary = spec.get("rules",{})
	load("res://scripts/gameplay/unit_agent.gd").sim_require_sight = rules.get("sight",false)
	Supply.enabled = rules.get("supply",true)
	Supply.house_room = int(rules.get("house_room",8))
	load("res://balance/farm.gd").per_beat = int(rules.get("farm_per_beat",1))
	for id in spec.get("stats",{}):
		var stats: Resource = load("res://assets/units/%s.tres" % id)
		for key in spec.stats[id]: stats.set(key,spec.stats[id][key])
	var setup: Node = root.get_node("MatchSetup")
	if not setup.start("spectate"): push_error("could not start"); quit(1); return
	for frame in range(60):
		await process_frame
		if current_scene != null and current_scene.is_in_group("skirmish") and current_scene.is_node_ready(): break
	game = current_scene
	for frame in range(3): await process_frame
	var ais := {}
	for pair in [["player","west","PlayerAI"],["enemy","east","EnemyPlayer"]]:
		var settings: Dictionary = spec.get(pair[1],{})
		var ai: Node = knights_side(pair[0],settings) if settings.get("faction","cyborgs") == "knights" else game.get_node(pair[2])
		apply(ai,settings.get("ai",{}))
		ais[pair[0]] = ai
	for frame in range(3): await process_frame
	unit_rules = rules
	game.get_node("Entities/Units").child_entered_tree.connect(_on_unit)
	game.resources_delivered.connect(_on_delivered)
	game.get_node("Interface").process_mode = Node.PROCESS_MODE_DISABLED
	var minutes: float = spec.get("minutes",20.0)
	var log: Array = []
	var started := Time.get_ticks_msec()
	var outcome := ""
	for step in range(1,int(minutes*2)+1):
		for second in range(30):
			for frame in range(30): await process_frame
			elapsed += 1.0
			track()
			if rules.get("drone_escort",false): _escort(ais)
			for team in ["player","enemy"]:
				if get_nodes_in_group("depots").filter(func(d): return d.team == team and d.health > 0).is_empty() and outcome.is_empty():
					outcome = ("EAST" if team == "player" else "WEST")+" wins: the other side has no Depot or Keep left"
			if not outcome.is_empty(): break
		var row := {"t": elapsed, "west": snapshot("player",ais["player"]), "east": snapshot("enemy",ais["enemy"])}
		log.append(row)
		print("%5.0fs W %s army %d(%d) lost %d sup %s | E %s army %d(%d) lost %d sup %s" % [elapsed,row.west.units,row.west.army,row.west.army_value,lost_value["player"],row.west.supply,row.east.units,row.east.army,row.east.army_value,lost_value["enemy"],row.east.supply])
		if not outcome.is_empty(): break
	var extra := {}
	for team in ais:
		var ai: Node = ais[team]
		extra[team] = {"first_army_at": ai.get("first_army_at"), "no_room": ai.get("no_room"), "keeps_founded": ai.get("keeps_founded"), "balloons": ai.get("balloons_sent")}
	var result := {"name": spec.get("name",""), "outcome": outcome, "elapsed": elapsed, "wall": (Time.get_ticks_msec()-started)/1000.0, "first_loss": first_loss, "extra": extra, "log": log}
	var out := FileAccess.open(OS.get_environment("MATCH_OUT"),FileAccess.WRITE)
	out.store_string(JSON.stringify(result))
	out.close()
	print("MATCH_DONE %s · %s · %.0f game s in %.0f s" % [spec.get("name",""),outcome,elapsed,result.wall])
	quit()
