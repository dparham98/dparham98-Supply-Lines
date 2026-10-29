extends CanvasLayer
@onready var game = get_parent()
@onready var network = game.get_node("DepotNetwork")
@onready var commands = $Bottom/Body/Row/Commands
@onready var card = $Bottom/Body/Row/Commands/Main
@onready var info = $Bottom/Body/Row/Info
@onready var build_menu = $Bottom/Body/Row/Commands/BuildMenu
@onready var supply = $Bottom/Body/Row/Commands/Supply
@onready var bars = $Bottom/Body/Row/Info/Bars
@onready var strip = $Bottom/Body/Selection
@onready var feed = $Feed
@onready var pages = $Bottom/Body/Header/Pages
# Cargo vehicles open on their delivery route page; Orders shows the ordinary command card.
var cargo_page := "route"
var strip_types: Array[String] = []
var feed_points: Array[Vector3] = []
const UNAFFORDABLE := Color(0.941,0.698,0.29)
const FEED_SECONDS := 45.0
var route_depots: Array[Node3D] = []
var local_sources: Array[Node3D] = []
var local_signature := ""
var assignment_sources: Array[Node3D] = []
var assignment_signature := ""
var build_depots: Array[Node3D] = []
var depot_signature := ""
var build_signature := ""
var payer_initialized := false
var build_open := false
var global_build_open := false
var global_payer: Node3D
var global_pinned := false
var global_sources: Array[Node3D] = []
var global_signature := ""
var shown: Node3D
var desired_buttons: Array[String] = []
func _ready() -> void:
	$Bottom/Body/Header/GlobalBuild.pressed.connect(open_global_build)
	pages.get_node("Orders").pressed.connect(func(): cargo_page = "orders")
	pages.get_node("Route").pressed.connect(func(): cargo_page = "route")
	for i in strip.get_child_count():
		strip.get_child(i).pressed.connect(narrow_selection.bind(i))
	for i in feed.get_child_count():
		feed.get_child(i).pressed.connect(focus_alert.bind(i))
	card.get_node("CancelPlan").pressed.connect(func():
		if is_instance_valid(shown) and shown.is_in_group("construction_plans"): shown.cancel())
	commands.get_node("GeneratorMode").item_selected.connect(func(index):
		if is_instance_valid(shown) and shown.is_in_group("energy_generators"):
			shown.set_fuel_preference(["wood","coal","either"][index]))
	card.get_node("ToggleRefuel").pressed.connect(toggle_refuel)
	# Supply panel buttons with fixed text get their key label once.
	# Each bound button shows its key in a corner badge; tooltips also list it.
	for panel in [card,supply]:
		for button in panel.get_children():
			if button is Button and button.has_node("Key"): button.get_node("Key").text = hotkey_text(button)
	card.get_node("ToggleGenerator").pressed.connect(func():
		if is_instance_valid(shown) and shown.is_in_group("energy_generators"): shown.enabled = not shown.enabled)
	supply.get_node("DeploySupplies").pressed.connect(func():
		var vehicle = selected_cargo()
		if vehicle:
			if vehicle.deployed: vehicle.pack_supplies()
			elif not vehicle.deploy_supplies(): game.notify("Cannot deploy supplies here or during another transition."))
	supply.get_node("MoveCargo").pressed.connect(func(): game.pending_unit_command = "move"; game.notify("Click a destination. Supplies pack before departure."))
	card.get_node("DropMaterials").pressed.connect(func():
		for unit in selected_units():
			if unit.can_gather and unit.cargo > 0:
				unit.order_queue.clear()
				unit._stop_route(); unit.order = "idle"; unit.source = null
				game.drop_material(unit)
		game.notify("Materials dropped. Any Infantry can gather the pile before spending it."))
	commands.get_node("LocalSource").item_selected.connect(func(index):
		if is_instance_valid(shown) and index >= 0 and index < local_sources.size():
			shown.supply_payer = local_sources[index]; shown.supply_payer_explicit = true
			shown.return_depot = local_sources[index]; shown.return_explicit = true)
	commands.get_node("AssignedSource").item_selected.connect(func(index):
		if is_instance_valid(shown) and index >= 0 and index < assignment_sources.size():
			game.notify("Depot assigned." if shown.assign_source(assignment_sources[index]) else "Assignment requires an empty production queue and a friendly covering Depot."))
	for mode in ["move","attack","gather","repair","capture"]:
		card.get_node(mode.capitalize()).pressed.connect(func(): game.pending_unit_command = mode; game.notify("Click a target for %s. Esc cancels." % mode))
	card.get_node("Stop").pressed.connect(stop_units)
	card.get_node("Return").pressed.connect(return_units)
	card.get_node("Build").pressed.connect(func(): close_build(); build_open = true; refresh_build_menu())
	card.get_node("PrintInfantry").pressed.connect(func():
		if is_instance_valid(shown) and shown.is_in_group("production_buildings"): shown.request_unit(&"infantry"))
	card.get_node("PrintTruck").pressed.connect(func():
		if network.owned_selected() and not network.selected.request_truck(): game.notify("Depot lacks local funds or queue space."))
	card.get_node("PrintTrain").pressed.connect(func():
		if network.owned_selected() and not network.selected.request_train(): game.notify("Depot lacks local train funds or queue space."))
	build_menu.get_node("Actions/Rail").pressed.connect(func():
		if global_build_open: begin_global_placement(&"rail"); return
		refresh_build_menu()
		if not network.owned_selected() or not network.builder_valid(): return
		game.placing_rail = false
		game.placing_depot = false; game.placing_generator = false; game.placing_structure = &""
		game.pending_unit_command = ""; game.placing_rail = true
		game.notify("Click individual rail tiles in the paying Depot territory. Esc finishes."))
	card.get_node("PrintCargo").pressed.connect(func():
		if network.owned_selected() and not network.selected.request_cargo(): game.notify("Depot lacks local funds or queue space."))
	for id in ["scout","grenadier","tank","motorcycle","drone","ubermech"]:
		card.get_node("Produce"+id.capitalize()).pressed.connect(func():
			if is_instance_valid(shown) and shown.is_in_group("production_buildings"): shown.request_unit(StringName(id)))
	build_menu.get_node("Actions/Mine").pressed.connect(func(): begin_production_placement(&"iron_mine"))
	build_menu.get_node("Actions/Barracks").pressed.connect(func(): begin_production_placement(&"barracks"))
	build_menu.get_node("Actions/TankFactory").pressed.connect(func(): begin_production_placement(&"tank_factory"))
	card.get_node("DeployTruck").pressed.connect(network.deploy_selected_truck)
	card.get_node("FocusAssigned").pressed.connect(func():
		if is_instance_valid(shown) and is_instance_valid(shown.assigned_depot): game.get_node("CameraRig").focus_position(shown.assigned_depot.global_position))
	build_menu.get_node("Payer").item_selected.connect(func(index):
		if global_build_open:
			global_pinned = index > 0
			global_payer = global_sources[index-1] if index > 0 and index <= global_sources.size() else null
			return
		if index >= 0 and index < build_depots.size():
			if shown.is_in_group("depots"): network.select_depot(shown)
			else:
				network.bind_builder(shown,build_depots[index])
				shown.supply_payer = build_depots[index]; shown.supply_payer_explicit = true)
	build_menu.get_node("Actions/Depot").pressed.connect(func(): begin_placement(false))
	build_menu.get_node("Actions/Generator").pressed.connect(func(): begin_placement(true))
	build_menu.get_node("Actions/Back").pressed.connect(close_build)
	supply.get_node("StartRoute").pressed.connect(assign_route)
	supply.get_node("PauseRoute").pressed.connect(func():
		var vehicle = selected_cargo()
		if vehicle:
			if vehicle.route_paused:
				if not vehicle.resume_supply_route(): game.notify(vehicle.route_error)
			elif vehicle.route_active: vehicle.pause_supply_route())
	supply.get_node("CancelRoute").pressed.connect(func():
		var vehicle = selected_cargo()
		if vehicle: vehicle.cancel_supply_route())
	$Bottom/Body/Header/Focus.pressed.connect(func():
		if is_instance_valid(shown): game.get_node("CameraRig").focus_position(shown.global_position))
	$Bottom/Body/Header/Restart.pressed.connect(func(): get_tree().reload_current_scene())
