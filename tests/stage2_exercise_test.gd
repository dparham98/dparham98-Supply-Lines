extends SceneTree
# Headless: scenes/maps/stage2_exercise.tscn (docs/STAGE2_EXERCISE.md). Every building stands where it was saved, on
# the player's side, paid from the right stockpile; every unit stands on a tile it can walk; the Build page offers
# both factions' buildings; each research building can start its first research; the Sentinels can cast; the enemy
# guard is the enemy's.
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func run() -> void:
	game = load("res://scenes/maps/stage2_exercise.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	var ai = game.get_node_or_null("EnemyPlayer")
	if ai != null: ai.set_process(false)
	var buildings := game.get_node("Entities/Buildings")
	var keep = buildings.get_node_or_null("Keep")
	var keep_b = buildings.get_node_or_null("KeepB")
	for id in ["TempleOfScience","Foundry","Keep","KeepB","Forge","Wainwright"]:
		var node = buildings.get_node_or_null(id)
		if not check(is_instance_valid(node) and node.is_inside_tree() and node.team == "player",id+" did not stand, or is not the player's"): return
	if not check(keep.is_in_group("keeps") and keep_b.is_in_group("keeps"),"Both Keeps should be Keeps"): return
	for id in ["TempleOfScience","Foundry"]:
		if not check(buildings.get_node(id).assigned_depot == game.depot,id+" should pay from the Depot"): return
	for id in ["Forge","Wainwright"]:
		if not check(buildings.get_node(id).assigned_depot == keep,id+" should pay from the Keep"): return
	var hud = game.get_node("Interface")
	for kind in [&"foundry",&"temple_of_science",&"rail",&"forge",&"wainwright",&"keep"]:
		if not check(hud.build_kind_offered(kind),"The Build page should offer %s" % kind): return
	var seen := {}
	for unit in get_nodes_in_group("units"):
		if unit.get("unit_stats") == null: continue
		var tile = game.ground.get_tile_at_position(unit.global_position)
		if not check(tile != null and game.ground.can_traverse(tile,unit.mobility_layer(),unit._owner_key()),"%s stands on a tile it can't walk" % unit.name): return
		if str(unit.name).begins_with("Guard"):
			if not check(unit.team == "enemy","%s should be the enemy's" % unit.name): return
			continue
		if unit.team == "player": seen[unit.unit_stats.unit_id] = true
	for id in [&"motorcycle",&"drone",&"ubermech",&"tank",&"grenadier",&"infantry",&"grail_sentinel",&"round_table_marine",&"questing_marine",&"forester_maiden"]:
		if not check(seen.has(id),"No player %s in the exercise" % id): return
	# Each research building starts its first research from its own stockpile.
	for pair in [["TempleOfScience",Research.MINELAYING],["Foundry",&"infantry_weapons_1"],["Forge",&"arms_1"]]:
		var node = buildings.get_node(pair[0])
		var blocker: String = node.research_blocker(pair[1])
		if not check(blocker.is_empty(),"%s can't start %s: %s (Depot %d E %d I, Keep %d F %d I)" % [pair[0],pair[1],blocker,game.depot.energy,game.depot.iron,keep.food,keep.iron]): return
		if not check(node.request_research(pair[1]),"%s refused %s: %s" % [pair[0],pair[1],game.message]): return
	var sentinel = game.get_node_or_null("Entities/Units/Sentinel1")
	if not check(sentinel != null and sentinel.med_reserve >= sentinel.spell_cost("mist"),"The first Sentinel should have reserve for Mist"): return
	print("STAGE2_EXERCISE_TEST_PASSED")
	quit()
