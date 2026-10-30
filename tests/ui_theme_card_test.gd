extends SceneTree
# UI phase A: shared theme, icon tiles with key badges, card order, production costs, disabled reasons.
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
func visible_names() -> Array:
	var names := []
	for button in hud.card.get_children():
		if button is Button and button.visible: names.append(str(button.name))
	return names
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game); await process_frame
	game.set_process(false)
	hud = game.get_node("Interface"); hud.set_process(false)
	for group in ["units","depots"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	var theme: Theme = load("res://assets/ui/supply_lines_theme.tres")
	# One shared theme on every top-level HUD control.
	for path in ["Bottom","Feed","PlaytestPanel"]:
		if not check(hud.get_node(path).theme == theme,"%s does not use the shared theme" % path): return
	# Every bound card and Supply button has an icon and a badge showing its key.
	for panel in [hud.card]:
		for button in panel.get_children():
			if not button is Button or button.shortcut == null: continue
			if not check(button.icon != null and button.has_node("Key") and button.get_node("Key").text == hud.hotkey_text(button) and not button.get_node("Key").text.is_empty(),"%s lacks an icon or key badge" % button.name): return
	# Unit orders come first, in one consistent order.
	var worker = game.get_node("Entities/Units/Infantry")
	select(worker)
	var names := visible_names()
	if not check(names.slice(0,4) == ["Move","Stop","Attack","Gather"] and not names.has("Build"),"Infantry card order wrong: %s" % [names]): return
	if not check(hud.label_of(hud.card.get_node("Gather")) == "Gather" and hud.card.get_node("Gather").text.is_empty() and hud.card.get_node("Gather").tooltip_text.begins_with("Gather [G]\n"),"Tile label or tooltip wrong"): return
	# Fixed slots: Move top-left, Stop beside it, Gather starts the second row.
	if not check(hud.card.get_node("Move").position == Vector2.ZERO and hud.card.get_node("Stop").position == Vector2(50,0) and hud.card.get_node("Gather").position == Vector2(0,50) and hud.card.get_node("Move").size == Vector2(46,46),"Tiles not on their fixed slots"): return
	# Disabled actions stay visible and say why.
	worker.cargo = 0; hud._process(0)
	var drop: Button = hud.card.get_node("DropMaterials")
	if not check(drop.visible and drop.disabled and drop.tooltip_text == "Drop [X]\nNothing carried to drop.","Drop materials reason missing: %s" % drop.tooltip_text): return
	worker.cargo = 5; hud._process(0)
	if not check(not drop.disabled and not "Nothing carried" in drop.tooltip_text,"Drop reason left after it became available"): return
	worker.cargo = 0
	# Production tiles: name over cost, amber with a reason when unaffordable.
	var depot = game.depot
	select(null,depot)
	var cargo: Button = hud.card.get_node("PrintCargo")
	if not check(hud.label_of(cargo) == "Cargo vehicle" and " E · " in cargo.tooltip_text and not cargo.has_theme_color_override("icon_normal_color"),"Affordable production tile wrong: %s" % cargo.tooltip_text): return
	depot.energy = 0; depot.iron = 0
	hud._process(0)
	if not check(cargo.has_theme_color_override("icon_normal_color") and "needs" in cargo.tooltip_text and "more energy" in cargo.tooltip_text,"Unaffordable production tile not marked"): return
	depot.energy = 1000; depot.iron = 1000
	hud._process(0)
	if not check(not cargo.has_theme_color_override("icon_normal_color") and "from Depot" in cargo.tooltip_text,"Production tile stayed amber after funds arrived"): return
	# The global Build button stays in the header.
	if not check(hud.get_node("Bottom/Body/Header/GlobalBuild").is_visible_in_tree(),"Global Build button missing"): return
	print("UI_THEME_CARD_TEST_PASSED")
	quit(0)
