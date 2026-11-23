extends SceneTree
# Command card hotkeys, camera key moves, additive selection, same-type selection (double-click or Ctrl-click),
# Tab through the primary type, and control groups.
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
func press(keycode: int, ctrl := false, shift := false) -> void:
	for pressed in [true,false]:
		var event := InputEventKey.new()
		event.physical_keycode = keycode
		event.keycode = keycode
		event.ctrl_pressed = ctrl
		event.shift_pressed = shift
		if keycode >= KEY_A and keycode <= KEY_Z: event.unicode = keycode+32
		event.pressed = pressed
		root.push_input(event)
	hud._process(0)
func click(unit: Node3D, shift := false, double := false, ctrl := false) -> void:
	var point: Vector2 = game.get_viewport().get_camera_3d().unproject_position(unit.global_position+Vector3.UP*1.5)
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		event.shift_pressed = shift
		event.double_click = double and pressed
		event.ctrl_pressed = ctrl
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
	for panel in [hud.card]:
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
	if not check(key_of("camera_overview") == KEY_O and key_of("camera_focus_hq") == KEY_SPACE and key_of("camera_focus_selection") == KEY_HOME,"Camera keys should be O, Space and Home"): return
	# Q and E belong to command cards now; the camera no longer turns from the keyboard.
	if not check(not InputMap.has_action("camera_rotate_left") and not InputMap.has_action("camera_rotate_right"),"Camera rotate keys should be gone"): return
	var unbound := []
	for panel in [hud.card]:
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
	if not check(depot_keys == ["D","V","T","C"] and depot_keys.size() == depot_keys.filter(func(k): return depot_keys.count(k) == 1).size(),"Depot card keys (Depot truck, Cargo, Train, Make crates; no Build) missing or duplicated %s" % [depot_keys]): return
	# The other cards and pages, by every tile each can show at once.
	var sets := {
		"Production building": [hud.card,["PrintInfantry","ProduceScout","ProduceGrenadier","ProduceTank","ProduceMotorcycle","ProduceDrone","ProduceUbermech"]],
		"Generator": [hud.card,["ToggleGenerator","BurnWood","BurnCoal","BurnEither","FocusAssigned"]],
		"Load page": [hud.pick,["LoadTiles/Iron","LoadTiles/Energy","LoadTiles/Wood","LoadTiles/Coal","LoadTiles/Clear","Cancel"]],
		"Build page": [hud.build_menu,["Actions/Depot","Actions/Generator","Actions/Barracks","Actions/TankFactory","Actions/Mine","Actions/CoalMine","Actions/Rail","Actions/Pin","Actions/Back"]]}
	for title in sets:
		var keys := []
		for path in sets[title][1]: keys.append(hud.hotkey_text(sets[title][0].get_node(path)))
		var unique := {}
		for key in keys: unique[key] = true
		if not check(not keys.has("") and unique.size() == keys.size(),"%s has a missing or repeated key: %s" % [title,keys]): return
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
	if not check(not tank.auto_refuel and hud.label_of(hud.card.get_node("ToggleRefuel")).begins_with("Auto-refuel: off"),"T did not toggle the Tank's Auto-refuel"): return
	press(KEY_T)
	# Cargo tiles share the grid: T toggles Auto-refuel, E arms Load, D deploys supplies.
	select_only(truck)
	press(KEY_T)
	if not check(not truck.auto_refuel,"T did not toggle the truck's Auto-refuel"): return
	press(KEY_T)
	press(KEY_E)
	if not check(game.pending_unit_command == "load","E did not arm Load"): return
	# The map prompt replaces the card while Load waits; Esc on its Cancel tile brings the card back.
	hud._process(0)
	press(KEY_ESCAPE)
	hud._process(0)
	if not check(game.pending_unit_command.is_empty() and hud.card.visible,"Esc did not cancel the Load prompt"): return
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
	# Ctrl-click picks the type on screen as a double-click does; Ctrl+Shift-click adds it to the selection.
	var third = spawn(worker.scene_file_path,Vector3(-6,0,18))
	await process_frame
	third.set_process(false)
	click(tank)
	click(worker,false,false,true)
	if not check(worker.is_selected and third.is_selected and not tank.is_selected and not truck.is_selected,"Ctrl-click did not select visible units of the same type"): return
	click(tank)
	click(worker,true,false,true)
	if not check(worker.is_selected and third.is_selected and tank.is_selected and not truck.is_selected,"Ctrl+Shift-click did not add the type"): return
	if not check(hud.selected_object().scene_file_path == worker.scene_file_path,"The added type should be the primary"): return
	# Tab steps the primary (card, stats, outlined portrait) through the types; Shift+Tab steps back.
	click(truck,true)
	hud._process(0)
	var order: Array = manager.types_of(hud.selected_units())
	if not check(order.size() == 3,"Three types should be selected: %s" % [order]): return
	var start: String = hud.selected_object().scene_file_path
	var visited := [start]
	for i in range(3):
		press(KEY_TAB)
		visited.append(hud.selected_object().scene_file_path)
	if not check(visited[1] == order[(order.find(start)+1)%3] and visited[2] == order[(order.find(start)+2)%3] and visited[3] == start,"Tab should visit every type in portrait order and come round: %s" % [visited]): return
	press(KEY_TAB)
	var outlined: Array = []
	for i in hud.portrait_units.size():
		if hud.portraits.get_child(i).get_node("Primary").visible: outlined.append(hud.portrait_units[i])
	if not check(outlined.size() == 1 and outlined[0] == hud.selected_object() and hud.state_label.text.contains("Tab: next type"),"One outlined portrait, the primary: %s" % [outlined]): return
	if not check(hud.portrait_units[0].scene_file_path == order[0],"The portraits keep their order while Tab moves the outline"): return
	var on: String = hud.selected_object().scene_file_path
	press(KEY_TAB,false,true)
	if not check(hud.selected_object().scene_file_path == order[(order.find(on)+2)%3],"Shift+Tab should step back"): return
	# The card follows the primary.
	var cards := {}
	for i in range(3):
		cards[hud.selected_object().scene_file_path] = hud.desired_buttons.duplicate()
		if not check(hud.shown == hud.selected_object(),"The HUD should show the primary"): return
		press(KEY_TAB)
	if not check(cards[truck.scene_file_path] != cards[worker.scene_file_path] and cards[tank.scene_file_path] != cards[worker.scene_file_path],"Each primary type should bring its own card: %s" % [cards]): return
	# A new selection starts from its first unit; one type selected leaves Tab alone.
	click(tank)
	press(KEY_TAB)
	if not check(hud.selected_object() == tank and manager.primary_type == "","Tab with one type should do nothing"): return
	third.queue_free()
	# Space focuses the HQ even while a HUD button has focus, and does not press that button.
	var hq: Node3D = get_first_node_in_group("headquarters")
	rig.focus_position(hq.global_position+Vector3(80,0,80))
	var stop_tile: Button = hud.card.get_node("Stop")
	var stopped := [0]
	stop_tile.pressed.connect(func(): stopped[0] += 1)
	stop_tile.grab_focus()
	press(KEY_SPACE)
	if not check(Vector2(rig._focus_target.x-hq.global_position.x,rig._focus_target.z-hq.global_position.z).length() < 0.5,"Space should focus the HQ"): return
	if not check(stopped[0] == 0,"Space should not press the focused HUD button"): return
	# A focused dropdown keeps Space for itself.
	var dropdown := OptionButton.new()
	hud.get_node("Bottom/Body/Row/Context").add_child(dropdown)
	dropdown.grab_focus()
	rig.focus_position(hq.global_position+Vector3(80,0,80))
	press(KEY_SPACE)
	if not check(Vector2(rig._focus_target.x-hq.global_position.x,rig._focus_target.z-hq.global_position.z).length() > 50,"Space should go to a focused dropdown, not the camera"): return
	dropdown.release_focus()
	dropdown.free()
	print("HUD_HOTKEYS_TEST_PASSED")
	quit(0)
