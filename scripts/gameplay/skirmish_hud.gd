extends CanvasLayer
@onready var game = get_parent()
@onready var network = game.get_node("DepotNetwork")
@onready var commands = $Bottom/Body/Row/Commands
@onready var card = $Bottom/Body/Row/Commands/Main
@onready var info = $Bottom/Body/Row/Info
@onready var build_menu = $Bottom/Body/Row/Commands/BuildMenu
@onready var bars = $Bottom/Body/Row/Info/Bars
@onready var strip = $Bottom/Body/Header/Selection
@onready var feed = $Feed
@onready var name_label: Label = $Bottom/Body/Row/Info/Head/Text/Name
@onready var context = $Bottom/Body/Row/Context
@onready var hint_label: Label = $Bottom/Body/Row/Context/Hint
@onready var hover_label: Label = $Bottom/Body/Row/Commands/Hover
@onready var shipment = $Bottom/Body/Row/Context/Shipment
@onready var shipment_target: OptionButton = $Bottom/Body/Row/Commands/OptionRow/ShipmentTarget
var shipment_stops: Array[Node3D] = []
var shipment_signature := ""
# Applied once per frame: hiding the panel mid-frame would cancel a press on its buttons.
var shipment_wanted := false
## Fixed command slots, row-major in the 4 × 3 grid. Commands that never share a card may share a slot.
const SLOTS := {"Move": 0, "Stop": 1, "Attack": 2, "ToggleRefuel": 3, "Gather": 4, "Return": 5, "DropMaterials": 6, "Build": 7,
	"Repair": 8, "Capture": 9, "DeployTruck": 10, "CancelPlan": 11,
	"DeployCargo": 2, "Load": 4, "Unload": 5, "Trips": 6,
	"PrintTruck": 0, "PrintCargo": 1, "PrintTrain": 2,
	"PrintInfantry": 0, "ProduceScout": 1, "ProduceGrenadier": 2, "ProduceTank": 3, "ProduceMotorcycle": 4, "ProduceDrone": 5, "ProduceUbermech": 6,
	"ToggleGenerator": 0, "FocusAssigned": 1}
const TILE := 46
const TRIP_LABELS := {"once": "once", "all": "all available", "repeat": "repeat"}
## One icon per stat row (assets/ui/icons).
const STAT_ICONS := {"Speed": "speed", "Range": "focus", "Damage": "damage", "Vision": "scout", "Vs buildings": "depot", "Splash": "splash",
	"Cost": "cost", "Deploys": "deploy", "Output": "generator", "Burning": "refuel", "Cycle": "cycle", "Mode": "mode",
	"Energy": "generator", "Iron": "mine", "Queue": "queue"}
