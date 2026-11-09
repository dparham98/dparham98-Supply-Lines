extends SceneTree
# Headless: the maglev network (docs/MAGLEV_TRACKS.md). Authored straight and curve pieces lay end
# to end from the nearest free end, Depot-paid by length; pieces connect head-on; a cut piece breaks
# the line; trains print at a loading stop and follow the joined centre lines with their consist.
var game: Node3D
var rails: Node
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> bool:
	if ok: return true
	push_error(message); quit(1); return false
func step(unit: Node3D, seconds: float) -> void:
	for i in range(ceili(seconds*60)): unit._process(1.0/60)
func run() -> void:
	game = load("res://scenes/maps/rail_exercise.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	for group in ["units","depots"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	rails = game.get_node("RailNetwork")
	var source = game.depot
	var destination = game.get_node("Entities/Buildings/EastDepot")
	var train = game.get_node("Entities/Units/Train")
	if not check(rails.pieces.size() == 7 and train.is_in_group("rail_trains") and train.move_speed == 8,"Rail fixture or train config incorrect"): return
	# Geometry at world scale 0.6: straights 4.8 m, curves radius 12 m, 3 m wide, costed by length.
	if not check(is_equal_approx(rails.piece_length("straight"),4.8) and is_equal_approx(rails.piece_length("curve"),12.0*PI*0.5) and rails.cost("straight") == 10 and rails.cost("curve") == 38,"Piece geometry or cost wrong: %.2f %.2f %d %d" % [rails.piece_length("straight"),rails.piece_length("curve"),rails.cost("straight"),rails.cost("curve")]): return
	# The seven fixture pieces join head-on into one line with a free end at each extreme.
	var first = game.get_node("Entities/Rails/Track0")
	var last = game.get_node("Entities/Rails/Track6")
	if not check(rails.connection(first,1).piece == game.get_node("Entities/Rails/Track1") and rails.connection(first,0).is_empty() and rails.connection(last,1).is_empty(),"Fixture pieces are not joined end to end"): return
	if not check(rails.free_ends("player").size() == 2 and rails.reachable(first,last,"player"),"Free ends or reachability wrong"): return
	if not check(not first.cells.is_empty() and game.ground.tiles[first.cells[0].y*500+first.cells[0].x].get("rail") == first,"Piece did not mark its tiles"): return
	# Laying from the east free end snaps onto it and the covering Depot pays by length.
	var east_end: Vector3 = last.ends()[1].position
	var payer_iron: int = destination.iron
	var extra = rails.place("straight",east_end+Vector3(1.5,0,0.8),Vector3.FORWARD,false)
	if not check(extra != null and rails.pieces.size() == 8 and rails.connection(last,1).piece == extra and extra.assigned_depot == destination and destination.iron == payer_iron-10,"Snapped straight not laid or not paid by the covering Depot"): return
	if not check(extra.ends()[1].position.distance_to(east_end+Vector3(4.8,0,0)) < 0.01 and extra.ends()[1].out.distance_to(Vector3.RIGHT) < 0.01,"Snapped straight continues the line: %s" % extra.ends()[1].position): return
	# A piece over existing track or outside every Depot territory is refused for free.
	var before: int = destination.iron
	if not check(rails.place("straight",game.get_node("Entities/Rails/Track3").point_at(2.4),Vector3.FORWARD,false) == null and rails.place("straight",Vector3(60,0,60),Vector3.RIGHT,false) == null and destination.iron == before and rails.pieces.size() == 8,"Invalid track was laid or charged"): return
	# Curves from a free end: a left curve exits a quarter turn to the travel's left,
	# the mirrored curve to its right, both 12 m along and 12 m across.
	var entry := Vector3.INF
	var heading := Vector3.RIGHT
	for end in rails.free_ends("player"):
		for payer in [source,destination]:
			if rails.can_place("curve",rails.transform_for("curve",end.position,end.out,false),payer,false) and rails.can_place("curve",rails.transform_for("curve",end.position,end.out,true),payer,false):
				entry = end.position; heading = end.out
	if not check(entry != Vector3.INF,"No open land for a curve test near the Depot"): return
	var left_side: Vector3 = Vector3.UP.cross(heading)
	var curve = rails.place("curve",entry,heading,false)
	if not check(curve != null and curve.kind == "curve","Curve not laid"): return
	var curve_payer: Node3D = curve.assigned_depot
	var exit: Dictionary = curve.ends()[1]
	var expected: Vector3 = curve.ends()[0].position+heading*12.0+left_side*12.0
	if not check(exit.position.distance_to(expected) < 0.05 and exit.out.distance_to(left_side) < 0.01,"Left curve exit wrong: %s heading %s (expected %s)" % [exit.position,exit.out,expected]): return
	var iron_after_curve: int = curve_payer.iron
	curve.free(); await process_frame
	var mirrored = rails.place("curve",entry,heading,true)
	if not check(mirrored != null and mirrored.assigned_depot.iron == iron_after_curve-38,"Mirrored curve not laid or mispriced"): return
	var start_end: Dictionary = mirrored.ends()[1]
	var far_end: Dictionary = mirrored.ends()[0]
	var expected_right: Vector3 = start_end.position+heading*12.0-left_side*12.0
	if not check(start_end.position.distance_to(entry) < 0.8 and far_end.position.distance_to(expected_right) < 0.05 and far_end.out.distance_to(-left_side) < 0.01,"Right curve exit wrong: %s / %s" % [mirrored.ends()[0].position,mirrored.ends()[1].position]): return
	mirrored.free(); await process_frame
	# A printed train appears at the Depot's loading stop, on friendly track.
	source.energy = 500; source.iron = 500
	if not check(source.request_train(),"Train print refused"): return
	source._process(3.1)
	var printed: Node3D
	for node in get_nodes_in_group("rail_trains"):
		if node != train: printed = node; node.set_process(false)
	if not check(printed != null and printed.on_friendly_track() and printed.global_position.distance_to(source.global_position) <= source.dropoff_range+0.01,"Paid train did not spawn at the loading stop"): return
	# Lines: the exercise train reaches both Depots; cutting the centre piece breaks the line.
	if not check(not rails.line_to_depot(train.piece,train.along,destination,"player").is_empty(),"Train cannot reach EastDepot along the fixture"): return
	var gap = game.get_node("Entities/Rails/Track3")
	var gap_transform: Transform3D = gap.global_transform
	var gap_payer = gap.assigned_depot
	gap.free(); await process_frame
	if not check(rails.line_to_depot(train.piece,train.along,destination,"player").is_empty() and not rails.line_to_depot(train.piece,train.along,source,"player").is_empty(),"Cut line still connected"): return
	var restored = rails.straight_scene.instantiate()
	restored.assigned_depot = gap_payer; restored.transform = gap_transform
	game.get_node("Entities/Rails").add_child(restored)
	if not check(rails.pieces.has(restored) and not rails.line_to_depot(train.piece,train.along,destination,"player").is_empty(),"Restored piece did not rejoin the line"): return
	# Movement: the train follows the line to the EastDepot stop and its consist rides the track.
	var model = train.get_node("Visuals/Model")
	if not check(model.has_method("place") and model.cars().size() == 1 and model.get_node_or_null("Engine") == null,"Train consist missing"): return
	if not check(train._route_near(destination,destination.dropoff_range),"Train could not route to EastDepot"): return
	var start: Vector3 = train.global_position
	var travelled := false
	for i in range(60*30):
		train._process(1.0/60)
		if train.global_position != start: travelled = true
		if train._route.is_empty(): break
	if not check(travelled and train._route.is_empty() and train.global_position.distance_to(destination.global_position) <= destination.dropoff_range+0.05,"Train did not arrive at the EastDepot stop: %s" % train.global_position): return
	if not check(train.on_friendly_track() and absf(train.global_position.z-156.5) < 0.05,"Train left the track: %s" % train.global_position): return
	var car: Node3D = model.cars()[0].node
	if not check(absf(car.global_position.z-156.5) < 0.3 and absf(car.global_position.y) < 0.01,"Car is not on the track: %s" % car.global_position): return
	# Losing one Depot leaves the line usable through the other; both enemies have a Depot on it then.
	destination.team = "enemy"; destination.ownership_changed.emit()
	if not check(rails.friendly_piece(last,"player") and rails.friendly_piece(last,"enemy"),"A line belongs to every team with a connected Depot"): return
	source.team = "enemy"; source.ownership_changed.emit()
	if not check(not rails.friendly_piece(last,"player"),"A line with no friendly Depot stayed friendly"): return
	source.team = "player"; source.ownership_changed.emit()
	destination.team = "player"; destination.ownership_changed.emit()
	print("RAIL_BATCH_CHECKS_PASSED"); quit()
