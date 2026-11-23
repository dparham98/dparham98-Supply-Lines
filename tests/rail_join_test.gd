extends SceneTree
# Headless: joining track (docs/RAIL_PLANNING.md). A click on laid track picks it: new track to a building then
# leaves from a fork laid in place of three straights, which keeps the line running as it did, or from the line's
# free end. The suggested track follows the cursor, costs only what the fork adds, and when laid the fork replaces
# the straights, the line stays one line, and a train can run from the Depot out along the branch. A train standing on
# the fork can leave it by either lane.
var game: Node3D
var rails: Node
var network: Node
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func site_near(point: Vector3) -> Node3D:
	for r in range(0,40,3):
		for offset in [Vector3(r,0,0),Vector3(-r,0,0),Vector3(0,0,r),Vector3(0,0,-r)]:
			var plan = network.queue_plan(point+offset,&"generator",null,false,false)
			if plan != null: return plan
	return null
func line_of(piece: Node3D) -> Array:
	return rails.lines()[piece.get_instance_id()].pieces
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/balanced_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	game.set_process(false)
	rails = game.get_node("RailNetwork")
	network = game.get_node("DepotNetwork")
	var depot: Node3D = game.depot
	depot.set_process(false)
	depot.storage_capacity = 100000; depot.iron = 20000; depot.energy = 20000
	for unit in get_nodes_in_group("units"): unit.set_process(false)
	# A line from the Depot to a site well off, along open ground.
	var far: Node3D
	var heading := Vector3.ZERO
	for direction in [Vector3(1,0,0),Vector3(-1,0,0),Vector3(0,0,1),Vector3(0,0,-1)]:
		far = site_near(depot.global_position+direction*75.0)
		if far == null: continue
		rails.pick_target(depot)
		rails.pick_target(far)
		if not rails.pending.is_empty() and rails.plan_blocker().is_empty(): heading = direction; break
		rails.drop_route(); far.queue_free(); far = null
	if not check(far != null,"No open line from the Depot"): return
	var line: Array[Node3D] = rails.commit_plan()
	rails.drop_route()
	if not check(line.size() >= 8,"The first line should be laid: %d pieces" % line.size()): return
	var first_line := line_of(line[0])
	# A click on a straight in the middle of the line picks the track.
	var middle: Node3D
	for piece in line:
		if piece.kind == "straight" and not rails._straight_run(piece,0,3).is_empty() and piece.global_position.distance_to(depot.global_position) > 30.0: middle = piece; break
	if not check(middle != null,"No three straights in a row on the line"): return
	var click: Vector3 = middle.point_at(1.0)
	var picked = rails.pick_at(click)
	if not check(picked is RailAnchor and picked.piece == middle,"A click on track should pick the track"): return
	if not check(rails.pick_at(click+Vector3(0,0,0)+Vector3.UP) is RailAnchor and not rails.pick_at(depot.global_position) is RailAnchor,"A click off the track picks the building, not the track"): return
	var joins: Array = rails.join_candidates(picked)
	if not check(joins.any(func(j): return j.has("kind")),"The middle of a straight run should offer forks"): return
	# A branch to a site off to the side.
	var side := Vector3(-heading.z,0,heading.x)
	var branch_site := site_near(middle.global_position+side*40.0+heading*10.0)
	if branch_site == null: branch_site = site_near(middle.global_position-side*40.0+heading*10.0)
	if not check(branch_site != null,"No site beside the line"): return
	rails.pick_target(picked)
	var said: String = rails.pick_target(branch_site)
	if not check(not rails.pending.is_empty(),"Track to the side site should be suggested: %s" % said): return
	var fork: Dictionary = rails.pending[0]
	if not check(fork.kind.begins_with("fork") and fork.replaces.size() == 3,"The new track should leave from a fork in place of three straights: %s" % fork.kind): return
	if not check(fork.replaces.all(func(p): return not p.get_node("Visuals").visible),"The straights the fork replaces are hidden while it is planned"): return
	var expected := 0
	for entry in rails.pending: expected += rails.cost(entry.kind)
	expected -= 3*rails.cost("straight")
	if not check(rails.plan_cost() == expected,"The fork pays only for what it adds: %d, expected %d" % [rails.plan_cost(),expected]): return
	if not check(rails.plan_targets().has(depot) and rails.plan_targets().has(branch_site) and rails.plan_blocker().is_empty(),"The branch connects the line's Depot and the site: %s" % rails.plan_blocker()): return
	# It follows the cursor, keeping the fork.
	var bend: Vector3 = (middle.global_position+branch_site.global_position)*0.5+heading*8.0
	var moved: bool = rails.drag_route(bend)
	if not check(rails.pending[0].kind.begins_with("fork"),"Following the cursor keeps the fork"): return
	# Dropping the plan shows the straights again.
	var replaced: Array = rails.pending[0].replaces
	rails.drop_route()
	if not check(replaced.all(func(p): return p.get_node("Visuals").visible),"Dropping the plan shows the straights again"): return
	rails.pick_target(rails.pick_at(click))
	rails.pick_target(branch_site)
	if moved: rails.drag_route(bend)
	replaced = rails.pending[0].replaces
	var iron: int = depot.iron
	var cost: int = rails.plan_cost()
	var count_before: int = rails.pieces.size()
	var planned: int = rails.pending.size()
	var laid: Array[Node3D] = rails.commit_plan()
	rails.drop_route()
	await process_frame
	if not check(laid.size() == planned and rails.pieces.size() == count_before+planned-3 and depot.iron == iron-cost,"Laying the branch: %d of %d laid, %d iron" % [laid.size(),planned,iron-depot.iron]): return
	var fork_piece: Node3D = laid[0]
	if not check(replaced.all(func(p): return not is_instance_valid(p) or not rails.pieces.has(p)),"The fork replaces the straights"): return
	if not check(rails.connection(fork_piece,0).size() > 0 and rails.connection(fork_piece,1).size() > 0 and rails.connection(fork_piece,2).size() > 0,"The fork joins the line on both sides and the branch"): return
	var whole := line_of(fork_piece)
	if not check(whole.size() == first_line.size()-3+planned and whole.has(line[0]) and whole.has(line[line.size()-1]) and whole.has(laid[laid.size()-1]),"The line, the fork and the branch are one line"): return
	# The line still runs end to end through the fork's straight lane, and a train can run from the Depot onto the branch.
	if not check(rails.reachable(line[0],line[line.size()-1],"player"),"The line still runs end to end"): return
	var stop: Dictionary = rails.spawn_stop(depot)
	if not check(not stop.is_empty(),"A train can be built on the line"): return
	var into_branch: Array = rails.chain(line[0],laid[laid.size()-1],"player")
	var out_of_branch: Array = rails.chain(laid[laid.size()-1],line[0],"player")
	if not check(not into_branch.is_empty() and not out_of_branch.is_empty(),"Trains should run both ways between the line and the branch"): return
	var through: Array = into_branch if not into_branch.is_empty() else out_of_branch
	if not check(through.any(func(step): return step.piece == fork_piece and step.lane == 1),"The run should take the fork's branch lane"): return
	# A train from the Depot drives out to the end of the branch, and back; where the fork faces away it runs on
	# past the fork, reverses and backs into the branch.
	var train: Node3D = rails.train_scene.instantiate()
	train.team = "player"
	game.get_node("Entities/Units").add_child(train)
	train.global_position = stop.position
	train.snap_to_track()
	train.set_process(false)
	var branch_end: Node3D = laid[laid.size()-1]
	var reversals := 0
	for goal in [branch_end.point_at(branch_end.length()*0.5),stop.position]:
		if not check(train._route_to_point(goal),"The train should find a way to %s" % goal): return
		var legs := 0
		var leg: Dictionary = train._line
		while not leg.is_empty(): legs += 1; leg = leg.get("then",{})
		reversals += legs-1
		for i in range(60*120):
			if train._line.is_empty(): break
			train._walk(1.0/60)
		if not check(train._line.is_empty() and train.global_position.distance_to(goal) < 3.0,"The train should arrive (%.1f m off)" % train.global_position.distance_to(goal)): return
	var into: Array = rails.chain(line[0],branch_end,"player")
	var out: Array = rails.chain(branch_end,line[0],"player")
	var needs_reverse: bool = into.any(func(step): return step.get("reverse",false)) or out.any(func(step): return step.get("reverse",false))
	if not check(not needs_reverse or reversals > 0,"Where the fork faces away the train should reverse at it"): return
	print("  fork faces %s: %d reversal%s on the round trip" % ["away (reversing)" if needs_reverse else "the Depot",reversals,"" if reversals == 1 else "s"])
	# A train standing on the fork itself gets onto the other lane: it runs out through the entry, reverses and
	# backs in. From the straight lane to the branch's end, and from the branch to the line beyond the straight exit.
	var beyond_exit: Node3D = rails.connection(fork_piece,1).piece
	for trip in [[0,branch_end.point_at(branch_end.length()*0.5)],[1,beyond_exit.point_at(beyond_exit.length()*0.5)]]:
		var from_lane: int = trip[0]
		var goal: Vector3 = trip[1]
		train.piece = fork_piece; train.lane = from_lane; train.along = fork_piece.length(from_lane)*0.6
		train.global_position = fork_piece.point_at(train.along,from_lane)
		train._line = {}
		train._rest_line = rails.line([{piece = fork_piece, enter = -1, lane = from_lane}],train.along,-1.0,train.consist_length()+2.0)
		train._s = train._rest_line.start
		if not check(train._route_to_point(goal),"A train on the fork's lane %d should find a way off it" % from_lane): return
		if not check(train._line.has("then"),"Off the fork's lane %d the train reverses at the fork" % from_lane): return
		for i in range(60*120):
			if train._line.is_empty(): break
			train._walk(1.0/60)
		if not check(train._line.is_empty() and train.global_position.distance_to(goal) < 3.0,"The train from the fork's lane %d should arrive (%.1f m off)" % [from_lane,train.global_position.distance_to(goal)]): return
	train.queue_free()
	# Extending from the line's free end: a click near the end of the line by the far site, to a site beyond it.
	var tip: Dictionary = {}
	for end in rails.free_ends("player"):
		if whole.has(end.piece) and end.position.distance_to(far.global_position) < 25.0: tip = end
	if not check(not tip.is_empty(),"The line should have a free end by the far site"): return
	var beyond := site_near(tip.position+tip.out*35.0)
	if not check(beyond != null,"No site beyond the line's end"): return
	var at_end = rails.pick_at(tip.position-tip.out*1.0)
	if not check(at_end is RailAnchor,"A click near the end picks the track"): return
	rails.pick_target(at_end)
	said = rails.pick_target(beyond)
	if not check(not rails.pending.is_empty(),"Track beyond the end should be suggested: %s" % said): return
	var extends_end := false
	for entry in rails.pending:
		for index in range(rails.probe(entry.kind).end_count()):
			var end: Dictionary = rails._pending_end(entry,index)
			if end.position.distance_to(tip.position) < 0.05 and end.out.dot(tip.out) < -0.99: extends_end = true
	if not check(extends_end or rails.pending[0].kind.begins_with("fork"),"The new track should run on from the free end (or a fork near it)"): return
	laid = rails.commit_plan()
	rails.drop_route()
	if not check(not laid.is_empty() and line_of(laid[0]).has(line[0]),"The extension joins the same line"): return
	print("RAIL_JOIN_TEST_PASSED")
	quit(0)
