extends SceneTree
# Headless: the Temple of Science and Mining Trains (docs/TEMPLE_OF_SCIENCE.md), on scenes/maps/temple_exercise.tscn.
# The Temple stands in the Depot's range and is on the Build page; Mining Trains costs 150 E / 100 I from the
# covering Depot, refunds on Cancel and takes 60 s; until it is done the train refuses to mine. Then the train runs
# to Mine07 along the saved track, digs a full load itself, unloads it at the Depot and heads back; Stop ends it.
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func step_train(train: Node3D, seconds: float, until: Callable) -> bool:
	var left := seconds
	while left > 0.0:
		train._process(0.1)
		left -= 0.1
		if until.call(): return true
	return false
func run() -> void:
	game = load("res://scenes/maps/temple_exercise.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	var ai = game.get_node_or_null("EnemyPlayer")
	if ai != null: ai.set_process(false)
	var network = game.get_node("DepotNetwork")
	var depot: Node3D = game.depot
	# The building and its Build page entry.
	var temple = game.get_node_or_null("Entities/Buildings/TempleOfScience")
	if not check(is_instance_valid(temple) and temple.is_inside_tree(),"The Temple did not stand on its footprint"): return
	if not check(temple.team == "player" and temple.is_in_group("research_buildings") and temple.is_in_group("production_buildings") and temple.is_in_group("selectable_buildings"),"The Temple should be a selectable player research building"): return
	if not check(temple.covering_depots().has(depot),"The Depot's range should cover the Temple"): return
	if not check(temple.get_node("Visuals/Model").scene_file_path == "res://scenes/models/temple_of_science_model.tscn","The Temple should carry its placeholder model in the Visuals slot"): return
	var spec: Dictionary = network.plan_spec(&"temple_of_science")
	if not check(spec.get("title") == "Temple of Science" and spec.get("size") == Vector2i(6,6) and spec.get("energy") == 150 and spec.get("iron") == 60,"Temple plan spec should be 6 x 6 for 150 E / 60 I: %s" % spec): return
	if not check(spec.get("model") != null,"The Temple's plan should know its model"): return
	var hud = game.get_node("Interface")
	if not check(hud.build_menu.get_node_or_null("Actions/Temple") != null,"The Build page has no Temple tile"): return
	# A plan for one builds a working Temple.
	var plan = network.queue_plan(depot.global_position+Vector3(14,0,4),&"temple_of_science",depot,true,false)
	if not check(is_instance_valid(plan),"A Temple plan could not be queued: "+game.message): return
	depot.stockpile.deposit(&"iron",60)
	var built = plan.complete_from_stock()
	if not check(is_instance_valid(built) and built.is_in_group("research_buildings"),"The plan did not finish as a Temple"): return
	built.take_damage(100000)
	await process_frame
	# The train cannot mine before the research.
	var train = game.get_node("Entities/Units/Train")
	var mine = game.get_node("Entities/Buildings/Mine07")
	train.set_process(false)
	if not check(train.is_in_group("rail_trains") and train.on_friendly_track(),"The exercise train should stand on friendly track"): return
	if not check(not train.can_mine() and train.mine_blocker(mine).begins_with("Research"),"The train should need the research first: "+train.mine_blocker(mine)): return
	if not check(not train.command_mine(mine) and not train.is_mining(),"The train mined without the research"): return
	# Research: paid from the Depot, one at a time, refunded on Cancel.
	var energy: int = depot.energy
	var iron: int = depot.iron
	if not check(temple.request_research(Research.MINING_TRAINS),"The Temple refused Mining Trains: "+game.message): return
	if not check(depot.energy == energy-150 and depot.iron == iron-100,"Mining Trains should cost 150 E / 100 I from the Depot"): return
	if not check(not temple.request_research(Research.MINING_TRAINS),"A second research should be refused while one runs"): return
	if not check(temple.cancel_research() and depot.energy == energy and depot.iron == iron,"Cancel should refund the Depot"): return
	if not check(temple.request_research(Research.MINING_TRAINS),"The research could not be restarted"): return
	temple._process(30.0)
	if not check(not Research.has(game,"player",Research.MINING_TRAINS) and absf(temple.fraction()-0.5) < 0.01,"The research should be half done after 30 s"): return
	temple._process(30.1)
	if not check(Research.has(game,"player",Research.MINING_TRAINS) and temple.researching == null,"The research did not finish after 60 s"): return
	if not check(not Research.has(game,"enemy",Research.MINING_TRAINS),"The research should hold only for the side that made it"): return
	if not check(not temple.request_research(Research.MINING_TRAINS),"A finished research should not be started again"): return
	# The HUD: the Temple's card, then the train's Mine iron tile, now open.
	game.selected_building = temple
	for frame in range(2): await process_frame
	if not check(hud.card.get_node("Research").visible and hud.card.get_node("Research").disabled,"The Temple card should show Mining Trains as researched"): return
	game.selected_building = null
	train.set_selected(true)
	for frame in range(2): await process_frame
	if not check(hud.card.get_node("MineIron").visible and not hud.card.get_node("MineIron").disabled,"The train card should offer Mine iron"): return
	train.set_selected(false)
	# Mining: out along the track to the mine, a full load, back to the Depot.
	if not check(train.mine_blocker(mine).is_empty(),"The train should be able to mine Mine07: "+train.mine_blocker(mine)): return
	if not check(not train.at_mine(mine),"The exercise train should start away from the mine"): return
	var reserves: int = mine.remaining
	iron = depot.iron
	if not check(train.command_mine(mine) and train.is_mining() and train.mining_stage == "to_mine","The train did not take the Mine iron order: "+game.message): return
	if not check(step_train(train,60.0,func(): return train.mining_stage == "digging"),"The train did not reach the mine: "+train.state): return
	if not check(train.at_mine(mine) and train.global_position.distance_to(depot.global_position) > 40.0,"The train should dig at the mine, far from the Depot"): return
	if not check(step_train(train,60.0,func(): return train.mining_stage == "to_depot"),"The train did not fill up at the mine: "+train.state): return
	if not check(train.carried_iron == train.stockpile.capacity and train.carried_iron == 300,"The train should leave the mine with 300 iron, not %d" % train.carried_iron): return
	if not check(mine.remaining == reserves-300,"The mine should lose the 300 iron the train dug"): return
	if not check(step_train(train,90.0,func(): return train.mining_stage == "to_mine"),"The train did not deliver its iron: "+train.state): return
	if not check(depot.iron == iron+300 and train.mined_delivered == 300 and train.carried_iron == 0,"The Depot should get the 300 iron (has %d, had %d)" % [depot.iron,iron]): return
	if not check(step_train(train,5.0,func(): return train._line.size() > 0),"The train should head back to the mine"): return
	# Stop ends the loop; a right-click on the mine (gather) starts it again.
	train.cancel_supply_route()
	if not check(not train.is_mining() and train.order == "idle","Stop should end mining"): return
	train.command_gather(mine)
	if not check(train.is_mining(),"A right-click on the mine should start mining"): return
	train.command_move(train.global_position)
	if not check(not train.is_mining(),"A move order should end mining"): return
	print("TEMPLE_OF_SCIENCE_TEST_PASSED")
	quit()