func toggle_refuel() -> void:
	if not is_instance_valid(shown) or not shown.is_in_group("units"): return
	var enable: bool = not shown.auto_refuel
	for unit in selected_units():
		if unit.fuel_active(): unit.auto_refuel = enable
func selected_units() -> Array[Node3D]:
	var units: Array[Node3D] = []
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.team == "player" and unit.is_selected: units.append(unit)
	return units
func selected_object() -> Node3D:
	var units := selected_units()
	if not units.is_empty(): return units[0]
	return game.selected_building if is_instance_valid(game.selected_building) and (game.selected_building.is_in_group("selectable_buildings") or game.selected_building.is_in_group("construction_plans")) else null
func selected_cargo() -> Node3D:
	var node = selected_object()
	return node if is_instance_valid(node) and node.is_in_group("units") and node.is_cargo_vehicle else null
func object_name(node: Node3D) -> String:
	if node.is_in_group("mines"): return "Iron Mine"
	if node.is_in_group("production_buildings"): return node.stats.display_name
	if node.is_in_group("depots"): return "Depot" if node.name == "Depot" else "%s · Depot" % node.name
	if node.is_in_group("energy_generators"): return "%s · Generator" % node.name
	if node.is_in_group("rail_trains"): return "Train"
	if node.is_cargo_vehicle: return "Cargo Vehicle"
	if node.is_depot_truck: return "Depot Truck"
	return node.unit_stats.display_name if node.unit_stats != null else "Infantry"
func nearest_depot(node: Node3D) -> Node3D:
	var nearest: Node3D
	var distance := INF
	for depot in get_tree().get_nodes_in_group("depots"):
		var d: float = node.global_position.distance_to(depot.global_position)
		if depot.team == node.team and d < distance: nearest = depot; distance = d
	return nearest
func _process(_delta: float) -> void:
	var manager = get_node("/root/SelectionManager")
	$SelectionBox.visible = manager.selecting and manager.drag_distance >= 6.0
	var rect := Rect2(manager.start_pos,manager.end_pos-manager.start_pos).abs()
	$SelectionBox.position = rect.position
	$SelectionBox.size = rect.size
	desired_buttons.clear()
	update_contents()
	var units := selected_units()
	if units.size() > 1 and not global_build_open:
		commands.get_node("Title").text = "%d FRIENDLY UNITS SELECTED" % units.size()
		commands.get_node("Hint").text = "Right-click moves the group. Commands apply where each unit supports them. Details show the first unit."
	# Apply final visibility once. Hiding a pressed button cancels its GUI gesture.
	for button in card.get_children(): button.visible = desired_buttons.has(str(button.name))
	update_strip(units)
	update_feed()
