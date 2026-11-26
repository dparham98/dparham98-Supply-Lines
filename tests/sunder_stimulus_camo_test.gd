extends SceneTree
# Headless (item 3 of the Round 3 handoff; docs/ROUND3_SPELLS_AND_RESEARCH.md):
# - Mist and Slow are cast from 24 m; Slow slows an enemy Tank.
# - Stimulus costs 35 reserve and is cast from 14 m. Friendly units within 5 m that aren't vehicles, the Dragon
#   too, move and attack 25% faster for 7 s; a second cast restarts the time and doesn't add up.
# - The Forge offers Sundering Lances (125 F / 150 I / 100 C, 60 s) and Forest Camouflage (75 F / 100 I / 50 C,
#   45 s), paid in coal too, and Cancel gives the coal back.
# - With Sundering Lances a Questing Marine's hit sunders an armoured or giant unit, not a light one, for 4 s; every
#   hit on it then deals 3 more after armour.
# - With Forest Camouflage a Warhound in forest is hidden from the other side unless a detector covers it; it shows
#   again 1.5 s after leaving the forest, and for 2 s after it attacks.
var game: Node3D
var network: Node
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
	network = game.get_node("DepotNetwork")
	game.set_process(false)
	game.get_node("Interface").set_process(false)
	var ai = game.get_node_or_null("EnemyPlayer")
	if ai != null: ai.set_process(false)
	for group in ["units","depots","production_buildings","farms","houses","energy_generators","mines","fog_of_war"]:
		for node in get_nodes_in_group(group): node.set_process(false)
func spawn(id: String, point: Vector3, team := "player") -> Node3D:
	var unit = load("res://scenes/gameplay/"+id+".tscn").instantiate()
	unit.team = team
	game.get_node("Entities/Units").add_child(unit)
	unit.set_process(false)
	unit._stop_route()
	for cell in unit._claimed.duplicate(): unit._release(cell)
	place(unit,game.ground.nearest_actor_cell(game.ground.get_tile_at_position(point),unit.mobility_layer(),unit._owner_key()))
	unit._attack_enabled = false
	return unit
## Puts a unit on `cell`.
func place(unit: Node3D, cell: Vector2i) -> void:
	for claimed in unit._claimed.duplicate(): unit._release(claimed)
	unit.grid_position = cell
	unit.global_position = game.ground.tile_to_world(cell)
	unit._claim(cell)
func step(nodes: Array, seconds: float, until := Callable()) -> float:
	var frames := ceili(seconds*60)
	for i in range(frames):
		for node in nodes:
			if is_instance_valid(node) and node.is_inside_tree(): node._process(1.0/60)
		if until.is_valid() and until.call(): return (i+1)/60.0
	return seconds
## A plan finished at once from its materials, as the playtest tools do.
func stand(kind: StringName, point: Vector3, team := "player") -> Node3D:
	var plan = network.queue_plan(point,kind,null,false,false,team)
	if plan == null: return null
	var building = network.finish_plan(plan)
	plan.queue_free()
	return building
func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x-b.x,a.z-b.z).length()
func run() -> void:
	if not await spells(): return
	if not await forge(): return
	if not await sundering(): return
	if not await camouflage(): return
	print("SUNDER_STIMULUS_CAMO_TEST_PASSED")
	quit()
## Casts `kind` at `point` and steps until the Sentinel is done.
func cast(sentinel: Node3D, kind: String, point: Vector3, others: Array = []) -> bool:
	sentinel.command_spell(kind,point)
	if sentinel.order != kind: return false
	step([sentinel]+others,20.0,func(): return sentinel.order != kind)
	return sentinel.order == "idle" and sentinel.state.begins_with(kind.capitalize()+" cast")
