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
	# Depots print vehicles but have no build menu; building goes through the header Build page.
	assert(hud.card.get_node("PrintCargo").visible and hud.card.get_node("PrintTrain").visible and not hud.card.has_node("Build"))
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
	assert(not hud.card.get_node("PrintCargo").visible and hud.info.get_node("Details").text.contains("Nearest Depot"))
	# The selection's hint is a tooltip on the Info and Context columns, not a HUD line.
	assert(not hud.has_node("Bottom/Body/Row/Context/Hint") and "nearest stockpile" in hud.info.tooltip_text and hud.context.tooltip_text == hud.info.tooltip_text)
	hud.get_node("Bottom/Body/Header/GlobalBuild").pressed.emit()
	hud._process(0)
	assert(hud.build_menu.visible and hud.get_node("Bottom/Body/Header/GlobalBuild").disabled and hud.build_menu.get_node("Bank").text.contains("AUTO"))
	var payer = game.depot
	var point := Vector3.ZERO
	for x in range(-25,26,5):
		for z in range(-25,26,5):
			var candidate: Vector3 = payer.global_position+Vector3(x,0,z)
			if network.can_place_size(candidate,payer,network.supply_rules.generator_footprint): point = candidate
	assert(point != Vector3.ZERO)
	var energy: int = payer.energy
	hud.build_menu.get_node("Actions/Generator").pressed.emit()
	assert(game.global_plan_kind == &"generator" and worker.is_selected)
	# Deliver a synthetic placement event to the actual game input handler.
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = rig.camera.unproject_position(point)
	manager.start_selection(event.position)
	assert(not manager.selecting)
	game._unhandled_input(event)
	var plan = get_nodes_in_group("construction_plans")[0]
	assert(plan.try_complete() != null and payer.energy == energy-100 and payer.iron == stock-40)
	assert(get_nodes_in_group("energy_generators").size() == 1)
	var generator = get_nodes_in_group("energy_generators")[0]
	generator.set_process(false)
	assert(generator.assigned_depot == payer)
	# Pin picks a payer on the map: an empty pinned Depot makes new plans wait instead of using a rich neighbour.
	var outpost = game.get_node("Entities/Buildings/Outpost")
	hud.build_menu.get_node("Actions/Pin").pressed.emit()
	hud._process(0)
	assert(game.pending_unit_command == "pin" and hud.pick.visible and not hud.build_menu.visible and hud.pick_stops().has(outpost))
	hud.pick_stop(outpost)
	hud._process(0)
	assert(hud.global_pinned and hud.global_payer == outpost and game.pending_unit_command.is_empty() and hud.build_menu.visible and "OUTPOST" in hud.build_menu.get_node("Bank").text.to_upper())
	energy = payer.energy
	var pinned = network.queue_plan(outpost.global_position+Vector3(12,0,12),&"generator",hud.global_payer,hud.global_pinned)
	assert(pinned != null and pinned.try_complete() == null and payer.energy == energy)
	pinned.cancel()
	hud.build_menu.get_node("Actions/Pin").pressed.emit()
	assert(not hud.global_pinned and game.pending_unit_command.is_empty())
	hud.build_menu.get_node("Actions/Back").pressed.emit()
	hud._process(0)
	assert(not hud.build_menu.visible and not hud.get_node("Bottom/Body/Header/GlobalBuild").disabled)
	# Buildings can be selected through the same screen-space selection manager.
	for unit in get_nodes_in_group("units"): unit.set_selected(false)
	screen = rig.camera.unproject_position(generator.global_position+Vector3.UP*1.5)
	manager.start_selection(screen)
	manager.end_selection(screen)
	hud._process(0)
	assert(hud.shown == generator and hud.info.get_node("HealthText").text.contains("300 / 300"))
	assert(hud.card.get_node("FocusAssigned").visible)
	generator.take_damage(25)
	hud._process(0)
	assert(hud.info.get_node("HealthText").text.contains("275 / 300"))
	var vehicle = game.get_node("Entities/Units/CargoVehicle")
	select_unit(vehicle)
	# Cargo vehicles use crate tiles on the command grid (the route panel was replaced).
	assert(hud.card.get_node("Load").visible and hud.card.get_node("Unload").visible and not hud.build_menu.visible and not vehicle.can_construct)
	# Load replaces the card with a map prompt; a pulsing minimap Depot picks the stop.
	hud.card.get_node("Load").pressed.emit()
	hud._process(0)
	assert(game.pending_unit_command == "load" and hud.pick.visible and not hud.card.visible and not hud.has_node("Bottom/Body/Row/Commands/OptionRow"))
	var map = hud.get_node("Bottom/Body/Row/MapColumn/Map")
	var stop_click := InputEventMouseButton.new()
	stop_click.button_index = MOUSE_BUTTON_LEFT
	stop_click.pressed = true
	stop_click.position = map.world_to_map(game.depot.global_position)
	assert(map.stop_at(stop_click.position) == game.depot)
	map._gui_input(stop_click)
	assert(vehicle.order == "load" and vehicle.job_target == game.depot and game.pending_unit_command.is_empty())
	vehicle.cancel_supply_route()
	# Right-click cancels the prompt; so does its Cancel tile.
	hud.card.get_node("Unload").pressed.emit()
	var cancel_click := InputEventMouseButton.new()
	cancel_click.button_index = MOUSE_BUTTON_RIGHT
	cancel_click.pressed = true
	cancel_click.position = Vector2(400,300)
	game._unhandled_input(cancel_click)
	hud._process(0)
	assert(game.pending_unit_command.is_empty() and not hud.pick.visible and hud.card.visible and vehicle.order == "idle")
	hud.card.get_node("Unload").pressed.emit()
	hud.pick.get_node("Cancel").pressed.emit()
	assert(game.pending_unit_command.is_empty())
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
