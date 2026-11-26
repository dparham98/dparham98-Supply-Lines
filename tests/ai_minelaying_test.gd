extends SceneTree
# Headless, on Two Lakes (docs/ENEMY_AI.md, docs/MINES.md): the Cyborg AI builds a Temple of Science after its Tank
# Factory; it researches Minelaying only once it has a Derailer, and after Mining Trains; with Minelaying, a Derailer
# at home buys mines, then lays them in a row across the way toward the other side, and stops at `mines_wanted`.
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
	game.vehicle_fuel_required = false
	var depot: Node3D = ai.home()
	var order: Array = ai.build_order
	if not check(order.has(&"temple_of_science") and order.find(&"temple_of_science") > order.find(&"tank_factory"),"The Cyborg AI builds a Temple of Science after its Tank Factory"): return
	# A Temple of its own.
	var network = game.get_node("DepotNetwork")
	var point = ai.building_site(depot,network.plan_spec(&"temple_of_science").size)
	var plan: Node3D = network.queue_plan(point,&"temple_of_science",depot,true,true,"enemy")
	var temple: Node3D = network.finish_plan(plan)
	plan.queue_free()
	if not check(temple != null and temple.is_in_group("research_buildings"),"The enemy should have a Temple"): return
	depot.stockpile.deposit(&"iron",600)
	depot.stockpile.deposit(&"energy",600)
	# No Derailer: Mining Trains only.
	ai._sort(ai.own_units())
	if not check(not ai.research_wanted().has(Research.MINELAYING),"No Derailer, no Minelaying"): return
	var derailer := actor("motorcycle","enemy",ai.rally_point(depot))
	derailer.set_process(false)
	ai._sort(ai.own_units())
	if not check(ai.army.has(derailer) and ai.research_wanted() == [Research.MINING_TRAINS,Research.MINELAYING],"With a Derailer it wants Mining Trains, then Minelaying: %s" % [ai.research_wanted()]): return
	ai.research()
	if not check(temple.researching != null and temple.researching.research_id == Research.MINING_TRAINS,"Mining Trains goes first: %s (%d E, %d I)" % [temple.research_blocker(Research.MINING_TRAINS),depot.energy,depot.iron]): return
	temple.researching = null
	Research.complete(game,"enemy",Research.MINING_TRAINS)
	ai.wants = {}
	ai.research()
	if not check(temple.researching != null and temple.researching.research_id == Research.MINELAYING,"Then Minelaying"): return
	temple.researching = null
	Research.complete(game,"enemy",Research.MINELAYING)
	# Laying: toward the player's Depot, once it knows of it.
	ai.known[game.depot.get_instance_id()] = game.depot.global_position
	ai.mines_wanted = 3
	derailer.mines = 0
	var iron_before: int = depot.stockpile.amount(&"iron")
	ai.lay_mines(depot)
	if not check(derailer.mines == 2 and depot.stockpile.amount(&"iron") == iron_before-20,"Idle at home, a Derailer buys 2 mines for 20 iron (mines %d, iron %d->%d)" % [derailer.mines,iron_before,depot.stockpile.amount(&"iron")]): return
	if not check(derailer.order == "lay_mine","A Derailer with mines aboard goes to lay one: %s" % derailer.state): return
	var spot: Vector3 = ai._laying[derailer.get_instance_id()]
	var way: Vector3 = (game.depot.global_position-depot.global_position)*Vector3(1,0,1)
	var out: Vector3 = (spot-depot.global_position)*Vector3(1,0,1)
	if not check(out.normalized().dot(way.normalized()) > 0.9 and absf(out.length()-minf(ai.mine_distance,way.length()*0.5)) < 1.0,"The first mine goes %.0f m out toward the player (it went %.1f m)" % [ai.mine_distance,out.length()]): return
	var laid := func() -> Array: return ai.own_mines()
	for i in range(90*30):
		derailer._process(1.0/30)
		if laid.call().size() == 1: break
	if not check(laid.call().size() == 1 and derailer.mines == 1,"The Derailer should lay its mine (%s)" % derailer.state): return
	ai.lay_mines(depot)
	if not check(derailer.order == "lay_mine","It lays its second mine"): return
	var second: Vector3 = ai._laying[derailer.get_instance_id()]
	if not check(absf(second.distance_to(laid.call()[0].global_position)-ai.mine_spacing) < 0.5,"The second mine goes %.0f m along the row from the first" % ai.mine_spacing): return
	for i in range(90*30):
		derailer._process(1.0/30)
		if laid.call().size() == 2: break
	# At `mines_wanted` it lays no more.
	derailer.mines = 2
	ai.mines_wanted = 2
	ai.lay_mines(depot)
	if not check(laid.call().size() == 2 and derailer.order != "lay_mine","At mines_wanted it lays no more"): return
	print("AI_MINELAYING_TEST_PASSED")
	quit(0)