func spells() -> bool:
	await open("res://scenes/maps/resource_skirmish.tscn")
	var rules: SpellRules = load("res://assets/combat/spell_rules.tres")
	if not check(rules.cast_range == 24.0 and rules.stimulus_cost == 35 and rules.stimulus_cast_range == 14.0 and rules.stimulus_radius == 5.0 and rules.stimulus_seconds == 7.0 and is_equal_approx(rules.stimulus_boost,0.25),"Spell rules: Mist and Slow from 24 m; Stimulus 35, 14 m, 5 m, 7 s, +25%"): return false
	var near: Vector3 = game.depot.global_position+Vector3(-30,0,-50)
	# Slow from 22 m away: no need to walk; an enemy Tank is slowed.
	Research.complete(game,"player",Research.SLOW)
	var tank = spawn("tank",near+Vector3(-22,0,0),"enemy")
	var sentinel = spawn("grail_sentinel",near)
	var from: Vector3 = sentinel.global_position
	if not check(cast(sentinel,"slow",tank.global_position),"The Sentinel should cast Slow: '%s'" % sentinel.state): return false
	if not check(sentinel.global_position.distance_to(from) < 0.5,"Slow should be cast from %.1f m without walking" % flat(from,tank.global_position)): return false
	if not check(is_equal_approx(tank.speed_scale(),0.6),"Slow should slow an enemy Tank to 60%%, not %.2f" % tank.speed_scale()): return false
	tank.queue_free()
	await process_frame
	# Stimulus at the Sentinel's feet: friends within 5 m that aren't vehicles.
	var marine = spawn("round_table_marine",near+Vector3(2,0,2))
	var hound = spawn("warhound",near+Vector3(0,0,-3))
	var dragon = spawn("azure_dragon",near+Vector3(-3,0,0))
	var own_tank = spawn("tank",near+Vector3(3,0,-3))
	var foe = spawn("infantry",near+Vector3(-2,0,3),"enemy")
	for unit in [marine,hound,dragon,own_tank,foe]:
		if not check(flat(unit.global_position,sentinel.global_position) <= rules.stimulus_radius-0.3,"%s should stand within Stimulus's radius: %.1f m" % [unit.name,flat(unit.global_position,sentinel.global_position)]): return false
	var reserve: int = sentinel.med_reserve
	if not check(cast(sentinel,"stimulus",sentinel.global_position),"The Sentinel should cast Stimulus: '%s'" % sentinel.state): return false
	if not check(reserve-sentinel.med_reserve == 35,"Stimulus should cost 35 reserve, not %d" % (reserve-sentinel.med_reserve)): return false
	for unit in [marine,hound,dragon]:
		if not check(is_equal_approx(unit.attack_rate_scale(),1.25) and is_equal_approx(unit.speed_scale(),1.25),"%s should move and attack 25%% faster: %.2f, %.2f" % [unit.name,unit.attack_rate_scale(),unit.speed_scale()]): return false
	if not check(not own_tank.stimulated() and not foe.stimulated(),"Stimulus should pass over a vehicle and an enemy"): return false
	# Attack rate: the Marine's reload is the interval / 1.25.
	marine._attack_enabled = true
	marine._shoot(foe)
	var interval: float = CombatResolver.interval_for(marine,foe,0)
	if not check(is_equal_approx(marine._cooldown,interval/1.25),"A stimulated Marine should reload in %.2f s, not %.2f" % [interval/1.25,marine._cooldown]): return false
	marine._attack_enabled = false
	# Move speed: 1.25 times as far in a second.
	var start: Vector3 = hound.global_position
	hound.command_move(hound.global_position+Vector3(-25,0,0))
	step([hound],1.0)
	var ran := flat(start,hound.global_position)
	if not check(ran > hound.move_speed*1.05,"A stimulated Warhound should run about %.1f m in 1 s, not %.1f" % [hound.move_speed*1.25,ran]): return false
	# A second Sentinel 20 m off walks within 14 m; its Stimulus restarts the time and doesn't add up.
	step([marine,dragon],4.0)
	var second = spawn("grail_sentinel",near+Vector3(0,0,20))
	if not check(flat(second.global_position,marine.global_position) > 15.0,"The second Sentinel should start beyond 14 m"): return false
	if not check(cast(second,"stimulus",marine.global_position,[marine,dragon]),"The second Sentinel should cast Stimulus: '%s'" % second.state): return false
	if not check(flat(second.global_position,marine.global_position) <= 14.0+0.5,"Stimulus should be cast from within 14 m, not %.1f" % flat(second.global_position,marine.global_position)): return false
	if not check(marine._stimulus_left > 6.0 and is_equal_approx(marine.attack_rate_scale(),1.25),"A second Stimulus should restart the time (%.1f s left) and not add up (%.2f)" % [marine._stimulus_left,marine.attack_rate_scale()]): return false
	step([marine],7.1)
	if not check(not marine.stimulated() and is_equal_approx(marine.speed_scale(),1.0),"Stimulus should wear off after 7 s"): return false
	if not check(sentinel.spell_blocker("stimulus").is_empty() and sentinel.spell_range("stimulus") == 14.0 and sentinel.spell_range("mist") == 24.0,"Spell ranges: Stimulus 14, Mist 24"): return false
	return true