# Fuel and cargo bars under health. Fuel turns amber when low and red when empty.
func update_bars(node: Node3D) -> void:
	if node.fuel_active():
		var fuel_bar: ProgressBar = bars.get_node("Fuel")
		fuel_bar.max_value = node.fuel_rules.reserve_capacity
		fuel_bar.value = node.fuel
		fuel_bar.get_theme_stylebox("fill").bg_color = Color(0.95,0.3,0.25) if node.fuel <= 0 else (Color(1,0.72,0.2) if node.fuel_low() else Color(0.4,0.85,0.45))
		bars.get_node("FuelLabel").visible = true
		fuel_bar.visible = true
	var capacity := 0
	var carried := 0
	if node.is_cargo_vehicle: capacity = node.stockpile.capacity; carried = node.stockpile.total()
	elif node.can_gather: capacity = node.carry_capacity; carried = node.cargo
	if capacity > 0:
		var cargo_bar: ProgressBar = bars.get_node("Cargo")
		cargo_bar.max_value = capacity
		cargo_bar.value = carried
		bars.get_node("CargoLabel").visible = true
		cargo_bar.visible = true
# One button per unit type in a mixed selection.
func update_strip(units: Array[Node3D]) -> void:
	var counts := {}
	var names := {}
	strip_types.clear()
	for unit in units:
		var key: String = unit.scene_file_path
		if not counts.has(key): strip_types.append(key); names[key] = object_name(unit)
		counts[key] = counts.get(key,0)+1
	strip.visible = units.size() > 1 and not global_build_open
	for i in strip.get_child_count():
		var button: Button = strip.get_child(i)
		button.visible = strip.visible and i < strip_types.size()
		if button.visible: button.text = "%s ×%d" % [names[strip_types[i]],counts[strip_types[i]]]
func narrow_selection(index: int) -> void:
	if index >= strip_types.size(): return
	var keep_type := not Input.is_key_pressed(KEY_SHIFT)
	for unit in selected_units():
		unit.set_selected((unit.scene_file_path == strip_types[index]) == keep_type)
func update_feed() -> void:
	var now := Time.get_ticks_msec()/1000.0
	feed_points.clear()
	for entry in game.alerts:
		if now-entry.time <= FEED_SECONDS and feed_points.size() < feed.get_child_count():
			var button: Button = feed.get_child(feed_points.size())
			button.text = "%s · %ds" % [entry.text,int(now-entry.time)]
			feed_points.append(entry.point)
	for i in feed.get_child_count(): feed.get_child(i).visible = i < feed_points.size()
func focus_alert(index: int) -> void:
	if index < feed_points.size(): game.get_node("CameraRig").focus_position(feed_points[index])
# Shortcuts only fire for visible, enabled buttons.
func hotkey_text(button: Button) -> String:
	if button.shortcut == null or button.shortcut.events.is_empty() or not button.shortcut.events[0] is InputEventAction: return ""
	var action: StringName = button.shortcut.events[0].action
	if not InputMap.has_action(action): return ""
	for event in InputMap.action_get_events(action):
		if event is InputEventKey: return event.as_text_physical_keycode()
	return ""
