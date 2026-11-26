extends SceneTree
# Headless: the two play-test scenes (docs/PLAYTEST_EXERCISES.md). In each, every building stands where it was saved,
# on the player's side and paid from the right stockpile; every unit stands on a tile it can walk; the HUD shows the
# right faction; the research buildings can start their first research; the guard and both mines are the enemy's.
# The Knights scene's track reaches both Keeps, the Dragon Yard can order a train, the Houses give room for the
# army and the Sentinels can cast. Then each runs 20 s with the enemy AI on and the player's home still stands.
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func open(path: String) -> void:
	if is_instance_valid(game):
		game.queue_free()
		await process_frame
	game = load(path).instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	var ai = game.get_node_or_null("EnemyPlayer")
	if ai != null: ai.set_process(false)
func run() -> void:
	await open("res://scenes/maps/cyborg_exercise.tscn")
	if not await cyborgs(): return
	await open("res://scenes/maps/knights_exercise.tscn")
	if not await knights(): return
	print("PLAYTEST_EXERCISES_TEST_PASSED")
	quit()
func standing(ids: Array, payer: Node3D) -> bool:
	var buildings := game.get_node("Entities/Buildings")
	for id in ids:
		var node = buildings.get_node_or_null(id)
		if not check(is_instance_valid(node) and node.is_inside_tree() and node.team == "player",id+" did not stand, or is not the player's"): return false
		if payer != null and not check(node.assigned_depot == payer,id+" should pay from "+payer.name): return false
	return true
## Every unit on a walkable tile, the player's covering `kinds`, the guard all the enemy's; both mines the enemy's.
func army(kinds: Array) -> bool:
	var seen := {}
	for unit in get_nodes_in_group("units"):
		if unit.get("unit_stats") == null: continue
		var tile = game.ground.get_tile_at_position(unit.global_position)
		if not check(tile != null and game.ground.can_traverse(tile,unit.mobility_layer(),unit._owner_key()),"%s stands on a tile it can't walk" % unit.name): return false
		if str(unit.name).begins_with("Guard"):
			if not check(unit.team == "enemy","%s should be the enemy's" % unit.name): return false
			continue
		if unit.team == "player": seen[unit.unit_stats.unit_id] = true
	for id in kinds:
		if not check(seen.has(id),"No player %s in the exercise" % id): return false
	for i in [1,2]:
		var mine = game.get_node_or_null("Entities/EnemyMine%d" % i)
		if not check(mine != null and mine.is_in_group("land_mines") and mine.team == "enemy","EnemyMine%d should be an enemy land mine" % i): return false
	return true
func research(pairs: Array) -> bool:
	var buildings := game.get_node("Entities/Buildings")
	for pair in pairs:
		var node = buildings.get_node(pair[0])
		var blocker: String = node.research_blocker(pair[1])
		if not check(blocker.is_empty(),"%s can't start %s: %s" % [pair[0],pair[1],blocker]): return false
		if not check(node.request_research(pair[1]),"%s refused %s: %s" % [pair[0],pair[1],game.message]): return false
	return true
## 20 s with the enemy AI on; `home` must still stand.
func play(home: Node3D) -> bool:
	var ai = game.get_node_or_null("EnemyPlayer")
	if ai != null: ai.set_process(true)
	var start := Time.get_ticks_msec()
	var simulated := 0.0
	while simulated < 20.0:
		await physics_frame
		simulated += 1.0/Engine.physics_ticks_per_second
		if Time.get_ticks_msec()-start > 120000: break
	return check(is_instance_valid(home) and home.is_inside_tree() and home.team == "player","The player's home fell in the first 20 s")
func cyborgs() -> bool:
	var hud = game.get_node("Interface")
	if not check(hud.has_cyborg_faction() and not hud.knights_build(),"The Cyborg exercise should show the Cyborg HUD"): return false
	if not standing(["Depot"],null) or not standing(["TempleOfScience","Foundry","TankFactory"],game.depot): return false
	if not army([&"motorcycle",&"drone",&"ubermech",&"tank",&"grenadier",&"infantry"]): return false
	if not research([["TempleOfScience",Research.MINELAYING],["Foundry",&"infantry_weapons_1"]]): return false
	return await play(game.depot)
func knights() -> bool:
	var buildings := game.get_node("Entities/Buildings")
	var keep = buildings.get_node_or_null("Keep")
	var keep_b = buildings.get_node_or_null("KeepB")
	if not check(buildings.get_node_or_null("Depot") == null,"The Knights exercise should have no Depot"): return false
	if not check(keep != null and keep_b != null and keep.is_in_group("keeps") and keep_b.is_in_group("keeps"),"Both Keeps should be Keeps"): return false
	if not check(game.depot == keep,"The game's home should be the Keep"): return false
	var hud = game.get_node("Interface")
	if not check(hud.knights_build() and not hud.has_cyborg_faction(),"The Knights exercise should show the Knights HUD"): return false
	if not standing(["KeepB"],null) or not standing(["Chapterhouse","Forge","DragonYard"],keep) or not standing(["House1","House2","House3"],null): return false
	if not army([&"grail_sentinel",&"round_table_marine",&"questing_marine",&"warhound",&"forester_maiden"]): return false
	var rails = game.get_node("RailNetwork")
	if not check(rails.pieces.size() >= 2,"The track should be laid (%d pieces)" % rails.pieces.size()): return false
	if not check(not rails.loading_pieces(keep,"player").is_empty() and not rails.loading_pieces(keep_b,"player").is_empty(),"The track should reach both Keeps' loading areas"): return false
	var yard = buildings.get_node("DragonYard")
	var refusal: String = KnightRail.yard_train_refusal(yard)
	if not check(refusal.is_empty(),"The Dragon Yard can't order a train: "+refusal): return false
	if not check(KnightHousing.used(self,"player") <= KnightHousing.cap(self,"player"),"The Houses should give room for the army (%s)" % KnightHousing.text(self,"player")): return false
	if not check(KnightHousing.room(self,"player",&"azure_dragon"),"There should be room for a Dragon (%s)" % KnightHousing.text(self,"player")): return false
	if not research([["Forge",&"arms_1"]]): return false
	for name in ["Sentinel1","Sentinel2","Sentinel3"]:
		var sentinel = game.get_node_or_null("Entities/Units/"+name)
		if not check(sentinel != null and sentinel.med_reserve >= sentinel.spell_cost("mist") and sentinel.med_reserve >= sentinel.spell_cost("slow"),name+" should have reserve for Mist and Slow"): return false
	return await play(keep)
