extends SceneTree
# Not part of the headless suite, which runs in real time: an AI-against-AI match on Two Lakes in game time
# (docs/KNIGHTS_AI.md). The West AI plays SUPPLY_LINES_WEST (cyborgs or arthurian_knights, default cyborgs), the East
# AI plays SUPPLY_LINES_EAST (default arthurian_knights), for SUPPLY_LINES_AI_MINUTES (default 10). Prints a line a
# minute for each side, then the checks of item 5 of docs/BALANCE_IMPLEMENTATION_HANDOFF.md:
# - a Cyborg side completes its build order;
# - neither side is wiped out before 10:00;
# - a Knights side has 50 army units by 8:00 (item 4's check).
# Run with a fixed step:
#   godot --headless --fixed-fps 30 --path . --script res://tests/ai_match_sim.gd
# SUPPLY_LINES_AI_DEBUG=1 also prints the plan each Cyborg AI is waiting on.
var game: Node3D
func _initialize() -> void: call_deferred("run")
func env(name: String, fallback: String) -> String:
	return OS.get_environment(name) if OS.has_environment(name) else fallback
func run() -> void:
	var west := StringName(env("SUPPLY_LINES_WEST","cyborgs"))
	var east := StringName(env("SUPPLY_LINES_EAST","arthurian_knights"))
	var minutes := int(env("SUPPLY_LINES_AI_MINUTES","10"))
	var setup = root.get_node("MatchSetup")
	setup.configured = true
	setup.mode = "spectate"
	setup.map_id = "two_lakes"
	setup.factions = {"player": west, "enemy": east}
	game = load(setup.map_path()).instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	var sides := {"player": game.get_node("PlayerAI"), "enemy": game.enemy_player()}
	var army_at_8 := {"player": -1, "enemy": -1}
	var wiped := {"player": -1, "enemy": -1}
	var started := Time.get_ticks_msec()
	for minute in range(1,minutes+1):
		for frame in range(30*60): await process_frame
		for team in sides:
			var ai: Node = sides[team]
			var faction: StringName = setup.factions[team]
			var left: int = ai.own_units().size()+ai.own_buildings().size()
			if left == 0 and wiped[team] < 0: wiped[team] = minute
			print("%s %2d min · %s · %s" % [team.to_upper(),minute,faction,_line(ai,faction)])
			if faction == &"cyborgs" and OS.has_environment("SUPPLY_LINES_AI_DEBUG") and is_instance_valid(ai.plan):
				print("     waiting on %s at %s · %s · iron short %d · builders %d" % [ai.plan.kind,ai.plan.global_position,ai.plan.state,ai.plan.shortfall(&"iron"),ai.workers.filter(func(u): return u.order == "construct" and u.order_target == ai.plan).size()])
				if ai.plan.state.contains("footprint"): print("     on the footprint: %s" % _blockers(ai.plan))
				var truck = ai._cargo_truck()
				print("     truck: %s" % ("none" if truck == null else "%s at %s · %s · %s · fetching %s · cargo %s" % [truck.name,truck.global_position,truck.order,truck.state,truck.get("fetch_plan"),truck.get("manifest")]))
			if minute == 8: army_at_8[team] = ai.army.size()
	print("Match ran %d game minutes in %.1f s" % [minutes,(Time.get_ticks_msec()-started)/1000.0])
	var failures := 0
	for team in sides:
		var ai: Node = sides[team]
		var faction: StringName = setup.factions[team]
		if faction == &"cyborgs" and ai.build_step < ai.build_order.size():
			failures += 1; print("FAIL %s: the build order stopped at step %d of %d (%s)" % [team,ai.build_step,ai.build_order.size(),ai.build_order[ai.build_step]])
		if wiped[team] > 0 and wiped[team] < 10:
			failures += 1; print("FAIL %s: wiped out at %d min" % [team,wiped[team]])
		if faction == &"arthurian_knights" and minutes >= 8 and army_at_8[team] < 50:
			print("NOTE %s: %d army units at 8:00 (the handoff expects 50)" % [team,army_at_8[team]])
	print("AI_MATCH_PASSED" if failures == 0 else "AI_MATCH_FAILED")
	quit(0 if failures == 0 else 1)
func _line(ai: Node, faction: StringName) -> String:
	var mine := func(group: String) -> int: return get_nodes_in_group(group).filter(func(n): return n.get("team") == ai.team and n.get("health") != null and n.health > 0).size()
	if faction == &"arthurian_knights":
		var halls: int = get_nodes_in_group("production_buildings").filter(func(b): return b.team == ai.team and b.stats.building_id == &"chapterhouse").size()
		var keep: Node3D = ai.home()
		var forges: int = get_nodes_in_group("research_buildings").filter(func(b): return b.team == ai.team and b.stats.building_id == &"forge").size()
		return "Keeps %d Farms %d Houses %d Halls %d Forge %d (Arms %d Mail %d) · Foresters %d army %d wave %d · housing %s · %s" % [ai.own_keeps().size(),mine.call("farms"),mine.call("houses"),halls,forges,Upgrades.level(game,ai.team,&"arms"),Upgrades.level(game,ai.team,&"mail"),ai.workers.size(),ai.army.size(),ai.wave.size(),KnightHousing.text(self,ai.team),"%d F %d W %d I" % [keep.food,keep.wood,keep.iron] if keep != null else "no Keep"]
	var depot: Node3D = ai.home()
	var count := func(id: StringName) -> int: return get_nodes_in_group("production_buildings").filter(func(b): return b.team == ai.team and b.stats.building_id == id).size()
	var levels: Array = ai.upgrade_lines.map(func(line): return Upgrades.level(game,ai.team,line))
	return "step %d/%d (%s) · Gen %d Bar %d Fac %d Foundry %d %s · workers %d army %d wave %d · %s" % [ai.build_step,ai.build_order.size(),str(ai.plan.kind) if is_instance_valid(ai.plan) else "-",mine.call("energy_generators"),count.call(&"barracks"),count.call(&"tank_factory"),get_nodes_in_group("research_buildings").filter(func(b): return b.team == ai.team and b.stats.building_id == &"foundry").size(),levels,ai.workers.size(),ai.army.size(),ai.wave.size(),"%d E %d I" % [depot.energy,depot.iron] if depot != null else "no Depot"]
## What stands on a plan's footprint: the claims on its cells, and the units whose cell is inside it.
func _blockers(plan: Node3D) -> String:
	var parts: Array[String] = []
	var rect: Rect2i = plan.footprint()
	for x in range(rect.position.x,rect.end.x):
		for z in range(rect.position.y,rect.end.y):
			var tile: Dictionary = game.ground.tiles[z*game.ground.grid_size.x+x]
			for key in ["occupied_by","apron","rail","mine_front","field"]:
				if tile.has(key) and tile.get(key) != null and not str(tile.get(key)).is_empty(): parts.append("%s=%s" % [key,tile.get(key)])
			if not game.ground.is_tile_valid(Vector2i(x,z)): parts.append("invalid tile (terrain %s)" % game.ground.get_terrain(Vector2i(x,z)))
	for unit in get_nodes_in_group("units"):
		var cell = game.ground.get_tile_at_position(unit.global_position)
		if cell != null and rect.has_point(cell): parts.append("%s(%s, %s, %s)" % [unit.name,unit.team,unit.order,unit.state])
	var unique: Array[String] = []
	for part in parts:
		if not unique.has(part): unique.append(part)
	return ", ".join(unique)
