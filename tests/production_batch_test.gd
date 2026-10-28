extends SceneTree
var game: Node3D
var hud: CanvasLayer
var network: Node
func _initialize() -> void:
	call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message)
	quit(1)
	return false
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
func click(control: Control) -> void:
	await click_at(control.get_global_rect().get_center())
func placement(size: Vector2i, payer: Node3D) -> Vector3:
	var rig = game.get_node("CameraRig")
	for x in range(-24,25,4):
		for z in range(-24,25,4):
			var point: Vector3 = payer.global_position+Vector3(x,0,z)
			var screen: Vector2 = rig.camera.unproject_position(point)
			if network.can_place_size(point,payer,size) and screen.y > 0 and screen.y < hud.get_node("Bottom").global_position.y-30: return point
	return Vector3.ZERO
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	hud = game.get_node("Interface")
	network = game.get_node("DepotNetwork")
	for frame in range(4): await process_frame
	game.set_process(false)
	for unit in get_nodes_in_group("units"): unit.set_process(false)
	game.depot.set_process(false)
	var first = game.depot
	first.storage_capacity = 10000
	first.energy = 2000
	first.iron = 2000
	var rig = game.get_node("CameraRig")
	rig.set_process(false)
	rig.focus_hq()
	for frame in range(180): rig.advance_camera(1.0/60)
	if not check(first.rules.depot_energy_cost == 20 and first.rules.depot_iron_cost == 20,"Original Depot cost mismatch"): return
	await click(hud.card.get_node("Build"))
	if not check(hud.build_menu.visible,"Depot Build command failed through GUI"): return
	var point := placement(Vector2i(6,6),first)
	if not check(point != Vector3.ZERO,"No Barracks placement"): return
	await click(hud.build_menu.get_node("Actions/Barracks"))
	if not check(game.placing_structure == &"barracks","Barracks GUI placement command failed"): return
	await click_at(rig.camera.unproject_position(point))
	if not check(get_nodes_in_group("production_buildings").size() == 1,"Barracks world placement failed"): return
	var barracks = get_nodes_in_group("production_buildings")[0]
	barracks.set_process(false)
	if not check(first.energy == 1900 and first.iron == 1955 and barracks.assigned_depot == first,"Barracks construction must pay exactly 100/45 locally"): return
	point = placement(Vector2i(8,8),first)
	await click(hud.build_menu.get_node("Actions/TankFactory"))
	if not check(game.placing_structure == &"tank_factory","Tank Factory GUI placement command failed"): return
	await click_at(rig.camera.unproject_position(point))
	if not check(get_nodes_in_group("production_buildings").size() == 2,"Factory world placement failed"): return
	var factory = get_nodes_in_group("production_buildings")[1]
	factory.set_process(false)
	if not check(first.energy == 1700 and first.iron == 1890,"Factory construction must pay exactly 200/65 locally"): return
	hud.close_build()
	network.select_depot(null)
	game.selected_building = barracks
	for frame in range(3): await process_frame
	if not check(hud.shown == barracks and hud.card.get_node("ProduceScout").visible,"Barracks contextual selection failed"): return
	await click(hud.card.get_node("ProduceScout"))
	await click(hud.card.get_node("ProduceGrenadier"))
	await click(hud.card.get_node("PrintInfantry"))
	if not check(barracks.queue == 3 and first.energy == 1480 and first.iron == 1850,"Barracks roster GUI costs mismatch"): return
	if not check(not barracks.request_unit(&"tank") and barracks.queue == 3,"Barracks accepted invalid/over-cap production"): return
	for i in range(3): barracks._process(3.1)
	var ids: Array[StringName] = []
	for unit in get_nodes_in_group("units"):
		unit.set_process(false)
		if unit.unit_stats != null: ids.append(unit.unit_stats.unit_id)
	if not check(ids.has(&"scout") and ids.has(&"grenadier") and barracks.queue == 0,"Barracks did not spawn assigned roster"): return
	game.selected_building = factory
	for frame in range(3): await process_frame
	await click(hud.card.get_node("ProduceTank"))
	await click(hud.card.get_node("ProduceMotorcycle"))
	await click(hud.card.get_node("ProduceDrone"))
	if not check(factory.queue == 3,"Factory GUI roster queue failed"): return
	for i in range(3): factory._process(3.1)
	await click(hud.card.get_node("ProduceUbermech"))
	factory._process(3.1)
	ids.clear()
	for unit in get_nodes_in_group("units"):
		unit.set_process(false)
		if unit.unit_stats != null:
			ids.append(unit.unit_stats.unit_id)
			if unit.unit_stats.unit_id not in [&"infantry"]:
				if not check(not unit.can_construct and not unit.can_gather and not unit.can_repair and not unit.can_capture_depots and unit._attack_enabled == (unit.unit_stats.unit_id != &"drone"),"New unit inherited engineering abilities or has incorrect combat availability"): return
	if not check(ids.has(&"tank") and ids.has(&"motorcycle") and ids.has(&"drone") and ids.has(&"ubermech"),"Factory did not produce full roster"): return
	# Blocked production retains its payment and job until a valid exit exists.
	if not check(factory.request_unit(&"tank"),"Factory could not queue blocked-exit fixture"): return
	var blocked: Array[Vector2i] = []
	var center = game.ground.get_tile_at_position(factory.global_position)
	for radius in range(6,16):
		for offset in [Vector2i(0,radius),Vector2i(radius,0),Vector2i(-radius,0),Vector2i(0,-radius)]:
			var cell: Vector2i = center+offset
			if game.ground.is_tile_valid(cell): blocked.append(cell); game.ground.set_tile_feature(cell,"occupied_by","production_test")
	factory._process(4)
	if not check(factory.queue == 1,"Blocked exit lost job"): return
	for cell in blocked: game.ground.set_tile_feature(cell,"occupied_by",null)
	factory._process(0.1)
	if not check(factory.queue == 0,"Exit did not resume"): return
	# Capture cancels paid jobs without switching to any other Depot.
	barracks.request_unit(&"scout")
	first.team = "enemy"
	first.ownership_changed.emit()
	if not check(barracks.queue == 0 and not barracks.request_unit(&"scout"),"Source capture did not stop production"): return
	first.team = "player"
	first.ownership_changed.emit()
	# New Depots grant exactly one free infantry and do not increment paid print objectives.
	var start = game.ground.find_buildable_footprint(Vector2i(220,170),Vector2i(8,8))
	var paid_count: int = game.units_printed
	var new_depot = network.establish(game.ground.tile_to_world(start+Vector2i(4,4)),0,0)
	new_depot.set_process(false)
	var count: int = get_nodes_in_group("units").size()
	if not check(new_depot.try_construction_infantry() and new_depot.construction_infantry_spawned,"Construction infantry was not granted"): return
	if not check(not new_depot.try_construction_infantry() and get_nodes_in_group("units").size() == count+1 and game.units_printed == paid_count,"Construction infantry granted twice or counted as paid production"): return
	if not check(new_depot.energy == 0 and new_depot.iron == 500,"Construction infantry charged inventory or testing grant lost"): return
	# Block the grant exits before deferred spawning, preserving a grant without a queue slot.
	start = game.ground.find_buildable_footprint(Vector2i(280,170),Vector2i(8,8))
	var waiting = network.establish(game.ground.tile_to_world(start+Vector2i(4,4)),0,0)
	waiting.set_process(false)
	blocked.clear()
	center = game.ground.get_tile_at_position(waiting.global_position)
	for radius in range(6,16):
		for offset in [Vector2i(0,radius),Vector2i(radius,0),Vector2i(-radius,0),Vector2i(0,-radius)]:
			var cell: Vector2i = center+offset
			if game.ground.is_tile_valid(cell): blocked.append(cell); game.ground.set_tile_feature(cell,"occupied_by","grant_test")
	if not check(not waiting.try_construction_infantry() and waiting.construction_infantry_pending and waiting.queue == 0,"Blocked grant was lost or used paid queue capacity"): return
	for cell in blocked: game.ground.set_tile_feature(cell,"occupied_by",null)
	if not check(waiting.try_construction_infantry() and not waiting.try_construction_infantry(),"Unblocked grant failed or duplicated"): return
	# A capture before the initial grant cancels it; recapture does not regenerate it.
	start = game.ground.find_buildable_footprint(Vector2i(320,170),Vector2i(8,8))
	var captured = network.establish(game.ground.tile_to_world(start+Vector2i(4,4)),0,0)
	captured.set_process(false)
	var enemy = game.get_node("Entities/Units/Hostile")
	enemy.global_position = captured.global_position+Vector3(9,0,0)
	captured.update_capture(8)
	if not check(captured.team == "enemy" and not captured.construction_infantry_pending,"Capture did not cancel unclaimed construction grant"): return
	captured.team = "player"
	captured.ownership_changed.emit()
	if not check(not captured.try_construction_infantry(),"Recapture regenerated construction grant"): return
	# Truck establishment follows the same one-time grant rule.
	start = game.ground.find_buildable_footprint(Vector2i(360,170),Vector2i(8,8))
	var truck = network.truck_scene.instantiate()
	truck.position = game.ground.tile_to_world(start+Vector2i(4,4))
	game.get_node("Entities/Units").add_child(truck)
	truck.set_process(false)
	for unit in get_nodes_in_group("units"): unit.set_selected(unit == truck)
	if not check(network.deploy_selected_truck() and network.selected.grant_construction_infantry,"Truck Depot did not receive construction grant"): return
	var deployed = network.selected
	deployed.set_process(false)
	if not check(deployed.try_construction_infantry() and not deployed.try_construction_infantry(),"Truck construction infantry not exactly once"): return
	# A rich independent neighbour cannot fund a building bound to an empty source.
	first.energy = 0
	first.iron = 0
	deployed.energy = 1000
	var rich_iron: int = deployed.iron
	if not check(not barracks.request_unit(&"scout") and deployed.energy == 1000 and deployed.iron == rich_iron,"Production silently borrowed from a neighbouring Depot"): return
	# Paid production is a recovery path even when the Depot cannot afford another infantry.
	first.energy = 35
	first.iron = 5
	if not check(barracks.request_unit(&"scout"),"Recovery fixture could not queue scout"): return
	for unit in get_nodes_in_group("units"):
		if unit.team == "player": unit.team = "test_inactive"
	for depot in get_nodes_in_group("depots"):
		depot.construction_infantry_pending = false
		depot.energy = 0
		depot.iron = 0
	game.outcome = ""
	game._process(0)
	if not check(not game.outcome.begins_with("DEFEAT"),"Queued production was ignored by defeat check"): return
	print("PRODUCTION_BATCH_CHECKS_PASSED")
	quit()
