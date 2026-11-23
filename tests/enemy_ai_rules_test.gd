extends SceneTree
# Headless, on Two Lakes: the enemy player's rules (docs/ENEMY_AI.md). It starts knowing nothing of the player's
# base and heads for start sites it has not seen; its plans are its own (its stockpile pays, the building is its,
# the player's HUD does not count them, and its messages are not shown); it repairs its damaged buildings; it finds
# an expansion site beside an iron mine on its side; what its Depot prints is its own; its track is found and laid
# without touching the player's plan and is its own; with Mining Trains researched it buys a train for its mine; it
# remembers buildings it has seen; it defends against enemies seen near its buildings; and with nothing left it has
# lost.
var game: Node3D
var ai: Node
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func actor(id: String, team: String, point: Vector3) -> Node3D:
	var unit = load("res://scenes/gameplay/"+id+".tscn").instantiate()
	unit.team = team
	game.get_node("Entities/Units").add_child(unit)
	unit.global_position = point
	return unit
func run() -> void:
	game = load("res://scenes/maps/lakes_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	ai = game.enemy_player()
	ai.set_process(false)
	var fog = game.fog_of_war()
	fog.update_now()
	var depot: Node3D = ai.home()
	var west: Vector3 = game.depot.global_position
	# It does not know where the player is: it heads for an unseen start, and the player's start is one of them.
	ai.remember()
	if not check(ai.known.is_empty(),"The enemy should know none of the player's buildings at the start"): return
	if not check(not fog.explored_by("enemy",west) and ai.wave_target(depot.global_position) != null,"The enemy should head for a start it has not seen"): return
	# Its plan: its own team, paid by its own Depot, not counted by the player's HUD, its notices not shown.
	game.message = ""
	var network = game.get_node("DepotNetwork")
	var point = ai.building_site(depot,network.plan_spec(&"barracks").size)
	if not check(point != null and depot.global_position.distance_to(point) <= SupplySource.radius(depot),"The enemy should find a Barracks site in its Depot's range"): return
	var plan: Node3D = network.queue_plan(point,&"barracks",depot,true,true,"enemy")
	if not check(plan != null and plan.team == "enemy" and network.plan_payer(plan) == depot,"An enemy plan should be the enemy's, paid by its Depot"): return
	if not check(game.message.is_empty(),"The enemy's notices should not reach the player: %s" % game.message): return
	if not check(not network.plan_source_valid(plan,game.depot),"The player's Depot should not pay the enemy's plan"): return
	var building: Node3D = network.finish_plan(plan)
	if not check(building != null and building.team == "enemy" and building.source_friendly(),"A Barracks built from the enemy's plan should be the enemy's, fed by its Depot"): return
	plan.queue_free()
	# Repair: a damaged building of its own, with no enemy near, gets a worker.
	ai._sort(ai.own_units())
	building.health = int(building.max_health*0.4)
	ai.repair()
	if not check(ai.workers.any(func(unit): return unit.order == "repair" and unit.order_target == building),"A damaged enemy building should be repaired by one of its workers"): return
	building.health = building.max_health
	# Expansion: a site beside an iron mine on its own side, far enough from home for the spacing rule.
	var site = ai.expansion_spot(depot,null)
	var spacing: float = network.depot_rules().min_depot_spacing()
	if not check(site != null and site.x > 0.0 and site.distance_to(depot.global_position) >= spacing,"The enemy should find an expansion site on its side past %.1f m: %s" % [spacing,site]): return
	if not check(network.can_place(site,null,true,"enemy"),"The expansion site should take a Depot"): return
	# What a Depot prints is its side's.
	depot.stockpile.deposit(&"energy",1000)
	depot.stockpile.deposit(&"iron",1000)
	if not check(depot.request_cargo(),"The enemy's Depot should print a Cargo truck"): return
	var before: Array = ai.own_units()
	for frame in range(30*20):
		depot._process(1.0/30.0)
		if depot.queue == 0: break
	var printed: Array = get_nodes_in_group("units").filter(func(unit): return unit.is_cargo_vehicle and not before.has(unit) and unit.team == "enemy")
	if not check(printed.size() == 1,"A Cargo truck printed at the enemy's Depot should be the enemy's"): return
	printed[0].free()
	# Track: found and laid for its side without touching the player's plan, paid by its Depot.
	var rails = game.get_node("RailNetwork")
	var mine: Node3D = ai.mining_target(depot)
	if not check(mine != null and mine.global_position.x > 0.0,"The enemy should pick a mine on its side for a mining train"): return
	# A piece the laid track's own cells find blocked is forbidden and the search run again, as the AI does.
	var forbidden := {}
	var path: Array = []
	for tries in range(6):
		var job: Dictionary = rails.begin_link(depot,mine,forbidden)
		while not rails.advance_link(job,5000): pass
		path = job.found.get("path",[])
		var unfit: Dictionary = rails.unfit_moves(path)
		if unfit.is_empty(): break
		forbidden.merge(unfit)
	if not check(not path.is_empty() and rails.unfit_moves(path).is_empty(),"The enemy should find track from its Depot to %s that can all be laid" % mine.name): return
	var iron: int = depot.iron
	game.message = ""
	var laid: Array[Node3D] = rails.lay_link(path,depot)
	if not check(laid.size() == path.size() and depot.iron == iron-rails.link_cost(path),"The enemy's track should all go down, paid by its Depot"): return
	if not check(laid.all(func(piece): return rails.friendly_piece(piece,"enemy") and not rails.friendly_piece(piece,"player")),"The enemy's track should be the enemy's"): return
	if not check(rails.pending.is_empty() and game.message.is_empty(),"Laying the enemy's track should leave the player's plan and messages alone"): return
	if not check(ai.mine_linked(depot,mine),"The enemy's track should join its Depot to %s" % mine.name): return
	# With the research done, it buys a train for the mine.
	Research.complete(game,"enemy",Research.MINING_TRAINS)
	ai.mining_mine = mine
	# Below the haul cap: a home full of iron would stop mining (home_full).
	depot.stockpile.set_amount(&"iron",100)
	ai.wants = {}
	ai.run_trains(depot)
	if not check(depot.pending.has("train"),"With Mining Trains researched and track to a mine, the enemy should buy a train"): return
	# Memory: a player building it sees is remembered, and stays known out of sight until it sees it gone.
	var seen := actor("scout","enemy",west+Vector3(10,0,0))
	seen.set_process(false)
	fog.update_now()
	ai.remember()
	if not check(ai.known.has(game.depot.get_instance_id()),"A player Depot the enemy sees should be remembered"): return
	seen.free()
	fog.update_now()
	ai.remember()
	if not check(ai.known.has(game.depot.get_instance_id()) and ai.wave_target(depot.global_position).distance_to(west) < 1.0,"Out of sight the enemy should still head for the Depot it saw"): return
	# Defence: an enemy seen near its buildings draws the army.
	var guard := actor("grenadier","enemy",depot.global_position+Vector3(-24,0,0))
	var raider := actor("tank","player",depot.global_position+Vector3(-30,0,14))
	raider.set_process(false)
	fog.update_now()
	ai.think()
	if not check(ai.army.has(guard) and guard.order in ["attack_move","attack"],"A raider near the base should be met: %s" % guard.order): return
	raider.free(); guard.free()
	# With nothing left the enemy has lost.
	for node in get_nodes_in_group("units"):
		if node.team == "enemy": node.free()
	for node in get_nodes_in_group("selectable_buildings"):
		if node.get("team") == "enemy": node.free()
	game.outcome = ""
	ai.think()
	if not check(ai.defeated and game.outcome.begins_with("VICTORY"),"With nothing left the enemy should be beaten: %s" % game.outcome): return
	print("ENEMY_AI_RULES_TEST_PASSED")
	quit()
