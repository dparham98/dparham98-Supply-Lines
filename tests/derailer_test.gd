extends SceneTree
# Headless: the Derailer (docs/DERAILER.md). The Motorcycle is now the Derailer, with a Derail card. Derail on a piece
# of track sends it there; it breaks the piece in the set time and recharges. The piece is destroyed, splitting the line;
# a train standing on it derails: it stops, tips over and loses its share of health. A wreck is left, and a click on
# it with the Rail tile armed lays the same piece again, joining the line.
var game: Node3D
var rails: Node
var network: Node
var hud: CanvasLayer
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
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/balanced_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	game.set_process(false)
	rails = game.get_node("RailNetwork")
	network = game.get_node("DepotNetwork")
	hud = game.get_node("Interface")
	hud.set_process(false)
	var depot: Node3D = game.depot
	depot.set_process(false)
	depot.storage_capacity = 100000; depot.iron = 20000; depot.energy = 20000
	for unit in get_nodes_in_group("units"): unit.set_process(false)
	# The name.
	var stats: Resource = load("res://assets/units/motorcycle.tres")
	if not check(stats.display_name == "Derailer" and stats.abilities.has(&"derail"),"The Motorcycle should be the Derailer, with Derail"): return
	# A line from the Depot.
	var far: Node3D
	for direction in [Vector3(1,0,0),Vector3(-1,0,0),Vector3(0,0,1),Vector3(0,0,-1)]:
		far = site_near(depot.global_position+direction*70.0)
		if far == null: continue
		rails.pick_target(depot)
		rails.pick_target(far)
		if not rails.pending.is_empty() and rails.plan_blocker().is_empty(): break
		rails.drop_route(); far.queue_free(); far = null
	if not check(far != null,"No open line from the Depot"): return
	var line: Array[Node3D] = rails.commit_plan()
	rails.drop_route()
	await process_frame
	if not check(line.size() >= 8,"The line should be laid"): return
	var target: Node3D
	for piece in line:
		if piece.kind == "straight" and piece.global_position.distance_to(depot.global_position) > 35.0: target = piece; break
	if not check(target != null,"No straight well out on the line"): return
	# A train runs out from the Depot and stops on that piece.
	var stop: Dictionary = rails.spawn_stop(depot)
	if not check(not stop.is_empty(),"A train can be built on the line"): return
	var train: Node3D = rails.train_scene.instantiate()
	train.team = "player"
	game.get_node("Entities/Units").add_child(train)
	train.global_position = stop.position
	train.snap_to_track()
	train.set_process(false)
	var end: Node3D = line[line.size()-1]
	if not check(train._route_to_point(target.point_at(target.length()*0.5)),"The train should find the piece"): return
	for i in range(60*60):
		if train._line.is_empty(): break
		train._walk(1.0/60)
	if not check(train.piece == target and not train.derailed,"The train should stand on the piece: %s" % train.state): return
	# A Derailer beside the track.
	var derailer: Node3D = load("res://scenes/gameplay/motorcycle.tscn").instantiate()
	derailer.team = "player"
	game.get_node("Entities/Units").add_child(derailer)
	derailer.global_position = depot.global_position+(target.global_position-depot.global_position)*0.5+Vector3(0,0,6)
	await process_frame
	derailer.set_process(false)
	if derailer.fuel_rules != null: derailer.fuel = derailer.fuel_rules.reserve_capacity
	# Its card shows Derail.
	game.selected_building = null
	derailer.set_selected(true)
	hud._process(0)
	if not check(hud.desired_buttons.has("Derail") and not hud.card.get_node("Derail").disabled,"The Derailer's card should show Derail: %s" % [hud.desired_buttons]): return
	if not check(hud.object_name(derailer) == "Derailer","The HUD names it the Derailer"): return
	# Arm Derail and click the piece.
	hud.card.get_node("Derail").pressed.emit()
	if not check(game.pending_unit_command == "derail","The card should arm Derail"): return
	var rig: Node = game.get_node("CameraRig")
	var camera: Camera3D = rig.camera
	rig.set_process(false)
	rig.focus_position(target.global_position,60)
	for frame in range(300): rig.advance_camera(1.0/60)
	var spot: Vector3 = target.point_at(target.length()*0.5)
	game.issue_card_order(camera.unproject_position(spot))
	if not check(derailer.order == "derail" and derailer.order_target == target,"The Derailer should head for the clicked piece: %s %s" % [derailer.order,derailer.state]): return
	# It drives there and breaks the piece in the set time.
	var kind: String = target.kind
	var xf: Transform3D = target.global_transform
	var health: int = train.health
	var count: int = rails.pieces.size()
	var seconds := 0.0
	while rails.pieces.has(target) and seconds < 40.0:
		derailer._process(1.0/30); seconds += 1.0/30
	if not check(not rails.pieces.has(target),"The piece should be destroyed (%s)" % derailer.state): return
	if not check(seconds >= rails.rules.derail_seconds,"Breaking takes the set time"): return
	if not check(rails.pieces.size() == count-1,"One piece goes: %d of %d" % [rails.pieces.size(),count]): return
	if not check(not rails.reachable(line[0],end,"player"),"The line is split where the piece was"): return
	if not check(derailer.derail_cooldown > 0.0 and derailer.order == "idle","Derail should recharge afterwards"): return
	hud._process(0)
	if not check(hud.card.get_node("Derail").disabled,"The card shows Derail recharging"): return
	# Another piece, while recharging: refused.
	derailer.command_derail(line[1])
	if not check(derailer.order != "derail","Derail is refused while recharging"): return
	derailer.set_selected(false)
	# The train on it derailed and stays put: no new route, and the rail change does not put it back on the track.
	await process_frame
	if not check(train.derailed and train.state == "Derailed","The train on the piece should derail"): return
	if not check(train.health == health-roundi(train.max_health*rails.rules.derail_damage),"The train loses its share of health: %d of %d" % [train.health,health]): return
	if not check(not train._route_to_point(line[0].point_at(1.0)),"A derailed train cannot be sent anywhere"): return
	var at: Vector3 = train.global_position
	train._process(0.5)
	if not check(train.global_position == at and absf(train.get_node("Visuals").rotation.z) > 0.3,"It stays tipped over where it fell"): return
	# A wreck is left in its place, the player's, showing the piece's model.
	var wrecks := get_nodes_in_group("rail_wrecks")
	if not check(wrecks.size() == 1,"One wreck should be left: %d" % wrecks.size()): return
	var wreck: Node3D = wrecks[0]
	if not check(wreck.kind == kind and wreck.team == "player" and wreck.global_transform.origin.is_equal_approx(xf.origin),"The wreck is the player's %s where it was" % kind): return
	if not check(wreck.get_node("Visuals/Straight").visible and not wreck.get_node("Visuals/Curve").visible and wreck.get_node("Visuals/Spike").visible,"The wreck shows the broken straight and the spike"): return
	if not check(rails.wreck_at(spot) == wreck and rails.wreck_at(spot,"enemy") == null,"The wreck is found under its middle, for its own side only"): return
	# Its owner is shown what to do: a pulsing marker over it, an alert in the feed, and a cross on the minimap.
	var marker: Node3D = wreck.get_node("RebuildMarker")
	if not check(marker.visible and wreck.get_node("Pulse").is_playing() and marker.get_node("Label").text.contains("Rail (R)") and marker.get_node("Label").text.contains("%d iron" % rails.cost(kind)),"The owner's wreck shows the rebuild marker: %s" % marker.get_node("Label").text): return
	if not check(Vector2(marker.global_position.x,marker.global_position.z).distance_to(Vector2(spot.x,spot.z)) < 1.0,"The marker stands over the wreck's middle"): return
	if not check(game.alerts.any(func(a): return a.kind == "rail" and a.point.distance_to(spot) < 1.0),"An alert points at the broken track"): return
	var enemy_wreck: Node3D = rails.wreck_scene.instantiate()
	enemy_wreck.team = "enemy"
	enemy_wreck.transform = wreck.transform.translated(Vector3(0,0,-40))
	wreck.get_parent().add_child(enemy_wreck)
	if not check(not enemy_wreck.get_node("RebuildMarker").visible,"Another side's wreck shows no marker to the player"): return
	enemy_wreck.free()
	# With the Rail tile armed, the cursor over the wreck offers to rebuild it, and a click does.
	game.placing_rail = true
	rails.cursor = spot
	if not check(rails.route_status().begins_with("WRECKED TRACK") and rails.route_status().ends_with("CLICK REBUILDS IT"),"The label offers the rebuild: %s" % rails.route_status()): return
	var iron: int = depot.iron
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = camera.unproject_position(spot)
	game._unhandled_input(click)
	await process_frame
	if not check(rails.pieces.size() == count and not game.placing_rail,"The click lays the piece again and leaves track laying"): return
	var again: Node3D = rails.pieces[rails.pieces.size()-1]
	if not check(again.kind == kind and again.global_transform.origin.is_equal_approx(xf.origin) and again.global_transform.basis.is_equal_approx(xf.basis),"The same piece goes back where it was"): return
	if not check(depot.iron == iron-rails.cost(kind),"Rebuilding costs the piece's iron: %d -> %d" % [iron,depot.iron]): return
	if not check(rails.reachable(line[0],end,"player"),"The line is joined again"): return
	if not check(get_nodes_in_group("rail_wrecks").all(func(w): return w.is_queued_for_deletion()),"The wreck is cleared"): return
	print("DERAILER_TEST_PASSED")
	quit(0)
