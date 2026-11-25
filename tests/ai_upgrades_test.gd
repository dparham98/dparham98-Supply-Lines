extends SceneTree
# Headless, on Two Lakes (docs/UPGRADES.md, docs/ENEMY_AI.md, docs/KNIGHTS_AI.md): the Cyborg AI puts a Foundry last
# in its build order and, once its army is big enough, researches the four lines level by level; the Knights AI puts
# up a Forge at home once its Chapterhouses stand, researches Arms and Mail in turn, and its Chapterhouses leave home
# what the next level needs.
var game: Node3D
var setup: Node
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func load_map(enemy: StringName) -> void:
	if is_instance_valid(game): game.free()
	setup.configured = true
	setup.mode = "ai"
	setup.map_id = "two_lakes"
	setup.factions = {"player": &"cyborgs", "enemy": enemy}
	game = load(setup.map_path()).instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
func building(ai: Node, home: Node3D, kind: StringName) -> Node3D:
	var network = game.get_node("DepotNetwork")
	var point = ai.building_site(home,network.plan_spec(kind).size)
	if point == null: return null
	var plan: Node3D = network.queue_plan(point,kind,home,true,true,ai.team)
	if plan == null: return null
	var made: Node3D = network.finish_plan(plan)
	plan.queue_free()
	return made
func run() -> void:
	setup = root.get_node("MatchSetup")
	# 1. Cyborgs.
	await load_map(&"cyborgs")
	var ai: Node = game.enemy_player()
	ai.set_process(false)
	if not check(ai.build_order[-1] == &"foundry","The Cyborg AI builds a Foundry last: %s" % [ai.build_order]): return
	var depot: Node3D = ai.home()
	var foundry := building(ai,depot,&"foundry")
	if not check(foundry != null and foundry.is_in_group("research_buildings"),"The enemy should have a Foundry"): return
	depot.stockpile.deposit(&"iron",900)
	depot.stockpile.deposit(&"energy",900)
	ai.mining_trains = false
	ai._sort(ai.own_units())
	ai.upgrades_army = ai.army.size()+1
	if not check(ai.research_wanted().is_empty(),"No upgrades before the army is big enough"): return
	ai.upgrades_army = 0
	var wanted: Array = ai.research_wanted()
	if not check(wanted.size() == 12 and wanted[0] == &"infantry_weapons_1" and wanted[1] == &"vehicle_weapons_1" and wanted[4] == &"infantry_weapons_2","Level 1 of each line, then level 2: %s" % [wanted]): return
	ai.research()
	if not check(foundry.researching != null and foundry.researching.research_id == &"infantry_weapons_1","Infantry Weapons I goes first"): return
	if not check(ai.wants.get("research") == Vector2i(100,150),"It saves 100 E / 150 I for it: %s" % [ai.wants.get("research")]): return
	foundry.researching = null
	for line in ai.upgrade_lines: Research.complete(game,"enemy",Upgrades.research_id(line,1))
	ai.research()
	if not check(foundry.researching != null and foundry.researching.research_id == &"infantry_weapons_2","Then Infantry Weapons II"): return
	# 2. Knights.
	await load_map(&"arthurian_knights")
	ai = game.enemy_player()
	ai.set_process(false)
	if not check(str(ai.get_script().resource_path).ends_with("knights_player.gd") and ai.upgrade_lines == [&"arms",&"mail"],"The Knights AI researches Arms and Mail"): return
	var keep: Node3D = ai.home()
	keep.stockpile.deposit(&"wood",300)
	keep.stockpile.deposit(&"iron",400)
	keep.stockpile.deposit(&"food",400)
	ai._sort(ai.own_units())
	# Two Farms and its one Chapterhouse up: the Forge is next. (Plans from its first round are dropped.)
	for old in ai.plans.values():
		if is_instance_valid(old): old.cancel()
	ai.plans.clear()
	ai.chapterhouses_wanted = 1
	ai.house_headroom = -100
	for kind in [&"farm",&"farm",&"chapterhouse"]:
		if not check(building(ai,keep,kind) != null,"Should place a %s" % kind): return
	ai.wants = {}
	ai.economy(keep,true)
	var plan = ai.plans.get(keep.get_instance_id())
	if not check(is_instance_valid(plan) and plan.kind == &"forge","With its Chapterhouses up, home plans a Forge: %s" % [plan.kind if is_instance_valid(plan) else null]): return
	if not check(ai.has_forge(),"A planned Forge counts as one"): return
	var network = game.get_node("DepotNetwork")
	var forge: Node3D = network.finish_plan(plan)
	plan.queue_free()
	await process_frame
	ai.plans.clear()
	ai.economy(keep,true)
	var next = ai.plans.get(keep.get_instance_id())
	if not check(not is_instance_valid(next) or next.kind != &"forge","Only one Forge"): return
	ai.upgrades_army = 0
	ai.wants = {}
	ai.research()
	if not check(forge.researching != null and forge.researching.research_id == &"arms_1","Arms I goes first"): return
	forge.researching = null
	Research.complete(game,"enemy",&"arms_1")
	# Saving for Mail I (100 F / 150 I): a Chapterhouse at home makes nothing that would eat into it.
	keep.stockpile.withdraw(&"food",keep.food)
	keep.stockpile.withdraw(&"iron",keep.iron)
	keep.stockpile.deposit(&"food",120)
	keep.stockpile.deposit(&"iron",120)
	ai.wants = {}
	ai.research()
	if not check(forge.researching == null and ai.wants.get("research") == Vector2i(100,150),"Short of Mail I's price, it saves for it: %s" % [ai.wants.get("research")]): return
	var hall: Node3D = ai.halls()[0]
	var queued: int = hall.queue
	ai.produce()
	if not check(hall.queue == queued,"The Chapterhouse leaves home what Mail I needs"): return
	keep.stockpile.deposit(&"food",200)
	keep.stockpile.deposit(&"iron",200)
	ai.wants = {}
	ai.research()
	if not check(forge.researching != null and forge.researching.research_id == &"mail_1","Then Mail I"): return
	setup.configured = false
	print("AI_UPGRADES_TEST_PASSED")
	quit(0)
