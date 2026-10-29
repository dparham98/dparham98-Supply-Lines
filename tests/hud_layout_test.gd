extends SceneTree
# HUD phase 4 layout: compact bar, status bars, type strip, alert feed and cargo pages.
var game: Node3D
var hud: CanvasLayer
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	Input.parse_input_event(shift_event(false))
	push_error(message); quit(1); return false
func shift_event(pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_SHIFT; event.physical_keycode = KEY_SHIFT; event.pressed = pressed
	return event
func frames(count := 6) -> void:
	for i in count: await process_frame
func select(units: Array) -> void:
	game.selected_building = null
	for node in get_nodes_in_group("units"): node.set_selected(units.has(node))
	hud._process(0)
	await frames()
func spawn(path: String, offset: Vector3) -> Node3D:
	var unit = load(path).instantiate()
	unit.position = game.depot.global_position+offset
	game.get_node("Entities/Units").add_child(unit)
	unit.set_process(false)
	return unit
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game); await process_frame
	game.set_process(false)
	hud = game.get_node("Interface")
	for group in ["units","depots"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	var rig = game.get_node("CameraRig"); rig.set_process(false)
	var bottom: Control = hud.get_node("Bottom")
	var bars = hud.bars
	var worker = game.get_node("Entities/Units/Infantry")
	var second = spawn(worker.scene_file_path,Vector3(-10,0,16))
	var tank = spawn("res://scenes/gameplay/tank.tscn",Vector3(14,0,14))
	var truck = spawn("res://scenes/gameplay/cargo_vehicle.tscn",Vector3(-14,0,10))
	# Compact bar: shorter than the former fixed 300 px for ordinary selections.
	await select([])
	if not check(bottom.size.y <= 240,"Empty HUD %.0f px tall" % bottom.size.y): return
	await select([worker])
	if not check(bottom.size.y < 300 and hud.info.get_node("Details").get_global_rect().end.y <= root.size.y,"Infantry HUD %.0f px tall or overflowing" % bottom.size.y): return
	# Status bars: Infantry shows cargo only; a Tank shows fuel coloured by level.
	if not check(bars.get_node("Cargo").visible and not bars.get_node("Fuel").visible,"Infantry bars wrong"): return
	worker.cargo = 5
	hud._process(0)
	if not check(is_equal_approx(bars.get_node("Cargo").value,5) and is_equal_approx(bars.get_node("Cargo").max_value,worker.carry_capacity),"Infantry cargo bar value wrong"): return
	worker.cargo = 0
	await select([tank])
	var fuel_bar: ProgressBar = bars.get_node("Fuel")
	if not check(fuel_bar.visible and not bars.get_node("Cargo").visible and is_equal_approx(fuel_bar.value,tank.fuel) and fuel_bar.get_theme_stylebox("fill").bg_color.g > 0.8,"Tank fuel bar wrong"): return
	tank.fuel = 5; hud._process(0)
	if not check(fuel_bar.get_theme_stylebox("fill").bg_color.r > 0.9 and fuel_bar.get_theme_stylebox("fill").bg_color.g > 0.6 and fuel_bar.get_theme_stylebox("fill").bg_color.b < 0.3,"Low fuel bar not amber"): return
	tank.fuel = 0; hud._process(0)
	if not check(fuel_bar.get_theme_stylebox("fill").bg_color.g < 0.4,"Empty fuel bar not red"): return
	tank.fuel = 60
	game.selected_building = game.depot
	for node in get_nodes_in_group("units"): node.set_selected(false)
	hud._process(0)
	if not check(not fuel_bar.visible and not bars.get_node("Cargo").visible,"Bars shown for a Depot"): return
	# Type strip: one button per type; click keeps a type, Shift-click removes it.
	await select([worker,second,tank])
	var strip = hud.strip
	if not check(strip.visible and strip.get_node("Type1").visible and strip.get_node("Type2").visible and not strip.get_node("Type3").visible,"Strip buttons wrong"): return
	var labels := [strip.get_node("Type1").text,strip.get_node("Type2").text]
	if not check("Infantry ×2" in labels and "Tank ×1" in labels,"Strip labels wrong: %s" % [labels]): return
	var tank_button := 1 if labels[1] == "Tank ×1" else 0
	strip.get_child(tank_button).pressed.emit()
	if not check(tank.is_selected and not worker.is_selected and not second.is_selected,"Strip click did not keep only Tanks"): return
	hud._process(0)
	if not check(not strip.visible,"Strip shown for a single unit"): return
	await select([worker,second,tank])
	Input.parse_input_event(shift_event(true)); Input.flush_buffered_events(); await process_frame
	strip.get_child(tank_button).pressed.emit()
	Input.parse_input_event(shift_event(false))
	if not check(not tank.is_selected and worker.is_selected and second.is_selected,"Shift strip click did not remove Tanks"): return
	# Alert feed: newest first, throttled per key, click focuses the camera.
	var point: Vector3 = game.depot.global_position+Vector3(40,0,-30)
	game.alert("Test alert",point)
	game.alert("Keyed alert",point,"k")
	game.alert("Keyed alert",point,"k")
	hud._process(0)
	var feed = hud.feed
	if not check(feed.get_node("Entry1").visible and feed.get_node("Entry1").text.begins_with("Keyed alert") and feed.get_node("Entry2").text.begins_with("Test alert") and not feed.get_node("Entry3").visible,"Feed entries or throttling wrong"): return
	feed.get_node("Entry2").pressed.emit()
	if not check(rig._focus_target.is_equal_approx(point),"Feed click did not focus the alert"): return
	# Alerts come from gameplay: running out of fuel, losing a unit, a building under attack.
	game.vehicle_fuel_required = true
	tank.fuel = 0.2
	tank.command_move(tank.global_position+Vector3(-10,0,0))
	for i in 240: tank._process(1.0/60)
	if not check(game.alerts[0].text == "Tank out of fuel","Out of fuel alert missing: %s" % [game.alerts[0].text]): return
	second.take_damage(second.health+10); await process_frame
	if not check(game.alerts[0].text == "Infantry lost","Unit lost alert missing"): return
	var hostile = game.get_node("Entities/Units/Hostile")
	hostile.global_position = game.depot.global_position+Vector3(0,0,6)
	var before: int = game.alerts.size()
	for shot in 3:
		hostile._cooldown = 0
		hostile._shoot(game.depot)
	if not check(game.alerts[0].text == "Depot under attack" and game.alerts.size() == mini(before+1,game.ALERT_LIMIT),"Building attack alert missing or not throttled"): return
	# Cargo vehicles: route page by default, Orders shows the command card.
	await select([truck])
	var pages = hud.pages
	if not check(pages.visible and hud.supply.visible and not hud.card.visible,"Cargo did not open on the route page"): return
	pages.get_node("Orders").pressed.emit(); hud._process(0)
	if not check(hud.card.visible and not hud.supply.visible and hud.card.get_node("Move").visible and hud.card.get_node("ToggleRefuel").visible and "ORDERS" in hud.commands.get_node("Title").text,"Orders page wrong"): return
	await select([worker])
	await select([truck])
	if not check(hud.supply.visible and not hud.card.visible,"Cargo page did not reset to route"): return
	await select([worker])
	if not check(not pages.visible,"Pages shown for Infantry"): return
	print("HUD_LAYOUT_TEST_PASSED")
	quit(0)
