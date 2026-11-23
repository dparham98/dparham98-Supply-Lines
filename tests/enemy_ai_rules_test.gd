extends SceneTree
# Headless, on Two Lakes: the enemy player's rules (docs/ENEMY_AI.md). It starts knowing nothing of the player's
# base and heads for start sites it has not seen; its plans are its own (its stockpile pays, the building is its,
# the player's HUD does not count them, and its messages are not shown); it remembers buildings it has seen; it
# defends against enemies seen near its buildings; and with nothing left it has lost.
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
