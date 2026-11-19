extends SceneTree
# Headless: rally points (docs/RALLY_POINTS.md) and autocast Fell (docs/FELL.md).
# Rally: with your Barracks selected, a right-click (here on the minimap) sets where its new units go; Shift adds a
# stop; on a forest the workers gather there; on the building it is cleared; a Depot's cargo vehicles use it too.
# Autocast: a right-click on the Fell card switches it; an idle worker then fells the Forest round where it was
# left, keeps no wood, and stops at the radius; switched off it stays idle.
var game: Node3D
var ground: Node3D
var network: Node
var hud: CanvasLayer
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func step(nodes: Array, seconds: float, done: Callable) -> bool:
	for i in range(ceili(seconds*60)):
		for node in nodes:
			if is_instance_valid(node): node._process(1.0/60)
		if done.call(): return true
	return false
func patch(origin: Vector2i, reach: int) -> int:
	var count := 0
	for z in range(origin.y-reach,origin.y+reach+1):
		for x in range(origin.x-reach,origin.x+reach+1):
			var cell := Vector2i(x,z)
			if origin.distance_squared_to(cell) <= reach*reach and ground.forest_amount(cell) > 0: count += 1
	return count
func site(kind: StringName, near: Vector3) -> Vector3:
	var spec: Dictionary = network.plan_spec(kind)
	for radius in range(10,100,4):
		for offset in [Vector3(radius,0,0),Vector3(-radius,0,0),Vector3(0,0,radius),Vector3(0,0,-radius)]:
			var point: Vector3 = near+offset
			var start: Vector2i = network.footprint_start(point,spec.size)
			if network.plan_terrain_valid(start,spec.size,kind) and not network.plan_overlaps(start,spec.size) and network.can_place_size(point,game.depot,spec.size): return point
	return Vector3.INF
