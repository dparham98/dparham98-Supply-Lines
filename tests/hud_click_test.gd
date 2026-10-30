extends SceneTree
var game: Node3D
var hud: CanvasLayer
func _initialize() -> void:
	call_deferred("run")
func click(control: Control) -> void:
	await click_at(control.get_global_rect().get_center())
func click_at(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion,true)
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event,true)
	# A human click spans multiple process frames. Do not emit button signals directly.
	for frame in range(5): await process_frame
	event = InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	root.push_input(event,true)
	for frame in range(3): await process_frame
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message)
	quit(1)
	return false
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/supply_routes.tscn").instantiate()
	root.add_child(game)
	hud = game.get_node("Interface")
	for frame in range(5): await process_frame
	for unit in get_nodes_in_group("units"): unit.set_process(false)
	for depot in get_nodes_in_group("depots"): depot.set_process(false)
	var rig = game.get_node("CameraRig")
	rig.set_process(false)
	rig.focus_hq()
	for frame in range(180): rig.advance_camera(1.0/60)
	var first = game.depot
	var initial_energy: int = first.energy
	var initial_iron: int = first.iron
	if not check(not hud.card.get_node("PrintInfantry").visible,"Depot must not offer repeatable Infantry"): return
	await click(hud.card.get_node("PrintCargo"))
	if not check(first.queue == 1 and first.energy == initial_energy-100 and first.iron == initial_iron-20,"Real GUI click failed: Depot infantry production"): return
	await click(hud.card.get_node("PrintTruck"))
	if not check(first.queue == 2 and first.pending[1] == "truck","Real GUI click failed: Depot Truck production"): return
	await click(hud.card.get_node("PrintCargo"))
	if not check(first.queue == 3 and first.pending[2] == "cargo","Real GUI click failed: cargo production"): return
	first.energy = 500
	first.iron = 500
	var network = game.get_node("DepotNetwork")
	network.select_depot(null)
	var worker = game.get_node("Entities/Units/Infantry")
	worker.set_selected(true)
	for frame in range(4): await process_frame
	if not check(not hud.card.has_node("Build"),"Infantry still has a build menu"): return
	await click(hud.get_node("Bottom/Body/Header/GlobalBuild"))
	if not check(hud.global_build_open and hud.build_menu.visible,"Real GUI click failed: Build page"): return
	await click(hud.build_menu.get_node("Actions/Generator"))
	if not check(game.global_plan_kind == &"generator","Real GUI click failed: Generator plan command"): return
	var point := Vector3.ZERO
	for x in range(-20,21,5):
		for z in range(-20,21,5):
			var candidate: Vector3 = first.global_position+Vector3(x,0,z)
			var screen: Vector2 = rig.camera.unproject_position(candidate)
			if network.can_place_size(candidate,first,network.supply_rules.generator_footprint) and screen.y < hud.get_node("Bottom").global_position.y-20: point = candidate
	if not check(point != Vector3.ZERO,"No generator placement point for GUI check"): return
	await click_at(rig.camera.unproject_position(point))
	for plan in get_nodes_in_group("construction_plans"): plan.try_complete()
	if not check(get_nodes_in_group("energy_generators").size() == 1 and first.energy >= 400 and first.iron == 480,"World click failed to build the generator plan"): return
	for generator in get_nodes_in_group("energy_generators"): generator.set_process(false)
	var expected_depot_energy: int = first.energy-20
	await click(hud.build_menu.get_node("Actions/Depot"))
	if not check(game.global_plan_kind == &"depot","Real GUI click failed: Depot plan command"): return
	point = Vector3.ZERO
	for x in range(-24,25,8):
		for z in range(-24,25,8):
			var candidate: Vector3 = first.global_position+Vector3(x,0,z)
			var screen: Vector2 = rig.camera.unproject_position(candidate)
			if network.can_place(candidate,first) and screen.y < hud.get_node("Bottom").global_position.y-20: point = candidate
	if not check(point != Vector3.ZERO,"No Depot placement point for GUI check"): return
	await click_at(rig.camera.unproject_position(point))
	for plan in get_nodes_in_group("construction_plans"): plan.try_complete()
	if not check(get_nodes_in_group("depots").size() == 4 and first.energy == expected_depot_energy and first.iron == 460,"World click failed to build the Depot plan"): return
	await click(hud.build_menu.get_node("Actions/Back"))
	if not check(not hud.global_build_open and hud.card.visible,"Real GUI click failed: Back from build menu"): return
	await click(hud.card.get_node("Move"))
	if not check(game.pending_unit_command == "move","Real GUI click failed: Move command"): return
	game.pending_unit_command = ""
	worker.set_selected(false)
	network.select_depot(null)
	var vehicle = game.get_node("Entities/Units/CargoVehicle")
	vehicle.set_selected(true)
	for frame in range(4): await process_frame
	# Cargo tiles replaced the route panel: arm Load, cycle Trips, then Stop.
	await click(hud.card.get_node("Load"))
	if not check(game.pending_unit_command == "load" and hud.pick.visible and not hud.card.visible,"Real GUI click failed: Load tile"): return
	await click(hud.pick.get_node("Cancel"))
	if not check(game.pending_unit_command.is_empty() and hud.card.visible,"Real GUI click failed: Cancel on the pick prompt"): return
	await click(hud.card.get_node("Trips"))
	if not check(vehicle.trips == "all","Real GUI click failed: Trips tile"): return
	vehicle.command_load(game.depot)
	await click(hud.card.get_node("Stop"))
	if not check(vehicle.order == "idle","Real GUI click failed: Stop cargo vehicle"): return
	print("HUD_GUI_CLICK_CHECKS_PASSED")
	quit()
