extends SceneTree
# Headless: the minimap gives orders (docs/MINIMAP_ORDERS.md). Right-click orders the selected units to the
# clicked point or marker, Shift queues, a waiting command takes its point from a left-click, and a left-click
# with nothing waiting still only moves the camera.
var game: Node3D
var minimap: Control
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func click(point: Vector3, button: MouseButton, shift := false) -> void:
	var event := InputEventMouseButton.new()
	event.position = minimap.world_to_map(point)
	event.button_index = button
	event.pressed = true
	event.shift_pressed = shift
	minimap._gui_input(event)
## Open land near `from` for `unit`, at least `reach` away.
func open_point(unit: Node3D, from: Vector3, reach: float) -> Vector3:
	var ground = game.ground
	for radius in range(int(reach),int(reach)+40,2):
		for offset in [Vector3(radius,0,0),Vector3(0,0,radius),Vector3(-radius,0,0),Vector3(0,0,-radius)]:
			var cell = ground.get_tile_at_position(from+offset)
			if cell != null and ground.can_traverse(cell,unit.mobility_layer(),unit._owner_key()) and ground.get_terrain(cell) not in [3,5,6] and clear_of_markers(ground.tile_to_world(cell)):
				return ground.tile_to_world(cell)
	return Vector3.INF
## Whether no marker an order could target lies within the minimap's pick radius of `point`.
func clear_of_markers(point: Vector3) -> bool:
	for group in ["units","resources","selectable_buildings","depots","mobile_supplies","construction_plans","supply_crates"]:
		for node in get_nodes_in_group(group):
			if Vector2(node.global_position.x-point.x,node.global_position.z-point.z).length() <= minimap.order_radius()+1: return false
	return true
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.get_node("Interface").set_process(false)
	for group in ["units","depots"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	var rig = game.get_node("CameraRig")
	rig.set_process(false)
	minimap = game.get_node("Interface/Bottom/Body/Row/MapColumn/Map")
	await process_frame
	if not check(minimap.size.x > 0,"The minimap has no size"): return
	var worker: Node3D = game.get_node("Entities/Units/Infantry")
	for node in get_nodes_in_group("units"): node.set_selected(false)
	var a := open_point(worker,worker.global_position,20)
	var b := open_point(worker,worker.global_position,40)
	if not check(a != Vector3.INF and b != Vector3.INF,"No open land near the Infantry"): return
	# With nothing selected a right-click gives no order.
	click(a,MOUSE_BUTTON_RIGHT)
	if not check(worker.order == "idle","A right-click with nothing selected should give no order"): return
	worker.set_selected(true)
	# Right-click moves the selected units there; Shift queues.
	click(a,MOUSE_BUTTON_RIGHT)
	if not check(worker.order == "move" and Vector2(worker.move_goal.x-a.x,worker.move_goal.z-a.z).length() < 0.5,"A minimap right-click should move the Infantry to %s: %s %s" % [a,worker.order,worker.move_goal]): return
	click(b,MOUSE_BUTTON_RIGHT,true)
	if not check(worker.order_queue.size() == 1 and worker.order_queue[0].kind == "move" and "queued" in game.message,"A Shift right-click on the minimap should queue a move"): return
	# A right-click on a hostile's marker attacks it.
	var hostile: Node3D = get_first_node_in_group("enemies")
	click(hostile.global_position+Vector3(1,0,1),MOUSE_BUTTON_RIGHT)
	if not check(worker.order == "attack" and worker.order_target == hostile and worker.order_queue.is_empty(),"A right-click on a hostile marker should attack it: %s" % worker.order): return
	# The pointer is itself again afterwards.
	if not check(game._map_point == Vector3.INF,"The minimap point should be cleared after the order"): return
	# A waiting Move takes its point from a left-click, then disarms.
	game.pending_unit_command = "move"
	click(b,MOUSE_BUTTON_LEFT)
	if not check(worker.order == "move" and Vector2(worker.move_goal.x-b.x,worker.move_goal.z-b.z).length() < 0.5 and game.pending_unit_command.is_empty(),"A waiting Move should take the minimap point"): return
	# A waiting Attack on open ground is attack-move.
	game.pending_unit_command = "attack"
	click(a,MOUSE_BUTTON_LEFT)
	if not check(worker.order == "attack_move","A waiting Attack on minimap ground should attack-move: %s" % worker.order): return
	# Right-click cancels a waiting command without ordering.
	game.pending_unit_command = "move"
	click(b,MOUSE_BUTTON_RIGHT)
	if not check(game.pending_unit_command.is_empty() and worker.order == "attack_move","A right-click should cancel the waiting command and give no order"): return
	# A waiting Pin with no stop under the click still pans, as before.
	worker.set_selected(false)
	game.pending_unit_command = "pin"
	click(b,MOUSE_BUTTON_LEFT)
	if not check(game.pending_unit_command == "pin" and Vector2(rig._focus_target.x-b.x,rig._focus_target.z-b.z).length() < 1.0,"Pin away from every stop should pan"): return
	game.cancel_armed()
	# With nothing waiting a left-click only moves the camera.
	worker.set_selected(true)
	click(a,MOUSE_BUTTON_LEFT)
	if not check(worker.order == "attack_move" and Vector2(rig._focus_target.x-a.x,rig._focus_target.z-a.z).length() < 1.0,"A plain left-click should only move the camera"): return
	print("MINIMAP_ORDERS_TEST_PASSED")
	quit()
