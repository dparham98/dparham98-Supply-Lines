extends SceneTree
var game: Node3D
var hud: CanvasLayer
func _initialize() -> void:
	call_deferred("run")
func select_unit(unit: Node3D) -> void:
	game.get_node("DepotNetwork").select_depot(null)
	for candidate in get_nodes_in_group("units"): candidate.set_selected(candidate == unit)
	hud._process(0)
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/supply_routes.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	game.set_process(false)
	hud = game.get_node("Interface")
	hud.set_process(false)
	for unit in get_nodes_in_group("units"): unit.set_process(false)
	for depot in get_nodes_in_group("depots"): depot.set_process(false)
	var rig = game.get_node("CameraRig")
	rig.set_process(false)
	rig.focus_hq()
	for frame in range(180): rig.advance_camera(1.0/60)
	var network = game.get_node("DepotNetwork")
	hud._process(0)
	assert(not hud.has_node("Panel") and not hud.has_node("SupplyPanel"))
	assert(hud.info.get_node("HealthText").text.contains("1000 / 1000"))
	assert(hud.card.get_node("PrintCargo").visible and hud.card.get_node("Build").visible)
	var stock: int = game.depot.iron
	hud.card.get_node("PrintCargo").pressed.emit()
	assert(game.depot.iron == stock-20 and game.depot.queue == 1)
	var worker = game.get_node("Entities/Units/Infantry")
	var manager = root.get_node("SelectionManager")
	var screen: Vector2 = rig.camera.unproject_position(worker.global_position+Vector3.UP*0.5)
	manager.start_selection(screen)
	manager.end_selection(screen)
	hud._process(0)
	assert(hud.shown == worker and hud.info.get_node("HealthText").text.contains("55 / 55"))
	assert(hud.card.get_node("Build").visible and not hud.card.get_node("PrintCargo").visible)
	assert(hud.info.get_node("Details").text.contains("Nearest Depot"))
	hud.card.get_node("Build").pressed.emit()
	hud._process(0)
	assert(hud.build_menu.visible and network.construction_builder == worker)
	assert(hud.build_menu.get_node("Bank").text.contains(str(stock-20)))
	var payer = network.selected
	var point := Vector3.ZERO
	for x in range(-25,26,5):
		for z in range(-25,26,5):
			var candidate: Vector3 = payer.global_position+Vector3(x,0,z)
			if network.can_place_size(candidate,payer,network.supply_rules.generator_footprint): point = candidate
	assert(point != Vector3.ZERO)
	var energy: int = payer.energy
	hud.build_menu.get_node("Actions/Generator").pressed.emit()
	assert(game.placing_generator and worker.is_selected)
	# Deliver a synthetic placement event to the actual game input handler.
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = rig.camera.unproject_position(point)
	manager.start_selection(event.position)
	assert(not manager.selecting)
	game._unhandled_input(event)
	assert(not game.placing_generator and payer.energy == energy-100 and payer.iron == stock-40)
	assert(get_nodes_in_group("energy_generators").size() == 1)
	var generator = get_nodes_in_group("energy_generators")[0]
	generator.set_process(false)
	assert(generator.assigned_depot == payer)
	# Leaving Depot territory cannot spend even when its inventory remains rich.
	var old: Vector3 = worker.global_position
	worker.global_position = Vector3(-200,0,-200)
	hud.refresh_build_menu()
	assert(hud.build_menu.get_node("Actions/Generator").disabled)
	assert(not network.construct_generator(point+Vector3(10,0,0)))
	worker.global_position = Vector3(187,0,157)
	hud.refresh_build_menu()
	var outpost = game.get_node("Entities/Buildings/Outpost")
	assert(hud.build_depots.has(outpost) and hud.build_depots.has(payer))
	var outpost_index: int = hud.build_depots.find(outpost)
	hud.build_menu.get_node("Payer").item_selected.emit(outpost_index)
	hud.refresh_build_menu()
	assert(network.selected == outpost and outpost.energy == 0)
	energy = payer.energy
	assert(not network.construct_generator(outpost.global_position+Vector3(12,0,12)))
	assert(payer.energy == energy)
	# Losing the chosen payer must not silently switch to a rich overlapping neighbour.
	outpost.team = "enemy"
	outpost.ownership_changed.emit()
	hud.refresh_build_menu()
	assert(network.selected == null and hud.build_menu.get_node("Actions/Generator").disabled)
	outpost.team = "player"
	outpost.ownership_changed.emit()
	worker.global_position = old
	hud.close_build()
	# Buildings can be selected through the same screen-space selection manager.
	for unit in get_nodes_in_group("units"): unit.set_selected(false)
	screen = rig.camera.unproject_position(generator.global_position+Vector3.UP*1.5)
	manager.start_selection(screen)
	manager.end_selection(screen)
	hud._process(0)
	assert(hud.shown == generator and hud.info.get_node("HealthText").text.contains("300 / 300"))
	assert(hud.card.get_node("FocusAssigned").visible and not hud.card.get_node("Build").visible)
	generator.take_damage(25)
	hud._process(0)
	assert(hud.info.get_node("HealthText").text.contains("275 / 300"))
	var vehicle = game.get_node("Entities/Units/CargoVehicle")
	select_unit(vehicle)
	assert(hud.supply.visible and not hud.build_menu.visible and not vehicle.can_construct)
	hud.supply.get_node("Source").select(hud.route_depots.find(game.depot))
	hud.supply.get_node("Destination").select(hud.route_depots.find(game.get_node("Entities/Buildings/Outpost")))
	hud.supply.get_node("StartRoute").pressed.emit()
	assert(vehicle.route_active)
	var map = hud.get_node("Bottom/Body/Row/MapColumn/Map")
	assert(map.world_to_map(Vector3(-250,0,-250)).is_equal_approx(Vector2.ZERO))
	assert(map.world_to_map(Vector3(250,0,250)).is_equal_approx(map.size))
	assert(map.map_to_world(map.size/2).is_equal_approx(Vector3.ZERO))
	var map_click := InputEventMouseButton.new()
	map_click.button_index = MOUSE_BUTTON_LEFT
	map_click.pressed = true
	map_click.position = map.size/2
	map._gui_input(map_click)
	assert(rig._focus_target.is_equal_approx(Vector3.ZERO) and vehicle.is_selected)
	select_unit(worker)
	hud.card.get_node("Move").pressed.emit()
	assert(game.pending_unit_command == "move")
	game.issue_card_order(rig.camera.unproject_position(worker.global_position+Vector3(3,0,0)))
	assert(worker.order == "move" and game.pending_unit_command.is_empty())
	hud.card.get_node("Stop").pressed.emit()
	assert(worker.order == "idle")
	hud.card.get_node("Attack").pressed.emit()
	assert(game.pending_unit_command == "attack")
	game.issue_card_order(rig.camera.unproject_position(game.get_node("Entities/Units/Hostile").global_position+Vector3.UP*1.5))
	assert(worker.order == "attack")
	hud.card.get_node("Gather").pressed.emit()
	assert(game.pending_unit_command == "gather")
	game.issue_card_order(rig.camera.unproject_position(game.get_node("Entities/Resources/OreDeposit").global_position+Vector3.UP*1.5))
	assert(worker.order == "gather")
	for unit in get_nodes_in_group("units"): unit.set_selected(false)
	game.selected_building = generator
	generator.take_damage(1000)
	hud._process(0)
	assert(hud.shown == null)
	print("BOTTOM_HUD_CHECKS_PASSED")
	quit()
