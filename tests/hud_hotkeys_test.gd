extends SceneTree
# Command card hotkeys, camera key moves, additive selection, same-type selection and control groups.
var game: Node3D
var hud: CanvasLayer
var manager: Node
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func key_of(action: String) -> int:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey: return event.physical_keycode
	return 0
func press(keycode: int, ctrl := false) -> void:
	for pressed in [true,false]:
		var event := InputEventKey.new()
		event.physical_keycode = keycode
		event.keycode = keycode
		event.ctrl_pressed = ctrl
		if keycode >= KEY_A and keycode <= KEY_Z: event.unicode = keycode+32
		event.pressed = pressed
		root.push_input(event)
	hud._process(0)
func click(unit: Node3D, shift := false, double := false) -> void:
	var point: Vector2 = game.get_viewport().get_camera_3d().unproject_position(unit.global_position+Vector3.UP*1.5)
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		event.shift_pressed = shift
		event.double_click = double and pressed
		manager._unhandled_input(event)
	hud._process(0)
func spawn(path: String, offset: Vector3) -> Node3D:
	var unit = load(path).instantiate()
	unit.position = game.depot.global_position+offset
	game.get_node("Entities/Units").add_child(unit)
	unit.set_process(false)
	return unit
func select_only(unit: Node3D) -> void:
	for other in get_nodes_in_group("units"): other.set_selected(other == unit)
	game.selected_building = null
	hud._process(0)
func visible_keys() -> Array:
	var keys := []
	for panel in [hud.card,hud.supply]:
		if not panel.is_visible_in_tree(): continue
		for button in panel.get_children():
			if button is Button and button.visible and not hud.hotkey_text(button).is_empty(): keys.append(hud.hotkey_text(button))
	return keys
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game); await process_frame
	game.set_process(false)
	hud = game.get_node("Interface"); hud.set_process(false)
	manager = root.get_node("SelectionManager")
	for group in ["units","depots"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	var rig = game.get_node("CameraRig"); rig.set_process(false)
	# Input Map: command keys exist, and the camera keys moved off M and F.
	if not check(key_of("command_move") == KEY_M and key_of("command_stop") == KEY_S and key_of("command_refuel") == KEY_T and key_of("control_group_1") == KEY_1,"Command hotkeys missing from the Input Map"): return
	if not check(key_of("camera_overview") == KEY_O and key_of("camera_focus_hq") == KEY_BACKSPACE and key_of("camera_focus_selection") == KEY_HOME,"Camera keys not moved to O and Backspace"): return
	var unbound := []
	for panel in [hud.card,hud.supply]:
		for button in panel.get_children():
			if button is Button and button.shortcut != null and hud.hotkey_text(button).is_empty(): unbound.append(button.name)
	if not check(unbound.is_empty(),"Shortcuts without an Input Map key: %s" % [unbound]): return
	var worker = game.get_node("Entities/Units/Infantry")
	var second = spawn(worker.scene_file_path,Vector3(-10,0,16))
	var tank = spawn("res://scenes/gameplay/tank.tscn",Vector3(14,0,14))
	var truck = spawn("res://scenes/gameplay/cargo_vehicle.tscn",Vector3(-14,0,10))
	rig.focus_position(game.depot.global_position+Vector3(0,0,12),55)
	for frame in range(180): rig.advance_camera(1.0/60)
	# No card shows two buttons with the same key.
	for node in [worker,tank,truck]:
		select_only(node)
		var keys := visible_keys()
		var unique := {}
		for key in keys: unique[key] = true
		if not check(not keys.is_empty() and unique.size() == keys.size(),"%s card has duplicate keys %s" % [node.name,keys]): return
	select_only(null)
	game.selected_building = game.depot; hud._process(0)
	var depot_keys := visible_keys()
	if not check(depot_keys.size() >= 4 and depot_keys.size() == depot_keys.filter(func(k): return depot_keys.count(k) == 1).size(),"Depot card keys missing or duplicated %s" % [depot_keys]): return
	game.selected_building = null
	# Keys press visible buttons and show their letter.
	select_only(worker)
	if not check(hud.card.get_node("Stop/Key").text == "S" and hud.card.get_node("Move/Key").text == "M","Button key labels missing"): return
	press(KEY_M)
	if not check(game.pending_unit_command == "move","M did not arm Move"): return
	game.pending_unit_command = ""
	worker.command_move(worker.global_position+Vector3(6,0,0))
	press(KEY_S)
	if not check(worker.order == "idle","S did not stop the unit"): return
	# A key whose button is hidden does nothing: Infantry has no Auto-refuel.
	var before_tank: bool = tank.auto_refuel
	press(KEY_T)
	if not check(tank.auto_refuel == before_tank,"Hidden Auto-refuel button fired"): return
	select_only(tank)
	press(KEY_T)
	if not check(not tank.auto_refuel and hud.card.get_node("ToggleRefuel").text.begins_with("Auto-refuel: off"),"T did not toggle the Tank's Auto-refuel"): return
	press(KEY_T)
	# Cargo Auto-refuel lives on the Orders page; T does nothing on the route page.
	select_only(truck)
	press(KEY_T)
	if not check(truck.auto_refuel,"T fired on the route page, which has no Auto-refuel"): return
	hud.pages.get_node("Orders").pressed.emit(); hud._process(0)
	press(KEY_T)
	if not check(not truck.auto_refuel,"T did not toggle the truck on its Orders page"): return
	press(KEY_T)
	# The Supply panel buttons have keys too, but typing into a field does not fire them.
	hud.pages.get_node("Route").pressed.emit(); hud._process(0)
	var field: LineEdit = hud.supply.get_node("Amounts/Energy").get_line_edit()
	field.grab_focus()
	press(KEY_D)
	if not check(not truck.deployed and truck.supply_transition.is_empty(),"Typing in a field fired Deploy"): return
	field.release_focus()
	press(KEY_D)
	if not check(not truck.supply_transition.is_empty() or truck.deployed,"D did not deploy the truck"): return
	# Selection: Shift toggles and adds, double-click picks the same type, control groups recall.
	click(worker)
	if not check(worker.is_selected and not tank.is_selected,"Plain click did not select one unit"): return
	click(tank,true)
	if not check(worker.is_selected and tank.is_selected,"Shift-click did not add"): return
	click(worker,true)
	if not check(not worker.is_selected and tank.is_selected,"Shift-click did not toggle off"): return
	click(worker)
	click(worker,false,true)
	if not check(worker.is_selected and second.is_selected and not tank.is_selected and not truck.is_selected,"Double-click did not select visible units of the same type"): return
	press(KEY_1,true)
	click(tank)
	if not check(tank.is_selected and not worker.is_selected,"Selection did not change before recall"): return
	press(KEY_1)
	if not check(worker.is_selected and second.is_selected and not tank.is_selected,"Control group 1 did not recall"): return
	second.queue_free(); await process_frame
	press(KEY_1)
	if not check(worker.is_selected and manager.groups[1].size() == 1,"Control group kept a freed unit"): return
	press(KEY_2)
	if not check(worker.is_selected,"Empty control group cleared the selection"): return
	print("HUD_HOTKEYS_TEST_PASSED")
	quit(0)
