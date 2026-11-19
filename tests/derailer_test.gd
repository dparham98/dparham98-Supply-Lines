extends SceneTree
# Headless: the Derailer (docs/DERAILER.md). The Motorcycle is now the Derailer, with a Derail card. Derail on a piece
# of track sends it there; it spikes the piece in the set time and recharges. A train onto the spiked piece derails:
# it stops, tips over and loses its share of health, and the piece is wrecked, splitting the line.
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
			var plan = network.queue_plan(point+offset,&"generator")
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
	var camera: Camera3D = game.get_node("CameraRig").camera
	game.get_node("CameraRig").set_process(false)
	game.get_node("CameraRig").focus_position(target.global_position,60)
	for frame in range(300): game.get_node("CameraRig").advance_camera(1.0/60)
	var spot: Vector3 = target.point_at(target.length()*0.5)
	game.issue_card_order(camera.unproject_position(spot))
	if not check(derailer.order == "derail" and derailer.order_target == target,"The Derailer should head for the clicked piece: %s %s" % [derailer.order,derailer.state]): return
	# It drives there and spikes the piece in the set time.
	var seconds := 0.0
	while not target.is_spiked() and seconds < 40.0:
		derailer._process(1.0/30); seconds += 1.0/30
	if not check(target.is_spiked() and target.spiked_by == "player","The piece should be spiked (%s)" % derailer.state): return
	if not check(target.get_node("Visuals/Spike").visible,"The spike shows on the track"): return
	if not check(derailer.derail_cooldown > 0.0 and derailer.order == "idle","Derail should recharge afterwards"): return
	hud._process(0)
	if not check(hud.card.get_node("Derail").disabled,"The card shows Derail recharging"): return
	# Another piece, while recharging: refused.
	derailer.command_derail(line[1])
	if not check(derailer.order != "derail","Derail is refused while recharging"): return
	derailer.set_selected(false)
	# A train from the Depot runs out along the line and derails on the spiked piece.
	var stop: Dictionary = rails.spawn_stop(depot)
	if not check(not stop.is_empty(),"A train can be built on the line"): return
	var train: Node3D = rails.train_scene.instantiate()
	train.team = "player"
	game.get_node("Entities/Units").add_child(train)
	train.global_position = stop.position
	train.snap_to_track()
	train.set_process(false)
	var end: Node3D = line[line.size()-1]
	if not check(train._route_to_point(end.point_at(end.length()*0.5)),"The train should find the far end"): return
	var health: int = train.health
	var count: int = rails.pieces.size()
	for i in range(60*60):
		if train.derailed or train._line.is_empty(): break
		train._walk(1.0/60)
	await process_frame
	if not check(train.derailed and train.state == "Derailed","The train should derail on the spiked piece"): return
	if not check(train.global_position.distance_to(target.global_position) < target.length()+2.0 if is_instance_valid(target) else true,"It stops at the spiked piece"): return
	if not check(not is_instance_valid(target) or not rails.pieces.has(target),"The spiked piece is wrecked"): return
	if not check(rails.pieces.size() == count-1,"One piece goes: %d of %d" % [rails.pieces.size(),count]): return
	if not check(train.health == health-roundi(train.max_health*rails.rules.derail_damage),"The train loses its share of health: %d of %d" % [train.health,health]): return
	if not check(not rails.reachable(line[0],end,"player"),"The line is split where the piece was"): return
	# It stays put: no new route, and the rail change does not put it back on the track.
	if not check(not train._route_to_point(line[0].point_at(1.0)),"A derailed train cannot be sent anywhere"): return
	var at: Vector3 = train.global_position
	train._process(0.5)
	if not check(train.global_position == at and train.derailed and absf(train.get_node("Visuals").rotation.z) > 0.3,"It stays tipped over where it fell"): return
	print("DERAILER_TEST_PASSED")
	quit(0)