func new_units(before: Array) -> Array:
	return get_nodes_in_group("units").filter(func(u): return not before.has(u))
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/balanced_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	game.set_process(false)
	ground = game.ground
	network = game.get_node("DepotNetwork")
	hud = game.get_node("Interface")
	var depot: Node3D = game.depot
	depot.set_process(false)
	depot.storage_capacity = 100000; depot.energy = 20000; depot.iron = 20000
	for unit in get_nodes_in_group("units"): unit.set_process(false); unit.set_selected(false)
	var rules = ground.harvesting_rules
	# A forest edge cell near the Depot.
	var home: Vector2i = ground.get_tile_at_position(depot.global_position)
	var edge := Vector2i(-1,-1)
	for r in range(1,60):
		for z in range(home.y-r,home.y+r+1):
			for x in range(home.x-r,home.x+r+1):
				if edge.x < 0 and maxi(absi(x-home.x),absi(z-home.y)) == r and ground.forest_amount(Vector2i(x,z)) > 0: edge = Vector2i(x,z)
		if edge.x >= 0: break
	if not check(edge.x >= 0,"No forest near the Depot"): return

	# --- Rally points on a Barracks.
	var point := site(&"barracks",depot.global_position)
	if not check(point != Vector3.INF,"No Barracks site"): return
	var plan = network.queue_plan(point,&"barracks")
	plan.set_process(false)
	var barracks: Node3D = plan.complete_from_stock()
	if not check(barracks != null,"Barracks not built"): return
	barracks.set_process(false)
	game.selected_building = barracks
	var first_stop: Vector3 = barracks.global_position+Vector3(12,0,0)
	var second_stop: Vector3 = barracks.global_position+Vector3(12,0,10)
	game.issue_map_order(first_stop,1.0,false)
	if not check(barracks.rally_points.size() == 1 and barracks.rally_points[0].kind == "move","A right-click should set the rally point: %s" % [barracks.rally_points]): return
	game.issue_map_order(second_stop,1.0,false,true)
	if not check(barracks.rally_points.size() == 2,"Shift should add a stop"): return
	var overlay = hud.get_node("MapOverlay")
	if not check(overlay.rally_path().size() == 3,"The overlay should draw the rally path from the building through both stops"): return
	var before := get_nodes_in_group("units")
	barracks.request_unit(&"infantry")
	barracks._process(barracks.base_seconds()+0.1)
	var made := new_units(before)
	if not check(made.size() == 1,"No Infantry produced"): return
	var infantry: Node3D = made[0]
	if not check(infantry.order == "move" and infantry.move_goal.distance_to(first_stop) < 1.0 and infantry.order_queue.size() == 1,"The Infantry should head for the first stop with the second queued: %s %s %d" % [infantry.order,infantry.move_goal,infantry.order_queue.size()]): return
	# On a forest: workers gather there.
	game.issue_map_order(ground.tile_to_world(edge),1.0,false)
	if not check(barracks.rally_points.size() == 1 and barracks.rally_points[0].kind == "gather","A rally on a forest should gather there: %s" % [barracks.rally_points]): return
	before = get_nodes_in_group("units")
	barracks.request_unit(&"infantry")
	barracks._process(barracks.base_seconds()+0.1)
	made = new_units(before)
	if not check(made.size() == 1 and made[0].order == "gather","The new Infantry should gather at the forest: %s" % [made[0].order if not made.is_empty() else "none"]): return
	# Not while units are selected: then a right-click orders them.
	made[0].set_selected(true)
	game.issue_map_order(first_stop,1.0,false)
	if not check(barracks.rally_points[0].kind == "gather" and made[0].order == "move","With units selected the right-click should order them"): return
	made[0].set_selected(false)
	# On the building itself: cleared, and new units stay by it.
	var rig = game.get_node("CameraRig")
	rig.set_process(false)
	rig.focus_position(barracks.global_position,40)
	for frame in range(180): rig.advance_camera(1.0/60)
	await process_frame
	game.issue_order(rig.camera.unproject_position(barracks.global_position+Vector3.UP*2.0))
	if not check(barracks.rally_points.is_empty(),"A right-click on the building should clear its rally: '%s'" % game.message): return
	before = get_nodes_in_group("units")
	barracks.request_unit(&"scout")
	barracks._process(barracks.base_seconds()+0.1)
	made = new_units(before)
	if not check(made.size() == 1 and made[0].order == "idle","Without a rally the unit waits by the building"): return
	# A Depot's cargo vehicle walks to its rally point; a gather stop is a move for it.
	game.selected_building = depot
	game.issue_map_order(ground.tile_to_world(edge),1.0,false)
	before = get_nodes_in_group("units")
	if not check(depot.request_cargo(),"Cargo not queued"): return
	depot._process(depot.print_seconds+0.1)
	made = new_units(before)
	if not check(made.size() == 1 and made[0].order == "move","The Depot's cargo vehicle should drive to the rally point: %s" % [made[0].order if not made.is_empty() else "none"]): return
	game.selected_building = null
	for unit in get_nodes_in_group("units"): unit.set_process(false)

	# --- Autocast Fell.
	var worker: Node3D = load("res://scenes/gameplay/infantry.tscn").instantiate()
	worker.team = "player"
	game.get_node("Entities/Units").add_child(worker)
	var toward: Vector3 = (depot.global_position-ground.tile_to_world(edge)).normalized()
	worker.global_position = ground.tile_to_world(edge)+toward*1.5
	worker.set_process(false)
	await process_frame
	worker.set_selected(true)
	hud._process(0)
	var button: Button = hud.card.get_node("Fell")
	if not check(button.visible and not button.get_node("Auto").visible and not worker.fell_autocast,"Autocast starts off"): return
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT; right.pressed = true
	button.gui_input.emit(right)
	if not check(worker.fell_autocast and button.get_node("Auto").visible,"A right-click on the Fell card should switch autocast on"): return
	rules.autocast_fell_radius_cells = 2
	var spot: Vector2i = ground.get_tile_at_position(worker.global_position)
	var standing := patch(spot,2)
	var beyond := patch(spot,5)-standing
	if not check(standing >= 1,"No forest round the worker"): return
	var wood_before: int = depot.wood
	if not check(step([worker],3.0,func(): return worker.order == "fell"),"The idle worker should start felling on its own: '%s'" % worker.state): return
	if not check(step([worker],standing*rules.forest_wood_per_tile/float(worker.harvest_amount)*worker.harvest_interval+90.0,func(): return patch(spot,2) == 0 and worker.order == "idle"),"Autocast should clear round its spot: %d cells left, state '%s'" % [patch(spot,2),worker.state]): return
	if not check(patch(spot,5) == beyond and depot.wood == wood_before,"It should stop at the radius and keep no wood: %d of %d beyond, wood %d" % [patch(spot,5),beyond,depot.wood-wood_before]): return
	step([worker],3.0,func(): return false)
	if not check(worker.order == "idle","With its patch clear it should stay idle, not wander into the forest: '%s'" % worker.order): return
	# Switched off, a worker left by trees stays idle.
	button.gui_input.emit(right)
	if not check(not worker.fell_autocast and not button.get_node("Auto").visible,"A second right-click should switch it off"): return
	worker.command_move(ground.tile_to_world(edge)+toward*6.0)
	step([worker],20.0,func(): return worker.order == "idle")
	step([worker],3.0,func(): return false)
	if not check(worker.order == "idle","With autocast off the worker should not fell"): return
	rules.autocast_fell_radius_cells = 4
	print("RALLY_AUTOFELL_TEST_PASSED")
	quit(0)
