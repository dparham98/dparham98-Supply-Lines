extends SceneTree
# Headless (item 11 of docs/BALANCE_IMPLEMENTATION_HANDOFF.md, docs/UPGRADES.md): the Cyborgs' Foundry researches
# Infantry and Vehicle Weapons and Armour, and the Knights' Forge researches Arms and Mail, three levels each in
# order. A level is paid when it starts: Energy and Iron from a covering Depot, or Food and Iron from a covering
# Keep. Attack adds 10% of base damage a level (at least 1); armour takes 1 off every hit a level, never below 1.
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func spawn(id: String, team: String, point: Vector3) -> Node3D:
	var unit = load("res://scenes/gameplay/%s.tscn" % id).instantiate()
	unit.team = team
	unit.position = point
	game.get_node("Entities/Units").add_child(unit,true)
	unit.set_process(false)
	return unit
## The first open spot in the payer's range that takes a plan of `kind`.
func place(network: Node, kind: StringName, payer: Node3D) -> Node:
	for offset in [Vector3(14,0,4),Vector3(-14,0,-10),Vector3(-14,0,10),Vector3(14,0,-12),Vector3(0,0,16),Vector3(0,0,-16),Vector3(18,0,14),Vector3(-18,0,-14)]:
		var plan = network.queue_plan(payer.global_position+offset,kind,payer,true,false)
		if is_instance_valid(plan): return plan
	return null
func load_map(path: String) -> void:
	if is_instance_valid(game):
		game.queue_free()
		await process_frame
	game = load(path).instantiate()
	root.add_child(game)
	for i in range(3): await process_frame
	for name in ["EnemyPlayer","KnightsPlayer"]:
		var ai = game.get_node_or_null(name)
		if ai != null: ai.set_process(false)
