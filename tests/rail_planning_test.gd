extends SceneTree
# Headless: track is planned before any of it is laid (docs/RAIL_PLANNING.md). Planned pieces need not be in a
# Depot's range; the plan is laid only once it connects two targets (Depots, mines or build sites), when one
# Depot pays all its iron. Mines are targets too. Laid lines with a Depot pay a small upkeep that grows with
# the trains running on them.
var game: Node3D
var rails: Node
var network: Node
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
## Plans `count` straights out from `start` heading `heading`, each onto the last one's far end. True when
## every piece was planned.
func plan_line(start: Vector3, heading: Vector3, count: int) -> bool:
	rails.clear_plan()
	if not rails.plan_piece("straight",start,heading).is_empty(): return false
	for i in range(count-1):
		var tip: Dictionary = far_end(start)
		if not rails.plan_piece("straight",tip.position+tip.out*0.5,heading).is_empty(): return false
	return true
func far_end(from: Vector3) -> Dictionary:
	var best := {}
	for end in rails.pending_free_ends():
		if best.is_empty() or end.position.distance_to(from) > best.position.distance_to(from): best = end
	return best
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/balanced_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	game.set_process(false)
	rails = game.get_node("RailNetwork")
	rails.set_process(false)
	network = game.get_node("DepotNetwork")
	var depot: Node3D = game.depot
	depot.set_process(false)
	depot.iron = 1500
	depot.energy = 1000
	var radius: float = SupplySource.radius(depot)
	# A line of seven straights (about 34 m) out from beside the Depot, past its range, on open land.
	var start := Vector3.INF
	var heading := Vector3.ZERO
	for direction in [Vector3.RIGHT,Vector3.LEFT,Vector3.FORWARD,Vector3.BACK]:
		for offset in [6.0,8.0,10.0]:
			var point: Vector3 = depot.global_position+direction*offset
			if plan_line(point,direction,7): start = point; heading = direction; break
		if start != Vector3.INF: break
	if not check(start != Vector3.INF,"No open line out from the Depot"): return
	var pieces_before: int = rails.pieces.size()
	var tip: Dictionary = far_end(start)
	if not check(Vector2(tip.position.x-depot.global_position.x,tip.position.z-depot.global_position.z).length() > radius+5.0,"The plan should reach past the Depot's %.1f m range" % radius): return
	if not check(rails.pending.size() == 7 and rails.pieces.size() == pieces_before and depot.iron == 1500,"Planning must not lay or pay anything"): return
	# One target is not enough.
	var targets: Array[Node3D] = rails.plan_targets()
	if not check(targets.size() == 1 and targets[0] == depot,"The plan should connect only the Depot so far: %s" % [targets]): return
	if not check(rails.plan_blocker().contains("two targets"),"The plan should say it needs two targets: "+rails.plan_blocker()): return
	if not check(rails.commit_plan().is_empty() and rails.pieces.size() == pieces_before and rails.pending.size() == 7 and depot.iron == 1500,"A plan with one target must not be laid"): return
	# Backspace takes back a piece, and a piece off the plan's free ends is refused.
	rails.unplan_last()
	if not check(rails.pending.size() == 6,"Undo should drop the last piece"): return
	tip = far_end(start)
	if not check(rails.plan_piece("straight",tip.position+tip.out*0.5,heading).is_empty() and rails.pending.size() == 7,"The piece should plan again"): return
	tip = far_end(start)
	var stray: String = rails.plan_piece("straight",tip.position+tip.out*20.0,heading)
	if not check(stray.contains("free end"),"A piece off the plan should be refused: "+stray): return
	# A build site past the far end is the second target.
	var site: Node3D = null
	for r in range(3,16):
		site = network.queue_plan(tip.position+tip.out*r,&"generator")
		if site != null: break
	if not check(site != null,"No build site past the plan"): return
	site.set_process(false)
	targets = rails.plan_targets()
	if not check(targets.has(depot) and targets.has(site) and rails.plan_blocker().is_empty(),"The plan should connect the Depot and the site: %s" % rails.plan_blocker()): return
	var cost: int = rails.plan_cost()
	if not check(cost == 7*rails.cost("straight"),"The plan should cost every piece: %d" % cost): return
	var laid: Array[Node3D] = rails.commit_plan()
	if not check(laid.size() == 7 and rails.pending.is_empty() and rails.pieces.size() == pieces_before+7 and depot.iron == 1500-cost,"Laying should place every piece and charge the Depot once: %d laid, %d iron" % [laid.size(),depot.iron]): return
	var ghosts := game.find_children("PlannedTrack*","Node3D",true,false).filter(func(n): return not n.is_queued_for_deletion())
	if not check(ghosts.is_empty(),"The planned ghosts should be gone: %d left" % ghosts.size()): return
	var outer: Node3D = laid[laid.size()-1]
	if not check(outer.global_position.distance_to(depot.global_position) > radius and rails.friendly_piece(outer,"player") and rails.powered(outer,"player"),"Track past the range should be friendly and powered"): return
	# Upkeep: 0.1 E/s per 100 m idle, twice that with one train running, paid from the Depot.
	var metres := 0.0
	for piece in rails.lines()[outer.get_instance_id()].pieces: metres += piece.total_length()
	var idle: float = rails.upkeep_rate(outer)
	if not check(is_equal_approx(idle,rails.rules.upkeep_per_100m*metres/100.0) and idle > 0.0,"Idle upkeep should follow the line's length: %.4f" % idle): return
	var energy: int = depot.energy
	rails.charge_upkeep(1000.0)
	if not check(depot.energy == energy-floori(idle*1000.0),"Upkeep should be paid from the Depot: %d of %d" % [energy-depot.energy,floori(idle*1000.0)]): return
	var train: Node3D = rails.train_scene.instantiate()
	train.team = "player"
	train.position = outer.global_position
	game.get_node("Entities/Units").add_child(train)
	train.set_process(false)
	await process_frame
	train.snap_to_track()
	if not check(rails.lines()[outer.get_instance_id()].pieces.has(train.piece),"The test train should be on the new line"): return
	train._route.append(Vector2i(-2,-2))
	if not check(is_equal_approx(rails.upkeep_rate(outer),idle*(1.0+rails.rules.upkeep_per_running_train)),"A running train should raise the upkeep: %.4f" % rails.upkeep_rate(outer)): return
	train._route.clear()
	if not check(is_equal_approx(rails.upkeep_rate(outer),idle),"A train standing still adds nothing"): return
	train.queue_free()
	# Mines are targets: the starter mine is one, within its footprint and the connect reach.
	var mines := get_nodes_in_group("mines")
	if not check(not mines.is_empty() and rails.plan_target_candidates().has(mines[0]),"Mines should be rail targets"): return
	if not check(rails.target_reach(mines[0]) > rails.rules.connect_reach,"A mine's reach should include its footprint"): return
	# Leaving track laying drops the plan.
	game.placing_rail = true
	rails.clear_plan()
	var open := Vector3.INF
	for r in range(30,80,4):
		var point: Vector3 = depot.global_position-heading*r
		if rails.plan_piece("straight",point,heading).is_empty(): open = point; break
	if not check(open != Vector3.INF and rails.pending.size() == 1,"No spot for a last planned piece"): return
	game.placing_rail = false
	if not check(rails.pending.is_empty(),"Leaving track laying should drop the plan"): return
	print("RAIL_PLANNING_TEST_PASSED")
	quit(0)