func update_contents() -> void:
	var node = selected_object()
	if node != shown:
		close_build()
		shown = node
		cargo_page = "route"
	for bar in bars.get_children(): bar.visible = false
	var is_unit: bool = is_instance_valid(node) and node.is_in_group("units")
	var show_build: bool = global_build_open or is_instance_valid(node) and build_open and ((is_unit and node.can_construct) or (node.is_in_group("depots") and node.team == "player"))
	var show_supply: bool = is_unit and node.is_cargo_vehicle and not show_build and cargo_page == "route"
	pages.visible = is_unit and node.is_cargo_vehicle and not show_build
	pages.get_node("Orders").set_pressed_no_signal(cargo_page == "orders")
	pages.get_node("Route").set_pressed_no_signal(cargo_page == "route")
	supply.visible = show_supply
	build_menu.visible = show_build
	card.visible = not show_build and not show_supply
	commands.get_node("GeneratorMode").visible = not show_build and is_instance_valid(node) and node.is_in_group("energy_generators") and node.team == "player"
	commands.get_node("LocalSource").visible = is_unit and node.can_gather and not show_build
	commands.get_node("AssignedSource").visible = not show_build and is_instance_valid(node) and (node.is_in_group("production_buildings") or node.is_in_group("energy_generators")) and node.team == "player"
	if commands.get_node("LocalSource").visible: update_local_source(node)
	if commands.get_node("AssignedSource").visible: update_assignment(node)
	commands.get_node("Hint").visible = not show_build
	card.columns = 3
	info.get_node("Health").visible = is_instance_valid(node)
	$Bottom/Body/Header/Focus.disabled = not is_instance_valid(node)
	$Bottom/Body/Header/Message.text = game.outcome if not game.outcome.is_empty() else game.message
	if global_build_open:
		commands.get_node("Title").text = "GLOBAL BUILD · UNPAID PLANS"
		refresh_global_menu()
		info.get_node("Health").visible = false
		info.get_node("Name").text = "Construction plans"
		info.get_node("HealthText").text = "%d pending" % get_tree().get_nodes_in_group("construction_plans").size()
		info.get_node("Details").text = "Place on valid terrain anywhere.\nPlans wait for one covering Depot\nwith the full local cost.\nClick a plan to inspect or cancel it."
		return
	if is_instance_valid(node) and node.is_in_group("construction_plans"):
		info.get_node("Health").visible = false
		info.get_node("Name").text = node.spec.title+" plan"
		info.get_node("HealthText").text = "Unpaid · no resources reserved"
		var payer_text: String = str(node.payer.name) if is_instance_valid(node.payer) else "Unavailable"
		info.get_node("Details").text = "%s\nCost %d E / %d I\nPayer: %s\nDoes not block movement" % [node.state,node.spec.energy,node.spec.iron,payer_text if node.pinned else "Auto covering friendly Depot"]
		commands.get_node("Title").text = "PENDING CONSTRUCTION"
		commands.get_node("Hint").text = "Completes when terrain is clear and one friendly covering Depot can pay. Cancel is free."
		show_button("CancelPlan","Cancel plan")
		return
	if not is_instance_valid(node):
		info.get_node("Name").text = "Nothing selected"
		info.get_node("HealthText").text = "Select a unit or building"
		info.get_node("Details").text = "Minimap: click to move camera.\nBlue: friendly · red: hostile\nGrey: neutral · gold: resources"
		commands.get_node("Title").text = "COMMAND CARD"
		commands.get_node("Hint").text = "Left-click selects. Drag selects units. Right-click gives orders."
		return
	var units := selected_units()
	info.get_node("Name").text = object_name(node)+( " · +%d selected" % (units.size()-1) if units.size() > 1 else "")
	info.get_node("Health").max_value = node.max_health
	info.get_node("Health").value = node.health
	info.get_node("HealthText").text = "Health %d / %d · %s" % [node.health,node.max_health,"shared" if node.is_in_group("mines") else node.team]
	commands.get_node("Hint").text = ""
	if node.is_in_group("depots"):
		card.columns = 2
		commands.get_node("Title").text = "DEPOT · PRODUCTION"
		info.get_node("Details").text = "Local E %d · I %d · W %d · C %d\nStorage %d / %d\nGeneration +%.1f E/s\nQueue %d / %d · %d%%\nCapture %d%% · territory %.0f" % [node.energy,node.iron,node.wood,node.coal,node.stockpile.total(),node.storage_capacity,node.generation_rate(),node.queue,node.queue_limit,roundi(node.progress/node.print_seconds*100),roundi(node.capture_progress/node.rules.capture_seconds*100),node.rules.construction_radius]
		if node.team == "player":
			show_production("PrintTruck","Depot truck",node.rules.truck_energy_cost,node.rules.truck_iron_cost,node)
			show_production("PrintCargo","Cargo vehicle",network.supply_rules.cargo_energy_cost,network.supply_rules.cargo_iron_cost,node)
			var rails = game.get_node("RailNetwork").rules
			show_production("PrintTrain","Train",rails.cargo_energy_cost,rails.cargo_iron_cost,node)
			show_button("Build","Build…")
			commands.get_node("Hint").text = "Spend this Depot only. Train launch/load/unload needs friendly track within %.0f units. New Depots include one infantry." % node.dropoff_range
			if build_open:
				commands.get_node("Title").text = "DEPOT · BUILD & LOCAL RESOURCES"
				refresh_build_menu()
	elif node.is_in_group("mines"):
		commands.get_node("Title").text = "SHARED MINE · IRON EXTRACTION"
		info.get_node("Details").text = "Iron reserves %d / %d\nShared access · no capture\nAny side can gather or repair" % [node.remaining,node.amount]
		commands.get_node("Hint").text = "Infantry gathers with right-click. Use its Repair card to repair this shared mine, or Attack to destroy it."
	elif node.is_in_group("production_buildings"):
		card.columns = 2
		commands.get_node("Title").text = node.stats.display_name.to_upper()+" · PRODUCTION"
		var payer = node.assigned_depot
		info.get_node("Details").text = "Assigned Depot: %s\nLocal energy %d · iron %d\nQueue %d / %d · %d%%\n%s" % [payer.name if is_instance_valid(payer) else "none",payer.energy if is_instance_valid(payer) else 0,payer.iron if is_instance_valid(payer) else 0,node.queue,node.stats.queue_limit,roundi(node.progress/node.stats.print_seconds*100),"Ready" if node.source_friendly() else "Assigned Depot unavailable"]
		if node.source_friendly():
			for scene in node.stats.unit_scenes:
				var stats = node.unit_stats_for(scene)
				show_production("PrintInfantry" if stats.unit_id == &"infantry" else "Produce"+str(stats.unit_id).capitalize(),stats.display_name,stats.energy_cost,stats.iron_cost,node.assigned_depot)
		commands.get_node("Hint").text = "Production uses this building’s assigned Depot only. Drone attacks and tentative abilities remain unspecified."
	elif node.is_in_group("energy_generators"):
		commands.get_node("Title").text = "GENERATOR · LOCAL POWER"
		var source = node.assigned_depot
		var stock := "No assigned stockpile" if not is_instance_valid(source) else "E%d I%d W%d C%d · %d/%d" % [source.energy,source.iron,source.wood,source.coal,source.stockpile.total(),source.storage_capacity]
		info.get_node("Details").text = "Assigned Depot: %s\n%s\n%s\nCurrent rate %.1f E/s\nCycle: %s · %.1f / %.1fs" % [source.name if is_instance_valid(source) else "none",stock,node.describe_state(),node.output_rate(),str(node.cycle_kind) if not node.cycle_kind.is_empty() else "waiting",node.cycle_elapsed,node.cycle_seconds]
		commands.get_node("GeneratorMode").select(["wood","coal","either"].find(node.fuel_preference))
		commands.get_node("Hint").text = "Wood: 1 → %d E / %.1fs. Coal: 1 → %d E / %.1fs. Either uses wood first. Changes apply next cycle; full storage pauses fuel use." % [node.fuel_rules.wood_output,node.fuel_rules.wood_seconds,node.fuel_rules.coal_output,node.fuel_rules.coal_seconds]
		if node.team == "player": show_button("ToggleGenerator","Pause" if node.enabled else "Resume")
		if is_instance_valid(node.assigned_depot): show_button("FocusAssigned","Focus Depot")
	else:
		var nearest = nearest_depot(node)
		var proximity := "%s · %.1f units away" % [nearest.name,node.global_position.distance_to(nearest.global_position)] if nearest != null else "No friendly Depot"
		var cargo_text := "%s carried %d / %d" % [str(node.cargo_kind).capitalize(),node.cargo,node.carry_capacity]
		if node.is_cargo_vehicle: cargo_text = "Cargo E%d I%d W%d C%d / %d" % [node.carried_energy,node.carried_iron,node.carried_wood,node.carried_coal,node.stockpile.capacity]
		elif node.is_depot_truck: cargo_text = "Deployment stock: E %d / I %d" % [node.deployment_rules.deployed_energy,node.deployment_rules.testing_starting_iron if node.deployment_rules.testing_starting_iron >= 0 else node.deployment_rules.deployed_iron]
		var combat := "Non-combat vehicle" if node.is_cargo_vehicle or node.is_depot_truck else "Range %.1f · damage %d / %.2fs%s" % [node.attack_range,node.attack_damage,node.shot_interval," (fallback)" if node.unit_stats != null and not node.unit_stats.has_resolved_attack() else ""]
		if not node._attack_enabled and not node.is_cargo_vehicle and not node.is_depot_truck: combat = "Attack unavailable · unresolved stats"
		if node.unit_stats != null and node._attack_enabled:
			var stats: UnitStats = node.unit_stats
			if stats.heavy_target_damage >= 0: combat += "\nTank/building %d / %.1fs · splash %.1f" % [stats.heavy_target_damage,stats.heavy_target_interval,stats.splash_radius]
			if stats.fire_while_moving: combat += " · Moving fire"
		if node.mobility_layer() == MobilityRules.Layer.AIR: combat += "\nFlight · separate air layer"
		elif node.unit_stats != null and node.unit_stats.mobility != null and node.unit_stats.mobility.clears_forest: combat += "\nClears forest on entry"
		elif node.mobility_layer() == MobilityRules.Layer.FOREST: combat += "\nForest traversal"
		if node.fuel_rules != null: combat += "\n"+node.fuel_summary()
		if node.is_in_group("rail_trains") and not node.fuel_warning.is_empty(): combat += "\n"+node.fuel_warning
		var cost_energy: int = node.energy_cost
		var cost_iron: int = node.iron_cost
		if node.is_cargo_vehicle: cost_energy = node.supply_rules.cargo_energy_cost; cost_iron = node.supply_rules.cargo_iron_cost
		elif node.is_depot_truck: cost_energy = node.deployment_rules.truck_energy_cost; cost_iron = node.deployment_rules.truck_iron_cost
		info.get_node("Details").text = "%s\n%s\nNearest Depot: %s\nSpeed %.1f · vision %.1f\n%s\nCost %d E / %d I" % [node.state,cargo_text,proximity,node.move_speed,node.vision,combat,cost_energy,cost_iron]
		commands.get_node("Title").text = "UNIT · ORDERS"
		update_bars(node)
		show_button("Move","Move")
		show_button("Stop","Stop")
		if node.fuel_active(): show_button("ToggleRefuel","Auto-refuel: %s" % ("on" if node.auto_refuel else "off"))
		if node.is_cargo_vehicle:
			commands.get_node("Title").text = "TRAIN · RAIL DELIVERY ROUTE" if node.is_in_group("rail_trains") else "CARGO VEHICLE · DELIVERY ROUTE"
			update_supply_panel()
			if cargo_page == "orders":
				commands.get_node("Title").text = ("TRAIN" if node.is_in_group("rail_trains") else "CARGO VEHICLE")+" · ORDERS"
				commands.get_node("Hint").text = "Move, Stop and Auto-refuel. Delivery route returns to route controls."
		elif node.is_depot_truck:
			show_button("DeployTruck","Deploy")
			commands.get_node("Hint").text = "Deploy on an empty 8 × 8 footprint. This vehicle does not carry transferable cargo."
		else:
			if node._attack_enabled: show_button("Attack","Attack")
			if node.can_gather:
				show_button("Gather","Gather")
				show_button("Return","Deliver")
				show_button("DropMaterials","Drop")
				explain(card.get_node("DropMaterials"),node.cargo <= 0,"Nothing carried to drop.")
			if node.can_construct: show_button("Build","Build…")
			if node.can_repair:
				show_button("Repair","Repair")
				card.get_node("Repair").tooltip_text = "Restore up to %d HP every %.1fs for %d energy / %d iron from the selected local supply source. No wood is spent." % [node.engineering_rules.repair_hp,node.engineering_rules.repair_interval,node.engineering_rules.repair_energy,node.engineering_rules.repair_iron]
			if node.can_capture_depots: show_button("Capture","Capture")
			commands.get_node("Hint").text = "Right-click to move, gather or attack. Nearest Depot distance is straight-line, not route length."
			if build_open and node.can_construct:
				commands.get_node("Title").text = "INFANTRY · BUILD & LOCAL RESOURCES"
				refresh_build_menu()