func forge() -> bool:
	await open("res://scenes/maps/arthurian_skirmish.tscn")
	var keep = game.get_node("Entities/Buildings/Keep")
	for kind in [&"food",&"iron"]: keep.stockpile.deposit(kind,400)
	var forge: Node3D = null
	for offset in [Vector3(0,0,16),Vector3(0,0,-16),Vector3(16,0,0),Vector3(-16,0,0)]:
		if forge == null: forge = stand(&"forge",keep.global_position+offset)
	if not check(forge != null,"A Forge should stand by the Keep"): return false
	forge.set_process(false)
	var lances: ResearchStats = forge.research_by_id(Research.SUNDERING)
	var camo: ResearchStats = forge.research_by_id(Research.CAMOUFLAGE)
	if not check(lances != null and lances.food_cost == 125 and lances.iron_cost == 150 and lances.coal_cost == 100 and lances.seconds == 60.0,"Sundering Lances: 125 F / 150 I / 100 C, 60 s"): return false
	if not check(camo != null and camo.food_cost == 75 and camo.iron_cost == 100 and camo.coal_cost == 50 and camo.seconds == 45.0,"Forest Camouflage: 75 F / 100 I / 50 C, 45 s"): return false
	if not check(forge.cost_text(lances) == "125 F · 150 I · 100 C","Cost text: '%s'" % forge.cost_text(lances)): return false
	keep.stockpile.spend({&"coal":keep.coal})
	if not check(forge.research_blocker(Research.SUNDERING).contains("100 C"),"Without coal Sundering Lances should wait: '%s'" % forge.research_blocker(Research.SUNDERING)): return false
	keep.stockpile.deposit(&"coal",120)
	if not check(forge.request_research(Research.SUNDERING) and keep.coal == 20,"Sundering Lances should take 100 coal from the Keep (%d left)" % keep.coal): return false
	if not check(forge.cancel_research() and keep.coal == 120,"Cancel should give the coal back (%d)" % keep.coal): return false
	return true
func sundering() -> bool:
	await open("res://scenes/maps/resource_skirmish.tscn")
	var rules: ForgeResearchRules = load("res://assets/combat/forge_research_rules.tres")
	if not check(rules.sunder_seconds == 4.0 and rules.sunder_bonus == 3,"Sundering: 4 s, +3"): return false
	var near: Vector3 = game.depot.global_position+Vector3(-30,0,-50)
	var lancer = spawn("questing_marine",near)
	var marine = spawn("round_table_marine",near+Vector3(0,0,4))
	var tank = spawn("tank",near+Vector3(-10,0,0),"enemy")
	var dragon = spawn("azure_dragon",near+Vector3(-10,0,8),"enemy")
	var foot = spawn("infantry",near+Vector3(-10,0,-6),"enemy")
	if not check(lancer.has_ability(&"sundering_lances"),"The Questing Marine carries Sundering Lances"): return false
	CombatResolver.strike(lancer,tank)
	if not check(not tank.sundered(),"Before the research a hit shouldn't sunder"): return false
	Research.complete(game,"player",Research.SUNDERING)
	CombatResolver.strike(marine,tank)
	if not check(not tank.sundered(),"A Round Table Marine's hit shouldn't sunder"): return false
	var health: int = tank.health
	CombatResolver.strike(lancer,tank)
	var first: int = CombatResolver.splash_damage(lancer,tank,tank)
	if not check(tank.sundered() and health-tank.health == first,"The Questing Marine's hit should sunder the Tank, the hit itself unchanged (%d, not %d)" % [health-tank.health,first]): return false
	health = tank.health
	tank.take_damage(10)
	if not check(health-tank.health == 13,"A sundered Tank should take 10+3, not %d" % (health-tank.health)): return false
	Research.complete(game,"enemy",&"vehicle_armour_1")
	health = tank.health
	tank.take_damage(10)
	if not check(health-tank.health == 12,"With Vehicle Armour I: 10-1+3 = 12, not %d" % (health-tank.health)): return false
	health = tank.health
	tank.take_damage(1)
	if not check(health-tank.health == 4,"A 1 after armour is still 1, then +3: 4, not %d" % (health-tank.health)): return false
	CombatResolver.strike(lancer,dragon)
	CombatResolver.strike(lancer,foot)
	if not check(dragon.sundered() and not foot.sundered(),"A giant Dragon is sundered; light Infantry isn't"): return false
	step([tank],4.1)
	health = tank.health
	tank.take_damage(10)
	if not check(not tank.sundered() and health-tank.health == 9,"After 4 s the Tank is no longer sundered: 10-1 = 9, not %d" % (health-tank.health)): return false
	return true
