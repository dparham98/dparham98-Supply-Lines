extends SceneTree
# Headless: a train queued at a Depot that more than one line of track reaches (docs/RAIL_PLANNING.md). The
# Train tile then waits for the player to click the line; the train is printed on that line. With one line it
# queues at once, as before.
var game: Node3D
var rails: Node
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
## Prints the Depot's head job at once.
func finish_job(depot: Node3D) -> void:
	depot.progress = depot.current_seconds()
	depot._process(0.0)
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/rail_exercise.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	for group in ["units","depots"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	rails = game.get_node("RailNetwork")
	var depot: Node3D = game.depot
	depot.energy = 2000; depot.iron = 500
	var hud = game.get_node("Interface")
	var network = game.get_node("DepotNetwork")
	network.select_depot(depot)
	# One line: the Train tile queues at once.
	var south: Array[Node3D] = rails.depot_lines(depot)
	if not check(south.size() == 1,"The fixture should have one line at the Depot: %d" % south.size()): return
	hud.queue_train()
	if not check(game.pending_unit_command.is_empty() and depot.pending.size() == 1 and depot.train_lines == [null],"With one line the train should queue at once"): return
	depot.cancel_current()
	if not check(depot.pending.is_empty() and depot.train_lines.is_empty(),"Cancelling the train should drop its line too"): return
	# A second, separate line north of the Depot, inside its ring.
	var north_xf: Transform3D = rails.transform_for("straight",depot.global_position+Vector3(-2.4,0,-9),Vector3.RIGHT)
	var north: Node3D = rails.straight_scene.instantiate()
	north.assigned_depot = depot
	north.transform = north_xf
	game.get_node("Entities/Rails").add_child(north)
	await process_frame
	var reaching: Array[Node3D] = rails.depot_lines(depot)
	if not check(reaching.size() == 2,"Two lines should reach the Depot: %d" % reaching.size()): return
	# Two lines: the tile waits for a line.
	hud.queue_train()
	if not check(game.pending_unit_command == "train_line" and depot.pending.is_empty(),"With two lines the Train tile should ask for a line first"): return
	# Open ground far from both lines is refused.
	game.issue_map_order(depot.global_position+Vector3(0,0,-60),1.0,true)
	if not check(game.pending_unit_command == "train_line" and depot.pending.is_empty() and "rail lines" in game.message,"A click off the lines should be refused: "+game.message): return
	# A click on the north line queues the train there.
	game.issue_map_order(north.global_position,1.0,true)
	if not check(game.pending_unit_command.is_empty() and depot.pending == ["train"] and depot.train_lines.size() == 1,"A click on a line should queue the train: %s" % [depot.train_lines]): return
	var chosen: Node3D = depot.train_lines[0]
	if not check(is_same(rails.lines()[chosen.get_instance_id()],rails.lines()[north.get_instance_id()]),"The train should keep the north line"): return
	var before := get_nodes_in_group("rail_trains").size()
	finish_job(depot)
	var trains := get_nodes_in_group("rail_trains")
	if not check(trains.size() == before+1 and depot.train_lines.is_empty(),"The train should be printed: %d trains" % trains.size()): return
	var made: Node3D = trains.filter(func(t): return t.global_position.distance_to(north.global_position) < 4.0).front() if trains.any(func(t): return t.global_position.distance_to(north.global_position) < 4.0) else null
	if not check(made != null,"The new train should stand on the north line"): return
	# The other line works too.
	var earlier := get_nodes_in_group("rail_trains")
	hud.queue_train()
	game.issue_map_order(south[0].global_position,1.0,true)
	finish_job(depot)
	var fresh := get_nodes_in_group("rail_trains").filter(func(t): return not earlier.has(t))
	if not check(fresh.size() == 1 and absf(fresh[0].global_position.z-south[0].global_position.z) < 1.0,"The second train should stand on the south line: %s" % [fresh.map(func(t): return t.global_position)]): return
	print("TRAIN_LINE_TEST_PASSED")
	quit(0)
