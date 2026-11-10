extends SceneTree
# Whole-card art on the command grid, build page and pick prompt: assignment, fit and art that follows state.
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
func art(button: Button) -> String:
	return button.icon.resource_path.get_file() if button.icon != null else ""
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game); await process_frame
	game.set_process(false)
	hud = game.get_node("Interface"); hud.set_process(false)
	for group in ["units","depots"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	# Every tile holds a 128 px card drawn at full tile size, with no text and its key badge intact.
	var theme: Theme = load("res://assets/ui/supply_lines_theme.tres")
	if not check(theme.get_constant("icon_max_width","CommandCard") == hud.TILE and theme.get_constant("icon_max_width","Button") == 18,"Card size leaked into the shared Button theme"): return
	if not check(theme.get_stylebox("normal","CommandCard") is StyleBoxEmpty and theme.get_color("icon_normal_color","CommandCard") == Color.WHITE,"Card style would tint or inset the art"): return
	var tiles := 0
	for panel in [hud.card,hud.build_menu.get_node("Actions"),hud.pick,hud.load_tiles]:
		for button in panel.get_children():
			if not button is Button: continue
			tiles += 1
			if not check(art(button).begins_with("sl_") and button.icon.get_width() == 128,"%s has no card art" % button.name): return
			if not check(button.expand_icon and button.theme_type_variation == &"CommandCard" and button.text.is_empty() and button.has_node("Key"),"%s is not set up as a card" % button.name): return
	if not check(tiles == 47,"Expected 47 card tiles, found %d" % tiles): return
	# Commands with their own art.
	var names := {"Return":"sl_deliver.png","DropMaterials":"sl_drop.png","DeployTruck":"sl_deploy_depot.png","ProduceUbermech":"sl_produce_ubermech.png","PrintTruck":"sl_produce_truck.png"}
	for id in names:
		if not check(art(hud.card.get_node(id)) == names[id],"%s has the wrong card" % id): return
	# Cargo: supplies, refuelling and trips each show the art for their state.
	var cargo: Node3D
	for unit in get_nodes_in_group("units"):
		if unit.is_cargo_vehicle and unit.fuel_active() and unit.team == "player": cargo = unit; break
	if not check(cargo != null,"No player Cargo vehicle"): return
	var supplies: Button = hud.card.get_node("DeployCargo")
	cargo.deployed = false; select(cargo)
	if not check(art(supplies) == "sl_deploy_supplies.png","Deploy supplies art wrong"): return
	cargo.deployed = true; select(cargo)
	if not check(art(supplies) == "sl_pack_supplies.png","Pack supplies art wrong"): return
	cargo.deployed = false
	for mode in ["once","all","repeat"]:
		cargo.trips = mode; select(cargo)
		if not check(art(hud.card.get_node("Trips")) == "sl_trips_%s.png" % mode,"Trips art wrong for %s" % mode): return
	var refuel: Button = hud.card.get_node("ToggleRefuel")
	cargo.auto_refuel = false; select(cargo)
	if not check(art(refuel) == "sl_auto_refuel_off.png" and not refuel.has_theme_color_override("icon_normal_color"),"Auto-refuel off art wrong or tinted"): return
	cargo.auto_refuel = true; select(cargo)
	if not check(art(refuel) == "sl_auto_refuel_on.png","Auto-refuel on art wrong"): return
	# Build page: Pin swaps to Unpin while a payer is pinned.
	select(null)
	var pin: Button = hud.build_menu.get_node("Actions/Pin")
	hud.global_pinned = false; hud.refresh_global_menu()
	if not check(art(pin) == "sl_pin_payer.png","Pin art wrong"): return
	hud.global_pinned = true; hud.refresh_global_menu()
	if not check(art(pin) == "sl_unpin_payer.png","Unpin art wrong"): return
	# Generator, on the map that has one: the image is the action the button will take.
	root.remove_child(game); game.free(); await process_frame
	game = load("res://scenes/maps/generator_exercise.tscn").instantiate()
	root.add_child(game); await process_frame
	game.set_process(false)
	hud = game.get_node("Interface"); hud.set_process(false)
	var generator: Node3D = game.get_node("Entities/Buildings/Generator")
	generator.set_process(false)
	generator.enabled = true; select(null,generator)
	if not check(art(hud.card.get_node("ToggleGenerator")) == "sl_generator_pause.png","Generator pause art wrong"): return
	generator.enabled = false; select(null,generator)
	if not check(art(hud.card.get_node("ToggleGenerator")) == "sl_generator_resume.png","Generator resume art wrong"): return
	# Fuel lives on the card: the current choice is lit, and the panel says how long the fuel lasts.
	var wood_tile: Button = hud.card.get_node("BurnWood")
	var coal_tile: Button = hud.card.get_node("BurnCoal")
	generator.set_fuel_preference("wood"); select(null,generator)
	if not check(wood_tile.visible and coal_tile.visible and hud.card.get_node("BurnEither").visible and hud.card.get_node("AssignDepot").visible,"Generator fuel tiles missing"): return
	if not check(not wood_tile.has_theme_color_override("icon_normal_color") and coal_tile.has_theme_color_override("icon_normal_color"),"Current fuel not lit"): return
	coal_tile.pressed.emit(); hud._process(0)
	if not check(generator.fuel_preference == "coal" and not coal_tile.has_theme_color_override("icon_normal_color") and wood_tile.has_theme_color_override("icon_normal_color"),"Burn Coal tile wrong"): return
	var depot = generator.assigned_depot
	depot.stockpile.set_amount(&"wood",4); depot.stockpile.set_amount(&"coal",2)
	if not check(generator.fuel_left_text() == "2 coal · 10s","Coal fuel left wrong: "+generator.fuel_left_text()): return
	generator.set_fuel_preference("either")
	if not check(generator.fuel_left_text() == "4 wood + 2 coal · 18s","Either fuel left wrong: "+generator.fuel_left_text()): return
	if not check(not hud.has_node("Bottom/Body/Row/Context/GeneratorMode") and not hud.context.get_node("AssignedSource").visible,"Generator dropdowns still shown"): return
	hud.card.get_node("AssignDepot").pressed.emit(); hud._process(0)
	if not check(game.pending_unit_command == "assign_depot" and hud.pick.visible and not hud.load_tiles.visible and hud.pick.get_node("Prompt").visible and hud.pick_stops().has(depot),"Assign Depot prompt wrong"): return
	hud.pick_stop(depot)
	if not check(game.pending_unit_command.is_empty() and generator.assigned_depot == depot,"Assign Depot pick failed"): return
	print("COMMAND_CARDS_TEST_PASSED")
	quit(0)