## A Forest cell with open ground on its east side, at least `clear` metres from any building or unit.
func forest_edge(clear: float) -> Variant:
	var ground = game.ground
	var things: Array = get_nodes_in_group("selectable_buildings")+get_nodes_in_group("units")
	for z in range(-220,221,6):
		for x in range(-220,221,6):
			var cell = ground.get_tile_at_position(Vector3(x,0,z))
			if cell == null: continue
			for dx in range(0,6):
				var at: Vector2i = cell+Vector2i(dx,0)
				var open: Vector2i = at+Vector2i(1,0)
				if ground.get_terrain(at) != 3 or not ground.can_traverse(open,MobilityRules.Layer.GROUND) or not ground.can_traverse(at,MobilityRules.Layer.FOREST): continue
				var point: Vector3 = ground.tile_to_world(at)
				if things.any(func(node): return node.global_position.distance_to(point) < clear): continue
				return at
	return null
func camouflage() -> bool:
	await open("res://scenes/maps/lakes_skirmish.tscn")
	var fog = get_first_node_in_group("fog_of_war")
	var rules: ForgeResearchRules = load("res://assets/combat/forge_research_rules.tres")
	if not check(rules.camo_leave_grace == 1.5 and rules.camo_attack_break == 2.0,"Camouflage: 1.5 s grace, 2 s after attacking"): return false
	var at = forest_edge(45.0)
	if not check(at != null,"No forest edge clear of everything on Two Lakes"): return false
	# An enemy Warhound in the forest; a player Deforester on the open cell beside it.
	var hound = spawn("warhound",game.ground.tile_to_world(at),"enemy")
	place(hound,at)
	var watcher = spawn("infantry",game.ground.tile_to_world(at+Vector2i(1,0)))
	place(watcher,at+Vector2i(1,0))
	if not check(hound.has_ability(&"forest_camouflage"),"The Warhound carries Forest Camouflage"): return false
	step([hound],0.1)
	fog.update_now()
	if not check(not hound.camouflaged() and watcher.team_sees(hound) and hound.visible,"Without the research the Warhound is seen"): return false
	Research.complete(game,"enemy",Research.CAMOUFLAGE)
	step([hound],0.1)
	fog.update_now()
	if not check(hound.camouflaged() and not watcher.team_sees(hound) and not hound.visible and not fog.shows(hound),"In forest with the research the Warhound should be hidden, even 2 m away"): return false
	# A detector sees it.
	var drone = spawn("drone",hound.global_position+Vector3(6,0,0))
	if not check(watcher.team_sees(hound),"A Drone within 20 m should detect the Warhound"): return false
	drone.queue_free()
	await process_frame
	if not check(not watcher.team_sees(hound),"Without the Drone it is hidden again"): return false
	# Out of the forest it shows after 1.5 s.
	var outside: Vector2i = at+Vector2i(2,0)
	if not game.ground.can_traverse(outside,MobilityRules.Layer.GROUND): outside = at+Vector2i(1,1) if game.ground.can_traverse(at+Vector2i(1,1),MobilityRules.Layer.GROUND) else at+Vector2i(1,-1)
	place(hound,outside)
	if not check(game.ground.get_terrain(hound.grid_position) != 3,"The Warhound should stand out of the forest"): return false
	step([hound],1.2)
	if not check(hound.camouflaged(),"For 1.5 s after leaving the forest it stays hidden"): return false
	step([hound],0.4)
	if not check(not hound.camouflaged() and watcher.team_sees(hound),"1.5 s out of the forest it shows"): return false
	# Attacking shows it for 2 s.
	place(hound,at)
	step([hound],0.1)
	fog.update_now()
	if not check(hound.camouflaged(),"Back in the forest it is hidden"): return false
	hound._attack_enabled = true
	var health: int = watcher.health
	hound._shoot(watcher)
	hound._attack_enabled = false
	if not check(watcher.health < health and not hound.camouflaged() and watcher.team_sees(hound),"A bite should show the Warhound: '%s'" % hound.state): return false
	step([hound],1.8)
	if not check(not hound.camouflaged(),"For 2 s after the bite it shows"): return false
	step([hound],0.3)
	if not check(hound.camouflaged(),"2 s after the bite it is hidden again"): return false
	return true