const TILE_GAP := 4
const OFF_ICON := Color(0.373,0.463,0.502)
@onready var state_label: Label = $Bottom/Body/Row/Info/Head/Text/State
const RESOURCE_KINDS := [&"energy",&"iron",&"wood",&"coal"]
var _icons := {}
# Cargo vehicles open on their delivery route page; Orders shows the ordinary command card.
var strip_types: Array[String] = []
var feed_points: Array[Vector3] = []
const UNAFFORDABLE := Color(0.941,0.698,0.29)
const FEED_SECONDS := 45.0
var local_sources: Array[Node3D] = []
var local_signature := ""
var assignment_sources: Array[Node3D] = []
var assignment_signature := ""
var build_depots: Array[Node3D] = []
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
	for i in strip.get_child_count():
		strip.get_child(i).pressed.connect(narrow_selection.bind(i))
	for i in feed.get_child_count():
		feed.get_child(i).pressed.connect(focus_alert.bind(i))
	card.get_node("CancelPlan").pressed.connect(func():
		if is_instance_valid(shown) and shown.is_in_group("construction_plans"): shown.cancel())
	context.get_node("GeneratorMode").item_selected.connect(func(index):
		if is_instance_valid(shown) and shown.is_in_group("energy_generators"):
			shown.set_fuel_preference(["wood","coal","either"][index]))
	card.get_node("ToggleRefuel").pressed.connect(toggle_refuel)
	# Supply panel buttons with fixed text get their key label once.
	for button in card.get_children():
		if button is Button: button.set_meta("detail",button.tooltip_text)
	# Each bound button shows its key in a corner badge; tooltips also list it.
	for panel in [card,build_menu.get_node("Actions")]:
		for button in panel.get_children():
			if button is Button and button.has_node("Key"): button.get_node("Key").text = hotkey_text(button)
	# Header buttons are text buttons: their key goes in the label.
	for id in ["GlobalBuild","Focus"]:
		var header: Button = $Bottom/Body/Header.get_node(id)
		if not hotkey_text(header).is_empty(): header.text += " · "+hotkey_text(header)
	card.get_node("ToggleGenerator").pressed.connect(func():
		if is_instance_valid(shown) and shown.is_in_group("energy_generators"): shown.enabled = not shown.enabled)
	card.get_node("DeployCargo").pressed.connect(func():
		var vehicle = selected_cargo()
		if vehicle:
			if vehicle.deployed: vehicle.pack_supplies()
			elif not vehicle.deploy_supplies(): game.notify("Cannot deploy supplies here or during another transition."))
	for mode in ["load","unload"]:
		card.get_node(mode.capitalize()).pressed.connect(func(): game.pending_unit_command = mode; game.notify("Click a friendly Depot or deployed Cargo vehicle to %s. Shift queues, Esc cancels." % mode))
	card.get_node("Trips").pressed.connect(func():
		var vehicle = selected_cargo()
		if vehicle:
			var mode: String = vehicle.cycle_trips()
			for unit in selected_units():
				if unit.is_cargo_vehicle: unit.trips = mode
			game.notify("Trips: %s." % TRIP_LABELS[mode]))
	shipment_target.item_selected.connect(order_shipment_stop)
	for kind in RESOURCE_KINDS:
		var row = shipment.get_node("Rows/"+str(kind).capitalize())
		row.get_node("Plus").pressed.connect(change_crates.bind(kind,1))
		row.get_node("Minus").pressed.connect(change_crates.bind(kind,-1))
	shipment.get_node("KeepStocked").toggled.connect(func(on: bool):
		var stockpile = shipment_stockpile()
		if stockpile == null: return
		stockpile.keep_stocked = on
		if on:
			for kind in RESOURCE_KINDS: stockpile.set_target(kind,stockpile.crate_count(kind)))
	card.get_node("DropMaterials").pressed.connect(func():
		for unit in selected_units():
			if unit.can_gather and unit.cargo > 0:
				unit.order_queue.clear()
				unit._stop_route(); unit.order = "idle"; unit.source = null
				game.drop_material(unit)
		game.notify("Materials dropped. Any Infantry can gather the pile before spending it."))
	commands.get_node("OptionRow/LocalSource").item_selected.connect(func(index):
		if is_instance_valid(shown) and index >= 0 and index < local_sources.size():
			shown.supply_payer = local_sources[index]; shown.supply_payer_explicit = true
			shown.return_depot = local_sources[index]; shown.return_explicit = true)
	context.get_node("AssignedSource").item_selected.connect(func(index):
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
	card.get_node("DeployTruck").pressed.connect(func(): game.pending_unit_command = "deploy"; game.notify("Click a site for the Depot. Only an empty 8 × 8 footprint is accepted; Shift queues."))
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
	build_menu.get_node("Actions/Back").pressed.connect(func(): game.cancel_armed(); close_build())
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
		hint_label.text = "Right-click moves the group. Commands apply where each unit supports them. Details show the first unit."
	# Apply final visibility once. Hiding a pressed button cancels its GUI gesture.
	for button in card.get_children():
		if button is Button: button.visible = desired_buttons.has(str(button.name))
	shipment.visible = shipment_wanted
	place_tiles()
	update_hover_line()
	update_strip(units)
	update_feed()
# Fuel and cargo bars under health. Fuel turns amber when low and red when empty.
func update_bars(node: Node3D) -> void:
	if node.fuel_active():
		var fuel_bar: ProgressBar = bars.get_node("Fuel")
		fuel_bar.max_value = node.fuel_rules.reserve_capacity
		fuel_bar.value = node.fuel
		fuel_bar.get_theme_stylebox("fill").bg_color = Color(0.95,0.3,0.25) if node.fuel <= 0 else (Color(1,0.72,0.2) if node.fuel_low() else Color(0.4,0.85,0.45))
		bars.get_node("FuelLabel").text = "Tank fuel" if node.is_cargo_vehicle else "Fuel"
		bars.get_node("FuelValue").text = "%.0f / %.0f" % [node.fuel,node.fuel_rules.reserve_capacity]
		for id in ["FuelLabel","Fuel","FuelValue"]: bars.get_node(id).visible = true
	var capacity := 0
	var carried := 0
	if node.can_gather and not node.is_cargo_vehicle: capacity = node.carry_capacity; carried = node.cargo
	if capacity > 0:
		var cargo_bar: ProgressBar = bars.get_node("Cargo")
		cargo_bar.max_value = capacity
		cargo_bar.value = carried
		bars.get_node("CargoValue").text = "%d / %d%s" % [carried,capacity," "+str(node.cargo_kind) if carried > 0 else ""]
		for id in ["CargoLabel","Cargo","CargoValue"]: bars.get_node(id).visible = true
const DEPOT_PRODUCTS := {"infantry":"Infantry","truck":"Depot truck","cargo":"Cargo vehicle","train":"Train"}
func set_icon(id: String) -> void:
	if id.is_empty(): info.get_node("Head/Icon").texture = null; return
	if not _icons.has(id): _icons[id] = load("res://assets/ui/icons/%s.svg" % id)
	info.get_node("Head/Icon").texture = _icons[id]
func icon_name(node: Node) -> String:
	if node.is_in_group("depots"): return "depot"
	if node.is_in_group("mines"): return "mine"
	if node.is_in_group("production_buildings"): return "factory"
	if node.is_in_group("energy_generators"): return "generator"
	if node.is_in_group("rail_trains"): return "train"
	if node.get("is_cargo_vehicle"): return "cargo"
	if node.get("is_depot_truck"): return "truck"
	var id := str(node.unit_stats.unit_id) if node.get("unit_stats") != null else "infantry"
	return id if ResourceLoader.exists("res://assets/ui/icons/%s.svg" % id) else "infantry"
func team_label(node: Node) -> String:
	return str(node.team).capitalize()
func grouped(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length()-i) % 3 == 0: out += ","
		out += digits[i]
	return ("-" if value < 0 else "")+out
# One storage bar split by resource against capacity, with a legend of exact amounts.
func show_storage(title: String, stockpile: ResourceStockpile) -> void:
	var section = info.get_node("Storage")
	section.visible = true
	section.get_node("Head/Label").text = title
	section.get_node("Head/Value").text = "%s / %s" % [grouped(stockpile.total()),grouped(stockpile.capacity)]
	var segments = section.get_node("Track/Segments")
	for kind in RESOURCE_KINDS:
		var amount := stockpile.amount(kind)
		var segment: Control = segments.get_node(str(kind).capitalize())
		var crated := stockpile.crated(kind)
		segment.visible = amount-crated > 0
		segment.size_flags_stretch_ratio = maxf(amount-crated,0.001)
		var crated_segment: Control = segments.get_node(str(kind).capitalize()+"Crated")
		crated_segment.visible = crated > 0
		crated_segment.size_flags_stretch_ratio = maxf(crated,0.001)
		section.get_node("Legend/%s/Amount" % str(kind).capitalize()).text = "%s %s%s" % [str(kind).capitalize(),grouped(amount)," · %d▢" % stockpile.crate_count(kind) if crated > 0 else ""]
	var free: Control = segments.get_node("Free")
	free.visible = stockpile.space() > 0
	free.size_flags_stretch_ratio = maxf(stockpile.space(),0.001)
func show_progress(label: String, value: String, ratio: float) -> void:
	var section = context.get_node("Production")
	section.visible = true
	section.get_node("Head/Label").text = label
	section.get_node("Head/Value").text = value
	section.get_node("Bar").max_value = 1.0
	section.get_node("Bar").step = 0.0
	section.get_node("Bar").value = clampf(ratio,0,1)
# Plain label and value pairs; information is never boxed.
func set_stats(pairs: Array) -> void:
	var grid = context.get_node("Stats")
	grid.visible = not pairs.is_empty()
	for i in range(1,7):
		var shown := i <= pairs.size()
		for part in ["I","K","V"]: grid.get_node("%s%d" % [part,i]).visible = shown
		if shown:
			grid.get_node("K%d" % i).text = pairs[i-1][0]
			grid.get_node("V%d" % i).text = pairs[i-1][1]
			var icon: String = STAT_ICONS.get(pairs[i-1][0],"focus")
			if not _icons.has(icon): _icons[icon] = load("res://assets/ui/icons/%s.svg" % icon)
			grid.get_node("I%d" % i).texture = _icons[icon]
func fuel_note(node: Node) -> String:
	if not node.fuel_active(): return "Fuel not required here"
	var status := "OUT OF FUEL · " if node.out_of_fuel else ("LOW FUEL · " if node.fuel_low() else "")
	var lines: PackedStringArray = node.fuel_summary().split("\n")
	return status+(lines[1] if lines.size() > 1 else "")
func update_unit_sections(node: Node3D) -> void:
	var pairs := [["Speed","%.1f" % node.move_speed]]
	if node.vision > 0: pairs.append(["Vision","%.1f" % node.vision])
	var abilities: Array[String] = []
	if node.is_cargo_vehicle or node.is_depot_truck:
		abilities.append("Non-combat vehicle")
	elif node._attack_enabled:
		pairs.insert(1,["Range","%.1f" % node.attack_range])
		pairs.insert(2,["Damage","%d / %.1fs" % [node.attack_damage,node.shot_interval]])
		if node.unit_stats != null:
			var stats: UnitStats = node.unit_stats
			if stats.heavy_target_damage >= 0:
				pairs.append(["Vs buildings","%d / %.1fs" % [stats.heavy_target_damage,stats.heavy_target_interval]])
				pairs.append(["Splash","%.1f" % stats.splash_radius])
			if stats.fire_while_moving: abilities.append("Fires while moving")
			if not stats.has_resolved_attack(): abilities.append("Fallback attack stats")
	else: abilities.append("Attack unavailable · unresolved stats")
	if node.mobility_layer() == MobilityRules.Layer.AIR: abilities.append("Flies on a separate air layer")
	elif node.unit_stats != null and node.unit_stats.mobility != null and node.unit_stats.mobility.clears_forest: abilities.append("Clears forest")
	elif node.mobility_layer() == MobilityRules.Layer.FOREST: abilities.append("Moves through forest")
	var cost_energy: int = node.energy_cost
	var cost_iron: int = node.iron_cost
	if node.is_cargo_vehicle: cost_energy = node.supply_rules.cargo_energy_cost; cost_iron = node.supply_rules.cargo_iron_cost
	elif node.is_depot_truck:
		cost_energy = node.deployment_rules.truck_energy_cost; cost_iron = node.deployment_rules.truck_iron_cost
		pairs.append(["Deploys","%d E · %d I" % [node.deployment_rules.deployed_energy,node.deployment_rules.testing_starting_iron if node.deployment_rules.testing_starting_iron >= 0 else node.deployment_rules.deployed_iron]])
	pairs.append(["Cost","%d E · %d I" % [cost_energy,cost_iron]])
	set_stats(pairs.slice(0,6))
	var line = context.get_node("Abilities")
	line.text = " · ".join(abilities)
	line.visible = not abilities.is_empty()
	if node.is_cargo_vehicle:
		show_storage("Cargo",node.stockpile)
		# A legacy route, or the current crate trip (pickup → delivery), with progress between them.
		var pair: Array = [node.origin_depot,node.destination_depot] if node.route_active and is_instance_valid(node.origin_depot) and is_instance_valid(node.destination_depot) else node.shipment_pair()
		if not pair.is_empty():
			state_label.text = "%s → %s · %s" % [pair[0].name,pair[1].name,("repeating" if node.repeating else "once") if node.route_active else "trips: "+TRIP_LABELS[node.trips]]
			var route = context.get_node("Route")
			route.visible = true
			route.get_node("From").text = str(pair[0].name)
			route.get_node("To").text = str(pair[1].name)
			var to_origin: float = node.global_position.distance_to(pair[0].global_position)
			var to_destination: float = node.global_position.distance_to(pair[1].global_position)
			route.get_node("Bar").max_value = 1.0
			route.get_node("Bar").step = 0.0
			route.get_node("Bar").value = to_origin/maxf(0.001,to_origin+to_destination)
	if node.is_in_group("rail_trains") and node.fuel_active():
		var needed: float = node.estimated_round_trip_fuel()
		if needed > 0:
			var tick: ColorRect = bars.get_node("Fuel/Need")
			tick.visible = true
			var ratio := clampf(needed/node.fuel_rules.reserve_capacity,0,1)
			tick.anchor_left = ratio; tick.anchor_right = ratio
			tick.offset_left = -1; tick.offset_right = 1
			info.get_node("Details").text += "
Round trip needs about %.0f coal" % needed
		if not node.fuel_warning.is_empty():
			info.get_node("Warning").text = node.fuel_warning
			info.get_node("Warning").visible = true
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
			set_alert_style(button,entry.get("kind",""))
			feed_points.append(entry.point)
	for i in feed.get_child_count(): feed.get_child(i).visible = i < feed_points.size()
const ALERT_STYLES := {"attack": ["attack",Color(0.89,0.35,0.31)], "lost": ["cancel",Color(0.89,0.35,0.31)], "fuel": ["refuel",Color(0.941,0.698,0.29)]}
# Feed entries show an icon and colour for their alert kind.
func set_alert_style(button: Button, kind: String) -> void:
	var style: Array = ALERT_STYLES.get(kind,["focus",Color(0.498,0.827,0.902)])
	if not _icons.has(style[0]): _icons[style[0]] = load("res://assets/ui/icons/%s.svg" % style[0])
	button.icon = _icons[style[0]]
	button.add_theme_color_override("icon_normal_color",style[1])
	button.add_theme_color_override("icon_hover_color",style[1])
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
	for bar in bars.get_children(): bar.visible = false
	bars.get_node("Fuel/Need").visible = false
	for section in ["Production","Route","Stats","Abilities"]: context.get_node(section).visible = false
	info.get_node("Storage").visible = false
	shipment_wanted = false
	info.get_node("Warning").visible = false
	state_label.text = ""
	set_icon("")
	var is_unit: bool = is_instance_valid(node) and node.is_in_group("units")
	var show_build: bool = global_build_open or is_instance_valid(node) and build_open and ((is_unit and node.can_construct) or (node.is_in_group("depots") and node.team == "player"))
	build_menu.visible = show_build
	card.visible = not show_build
	update_shipment_target(is_unit and node.is_cargo_vehicle and game.pending_unit_command in ["load","unload"])
	context.get_node("GeneratorMode").visible = not show_build and is_instance_valid(node) and node.is_in_group("energy_generators") and node.team == "player"
	commands.get_node("OptionRow/LocalSource").visible = is_unit and node.can_gather and not show_build
	context.get_node("AssignedSource").visible = not show_build and is_instance_valid(node) and (node.is_in_group("production_buildings") or node.is_in_group("energy_generators")) and node.team == "player"
	if commands.get_node("OptionRow/LocalSource").visible:
		update_local_source(node)
		# The picker only matters when there is a choice of stockpile.
		commands.get_node("OptionRow/LocalSource").visible = local_sources.size() > 1
	if context.get_node("AssignedSource").visible: update_assignment(node)
	hint_label.visible = not show_build
	info.get_node("Health").visible = is_instance_valid(node)
	$Bottom/Body/Header/Focus.disabled = not is_instance_valid(node)
	$Bottom/Body/Header/Message.text = game.outcome if not game.outcome.is_empty() else game.message
	if global_build_open:
		commands.get_node("Title").text = "GLOBAL BUILD · UNPAID PLANS"
		refresh_global_menu()
		info.get_node("Health").visible = false
		name_label.text = "Construction plans"
		info.get_node("HealthText").text = "%d pending" % get_tree().get_nodes_in_group("construction_plans").size()
		info.get_node("Details").text = "Place on valid terrain anywhere.\nPlans wait for one covering Depot\nwith the full local cost.\nClick a plan to inspect or cancel it."
		return
	if is_instance_valid(node) and node.is_in_group("construction_plans"):
		info.get_node("Health").visible = false
		name_label.text = node.spec.title+" plan"
		set_icon("plan")
		info.get_node("HealthText").text = "Unpaid · no resources reserved"
		var payer_text: String = str(node.payer.name) if is_instance_valid(node.payer) else "Unavailable"
		info.get_node("Details").text = "%s\nCost %d E / %d I\nPayer: %s\nDoes not block movement" % [node.state,node.spec.energy,node.spec.iron,payer_text if node.pinned else "Auto covering friendly Depot"]
		commands.get_node("Title").text = "PENDING CONSTRUCTION"
		hint_label.text = "Completes when terrain is clear and one friendly covering Depot can pay. Cancel is free."
		show_button("CancelPlan","Cancel plan")
		return
	if not is_instance_valid(node):
		name_label.text = "Nothing selected"
		info.get_node("HealthText").text = "Select a unit or building"
		info.get_node("Details").text = "Minimap: click to move camera.\nBlue: friendly · red: hostile\nGrey: neutral · gold: resources"
		commands.get_node("Title").text = "COMMAND CARD"
		hint_label.text = "Left-click selects. Drag selects units. Right-click gives orders."
		return
	var units := selected_units()
	name_label.text = object_name(node)+( " · +%d selected" % (units.size()-1) if units.size() > 1 else "")
	info.get_node("Health").max_value = node.max_health
	info.get_node("Health").value = node.health
	info.get_node("HealthText").text = "Health %d / %d" % [node.health,node.max_health]
	set_icon(icon_name(node))
	hint_label.text = ""
	if node.is_in_group("depots"):
		commands.get_node("Title").text = "DEPOT · PRODUCTION"
		state_label.text = "%s · territory %.0f · %+.1f E/s" % [team_label(node),node.rules.construction_radius,node.generation_rate()]
		show_storage("Storage",node.stockpile)
		if node.queue > 0:
			var kind: String = node.pending[0] if not node.pending.is_empty() else ""
			show_progress("Producing · "+DEPOT_PRODUCTS.get(kind,kind.capitalize()),"%d%%%s" % [roundi(node.progress/node.print_seconds*100)," · %d more queued" % (node.queue-1) if node.queue > 1 else ""],node.progress/node.print_seconds)
		info.get_node("Details").text = "Queue %d / %d%s" % [node.queue,node.queue_limit," · capture %d%%" % roundi(node.capture_progress/node.rules.capture_seconds*100) if node.capture_progress > 0 else ""]
		if node.team == "player":
			show_shipment(node.stockpile)
			show_production("PrintTruck","Depot truck",node.rules.truck_energy_cost,node.rules.truck_iron_cost,node)
			show_production("PrintCargo","Cargo vehicle",network.supply_rules.cargo_energy_cost,network.supply_rules.cargo_iron_cost,node)
			var rails = game.get_node("RailNetwork").rules
			show_production("PrintTrain","Train",rails.cargo_energy_cost,rails.cargo_iron_cost,node)
			show_button("Build","Build…")
			hint_label.text = "Spend this Depot only. Train launch/load/unload needs friendly track within %.0f units. New Depots include one infantry." % node.dropoff_range
			if build_open:
				commands.get_node("Title").text = "DEPOT · BUILD & LOCAL RESOURCES"
				refresh_build_menu()
	elif node.is_in_group("mines"):
		commands.get_node("Title").text = "SHARED MINE · IRON EXTRACTION"
		state_label.text = "Shared · any side can gather, repair or destroy"
		show_progress("Iron reserves","%s / %s" % [grouped(node.remaining),grouped(node.amount)],float(node.remaining)/maxi(1,node.amount))
		info.get_node("Details").text = "Shared access · no capture"
		hint_label.text = "Infantry gathers with right-click. Use its Repair card to repair this shared mine, or Attack to destroy it."
	elif node.is_in_group("production_buildings"):
		commands.get_node("Title").text = node.stats.display_name.to_upper()+" · PRODUCTION"
		var payer = node.assigned_depot
		state_label.text = "%s · %s" % [team_label(node),("pays from "+str(payer.name)) if node.source_friendly() else "assigned Depot unavailable"]
		if node.queue > 0 and not node.pending.is_empty():
			show_progress("Producing · "+node.unit_stats_for(node.pending[0]).display_name,"%d%%%s" % [roundi(node.progress/node.stats.print_seconds*100)," · %d more queued" % (node.queue-1) if node.queue > 1 else ""],node.progress/node.stats.print_seconds)
		if is_instance_valid(payer): set_stats([["Energy",grouped(payer.energy)],["Iron",grouped(payer.iron)],["Queue","%d / %d" % [node.queue,node.stats.queue_limit]]])
		info.get_node("Details").text = "Production uses this building's assigned Depot only."
		if node.source_friendly():
			for scene in node.stats.unit_scenes:
				var stats = node.unit_stats_for(scene)
				show_production("PrintInfantry" if stats.unit_id == &"infantry" else "Produce"+str(stats.unit_id).capitalize(),stats.display_name,stats.energy_cost,stats.iron_cost,node.assigned_depot)
		hint_label.text = "Production uses this building’s assigned Depot only. Drone attacks and tentative abilities remain unspecified."
	elif node.is_in_group("energy_generators"):
		commands.get_node("Title").text = "GENERATOR · LOCAL POWER"
		var source = node.assigned_depot
		state_label.text = node.describe_state()
		set_stats([["Output","%.1f E/s" % node.output_rate()],["Burning",str(node.cycle_kind).capitalize() if not node.cycle_kind.is_empty() else "Waiting"],["Cycle","%.1f / %.1fs" % [node.cycle_elapsed,node.cycle_seconds]],["Mode",node.fuel_preference.capitalize()]])
		if is_instance_valid(source): show_storage("%s storage" % source.name,source.stockpile)
		info.get_node("Details").text = "Assigned Depot: %s" % (source.name if is_instance_valid(source) else "none")
		context.get_node("GeneratorMode").select(["wood","coal","either"].find(node.fuel_preference))
		hint_label.text = "Wood: 1 → %d E / %.1fs. Coal: 1 → %d E / %.1fs. Either uses wood first. Changes apply next cycle; full storage pauses fuel use." % [node.fuel_rules.wood_output,node.fuel_rules.wood_seconds,node.fuel_rules.coal_output,node.fuel_rules.coal_seconds]
		if node.team == "player": show_button("ToggleGenerator","Pause" if node.enabled else "Resume")
		if is_instance_valid(node.assigned_depot): show_button("FocusAssigned","Focus Depot")
	else:
		var nearest = nearest_depot(node)
		state_label.text = "%s · %s%s" % [team_label(node),node.state," · %d queued" % node.order_queue.size() if not node.order_queue.is_empty() else ""]
		var notes: Array[String] = []
		notes.append("Nearest Depot: %s · %.1f units away" % [nearest.name,node.global_position.distance_to(nearest.global_position)] if nearest != null else "No friendly Depot")
		if node.fuel_rules != null: notes.append(fuel_note(node))
		if node.can_gather and is_instance_valid(node.supply_payer): notes.append("Pays from and delivers to %s" % node.supply_payer.name)
		info.get_node("Details").text = "\n".join(notes)
		commands.get_node("Title").text = "UNIT · ORDERS"
		update_bars(node)
		update_unit_sections(node)
		show_button("Move","Move")
		show_button("Stop","Stop")
		if node.fuel_active():
			show_button("ToggleRefuel","Auto-refuel: %s" % ("on" if node.auto_refuel else "off"))
			if node.auto_refuel: card.get_node("ToggleRefuel").remove_theme_color_override("icon_normal_color")
			else: card.get_node("ToggleRefuel").add_theme_color_override("icon_normal_color",OFF_ICON)
		if node.is_cargo_vehicle:
			show_button("DeployCargo","Pack up supplies" if node.deployed else "Deploy supplies")
			explain(card.get_node("DeployCargo"),not node.supply_transition.is_empty(),"Wait for deploying or packing to finish.")
			show_button("Load","Load crates")
			show_button("Unload","Unload crates")
			show_button("Trips","Trips: %s" % TRIP_LABELS[node.trips])
			if node.supplies_available() and node.team == "player": show_shipment(node.stockpile)
			hint_label.text = "Right-click a Depot to unload crates, or to load when empty. Shift queues stops. Trips: %s." % TRIP_LABELS[node.trips]
		elif node.is_depot_truck:
			show_button("DeployTruck","Deploy")
			hint_label.text = "Deploy on an empty 8 × 8 footprint. This vehicle does not carry transferable cargo."
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
			hint_label.text = "Right-click to move, gather or attack. Nearest Depot distance is straight-line, not route length."
			if build_open and node.can_construct:
				commands.get_node("Title").text = "INFANTRY · BUILD & LOCAL RESOURCES"
				refresh_build_menu()
func show_button(id: String, text: String) -> void:
	desired_buttons.append(id)
	set_tile(card.get_node(id),text,str(card.get_node(id).get_meta("detail","")))
# Icon-only tile: the label and detail go to the tooltip and the hover line.
func set_tile(button: Button, label: String, detail: String) -> void:
	button.set_meta("label",label)
	if not button.text.is_empty(): button.text = ""
	var key := hotkey_text(button)
	var tip := label+(" [%s]" % key if not key.is_empty() else "")+("\n"+detail if not detail.is_empty() else "")
	if button.tooltip_text != tip: button.tooltip_text = tip
func label_of(button: Button) -> String:
	return str(button.get_meta("label",button.text))
func place_tiles() -> void:
	for button in card.get_children():
		if button is Button and button.visible and SLOTS.has(str(button.name)):
			var slot: int = SLOTS[str(button.name)]
			button.position = Vector2((slot%4)*(TILE+TILE_GAP),(slot/4)*(TILE+TILE_GAP))
			button.size = Vector2(TILE,TILE)
# Under the grid: the hovered tile, or the armed command, with its key and hint.
func update_hover_line() -> void:
	var hovered := get_viewport().gui_get_hovered_control()
	var text := ""
	if hovered is Button and (card.is_ancestor_of(hovered) or build_menu.is_ancestor_of(hovered)) and hovered.has_meta("label"):
		text = hovered.tooltip_text
	elif not game.pending_unit_command.is_empty():
		text = "%s · click a target. Shift queues, Esc cancels." % game.pending_unit_command.capitalize()
	# One line only: the label's height is fixed so hovering never moves the HUD.
	text = text.replace("
"," · ")
	if hover_label.text != text: hover_label.text = text
# Set a label with its hotkey; unchanged text isn't reassigned, so buttons don't relayout each frame.
# Unchanged text isn't reassigned, so buttons don't relayout every frame.
func set_label(button: Button, text: String) -> void:
	if button.text != text: button.text = text
# Production tiles: name over cost. Unaffordable costs turn amber and the tooltip says what's missing.
func show_production(id: String, title: String, energy_cost: int, iron_cost: int, payer: Node) -> void:
	desired_buttons.append(id)
	var button: Button = card.get_node(id)
	var missing := []
	if is_instance_valid(payer):
		if payer.energy < energy_cost: missing.append("%d more energy" % (energy_cost-payer.energy))
		if payer.iron < iron_cost: missing.append("%d more iron" % (iron_cost-payer.iron))
	if missing.is_empty():
		button.remove_theme_color_override("icon_normal_color")
		set_tile(button,title,"%d E · %d I · from %s" % [energy_cost,iron_cost,payer.name if is_instance_valid(payer) else "the paying Depot"])
	else:
		button.add_theme_color_override("icon_normal_color",UNAFFORDABLE)
		set_tile(button,title,"%d E · %d I · needs %s" % [energy_cost,iron_cost," and ".join(missing)])
# Disabled actions stay visible and explain why.
func explain(button: Button, disabled: bool, reason: String) -> void:
	button.disabled = disabled
	if button.has_meta("label"): set_tile(button,label_of(button),reason if disabled else str(button.get_meta("detail","")))
	elif disabled: button.tooltip_text = reason
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
	set_tile(build_menu.get_node("Actions/Mine"),"Iron mine","%d E · %d I" % [network.engineering_rules.mine_energy_cost,network.engineering_rules.mine_iron_cost])
	build_menu.get_node("Actions/Rail").disabled = not valid or not payer.is_in_group("depots")
	var rails = game.get_node("RailNetwork").rules
	set_tile(build_menu.get_node("Actions/Rail"),"Rail tile","%d E · %d I" % [rails.rail_energy_cost,rails.rail_iron_cost])
	if valid:
		set_tile(build_menu.get_node("Actions/Depot"),"Depot","%d E · %d I" % [network.depot_rules().depot_energy_cost,network.depot_rules().depot_iron_cost])
		set_tile(build_menu.get_node("Actions/Generator"),"Generator","%d E · %d I" % [network.supply_rules.generator_energy_cost,network.supply_rules.generator_iron_cost])
		for pair in [[&"barracks","Barracks"],[&"tank_factory","TankFactory"]]:
			var preview = network.production_scene(pair[0]).instantiate()
			set_tile(build_menu.get_node("Actions/"+pair[1]),preview.stats.display_name,"%d E · %d I" % [preview.stats.energy_cost,preview.stats.iron_cost])
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
# Prepare shipment: crates per resource at the selected Depot or deployed Cargo vehicle.
func shipment_stockpile() -> ResourceStockpile:
	var node = selected_object()
	if not is_instance_valid(node) or node.get("team") != "player": return null
	if node.is_in_group("depots") or (node.get("is_cargo_vehicle") == true and node.supplies_available()): return node.stockpile
	return null
func show_shipment(stockpile: ResourceStockpile) -> void:
	shipment_wanted = true
	shipment.get_node("Head/Value").text = "%d crate%s · %d each" % [stockpile.crate_count(),"" if stockpile.crate_count() == 1 else "s",ResourceStockpile.CRATE]
	for kind in RESOURCE_KINDS:
		var row = shipment.get_node("Rows/"+str(kind).capitalize())
		row.get_node("Count").text = "%s %d" % [str(kind).capitalize(),stockpile.crate_count(kind)]
		row.get_node("Plus").disabled = stockpile.available(kind) < ResourceStockpile.CRATE
		row.get_node("Minus").disabled = stockpile.crate_count(kind) == 0
	shipment.get_node("KeepStocked").set_pressed_no_signal(stockpile.keep_stocked)
func change_crates(kind: StringName, delta: int) -> void:
	var stockpile := shipment_stockpile()
	if stockpile == null: return
	var changed: bool = stockpile.pack(kind) if delta > 0 else stockpile.unpack(kind)
	if changed and stockpile.keep_stocked: stockpile.set_target(kind,stockpile.crate_count(kind))
	if not changed: game.notify("Needs %d loose %s for a crate." % [ResourceStockpile.CRATE,kind] if delta > 0 else "No %s crate to unpack." % kind)
# Distant stops for an armed Load or Unload: every friendly Depot, plus deployed trucks for trucks.
func update_shipment_target(armed: bool) -> void:
	shipment_target.visible = armed
	if not armed: return
	var vehicle = selected_cargo()
	var stops: Array[Node3D] = []
	var signature := ""
	for group in ["depots","mobile_supplies"]:
		for node in get_tree().get_nodes_in_group(group):
			if vehicle.shipment_endpoint(node): stops.append(node); signature += str(node.get_instance_id())+":"
	if signature != shipment_signature:
		shipment_signature = signature
		shipment_target.clear()
		shipment_target.add_item("%s at a distant stop…" % game.pending_unit_command.capitalize())
		for stop in stops: shipment_target.add_item("%s · %d crates · %d space" % [stop.name,stop.stockpile.crate_count(),stop.stockpile.space()])
		shipment_target.select(0)
	shipment_stops = stops
func order_shipment_stop(index: int) -> void:
	if index <= 0 or index > shipment_stops.size(): return
	var stop: Node3D = shipment_stops[index-1]
	var queued := Input.is_key_pressed(KEY_SHIFT)
	for unit in selected_units():
		if unit.is_cargo_vehicle: game.give_order(unit,{kind = game.pending_unit_command, target = stop},queued)
	game.notify("%s at %s %s." % [game.pending_unit_command.capitalize(),stop.name,"queued" if queued else "ordered"])
	if not queued: game.pending_unit_command = ""
	shipment_signature = ""
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
	var option: OptionButton = commands.get_node("OptionRow/LocalSource")
	var signature := str(unit.get_instance_id())+":"
	for source in candidates: signature += str(source.get_instance_id())+":"
	if signature != local_signature:
		local_signature = signature; option.clear()
		for source in candidates: option.add_item(str(source.name))
	local_sources = candidates
	for i in range(candidates.size()):
		var source = candidates[i]
		option.set_item_text(i,"Pay from, deliver to: %s · E%d I%d" % [source.name,source.energy,source.iron])
	var index := candidates.find(unit.supply_payer) if is_instance_valid(unit.supply_payer) else -1
	if not unit.supply_payer_explicit and not candidates.is_empty():
		index = 0; unit.supply_payer = candidates[0]; unit.supply_payer_explicit = true
		unit.return_depot = candidates[0]; unit.return_explicit = true
	option.select(index)
	option.text = "Selected supply unavailable · choose source" if index < 0 else option.get_item_text(index)
	option.tooltip_text = "Which stockpile this unit pays from for building and repair, and delivers gathered materials to. Shown when more than one is in range."
func update_assignment(building: Node3D) -> void:
	var candidates: Array[Node3D] = []
	for depot in get_tree().get_nodes_in_group("depots"):
		if SupplySource.covers(depot,building.global_position,building.team): candidates.append(depot)
	var option: OptionButton = context.get_node("AssignedSource")
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
		set_tile(button,spec.title,"%d E · %d I · plan, paid when built" % [spec.energy,spec.iron])
