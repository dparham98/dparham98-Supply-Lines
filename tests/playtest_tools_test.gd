extends SceneTree
# Development-only playtest panel: F10 gate, resources, fuel, spawning, pause and speed.
var game: Node3D
var panel: PanelContainer
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	Engine.time_scale = 1.0; paused = false
	push_error(message); quit(1); return false
func press_f10() -> void:
	for pressed in [true,false]:
		var event := InputEventKey.new()
		event.physical_keycode = KEY_F10; event.keycode = KEY_F10
		event.pressed = pressed
		root.push_input(event)
func load_game() -> void:
	if is_instance_valid(game): game.free()
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game); await process_frame
	game.set_process(false)
	for group in ["units","depots"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	panel = game.get_node("Interface/PlaytestPanel")
func run() -> void:
	root.size = Vector2i(1280,900)
	await load_game()
	var depot = game.depot
	# Gate: F10 opens the panel only when the scene enables it in a debug build.
	if not check(game.playtest_tools and OS.is_debug_build() and not panel.visible,"Playtest tools not enabled or panel visible at start"): return
	press_f10()
	if not check(panel.visible,"F10 did not open the panel"): return
	press_f10()
	if not check(not panel.visible,"F10 did not close the panel"): return
	game.playtest_tools = false
	press_f10()
	if not check(not panel.visible,"Panel opened with playtest_tools off"): return
	game.playtest_tools = true
	press_f10()
	# Resources go to the selected Depot, respecting storage space.
	game.selected_building = null
	for node in get_nodes_in_group("units"): node.set_selected(false)
	panel.report("")
	if not check(panel.add_resource(&"coal") == 0 and "Select" in panel.status.text,"Resource added with nothing selected"): return
	game.selected_building = depot
	var coal: int = depot.coal
	if not check(panel.add_resource(&"coal") == 100 and depot.coal == coal+100,"Depot coal not added"): return
	depot.stockpile.set_amount(&"wood",depot.stockpile.amount(&"wood")+depot.stockpile.space()-30)
	if not check(panel.add_resource(&"iron") == 30 and depot.stockpile.space() == 0 and panel.add_resource(&"iron") == 0 and "full" in panel.status.text,"Depot capacity not respected"): return
	game.selected_building = null
	# A selected Cargo vehicle gets cargo directly, which replaces the stop-a-route workaround.
	var truck = load("res://scenes/gameplay/cargo_vehicle.tscn").instantiate()
	truck.position = depot.global_position+Vector3(-14,0,10)
	game.get_node("Entities/Units").add_child(truck); truck.set_process(false)
	truck.set_selected(true)
	if not check(panel.resource_target() == truck and panel.add_resource(&"coal") == 100 and truck.carried_coal == 100 and panel.add_resource(&"coal") == 0,"Cargo vehicle coal not loaded within capacity"): return
	# Fuel fill and empty apply to selected fuel users only.
	var tank = load("res://scenes/gameplay/tank.tscn").instantiate()
	tank.position = depot.global_position+Vector3(14,0,14)
	game.get_node("Entities/Units").add_child(tank); tank.set_process(false)
	tank.set_selected(true)
	if not check(panel.set_fuel(false) == 2 and tank.fuel == 0 and truck.fuel == 0,"Empty fuel failed"): return
	tank.out_of_fuel = true
	if not check(panel.set_fuel(true) == 2 and is_equal_approx(tank.fuel,tank.fuel_rules.reserve_capacity) and not tank.out_of_fuel,"Fill fuel failed"): return
	truck.set_selected(false); tank.set_selected(false)
	# Spawning: the authored list, team choice, and an armed click that doesn't change selection.
	var names := []
	for i in panel.get_node("Body/Spawn/Unit").item_count: names.append(panel.get_node("Body/Spawn/Unit").get_item_text(i))
	if not check(names.size() == panel.spawn_scenes.size() and "Tank" in names and "Cargo Vehicle" in names,"Spawn list wrong: %s" % [names]): return
	panel.get_node("Body/Spawn/Unit").select(names.find("Tank"))
	panel.get_node("Body/Spawn/Team").select(1)
	var enemy = panel.spawn_at(depot.global_position+Vector3(30,0,0))
	enemy.set_process(false)
	if not check(enemy.team == "enemy" and enemy.is_in_group("enemies") and enemy.fuel > 0,"Enemy spawn wrong"): return
	panel.get_node("Body/Spawn/Team").select(0)
	var rig = game.get_node("CameraRig"); rig.set_process(false)
	rig.focus_position(depot.global_position,55)
	for frame in range(180): rig.advance_camera(1.0/60)
	var worker = game.get_node("Entities/Units/Infantry")
	worker.set_selected(true)
	var before := get_nodes_in_group("units").size()
	panel.get_node("Body/Spawn/Place").pressed.emit()
	var screen: Vector2 = game.get_viewport().get_camera_3d().unproject_position(depot.global_position+Vector3(10,0,-12))
	for pressed in [true,false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT; click.position = screen; click.pressed = pressed
		root.push_input(click)
	await process_frame
	if not check(get_nodes_in_group("units").size() == before+1 and not panel.spawn_armed and worker.is_selected,"Armed spawn click failed or changed selection"): return
	for node in get_nodes_in_group("units"): node.set_process(false)
	# Pause keeps the HUD, camera, selection and panel running.
	panel.get_node("Body/Speed/Pause").pressed.emit()
	if not check(paused and not tank.can_process() and game.get_node("Interface").can_process() and rig.can_process() and root.get_node("SelectionManager").can_process(),"Pause modes wrong"): return
	panel._process(0)
	if not check(panel.get_node("Body/Speed/Pause").text == "Resume","Pause button label not updated"): return
	panel.get_node("Body/Speed/Pause").pressed.emit()
	if not check(not paused,"Resume failed"): return
	panel.get_node("Body/Speed/X4").pressed.emit()
	if not check(is_equal_approx(Engine.time_scale,4),"Speed 4x not applied"): return
	# Restart never inherits a paused or fast tree.
	paused = true
	await load_game()
	if not check(not paused and is_equal_approx(Engine.time_scale,1),"Reloaded scene kept pause or speed"): return
	print("PLAYTEST_TOOLS_TEST_PASSED")
	quit(0)
