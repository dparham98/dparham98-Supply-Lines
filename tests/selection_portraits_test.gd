extends SceneTree
# Headless: Shift held through a box drag adds the boxed units, and a multiple selection shows one portrait per
# unit instead of "primary +N selected" (docs/SELECTION_PORTRAITS.md).
var game: Node3D
var hud: CanvasLayer
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func key(code: Key, echo := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	event.echo = echo
	return event
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	game.set_process(false)
	hud = game.get_node("Interface")
	hud.set_process(false)
	for unit in get_nodes_in_group("units"): unit.set_process(false)
	var rig = game.get_node("CameraRig")
	rig.set_process(false)
	var units: Array = get_nodes_in_group("units").filter(func(u): return u.team == "player")
	if not check(units.size() >= 2,"The map needs two player units"): return
	var first: Node3D = units[0]
	var second: Node3D = units[1]
	rig.focus_position(first.global_position,40)
	for frame in range(200): rig.advance_camera(1.0/60)
	# Put the second unit clear of the others, beside the first.
	second.global_position = first.global_position+Vector3(9,0,0)
	for unit in units:
		if unit != first and unit != second and unit.global_position.distance_to(second.global_position) < 6: unit.global_position += Vector3(0,0,30)
	var manager = root.get_node("SelectionManager")
	var camera: Camera3D = rig.camera
	# Click the first unit.
	var at: Vector2 = camera.unproject_position(first.global_position+Vector3.UP*0.5)
	manager.start_selection(at)
	manager.end_selection(at)
	if not check(first.is_selected and not second.is_selected,"A click should select the first unit only"): return
	# Shift-box the second: Shift pressed mid-drag, and its key repeats, must not cancel the box.
	var centre: Vector2 = camera.unproject_position(second.global_position+Vector3.UP*0.5)
	manager.start_selection(centre-Vector2(24,24))
	var motion := InputEventMouseMotion.new()
	motion.position = centre+Vector2(24,24)
	manager._input(motion)
	manager._input(key(KEY_SHIFT))
	manager._input(key(KEY_SHIFT,true))
	manager._input(key(KEY_SHIFT,true))
	if not check(manager.selecting,"Holding Shift through a drag should not cancel the box"): return
	manager.end_selection(centre+Vector2(24,24),null,true)
	if not check(first.is_selected and second.is_selected,"Shift-box should add the boxed unit and keep the first"): return
	# Another key still cancels a drag.
	manager.start_selection(centre-Vector2(24,24))
	manager._input(motion)
	manager._input(key(KEY_A))
	if not check(not manager.selecting,"A non-modifier key should still cancel the box"): return
	# Portraits: one per selected unit, the card's unit outlined, and no "+N selected" name.
	# A third unit, so one can be removed and two stay selected.
	var third: Node3D = load("res://scenes/gameplay/infantry.tscn").instantiate()
	third.position = first.global_position+Vector3(-6,0,0)
	game.get_node("Entities/Units").add_child(third)
	await process_frame
	third.set_process(false)
	third.set_selected(true)
	hud._process(0)
	var selected: Array = hud.selected_units()
	var portraits: GridContainer = hud.portraits
	var shown := portraits.get_children().filter(func(p): return p.visible)
	if not check(portraits.visible and shown.size() == selected.size(),"There should be one portrait per selected unit: %d for %d" % [shown.size(),selected.size()]): return
	if not check(hud.name_label.text == "%d units selected" % selected.size() and not "+" in hud.name_label.text,"The name should count the selection: "+hud.name_label.text): return
	if not check(not hud.info.get_node("Details").visible and not hud.info.get_node("Health").visible,"Portraits should replace the single unit's health and details"): return
	if not check(shown[0].get_node("Primary").visible and shown.slice(1).all(func(p): return not p.get_node("Primary").visible),"Only the card's unit should be outlined, first"): return
	if not check(hud.portrait_units[0] == selected[0] and shown.all(func(p): return p.icon != null),"Portraits should start with the card's unit and show icons"): return
	# Health on the portrait follows the unit, coloured by how hurt it is.
	var hurt: Node3D = hud.portrait_units[1]
	hurt.health = int(hurt.max_health*0.2)
	hud._process(0)
	var bar: ProgressBar = shown[1].get_node("Health")
	if not check(bar.value == hurt.health and bar.get_theme_stylebox("fill").bg_color.r > 0.9 and shown[0].get_node("Health").get_theme_stylebox("fill").bg_color.g > 0.6,"A badly hurt unit's portrait bar should be red, the others green"): return
	if not check(shown[1].tooltip_text.begins_with(hud.object_name(hurt)),"The portrait tooltip should name the unit: "+shown[1].tooltip_text): return
	# Shift-click removes one unit; a click keeps only that unit.
	var count := selected.size()
	var removed: Node3D = hud.portrait_units[1]
	var shift := key(KEY_SHIFT)
	Input.parse_input_event(shift)
	Input.flush_buffered_events()
	if not check(Input.is_key_pressed(KEY_SHIFT),"The test could not hold Shift"): return
	shown[1].pressed.emit()
	shift = shift.duplicate()
	shift.pressed = false
	Input.parse_input_event(shift)
	Input.flush_buffered_events()
	hud._process(0)
	if not check(hud.selected_units().size() == count-1 and not removed.is_selected,"Removing a unit should shrink the selection"): return
	var keep: Node3D = hud.portrait_units[hud.portrait_units.size()-1]
	shown = portraits.get_children().filter(func(p): return p.visible)
	shown[hud.portrait_units.size()-1].pressed.emit()
	hud._process(0)
	if not check(hud.selected_units() == [keep] and not portraits.visible and hud.name_label.text == hud.object_name(keep),"A portrait click should select only that unit and show its own panel"): return
	print("SELECTION_PORTRAITS_TEST_PASSED")
	quit(0)