func run() -> void:
	# --- The Cyborgs' Foundry.
	await load_map("res://scenes/maps/temple_exercise.tscn")
	var network = game.get_node("DepotNetwork")
	var depot: Node3D = game.depot
	var spec: Dictionary = network.plan_spec(&"foundry")
	if not check(spec.get("title") == "Foundry" and spec.get("energy") == 150 and spec.get("iron") == 80 and spec.get("size") == Vector2i(6,6),"Foundry plan spec should be 6 x 6 for 150 E / 80 I: %s" % spec): return
	var hud = game.get_node("Interface")
	if not check(hud.build_menu.get_node_or_null("Actions/Foundry") != null and hud.build_menu.get_node_or_null("Actions/Forge") != null,"The Build page needs Foundry and Forge tiles"): return
	var plan = place(network,&"foundry",depot)
	if not check(is_instance_valid(plan),"A Foundry plan could not be queued: "+game.message): return
	depot.stockpile.deposit(&"iron",80)
	var foundry = plan.complete_from_stock()
	if not check(is_instance_valid(foundry) and foundry.is_in_group("research_buildings") and foundry.research.size() == 12,"The plan should finish as a Foundry with 12 levels to research"): return
	await process_frame
	foundry.set_process(false)
	if not check(foundry.covering_depots().has(depot),"The Depot's range should cover the Foundry"): return
	# Levels in order.
	if not check(foundry.research_blocker(&"infantry_weapons_2").contains("level 1"),"Level 2 should wait for level 1: "+foundry.research_blocker(&"infantry_weapons_2")): return
	depot.stockpile.deposit(&"energy",400)
	depot.stockpile.deposit(&"iron",400)
	var energy: int = depot.energy
	var iron: int = depot.iron
	if not check(foundry.request_research(&"infantry_weapons_1"),"Infantry Weapons I was refused: "+game.message): return
	if not check(depot.energy == energy-100 and depot.iron == iron-150,"Level 1 should cost 100 E / 150 I"): return
	if not check(foundry.cancel_research() and depot.energy == energy and depot.iron == iron,"Cancel should refund the Depot"): return
	foundry.request_research(&"infantry_weapons_1")
	foundry._process(59.0)
	if not check(Upgrades.level(foundry,"player",Upgrades.INFANTRY_WEAPONS) == 0,"Level 1 takes 60 s"): return
	foundry._process(1.5)
	if not check(Upgrades.level(foundry,"player",Upgrades.INFANTRY_WEAPONS) == 1 and foundry.research_blocker(&"infantry_weapons_2").is_empty(),"After 60 s level 1 is done and level 2 opens"): return
	var lvl2: ResearchStats = foundry.research_by_id(&"infantry_weapons_2")
	var lvl3: ResearchStats = foundry.research_by_id(&"vehicle_armour_3")
	if not check(lvl2.energy_cost == 150 and lvl2.iron_cost == 250 and lvl2.seconds == 90.0 and lvl3.energy_cost == 200 and lvl3.iron_cost == 350 and lvl3.seconds == 120.0,"Levels 2 and 3 cost 150/250 in 90 s and 200/350 in 120 s"): return
	# The card: one tile per line, offering the next level.
	game.selected_building = foundry
	hud._process(0)
	for n in range(1,5):
		if not check(hud.desired_buttons.has("Upgrade%d" % n),"The Foundry card should show Upgrade%d: %s" % [n,hud.desired_buttons]): return
	if not check(hud.card.get_node("Upgrade1").get_meta("research") == &"infantry_weapons_2","The Infantry Weapons tile should offer level 2"): return
	game.selected_building = null
	# Attack: +10% of base a level, at least 1. Infantry lines leave vehicles alone, and the other way round.
	var deforester := spawn("infantry","player",depot.global_position+Vector3(6,0,6))
	var tank := spawn("tank","player",depot.global_position+Vector3(8,0,6))
	Research.complete(game,"player",&"infantry_weapons_2")
	if not check(Upgrades.with_attack(deforester,20) == 24 and Upgrades.with_attack(deforester,4) == 6 and Upgrades.with_attack(tank,20) == 20,"Infantry Weapons II: 20 -> 24, 4 -> 6, tanks unchanged (%d, %d, %d)" % [Upgrades.with_attack(deforester,20),Upgrades.with_attack(deforester,4),Upgrades.with_attack(tank,20)]): return
	# Armour: -1 a hit a level, never below 1.
	for n in range(1,4): Research.complete(game,"player",Upgrades.research_id(Upgrades.VEHICLE_ARMOUR,n))
	if not check(Upgrades.after_armour(tank,10) == 7 and Upgrades.after_armour(tank,2) == 1 and Upgrades.after_armour(deforester,10) == 10,"Vehicle Armour III: 10 -> 7, 2 -> 1, infantry unchanged"): return
	var hp: int = tank.health
	tank.take_damage(10)
	if not check(tank.health == hp-7,"An armoured tank should lose 7 to a 10 hit (lost %d)" % (hp-tank.health)): return
	# The upgrade reaches real hits through the resolver.
	var enemy := spawn("infantry","enemy",depot.global_position+Vector3(7,0,7))
	var base := CombatResolver.damage_for(deforester,enemy)
	if not check(CombatResolver.splash_damage(deforester,enemy,enemy) == Upgrades.with_attack(deforester,base) and Upgrades.with_attack(deforester,base) > base,"A Deforester's shot should carry Infantry Weapons II"): return
	# --- The Knights' Forge, paid in Food and Iron by a Keep.
	await load_map("res://scenes/maps/arthurian_skirmish.tscn")
	network = game.get_node("DepotNetwork")
	var keep: Node3D = null
	for node in get_nodes_in_group("keeps"):
		if node.team == "player": keep = node
	if not check(keep != null,"The Knights map should have a player Keep"): return
	spec = network.plan_spec(&"forge")
	if not check(spec.get("title") == "Forge" and spec.get("wood") == 60 and spec.get("iron") == 80 and spec.get("energy") == 0 and spec.get("keep_stock") == true,"Forge plan spec should be 60 W / 80 I from a Keep's stock: %s" % spec): return
	keep.stockpile.deposit(&"wood",200)
	keep.stockpile.deposit(&"iron",400)
	keep.stockpile.deposit(&"food",400)
	plan = place(network,&"forge",keep)
	if not check(is_instance_valid(plan),"A Forge plan could not be queued: "+game.message): return
	var forge = plan.complete_from_stock()
	if not check(is_instance_valid(forge) and forge.is_in_group("research_buildings") and forge.research.size() == 6,"The plan should finish as a Forge with 6 levels"): return
	await process_frame
	forge.set_process(false)
	var food: int = keep.food
	iron = keep.iron
	if not check(forge.request_research(&"arms_1"),"Arms I was refused: "+game.message): return
	if not check(keep.food == food-100 and keep.iron == iron-150,"Arms I should cost 100 F / 150 I from the Keep (food %d -> %d, iron %d -> %d)" % [food,keep.food,iron,keep.iron]): return
	forge._process(61.0)
	if not check(Upgrades.level(forge,"player",Upgrades.ARMS) == 1,"Arms I should be done after 60 s"): return
	game.selected_building = forge
	game.get_node("Interface")._process(0)
	var tiles: Array = game.get_node("Interface").desired_buttons
	if not check(tiles.has("Upgrade1") and tiles.has("Upgrade2") and not tiles.has("Upgrade3"),"The Forge card should show two upgrade tiles: %s" % [tiles]): return
	game.selected_building = null
	var marine := spawn("round_table_marine","player",keep.global_position+Vector3(6,0,6))
	if not check(Upgrades.with_attack(marine,30) == 33,"Arms I: a Marine's 30 becomes 33"): return
	Research.complete(game,"player",&"mail_1")
	if not check(Upgrades.after_armour(marine,10) == 9,"Mail I: 10 -> 9 on a Marine"): return
	game.queue_free()
	await process_frame
	print("UPGRADES_TEST_PASSED")
	quit(0)
