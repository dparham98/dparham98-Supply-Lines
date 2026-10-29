extends SceneTree
# UI phase F: compact fixed-slot command grid, build menu grid page, two-column info, hover line.
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
	# The hover line names an armed command.
	game.pending_unit_command = "attack"
	hud.update_hover_line()
	if not check(hud.hover_label.text.begins_with("Attack · click a target"),"Hover line missing the armed command"): return
	game.pending_unit_command = ""
	# Build opens a grid page of the same tiles, with Back last.
	await select(worker)
	hud.card.get_node("Build").pressed.emit()
	hud._process(0)
	var actions: GridContainer = hud.build_menu.get_node("Actions")
	if not check(hud.build_menu.visible and not hud.card.visible and actions.columns == 4,"Build page not shown as a grid"): return
	var last: Control = actions.get_child(actions.get_child_count()-1)
	if not check(last.name == "Back" and actions.get_node("Depot").icon != null and actions.get_node("Depot").text.is_empty(),"Build tiles wrong"): return
	if not check(" E · " in actions.get_node("Generator").tooltip_text and hud.label_of(actions.get_node("Generator")) == "Generator","Build tile tooltip lacks name or cost"): return
	actions.get_node("Back").pressed.emit(); hud._process(0)
	if not check(hud.card.visible and not hud.build_menu.visible,"Back did not return to the card"): return
	print("COMPACT_GRID_TEST_PASSED")
	quit(0)
