extends SceneTree
# UI phase F: compact fixed-slot command grid, build menu grid page and two-column info. Tile text is in tooltips.
var game: Node3D
var hud: CanvasLayer
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func select(unit: Node3D, building: Node3D = null) -> void:
	game.selected_building = building
	for node in get_nodes_in_group("units"): node.set_selected(node == unit)
	hud._process(0)
	for frame in 4: await process_frame
	hud._process(0)
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game); await process_frame
	game.set_process(false)
	hud = game.get_node("Interface"); hud.set_process(false)
	for group in ["units","depots"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	var worker = game.get_node("Entities/Units/Infantry")
	await select(worker)
	# The grid is about 200 px wide; Info and Context sit side by side in the freed width.
	if not check(hud.card.size.x <= 200 and hud.commands.size.x <= 240,"Command column too wide: card %.0f, column %.0f" % [hud.card.size.x,hud.commands.size.x]): return
	var info: Control = hud.info
	var context: Control = hud.context
	if not check(context.visible and context.global_position.x > info.global_position.x+info.size.x-1 and is_equal_approx(context.global_position.y,info.global_position.y),"Info and Context are not side by side"): return
	if not check(info.size.x >= 280 and context.size.x >= 240,"Info or Context too narrow: %.0f / %.0f" % [info.size.x,context.size.x]): return
	# Fixed slots: every visible tile sits on its own slot inside the grid, with no overlaps.
	var used := {}
	for button in hud.card.get_children():
		if not button is Button or not button.visible: continue
		var slot: int = hud.SLOTS[str(button.name)]
		if not check(not used.has(slot) and button.position == Vector2((slot%4)*50,(slot/4)*50) and button.text.is_empty(),"%s not on its own fixed slot" % button.name): return
		used[slot] = true
	if not check(hud.card.get_node("Slots").get_child_count() == 12,"Grid lacks 12 slots"): return
	# Tiles stay put between selections: Move and Stop never move.
	var tank = load("res://scenes/gameplay/tank.tscn").instantiate()
	tank.position = game.depot.global_position+Vector3(14,0,14)
	game.get_node("Entities/Units").add_child(tank); tank.set_process(false)
	await select(tank)
	if not check(hud.card.get_node("Move").position == Vector2.ZERO and hud.card.get_node("Stop").position == Vector2(50,0) and hud.card.get_node("ToggleRefuel").position == Vector2(150,0),"Tank tiles moved"): return
	# Tile names and keys are in tooltips; no hover line takes HUD space.
	if not check(not hud.has_node("Bottom/Body/Row/Commands/Hover") and hud.card.get_node("Attack").tooltip_text.begins_with("Attack [A]"),"Tile tooltip missing, or the hover line is back"): return
	# The hint is drawn by the HUD's own Tip panel (never Godot's popup, which can swallow a click in progress).
	var tip = hud.get_node("Tip")
	var attack_center: Vector2 = hud.card.get_node("Attack").get_global_rect().get_center()
	var motion := InputEventMouseMotion.new(); motion.position = attack_center; motion.global_position = attack_center
	root.push_input(motion,true); Input.parse_input_event(motion); Input.flush_buffered_events()
	hud.tip_delay = 0.0
	hud._process(0)
	if not check(tip.visible and tip.get_node("Text").text.begins_with("Attack [A]") and tip.mouse_filter == Control.MOUSE_FILTER_IGNORE,"Hover tip not shown for the Attack tile: %s" % tip.get_node("Text").text): return
	var press := InputEventMouseButton.new(); press.position = attack_center; press.global_position = attack_center; press.button_index = MOUSE_BUTTON_LEFT; press.pressed = true
	Input.parse_input_event(press); Input.flush_buffered_events()
	hud._process(0)
	if not check(not tip.visible,"Hover tip stayed up while the button was held"): return
	press.pressed = false; Input.parse_input_event(press); Input.flush_buffered_events()
	hud.tip_delay = hud.TIP_DELAY
	if not check(ProjectSettings.get_setting("gui/timers/tooltip_delay_sec") >= 1000,"Godot's own tooltip popup is enabled again"): return
	# The header Build page is a grid of the same tiles, with Back last; Infantry has no build tile.
	await select(worker)
	if not check(not hud.card.has_node("Build"),"Infantry still has a Build tile"): return
	hud.get_node("Bottom/Body/Header/GlobalBuild").pressed.emit()
	hud._process(0)
	var actions: GridContainer = hud.build_menu.get_node("Actions")
	if not check(hud.build_menu.visible and not hud.card.visible and actions.columns == 4,"Build page not shown as a grid"): return
	var last: Control = actions.get_child(actions.get_child_count()-1)
	if not check(last.name == "Back" and actions.get_node("Depot").icon != null and actions.get_node("Depot").text.is_empty(),"Build tiles wrong"): return
	if not check(" E · " in actions.get_node("Generator").tooltip_text and hud.label_of(actions.get_node("Generator")) == "Generator","Build tile tooltip lacks name or cost"): return
	actions.get_node("Back").pressed.emit(); hud._process(0)
	if not check(hud.card.visible and not hud.build_menu.visible,"Back did not return to the card"): return
	# Fixed HUD height and a square framed minimap for every kind of selection.
	var truck = load("res://scenes/gameplay/cargo_vehicle.tscn").instantiate()
	truck.position = game.depot.global_position+Vector3(-14,0,10)
	game.get_node("Entities/Units").add_child(truck); truck.set_process(false)
	var map: Control = hud.get_node("Bottom/Body/Row/MapColumn/Map")
	for case in [[null,null],[worker,null],[tank,null],[truck,null],[null,game.depot]]:
		await select(case[0],case[1])
		if not check(is_equal_approx(hud.get_node("Bottom").size.y,260) and map.size.x == map.size.y,"HUD height %.0f or map %s not fixed" % [hud.get_node("Bottom").size.y,map.size]): return
	# Bars stay short: Info has a fixed width.
	if not check(is_equal_approx(info.size.x,300) and hud.get_node("Bottom/Body/Row/Info/Health").size.x <= 300,"Info column not fixed at 300 px"): return
	print("COMPACT_GRID_TEST_PASSED")
	quit(0)
