extends SceneTree
var game: Node3D
var worker: Node3D
var hud: CanvasLayer
var mine: Node3D
var vehicle: Node3D
func _initialize() -> void:
	call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message)
	quit(1)
	return false
func step(seconds: float) -> void:
	for i in range(ceili(seconds*60)):
		worker._process(1.0/60)
		mine._process(1.0/60)
		if is_instance_valid(vehicle): vehicle._process(1.0/60)
func focus(point: Vector3) -> void:
	var rig = game.get_node("CameraRig")
	rig.focus_position(point)
	for frame in range(180): rig.advance_camera(1.0/60)
func click_at(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion,true)
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event,true)
	for frame in range(5): await process_frame
	event = InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	root.push_input(event,true)
	for frame in range(3): await process_frame
func target(node: Node3D) -> Vector2:
	return game.get_viewport().get_camera_3d().unproject_position(node.global_position+Vector3.UP*1.5)
func click(control: Control) -> void:
	# Nested containers settle over several rendered frames after a selection change.
	var previous := Rect2()
	var stable := 0
	for frame in range(30):
		await process_frame
		var rect := control.get_global_rect()
		if rect == previous and root.get_visible_rect().has_point(rect.get_center()) and control.is_visible_in_tree(): stable += 1
		else: stable = 0
		previous = rect
		if stable >= 3: break
	if not check(stable >= 3,"HUD control did not reach stable visible layout"): return
	await click_at(control.get_global_rect().get_center())
