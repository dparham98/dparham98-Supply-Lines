extends SceneTree
# Headless: forks, Depot-connected rail and the energy-only one-car train (docs/MAGLEV_TRACKS.md).
var game: Node3D
var rails: Node
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> bool:
	if ok: return true
	push_error(message); quit(1); return false
func step(unit: Node3D, seconds: float) -> void:
	for i in range(ceili(seconds*60)): unit._process(1.0/60)
func add_piece(kind: String, xf: Transform3D, payer: Node3D) -> Node3D:
	var piece: Node3D = rails.scene_for(kind).instantiate()
	piece.assigned_depot = payer; piece.transform = xf
	game.get_node("Entities/Rails").add_child(piece)
	return piece
func open_tile(cell: Vector2i) -> void:
	var tile: Dictionary = game.ground.tiles[cell.y*500+cell.x]
	tile.terrain = 0; tile.buildable = true
func run() -> void:
	game = load("res://scenes/maps/rail_exercise.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	for group in ["units","depots"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	rails = game.get_node("RailNetwork")
	var source: Node3D = game.depot
	var destination: Node3D = game.get_node("Entities/Buildings/EastDepot")
	var train: Node3D = game.get_node("Entities/Units/Train")
	# Testing switch: built vehicles start full.
	if not check(FuelRules.testing_full_tanks,"Vehicles should start full while testing"): return
	# The train is a single energy-only car with the old capacity.
	game.vehicle_fuel_required = true
	if not check(train.get_node("Visuals/Model").cars().size() == 1 and train.fuel_rules == null and not train.fuel_active() and rails.rules.cargo_capacity == 300,"Train should be one fuel-free car carrying 300"): return
	# Fork geometry and price: both lanes count, and every end can be the one that joins the track.
	if not check(is_equal_approx(rails.piece_length("fork_left"),14.4+12.0*PI*0.5) and rails.cost("fork_left") == 67 and rails.cost("fork_right") == 67,"Fork length or price wrong: %.2f %d" % [rails.piece_length("fork_left"),rails.cost("fork_left")]): return
	for kind in ["fork_left","fork_right"]:
		for join in range(3):
			var at := Vector3(10,0,20)
			var xf: Transform3D = rails.transform_for(kind,at,Vector3.RIGHT,join)
			var end: Dictionary = rails.probe(kind).local_end(join)
			if not check((xf*(end.position as Vector3)).distance_to(at) < 0.01 and (xf.basis*(end.out as Vector3)).distance_to(Vector3.LEFT) < 0.01,"%s end %d does not join" % [kind,join]): return
	# Laying rule: only in a Depot's loading range or joined to connected track.
	var near_xf: Transform3D = rails.transform_for("straight",source.global_position+Vector3(-6,0,-7),Vector3.RIGHT)
	var far_xf: Transform3D = rails.transform_for("straight",source.global_position+Vector3(-6,0,-14),Vector3.RIGHT)
	if not check(rails.connects("straight",near_xf) and not rails.connects("straight",far_xf) and not rails.can_place("straight",far_xf,source,false),"Connection rule wrong"): return
	# A fork on a free end, with a straight on each exit.
	# The fixture's west end has room for the fork; its exits run onto terrain cleared here for the test.
	var open: Dictionary = {}
	for end in rails.free_ends("player"):
		if rails.ground_clear(rails.cells_for("fork_left",rails.transform_for("fork_left",end.position,end.out))): open = end
	if not check(not open.is_empty(),"No open land for a fork"): return
	var fork_kind := "fork_left"
	var fork_xf: Transform3D = rails.transform_for(fork_kind,open.position,open.out)
	var fork: Node3D = add_piece(fork_kind,fork_xf,source)
	var fork_ends: Array[Dictionary] = fork.ends()
	var left: Vector3 = Vector3.UP.cross(open.out)*(1.0 if fork_kind == "fork_left" else -1.0)
	if not check(rails.pieces.has(fork) and rails.connection(fork,0).piece == open.piece,"Fork did not join the line"): return
	if not check(fork_ends[1].position.distance_to(open.position+open.out*14.4) < 0.05 and fork_ends[1].out.distance_to(open.out) < 0.01,"Fork straight exit wrong: %s" % fork_ends[1].position): return
	if not check(fork_ends[2].position.distance_to(open.position+open.out*12.0+left*12.0) < 0.05 and fork_ends[2].out.distance_to(left) < 0.01,"Fork branch exit wrong: %s" % fork_ends[2].position): return
	var exit_xfs: Array[Transform3D] = [rails.transform_for("straight",fork_ends[1].position,fork_ends[1].out),rails.transform_for("straight",fork_ends[2].position,fork_ends[2].out)]
	for xf in exit_xfs:
		for cell in rails.cells_for("straight",xf): open_tile(cell)
	var straight_on: Node3D = add_piece("straight",exit_xfs[0],source)
	var branch: Node3D = add_piece("straight",exit_xfs[1],source)
	if not check(rails.pieces.has(straight_on) and rails.pieces.has(branch),"Exit pieces did not register"): return
	# Routes go entry to either exit, never exit to exit.
	var to_branch: Array = rails.chain(train.piece,branch,"player",train.lane)
	var to_straight: Array = rails.chain(train.piece,straight_on,"player",train.lane)
	var lane_on := func(route: Array) -> int:
		for entry in route:
			if entry.piece == fork: return entry.lane
		return -1
	if not check(lane_on.call(to_branch) == 1 and lane_on.call(to_straight) == 0,"Routes took the wrong fork lane"): return
	if not check(not rails.reachable(straight_on,branch,"player") and not rails.reachable(branch,straight_on,"player"),"A train crossed from one fork exit to the other"): return
	# A run onto the branch throws the switch, follows the arc and pays energy by the metre.
	source.energy = 1000; destination.energy = 1000
	var goal: Vector3 = branch.point_at(2.4)
	if not check(train._route_to_point(goal),"No route to the branch"): return
	var trip: float = train._goal-train._s
	if not check(fork.route_lane == 1,"Switch not thrown for the branch"): return
	await create_timer(0.5).timeout
	if not check(absf(fork.blade_branch.position.y) < 0.01 and absf(fork.blade_straight.position.y+0.46) < 0.01,"Blades did not move: %s %s" % [fork.blade_branch.position,fork.blade_straight.position]): return
	for i in range(60*40):
		train._process(1.0/60)
		if train._route.is_empty() and train._line.is_empty(): break
	if not check(train.piece == branch and train.global_position.distance_to(goal) < 2.0,"Train did not reach the branch: %s" % train.global_position): return
	var paid: int = 2000-source.energy-destination.energy
	if not check(paid == floori(trip*rails.rules.train_energy_per_metre),"Train paid %d energy for %.1f m" % [paid,trip]): return
	# No energy on the line: it holds position with its state, and carries on when energy returns.
	source.energy = 0; destination.energy = 0
	var home: Vector3 = source.global_position
	if not check(train._route_near(source,source.dropoff_range),"No route back to the Depot"): return
	var held: Vector3 = train.global_position
	step(train,1.0)
	if not check(train.global_position == held and train.state.begins_with("No power"),"Train moved without power: %s" % train.state): return
	source.energy = 100
	step(train,1.0)
	if not check(train.global_position != held,"Train did not resume when power returned"): return
	train._stop_route()
	# The nearest connected Depot with energy pays.
	var at: Vector3 = train.global_position
	var nearer: Node3D = source if at.distance_squared_to(home) < at.distance_squared_to(destination.global_position) else destination
	var farther: Node3D = destination if nearer == source else source
	nearer.energy = 50; farther.energy = 50
	if not check(rails.power_source(train.piece,at,"player") == nearer,"Nearest Depot should pay"): return
	nearer.energy = 0
	if not check(rails.power_source(train.piece,at,"player") == farther,"Next Depot should pay when the nearest is empty"): return
	# Cut line: a route stops, keeps its cargo and resumes by itself when the line is whole.
	source.energy = 500; destination.energy = 500
	if not check(train.start_supply_route(source,destination,1,0,true) and train.route_active,"Route refused"): return
	var gap: Node3D = game.get_node("Entities/Rails/Track3")
	var gap_xf: Transform3D = gap.global_transform
	gap.free()
	await process_frame
	if not check(train.waiting_for_rail and train.route_active and not train.route_paused and train.state.begins_with("No power"),"A cut line should hold the route: %s" % train.state): return
	add_piece("straight",gap_xf,source)
	await process_frame
	if not check(not train.waiting_for_rail and train.route_active,"Route did not resume with the line restored"): return
	print("RAIL_FORK_POWER_TEST_PASSED"); quit()
