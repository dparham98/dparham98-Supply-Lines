extends SceneTree
# Headless, on Two Lakes (docs/KNIGHTS_RAIL.md, docs/KNIGHTS_AI.md): with a second Keep, the Knights AI plans a
# Dragon Yard; with one standing, it joins the Keeps with track paid by home, buys a train at home for 60 F / 40 W /
# 30 I and sends it hauling iron home, and gets coal for it: a Forester carries iron out to a Coal Mine site, and once
# the mine stands works it while home is short of coal.
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
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
	var setup = root.get_node("MatchSetup")
	setup.configured = true
	setup.mode = "ai"
	setup.map_id = "two_lakes"
	setup.factions = {"player": &"cyborgs", "enemy": &"arthurian_knights"}
	game = load(setup.map_path()).instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	var ai: Node = game.enemy_player()
	ai.set_process(false)
	for old in ai.plans.values():
		if is_instance_valid(old): old.cancel()
	ai.plans.clear()
	var network = game.get_node("DepotNetwork")
	var rails = game.get_node("RailNetwork")
	var keep: Node3D = ai.home()
	keep.stockpile.deposit(&"iron",500)
	keep.stockpile.deposit(&"wood",300)
	keep.stockpile.deposit(&"food",300)
	# A second Keep.
	var site = ai.expansion_spot(keep,null)
	var keep_plan: Node3D = network.queue_plan(site,&"keep",null,false,false,"enemy")
	var outpost: Node3D = network.finish_plan(keep_plan)
	keep_plan.queue_free()
	await process_frame
	if not check(outpost != null and ai.own_keeps().size() == 2,"The enemy should have a second Keep"): return
	# With two Farms up and no Chapterhouse wanted, the Dragon Yard is next.
	ai.chapterhouses_wanted = 0
	ai.house_headroom = -100
	for kind in [&"farm",&"farm"]:
		if not check(building(ai,keep,kind) != null,"Should place a Farm"): return
	ai._sort(ai.own_units())
	if not check(not KnightRail.has_dragon_yard(keep,"enemy"),"No Dragon Yard yet"): return
	ai.rail_economy(keep)
	if not check(ai._search.is_empty(),"No track before a Dragon Yard"): return
	ai.economy(keep,true)
	var plan = ai.plans.get(keep.get_instance_id())
	if not check(is_instance_valid(plan) and plan.kind == &"dragon_yard","With two Keeps, it plans a Dragon Yard: %s" % [plan.kind if is_instance_valid(plan) else null]): return
	if not check(ai.has_building(&"dragon_yard"),"A planned Dragon Yard counts"): return
	network.finish_plan(plan)
	plan.queue_free()
	await process_frame
	ai.plans.clear()
	if not check(KnightRail.has_dragon_yard(keep,"enemy"),"The Dragon Yard stands"): return
	# Track from home to the second Keep, paid by home.
	var iron_before: int = keep.iron
	for round in range(12):
		ai.wants = {}
		ai.rail_economy(keep)
		if ai.linked(keep,outpost): break
		if not ai._search.is_empty():
			while not ai._search.job.done: rails.advance_link(ai._search.job,20000)
	if not check(ai.linked(keep,outpost),"Track should join the Keeps (search %s, no path %s)" % [ai._search.keys(),ai._no_path.keys()]): return
	if not check(keep.iron < iron_before,"Home pays for the track"): return
	# A train bought at home.
	keep.stockpile.deposit(&"iron",200)
	var r := KnightHousing.rules()
	ai.run_trains(keep)
	ai.run_trains(keep)
	if not check(keep.pending.count("train") == 1,"Home should buy one train for the line: %s" % [keep.pending]): return
	var train: Node3D = null
	# Two Foresters are queued ahead of it.
	for i in range(30*150):
		keep._process(1.0/30)
		var trains := get_nodes_in_group("rail_trains").filter(func(t): return t.team == "enemy")
		if not trains.is_empty(): train = trains[0]; break
	if not check(train != null and train.coal_fuelled,"The Knights train should be built: %s · %s" % [keep.pending,keep.get_node("Progress").text]): return
	ai.run_trains(keep)
	if not check(train.route_active and train.origin_depot == outpost and train.destination_depot == keep,"The train hauls from the second Keep home: %s" % train.state): return
	# Coal for it: a Forester carries iron to a Coal Mine site, then works the mine.
	ai._sort(ai.own_units())
	ai._coal(keep)
	if not check(is_instance_valid(ai.coal_plan) and ai.coal_plan.kind == &"coal_mine" and ai.coal_hand != null,"It plans a Coal Mine and picks a Forester for it: %s, %s" % [ai.coal_plan,ai.coal_hand]): return
	if not check(ai.coal_hand.order in ["gather","construct"],"The Forester fetches iron for the site: %s" % ai.coal_hand.state): return
	var hand: Node3D = ai.coal_hand
	ai.economy(keep,true)
	if not check(ai.coal_hand == hand and hand.order in ["gather","construct"],"The Keep's own work leaves the coal Forester alone"): return
	var mine: Node3D = network.finish_plan(ai.coal_plan)
	ai.coal_plan.queue_free()
	await process_frame
	ai._coal(keep)
	if not check(hand.order == "gather" and hand.source == mine,"Once the mine stands, the Forester works it: %s" % hand.state): return
	keep.stockpile.deposit(&"coal",ai.train_coal_wanted*2)
	ai._coal(keep)
	if not check(ai.coal_hand == null and hand.order != "gather","With coal enough, the Forester goes back to the Keep's work"): return
	setup.configured = false
	print("AI_KNIGHTS_RAIL_TEST_PASSED")
	quit(0)