func show_button(id: String, text: String) -> void:
	desired_buttons.append(id)
	set_label(card.get_node(id),text)
# Set a label with its hotkey; unchanged text isn't reassigned, so buttons don't relayout each frame.
# Unchanged text isn't reassigned, so buttons don't relayout every frame.
func set_label(button: Button, text: String) -> void:
	if button.text != text: button.text = text
# Production tiles: name over cost. Unaffordable costs turn amber and the tooltip says what's missing.
func show_production(id: String, title: String, energy_cost: int, iron_cost: int, payer: Node) -> void:
	show_button(id,"%s
%d E · %d I" % [title,energy_cost,iron_cost])
	var button: Button = card.get_node(id)
	var missing := []
	if is_instance_valid(payer):
		if payer.energy < energy_cost: missing.append("%d more energy" % (energy_cost-payer.energy))
		if payer.iron < iron_cost: missing.append("%d more iron" % (iron_cost-payer.iron))
	if missing.is_empty():
		button.remove_theme_color_override("font_color")
		button.tooltip_text = "Costs %d energy and %d iron from %s." % [energy_cost,iron_cost,payer.name if is_instance_valid(payer) else "the paying Depot"]
	else:
		button.add_theme_color_override("font_color",UNAFFORDABLE)
		button.tooltip_text = "Needs %s. Generation, deliveries and queued orders can still cover it." % " and ".join(missing)
# Disabled actions stay visible and explain why.
func explain(button: Button, disabled: bool, reason: String) -> void:
	button.disabled = disabled
	if disabled: button.tooltip_text = reason
	elif button.tooltip_text == reason: button.tooltip_text = ""
func close_build() -> void:
	global_build_open = false
	game.global_plan_kind = &""
	build_open = false
	payer_initialized = false
	game.placing_rail = false
	game.placing_depot = false
	game.placing_generator = false
	game.placing_structure = &""
	network.clear_builder()
func refresh_build_menu() -> void:
	if global_build_open: refresh_global_menu(); return
	var node = selected_object()
	if node == null or (not node.is_in_group("depots") and (not node.is_in_group("units") or not node.can_construct)): return
	var candidates: Array[Node3D] = []
	candidates = SupplySource.candidates(get_tree(),node.global_position,"player")
	if node.is_in_group("depots"): candidates.assign([node] if node.team == "player" else [])
	candidates.sort_custom(func(a,b): return a.global_position.distance_squared_to(node.global_position) < b.global_position.distance_squared_to(node.global_position))
	var option: OptionButton = build_menu.get_node("Payer")
	var old = node.supply_payer if node.is_in_group("units") and node.supply_payer_explicit else network.selected
	var signature := ""
	for depot in candidates: signature += str(depot.get_instance_id())+":"
	if signature != build_signature:
		build_signature = signature
		option.clear()
		for depot in candidates: option.add_item(depot.name)
	build_depots = candidates
	for i in range(candidates.size()):
		var depot = candidates[i]
		option.set_item_text(i,"Pay from %s · E %d / I %d / W %d" % [depot.name,depot.energy,depot.iron,depot.wood])
	var index := candidates.find(old) if is_instance_valid(old) else -1
	if index < 0 and not payer_initialized and not candidates.is_empty() and (not node.is_in_group("units") or not node.supply_payer_explicit): index = 0
	if index >= 0: payer_initialized = true
	option.select(index)
	var payer = candidates[index] if index >= 0 else null
	if node.is_in_group("depots"):
		network.clear_builder()
		network.select_depot(payer)
	else:
		network.bind_builder(node,payer)
		if is_instance_valid(payer): node.supply_payer = payer; node.supply_payer_explicit = true
	var valid: bool = network.owned_selected() and network.builder_valid()
	build_menu.get_node("Bank").text = "LOCAL STOCK · %s · E %d / I %d / W %d / C %d · %d/%d" % [payer.name,payer.energy,payer.iron,payer.wood,payer.coal,payer.stockpile.total(),payer.storage_capacity] if valid else ("Choose one paying stockpile from the local list." if not candidates.is_empty() else "No friendly supply coverage here. Deploy a cargo vehicle or move into Depot territory.")
	build_menu.get_node("Actions/Depot").disabled = not valid
	build_menu.get_node("Actions/Generator").disabled = not valid
	build_menu.get_node("Actions/Barracks").disabled = not valid
	build_menu.get_node("Actions/TankFactory").disabled = not valid
	build_menu.get_node("Actions/Mine").disabled = not valid
	build_menu.get_node("Actions/Mine").text = "Iron Mine · %d E / %d I" % [network.engineering_rules.mine_energy_cost,network.engineering_rules.mine_iron_cost]
	build_menu.get_node("Actions/Rail").disabled = not valid or not payer.is_in_group("depots")
	var rails = game.get_node("RailNetwork").rules
	build_menu.get_node("Actions/Rail").text = "Rail tile · %d E / %d I" % [rails.rail_energy_cost,rails.rail_iron_cost]
	if valid:
		build_menu.get_node("Actions/Depot").text = "Depot · %d E / %d I" % [network.depot_rules().depot_energy_cost,network.depot_rules().depot_iron_cost]
		build_menu.get_node("Actions/Generator").text = "Generator · %d E / %d I" % [network.supply_rules.generator_energy_cost,network.supply_rules.generator_iron_cost]
		for pair in [[&"barracks","Barracks"],[&"tank_factory","TankFactory"]]:
			var preview = network.production_scene(pair[0]).instantiate()
			build_menu.get_node("Actions/"+pair[1]).text = "%s · %d E / %d I" % [preview.stats.display_name,preview.stats.energy_cost,preview.stats.iron_cost]
			preview.free()
func begin_placement(generator: bool) -> void:
	if global_build_open: begin_global_placement(&"generator" if generator else &"depot"); return
	game.placing_rail = false
	refresh_build_menu()
	if not network.builder_valid(): return
	game.pending_unit_command = ""
	game.placing_structure = &""
	game.placing_depot = not generator
	game.placing_generator = generator
	game.notify("Click empty land within paying Depot territory. Esc cancels. No resource pooling.")
func stop_units() -> void:
	for unit in selected_units():
		unit.order_queue.clear()
		if unit.is_cargo_vehicle: unit.cancel_supply_route()
		else: unit._stop_route(); unit.order = "idle"; unit.source = null; unit.order_target = null
func return_units() -> void:
	for unit in selected_units():
		if not unit.is_cargo_vehicle and not unit.is_depot_truck:
			unit.order_queue.clear()
			unit.command_return(unit.supply_payer if unit.supply_payer_explicit else nearest_depot(unit))
			if unit.supply_payer_explicit: unit.return_explicit = true
func update_supply_panel() -> void:
	var depots: Array[Node3D] = []
	var signature := ""
	for depot in get_tree().get_nodes_in_group("depots"):
		if SupplySource.available(depot,"player"): depots.append(depot); signature += str(depot.get_instance_id())+":"
	if signature != depot_signature:
		depot_signature = signature
		for id in ["Source","Destination"]:
			var option: OptionButton = supply.get_node(id)
			var old = route_depots[option.selected] if option.selected >= 0 and option.selected < route_depots.size() else null
			option.clear()
			option.tooltip_text = "All living friendly Depots, regardless of vehicle distance. Assign now; travel uses valid ground paths or friendly rails."
			for depot in depots: option.add_item(depot.name)
			if is_instance_valid(old) and depots.has(old): option.select(depots.find(old))
			elif id == "Destination" and depots.size() > 1: option.select(1)
		route_depots = depots
	var vehicle = selected_cargo()
	explain(supply.get_node("StartRoute"),vehicle == null or route_depots.size() < 2,"Needs two living friendly Depots.")
	explain(supply.get_node("PauseRoute"),vehicle == null or not vehicle.route_active,"No route assigned.")
	explain(supply.get_node("CancelRoute"),vehicle == null,"Select a Cargo vehicle or Train.")
	if vehicle:
		var button: Button = supply.get_node("DeploySupplies")
		set_label(button,"Pack up supplies" if vehicle.deployed else "Deploy supplies · 2s")
		explain(button,not vehicle.supply_transition.is_empty(),"Wait for deploying or packing to finish.")
		supply.get_node("RouteStatus").tooltip_text = "Supply range %.1f · Infantry delivery %.1f. Routes pause on deployment and resume explicitly." % [vehicle.mobile_rules.supply_radius(),vehicle.dropoff_range]
		commands.get_node("Hint").text = "%s · Supply %.1f / drop-off %.1f. Right-click with Infantry to deliver. Movement packs first." % [vehicle.state,vehicle.mobile_rules.supply_radius(),vehicle.dropoff_range]
		var endpoints := "%s → %s" % [vehicle.origin_depot.name if is_instance_valid(vehicle.origin_depot) else "none",vehicle.destination_depot.name if is_instance_valid(vehicle.destination_depot) else "none"]
		supply.get_node("RouteStatus").text = (endpoints+(" · repeat" if vehicle.repeating else "")+" · "+("Paused · Resume explicitly" if vehicle.route_paused else vehicle.state)) if vehicle.route_active else "No route assigned · choose any two friendly Depots"
		commands.get_node("Hint").text = "Assign from anywhere · Capacity %d total · Trains wait for friendly rails." % vehicle.stockpile.capacity
func assign_route() -> void:
	var vehicle = selected_cargo()
	var a: int = supply.get_node("Source").selected
	var b: int = supply.get_node("Destination").selected
	if vehicle == null or a < 0 or b < 0 or a >= route_depots.size() or b >= route_depots.size(): return
	var success: bool = vehicle.start_supply_route(route_depots[a],route_depots[b],int(supply.get_node("Amounts/Energy").value),int(supply.get_node("Amounts/Iron").value),supply.get_node("Repeat").button_pressed,int(supply.get_node("Amounts/Wood").value),int(supply.get_node("Amounts/Coal").value))
	var text: String = vehicle.state if success else vehicle.route_error
	if success and vehicle.is_in_group("rail_trains") and not vehicle.fuel_warning.is_empty(): text += " · Train fuel warning: "+vehicle.fuel_warning
	game.notify(text)

func begin_production_placement(kind: StringName) -> void:
	if global_build_open: begin_global_placement(kind); return
	refresh_build_menu()
	if not network.owned_selected() or not network.builder_valid(): return
	game.pending_unit_command = ""
	game.placing_rail = false
	game.placing_depot = false
	game.placing_generator = false
	game.placing_structure = kind
	game.notify("Click empty land in the paying Depot territory. Esc cancels.")

func update_local_source(unit: Node3D) -> void:
	var candidates := SupplySource.candidates(get_tree(),unit.global_position,unit.team)
	var option: OptionButton = commands.get_node("LocalSource")
	var signature := str(unit.get_instance_id())+":"
	for source in candidates: signature += str(source.get_instance_id())+":"
	if signature != local_signature:
		local_signature = signature; option.clear()
		for source in candidates: option.add_item(str(source.name))
	local_sources = candidates
	for i in range(candidates.size()):
		var source = candidates[i]
		option.set_item_text(i,"Supply: %s · E%d I%d W%d C%d" % [source.name,source.energy,source.iron,source.wood,source.coal])
	var index := candidates.find(unit.supply_payer) if is_instance_valid(unit.supply_payer) else -1
	if not unit.supply_payer_explicit and not candidates.is_empty():
		index = 0; unit.supply_payer = candidates[0]; unit.supply_payer_explicit = true
		unit.return_depot = candidates[0]; unit.return_explicit = true
	option.select(index)
	option.text = "Selected supply unavailable · choose source" if index < 0 else option.get_item_text(index)
	option.tooltip_text = "One source for construction/repair and Deliver. Choose a new source explicitly if it packs or is lost. Right-click a deployed vehicle to set a remote drop-off."
func update_assignment(building: Node3D) -> void:
	var candidates: Array[Node3D] = []
	for depot in get_tree().get_nodes_in_group("depots"):
		if SupplySource.covers(depot,building.global_position,building.team): candidates.append(depot)
	var option: OptionButton = commands.get_node("AssignedSource")
	var signature := str(building.get_instance_id())+":"
	for source in candidates: signature += str(source.get_instance_id())+":"
	if signature != assignment_signature:
		assignment_signature = signature; option.clear()
		for source in candidates: option.add_item("Assign Depot: "+str(source.name))
	assignment_sources = candidates
	var index := candidates.find(building.assigned_depot) if is_instance_valid(building.assigned_depot) else -1
	option.select(index)
	option.text = "Choose covering Depot to operate" if index < 0 else option.get_item_text(index)
	option.tooltip_text = "Construction payer and operating Depot are separate. Production queues must be empty to reassign. No automatic assignment or resource pooling."

func open_global_build() -> void:
	close_build()
	game.pending_unit_command = ""
	global_build_open = true
	build_open = true
	shown = selected_object()
	global_signature = ""
	refresh_global_menu()
func begin_global_placement(kind: StringName) -> void:
	game.pending_unit_command = ""
	game.placing_rail = false; game.placing_depot = false; game.placing_generator = false; game.placing_structure = &""
	game.global_plan_kind = kind
	game.notify("Click valid terrain to place an unpaid %s plan. Esc cancels placement; existing plans remain." % network.plan_spec(kind).title)
func refresh_global_menu() -> void:
	var candidates: Array[Node3D] = []
	for depot in get_tree().get_nodes_in_group("depots"):
		if SupplySource.available(depot,"player"): candidates.append(depot)
	var index := candidates.find(global_payer) if is_instance_valid(global_payer) else -1
	if global_pinned and index < 0:
		candidates.append(global_payer if is_instance_valid(global_payer) else null)
		index = candidates.size()-1
	var signature := "global:"
	for source in candidates: signature += str(source.get_instance_id())+":" if is_instance_valid(source) else "lost:"
	var option: OptionButton = build_menu.get_node("Payer")
	if signature != global_signature or build_signature != "global":
		global_signature = signature; build_signature = "global"
		option.clear()
		option.add_item("Auto: nearest covering friendly Depot able to pay")
		for source in candidates: option.add_item(str(source.name) if SupplySource.available(source,"player") else "Pinned Depot unavailable · plans wait")
	global_sources = candidates
	option.select(index+1 if global_pinned else 0)
	build_menu.get_node("Bank").text = "UNPAID PLANS · one covering Depot pays the full cost · no pooled resources"
	for pair in [[&"depot","Depot"],[&"generator","Generator"],[&"barracks","Barracks"],[&"tank_factory","TankFactory"],[&"iron_mine","Mine"],[&"rail","Rail"]]:
		var spec: Dictionary = network.plan_spec(pair[0])
		var button: Button = build_menu.get_node("Actions/"+pair[1])
		button.disabled = false
		button.text = "%s · %d E / %d I" % [spec.title,spec.energy,spec.iron]