func select_worker() -> void:
	game.get_node("DepotNetwork").select_depot(null)
	for unit in get_nodes_in_group("units"): unit.set_selected(unit == worker)
	hud._process(0)
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/engineering_exercise.tscn").instantiate()
	root.add_child(game)
	for frame in range(4): await process_frame
	game.set_process(false)
	worker = game.get_node("Entities/Units/Infantry")
	mine = game.get_node("Entities/Buildings/IronMine")
	hud = game.get_node("Interface")
	var first = game.depot
	var wood = game.get_node("Entities/Resources/WoodStand")
	var generator = game.get_node("Entities/Buildings/DamagedGenerator")
	for unit in get_nodes_in_group("units"): unit.set_process(false)
	for building in get_nodes_in_group("selectable_buildings"): building.set_process(false)
	game.get_node("CameraRig").set_process(false)
	if not check(first.iron == 500 and first.wood == 0 and generator.health == 120 and worker.can_repair,"Engineering fixture initialization mismatch"): return
	first.energy = 500
	first.iron = 500
	select_worker()
	focus(generator.global_position)
	await click(hud.card.get_node("Repair"))
	if not check(game.pending_unit_command == "repair","Repair button did not respond to GUI mouse gesture"): return
	await click_at(target(generator))
	if not check(worker.order == "repair" and worker.repair_payer == first,"Repair target/payer not set"): return
	for i in range(90*60):
		step(1.0/60)
		if generator.health == 300: break
	if not check(generator.health == 300 and first.energy == 464 and first.iron == 482,"Repair did not path, cap HP and spend exact local costs"): return
	step(2)
	if not check(first.energy == 464 and first.iron == 482,"Full-health repair charged resources"): return
	# Wood delivery is separate from iron, including during travel and source switching.
	var iron_before: int = first.iron
	focus(wood.global_position)
	await click(hud.card.get_node("Gather"))
	await click_at(target(wood))
	if not check(worker.order == "gather" and worker.source == wood,"Wood gather GUI target failed"): return
	for i in range(100*60):
		step(1.0/60)
		if first.wood >= 10: break
	if not check(first.wood >= 10 and first.iron == iron_before and game.wood_delivered == first.wood and wood.remaining < wood.amount,"Wood was not delivered separately"): return
	worker._stop_route()
	worker.order = "idle"
	# Existing wood load must be returned before switching to iron.
	worker.cargo = 5
	worker.cargo_kind = &"wood"
	worker.command_gather(mine)
	if not check(worker.order == "return" and worker.cargo_kind == &"wood","Switching source reclassified carried resources"): return
	worker.cargo = 0
	worker.order = "idle"
	# Shared mine extraction needs no capture; both teams use the same finite deposit.
	var reserve: int = mine.remaining
	if not check(mine.extract(5,"player") == 5 and mine.extract(5,"enemy") == 5 and mine.remaining == reserve-10,"Shared mine rejected either side or duplicated stock"): return
	focus(mine.global_position)
	await click(hud.card.get_node("Gather"))
	await click_at(target(mine))
	if not check(worker.order == "gather" and worker.source == mine,"Shared mine GUI gather failed"): return
	var delivered: int = game.ore_delivered
	for i in range(100*60):
		step(1.0/60)
		if game.ore_delivered > delivered: break
	if not check(game.ore_delivered > delivered and mine.remaining < reserve,"Shared mine did not produce carried/delivered iron"): return
	worker._stop_route(); worker.order = "idle"; worker.cargo = 0
	# Cargo can explicitly transfer wood with the same shared capacity and conservation rules.
	var network = game.get_node("DepotNetwork")
	var start = game.ground.find_buildable_footprint(Vector2i(450,430),Vector2i(8,8))
	var outpost = network.establish(game.ground.tile_to_world(start+Vector2i(4,4)),0,0)
	outpost.set_process(false)
	vehicle = network.cargo_scene.instantiate()
	vehicle.position = first.global_position+Vector3(0,0,8)
	game.get_node("Entities/Units").add_child(vehicle)
	vehicle.set_process(false)
	worker.order = "idle"
	var total_wood: int = first.wood
	if not check(not vehicle.start_supply_route(first,outpost,80,20,false,1),"Cargo accepted excess combined capacity including wood"): return
	if not check(vehicle.start_supply_route(first,outpost,0,0,false,10),"Wood-only cargo route rejected"): return
	for i in range(180*60):
		step(1.0/60)
		if not check(first.wood+outpost.wood+vehicle.carried_wood == total_wood,"Wood cargo conservation failed"): return
		if not vehicle.route_active: break
	if not check(outpost.wood == 10 and not vehicle.route_active,"Explicit wood delivery did not complete"): return
	# Empty assigned payer cannot silently borrow for repair from an independent rich Depot.
	generator.take_damage(7)
	first.energy = 0
	first.iron = 0
	outpost.energy = 1000
	worker.command_repair(generator)
	for i in range(100*60):
		step(1.0/60)
		if worker.global_position.distance_to(generator.global_position) <= worker.engineering_rules.repair_range: break
	step(3)
	if not check(generator.health == 293 and outpost.energy == 1000,"Repair borrowed from another Depot"): return
	first.energy = 2
	first.iron = 1
	step(2)
	if not check(generator.health == 300 and first.energy == 0 and first.iron == 0,"Partial final repair failed, overshot HP, or overcharged"): return
	# Captured payer pauses work; retaining cargo is independent of repair.
	generator.take_damage(10)
	worker.cargo = 3
	worker.cargo_kind = &"wood"
	worker.command_repair(generator)
	first.team = "enemy"
	first.ownership_changed.emit()
	step(2)
	if not check(generator.health == 290 and worker.cargo == 3,"Lost payer repaired anyway or repair lost carried cargo"): return
	first.team = "player"
	first.ownership_changed.emit()
	first.energy = 2
	first.iron = 1
	step(2)
	if not check(generator.health == 300 and worker.cargo == 3,"Recaptured repair payer could not resume"): return
	# Finite harvest and footprint release; exhausted mines retain their footprint.
	var wood_cells: Array = wood.cells.duplicate()
	wood.extract(wood.remaining+10,"player")
	if not check(wood.remaining == 0 and wood.extract(10,"player") == 0,"Wood resource paid out twice"): return
	for cell in wood_cells:
		if not check(game.ground.is_tile_valid(cell),"Depleted wood stand retained occupancy"): return
	mine.team = "player"
	mine.extract(mine.remaining+10,"player")
	if not check(mine.remaining == 0 and not game.ground.is_tile_valid(mine.cells[0]),"Mine depletion broke building occupancy"): return
	generator.take_damage(1000)
	worker._repair(2)
	if not check(worker.order == "idle" and generator.health == 0,"Repair resurrected a destroyed building"): return
	print("ENGINEERING_BATCH_CHECKS_PASSED")
	quit()
