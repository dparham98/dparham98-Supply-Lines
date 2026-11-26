extends CanvasLayer
@onready var game = get_parent()
@onready var network = game.get_node("DepotNetwork")
@onready var commands = $Bottom/Body/Row/Commands
@onready var card = $Bottom/Body/Row/Commands/Main
@onready var info = $Bottom/Body/Row/Info
@onready var build_menu = $Bottom/Body/Row/Commands/BuildMenu
@onready var bars = $Bottom/Body/Row/Info/Bars
@onready var feed = $Feed
## One portrait per selected unit while more than one is selected (docs/SELECTION_PORTRAITS.md).
@onready var portraits = $Bottom/Body/Row/Info/Portraits
var portrait_units: Array[Node3D] = []
## Top left: the energy banking rate and the Generator settings of the Depot in context. Top right: its
## storage. Both show while your Depot, or a building in its range, is selected (docs/DEPOT_PANELS.md).
@onready var depot_panel = $DepotPanel
@onready var storage_panel = $StoragePanel
var panel_depot: Node3D
## Under the Depot panel: the selected production building's power (docs/PRODUCTION_POWER.md).
@onready var production_panel = $ProductionPanel
var panel_building: Node3D
const FEED_TOP := 44.0
const PANEL_GAP := 8.0
@onready var name_label: Label = $Bottom/Body/Row/Info/Head/Text/Name
@onready var context = $Bottom/Body/Row/Context
@onready var manifest_panel = $Bottom/Body/Row/Context/Manifest
## Replaces the card while Load, Unload or Pin waits for a stop picked on the map or minimap.
@onready var pick = $Bottom/Body/Row/Commands/Pick
@onready var load_tiles = $Bottom/Body/Row/Commands/Pick/LoadTiles
## The selection's hint, shown as a tooltip over the Info and Context columns rather than taking HUD space.
var hint_text := ""
## Hints are drawn by $Tip inside this layer after TIP_DELAY over a control with tooltip text. Godot's own
## tooltip is a popup window, and one opening between a press and its release swallows the click, so the
## project's tooltip delay is set so high that it never opens.
const TIP_DELAY := 0.25
const TIP_WIDTH := 260.0
var tip_delay := TIP_DELAY
var _tip_control: Control
var _tip_since := 0.0
## Fixed command slots, row-major in the 4 × 3 grid. Commands that never share a card may share a slot.
const SLOTS := {"Move": 0, "Stop": 1, "Attack": 2, "ToggleRefuel": 3, "Gather": 4, "Return": 5, "DropMaterials": 6, "Build": 7,
	"BurnWood": 4, "BurnCoal": 5, "BurnEither": 6, "MakeCrates": 3, "Worksite": 7,
	"Mist": 4, "Slow": 5,
	"Repair": 8, "Heal": 8, "Derail": 8, "Capture": 9, "LayMine": 9, "BuyMine": 10, "DeployTruck": 10, "Fell": 10, "CancelPlan": 11,
	"DeployCargo": 2, "Load": 4, "Unload": 5, "Trips": 6,
	"PrintTruck": 0, "PrintCargo": 1, "PrintTrain": 2,
	"TrainForester": 0, "TrainWarhound": 1, "LaunchBalloon": 2,
	"PrintInfantry": 0, "ProduceScout": 1, "ProduceGrenadier": 2, "ProduceTank": 3, "ProduceMotorcycle": 4, "ProduceDrone": 5, "ProduceUbermech": 6,
	"ProduceRoundTableMarine": 0, "ProduceGrailSentinel": 1, "ProduceQuestingMarine": 2, "ProduceAzureDragon": 3,
	"ToggleGenerator": 0, "FocusAssigned": 1,
	"Research": 0, "ResearchMines": 1, "MineIron": 7,
	"Upgrade1": 0, "Upgrade2": 1, "Upgrade3": 2, "Upgrade4": 3}
const TILE := 46
const TRIP_LABELS := {"once": "once", "all": "all available", "repeat": "repeat"}
## One icon per stat row (assets/ui/icons).
const STAT_ICONS := {"Speed": "speed", "Range": "focus", "Damage": "damage", "Vision": "scout", "Vs armour": "depot", "Splash": "splash",
	"Cost": "cost", "Deploys": "deploy", "Output": "generator", "Burning": "refuel", "Cycle": "cycle", "Mode": "mode",
	"Energy": "generator", "Food": "crate", "Iron": "mine", "Queue": "queue", "Fuel left": "cargo", "Energy ceiling": "generator", "Coal kept": "refuel",
	"Housing": "depot", "Food a beat": "crate", "Workers": "queue"}
const TILE_GAP := 4
@onready var state_label: Label = $Bottom/Body/Row/Info/Head/Text/State
const RESOURCE_KINDS := [&"energy",&"iron",&"wood",&"coal",&"food"]
const UNIT_BUTTONS := {
	&"infantry": "PrintInfantry",
	&"scout": "ProduceScout",
	&"grenadier": "ProduceGrenadier",
	&"tank": "ProduceTank",
	&"motorcycle": "ProduceMotorcycle",
	&"drone": "ProduceDrone",
	&"ubermech": "ProduceUbermech",
	&"round_table_marine": "ProduceRoundTableMarine",
	&"grail_sentinel": "ProduceGrailSentinel",
	&"questing_marine": "ProduceQuestingMarine",
	&"azure_dragon": "ProduceAzureDragon",
}
const ARTHURIAN_UNIT_IDS := [&"forester_maiden",&"warhound",&"round_table_marine",&"grail_sentinel",&"questing_marine",&"azure_dragon"]
func production_button_id(unit_id: StringName) -> String:
	return UNIT_BUTTONS.get(unit_id, "Produce"+str(unit_id).capitalize())
func has_arthurian_faction() -> bool:
	if not is_inside_tree(): return false
	for node in get_tree().get_nodes_in_group("keeps"):
		if node.get("team") == "player": return true
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.get("team") == "player" and unit.get("unit_stats") != null and unit.unit_stats.unit_id in ARTHURIAN_UNIT_IDS: return true
	return false
## Build-page buildings only the Cyborgs see; Keep and Chapterhouse are the Knights'. Mines are for both.
const CYBORG_BUILDINGS := [&"depot",&"generator",&"barracks",&"tank_factory",&"temple_of_science",&"foundry",&"rail"]
const KNIGHT_BUILDINGS := [&"keep",&"chapterhouse",&"farm",&"house",&"forge"]
## True when the player builds as the Cyborgs: the match setup's faction, or, in a scene run straight from the
## editor or a test, any Depot of the player's that is not a Keep, or no Knights presence at all.
func has_cyborg_faction() -> bool:
	var setup = get_node_or_null("/root/MatchSetup")
	if setup != null and setup.configured: return setup.factions.get("player",&"cyborgs") == &"cyborgs"
	if not is_inside_tree(): return true
	for node in get_tree().get_nodes_in_group("depots"):
		if node.get("team") == "player" and not node.is_in_group("keeps"): return true
	return not has_arthurian_faction()
## Whether the player's Build page offers this building kind.
func build_kind_offered(kind: StringName) -> bool:
	if kind in CYBORG_BUILDINGS: return has_cyborg_faction()
	if kind in KNIGHT_BUILDINGS: return knights_build()
	return true
## True when the player builds as the Knights (see has_cyborg_faction).
func knights_build() -> bool:
	var setup = get_node_or_null("/root/MatchSetup")
	if setup != null and setup.configured: return setup.factions.get("player",&"cyborgs") == &"arthurian_knights"
	return has_arthurian_faction()
var _icons := {}
# Cargo vehicles open on their delivery route page; Orders shows the ordinary command card.
var feed_points: Array[Vector3] = []
## Darkens a whole-card image that cannot be paid for yet. The card keeps its own colours.
const UNAFFORDABLE := Color(0.5,0.42,0.4)
## Darkens the fuel choices that are not the current one.
const UNSELECTED := Color(0.5,0.46,0.44)
## Warnings (the alert feed and the header message) show for FEED_SECONDS, then fade out over FEED_FADE_SECONDS
## (docs/HUD_POLISH.md). Nothing needs closing by hand.
const FEED_SECONDS := 3.0
const FEED_FADE_SECONDS := 0.6
## How visible a warning `age` seconds old is: 1 while it shows, falling to 0 as it fades.
static func warning_alpha(age: float) -> float:
	return clampf((FEED_SECONDS+FEED_FADE_SECONDS-age)/FEED_FADE_SECONDS,0.0,1.0)
## The build page holds global, unpaid plans only; Infantry and Depots have no build menus of their own.
var global_build_open := false
## The build page opened from a truck's Worksite tile (docs/TRUCK_WORKSITES.md).
var worksite_open := false
## The Depot's Make crates page, which reuses the Load page's resource tiles.
var crate_page_open := false
## Pin: new plans pay only from this stockpile. Unpinned plans pay from the nearest covering one able to pay.
var global_payer: Node3D
var global_pinned := false
var shown: Node3D
var desired_buttons: Array[String] = []
func _ready() -> void:
	$Bottom/Body/Header/GlobalBuild.pressed.connect(open_global_build)
	for i in portraits.get_child_count():
		portraits.get_child(i).pressed.connect(pick_portrait.bind(i))
	for i in feed.get_child_count():
		feed.get_child(i).pressed.connect(focus_alert.bind(i))
	card.get_node("CancelPlan").pressed.connect(func():
		if is_instance_valid(shown) and shown.is_in_group("construction_plans"): shown.cancel()
		elif is_instance_valid(shown) and shown.is_in_group("research_buildings"): shown.cancel_research()
		elif is_instance_valid(shown) and shown.is_in_group("depots"): shown.cancel_current())
	card.get_node("ToggleRefuel").pressed.connect(toggle_refuel)
	# Supply panel buttons with fixed text get their key label once.
	for button in card.get_children():
		if button is Button: button.set_meta("detail",button.tooltip_text)
	# Each bound button shows its key in a corner badge; tooltips also list it.
	for panel in [card,build_menu.get_node("Actions"),pick,load_tiles]:
		for button in panel.get_children():
			if button is Button and button.has_node("Key"): button.get_node("Key").text = hotkey_text(button)
			# Tooltips already name the key; Godot's own "(A - Physical)" line would repeat it.
			if button is Button: button.shortcut_in_tooltip = false
	# Header buttons are text buttons: their key goes in the label.
	for id in ["GlobalBuild","Focus"]:
		var header: Button = $Bottom/Body/Header.get_node(id)
		if not hotkey_text(header).is_empty(): header.text += " · "+hotkey_text(header)
		header.shortcut_in_tooltip = false
	card.get_node("ToggleGenerator").pressed.connect(func():
		if is_instance_valid(shown) and shown.is_in_group("energy_generators"):
			var on: bool = not shown.enabled
			for node in same_buildings(): node.enabled = on)
	card.get_node("DeployCargo").pressed.connect(func():
		var vehicle = selected_cargo()
		if vehicle:
			if vehicle.deployed: vehicle.pack_supplies()
			elif not vehicle.deploy_supplies(): game.notify("Cannot deploy supplies here or during another transition."))
	for mode in ["load","unload"]:
		card.get_node(mode.capitalize()).pressed.connect(func(): game.pending_unit_command = mode; game.notify("%s: choose a stop on the map or minimap." % mode.capitalize()))
	pick.get_node("Cancel").pressed.connect(func(): game.cancel_armed(); game.notify("Command cancelled."))
	card.get_node("Trips").pressed.connect(func():
		var vehicle = selected_cargo()
		if vehicle:
			var mode: String = vehicle.cycle_trips()
			for unit in selected_units():
				if unit.is_cargo_vehicle: unit.trips = mode
			game.notify("Trips: %s." % TRIP_LABELS[mode]))
	for pair in [["Iron",&"iron"],["Energy",&"energy"],["Wood",&"wood"],["Coal",&"coal"],["Food",&"food"]]:
		load_tiles.get_node(pair[0]).pressed.connect(func():
			if crate_page_open: make_crates(pair[1],Input.is_key_pressed(KEY_SHIFT))
			else: edit_manifest(pair[1],Input.is_key_pressed(KEY_SHIFT)))
		# Right-click takes a crate off the manifest; Shift+right-click takes all of that resource off.
		load_tiles.get_node(pair[0]).gui_input.connect(func(event: InputEvent):
			if crate_page_open or not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_RIGHT or not event.pressed: return
			lower_manifest(pair[1],event.shift_pressed)
			load_tiles.get_node(pair[0]).accept_event())
	load_tiles.get_node("Clear").pressed.connect(clear_manifest)
	card.get_node("MakeCrates").pressed.connect(open_crate_page)
	depot_panel.get_node("Body/CeilingSlider").value_changed.connect(func(value: float):
		if is_instance_valid(panel_depot): panel_depot.set_energy_ceiling(value))
	depot_panel.get_node("Body/CoalSlider").value_changed.connect(func(value: float):
		if is_instance_valid(panel_depot): panel_depot.set_coal_reserve(value))
	production_panel.get_node("Body/PowerSlider").value_changed.connect(func(value: float):
		if is_instance_valid(panel_building):
			for node in same_buildings(): node.set_power(value))
	card.get_node("Worksite").pressed.connect(open_worksite)
	for pair in [["BurnWood","wood"],["BurnCoal","coal"],["BurnEither","either"]]:
		card.get_node(pair[0]).pressed.connect(func():
			if is_instance_valid(shown) and shown.is_in_group("energy_generators"):
				for node in same_buildings(): node.set_fuel_preference(pair[1]))
	card.get_node("DropMaterials").pressed.connect(func():
		for unit in selected_units():
			if unit.can_gather and unit.cargo > 0:
				unit.order_queue.clear()
				unit._stop_route(); unit.order = "idle"; unit.source = null
				game.drop_material(unit)
		game.notify("Materials dropped. Any Deforester can gather the pile before spending it."))
	for mode in ["move","attack","gather","fell","repair","heal","capture","derail"]:
		card.get_node(mode.capitalize()).pressed.connect(func(): game.pending_unit_command = mode; game.notify("Click a target for %s. Esc cancels." % mode))
	card.get_node("Stop").pressed.connect(stop_units)
	# Lay mine (docs/MINES.md): arms a click on the map for the selected Derailers that carry mines.
	card.get_node("LayMine").pressed.connect(func():
		var layers := selected_units().filter(func(u): return u.has_method("lay_mine_blocker") and u.lay_mine_blocker().is_empty())
		if layers.is_empty():
			var first = selected_units().front() if not selected_units().is_empty() else null
			game.notify(first.lay_mine_blocker() if first != null and first.has_method("lay_mine_blocker") else "Select a Derailer carrying mines.")
			return
		game.pending_unit_command = "lay_mine"
		game.notify("Lay mine: click where the Derailer should lay it. Esc cancels."))
	# Buy mine (docs/MINES.md): each selected Derailer that can buys one.
	card.get_node("BuyMine").pressed.connect(func():
		var bought := 0
		for unit in selected_units():
			if unit.has_method("command_buy_mine") and unit.command_buy_mine(): bought += 1
		if bought > 0: game.notify("%d mine%s bought." % [bought,"" if bought == 1 else "s"])
		else:
			var first = selected_units().front() if not selected_units().is_empty() else null
			game.notify(first.buy_mine_blocker() if first != null and first.has_method("buy_mine_blocker") else "Select a Derailer."))
	# Right-click on the Fell card switches autocast (docs/FELL.md).
	card.get_node("Fell").gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			toggle_fell_autocast()
			card.get_node("Fell").accept_event())
	card.get_node("Return").pressed.connect(return_units)
	card.get_node("PrintInfantry").pressed.connect(func():
		if is_instance_valid(shown) and shown.is_in_group("production_buildings"): least_busy().request_unit(&"infantry"))
	card.get_node("PrintTruck").pressed.connect(func():
		if network.owned_selected() and not least_busy().request_truck(): game.notify("Depot lacks local funds or queue space."))
	card.get_node("PrintTrain").pressed.connect(queue_train)
	# The Temple of Science's research (docs/TEMPLE_OF_SCIENCE.md) and the Mining Trains order it unlocks.
	card.get_node("Research").pressed.connect(func():
		if is_instance_valid(shown) and shown.is_in_group("research_buildings"): shown.request_research(Research.MINING_TRAINS))
	card.get_node("ResearchMines").pressed.connect(func():
		if is_instance_valid(shown) and shown.is_in_group("research_buildings"): shown.request_research(Research.MINELAYING))
	# The Foundry's and Forge's upgrade lines (docs/UPGRADES.md): each tile asks for its line's next level.
	for n in range(1,5):
		var tile: Button = card.get_node("Upgrade%d" % n)
		tile.pressed.connect(func():
			if is_instance_valid(shown) and shown.is_in_group("research_buildings") and tile.has_meta("research"): shown.request_research(tile.get_meta("research")))
	# The Grail Sentinel's Mist and Slow (docs/MIST_AND_SLOW.md): click a point; a Sentinel walks within range and casts.
	card.get_node("Mist").pressed.connect(func(): game.pending_unit_command = "mist"; game.notify("Mist: click a point. Units in the 8 m cloud are hidden from anyone more than 8 m away for 8 s. Esc cancels."))
	card.get_node("Slow").pressed.connect(func(): game.pending_unit_command = "slow"; game.notify("Slow: click a point. Enemy units within 5 m move 40% slower for 5 s. Esc cancels."))
	card.get_node("MineIron").pressed.connect(func(): game.pending_unit_command = "mine_rail"; game.notify("Mine iron: click an Iron Mine joined to this train's track. Esc cancels."))
	card.get_node("PrintCargo").pressed.connect(func():
		if network.owned_selected() and not least_busy().request_cargo(): game.notify("Depot lacks local funds or queue space."))
	card.get_node("TrainForester").pressed.connect(func():
		if is_instance_valid(shown) and shown.is_in_group("keeps") and shown.team == "player":
			if not least_busy().request_forester(): game.notify("Keep lacks Food or queue space."))
	# Launch balloon (docs/AIR_BALLOON.md): arms a click on the map for the selected Keep's balloon.
	card.get_node("LaunchBalloon").pressed.connect(func():
		if not is_instance_valid(shown) or not shown.is_in_group("keeps") or shown.team != "player": return
		var refusal: String = shown.balloon_refusal()
		if not refusal.is_empty(): game.notify(refusal); return
		game.pending_unit_command = "launch_balloon"
		game.notify("Launch balloon: click where %s should set its crates down. Esc cancels." % shown.name))
	card.get_node("TrainWarhound").pressed.connect(func():
		if is_instance_valid(shown) and shown.is_in_group("keeps") and shown.team == "player":
			if not least_busy().request_warhound(): game.notify("Keep lacks Food, Iron or queue space."))
	for id in ["scout","grenadier","tank","motorcycle","drone","ubermech","round_table_marine","grail_sentinel","questing_marine","azure_dragon"]:
		var btn_id := production_button_id(StringName(id))
		card.get_node(btn_id).pressed.connect(func():
			if is_instance_valid(shown) and shown.is_in_group("production_buildings"): least_busy().request_unit(StringName(id)))
	for pair in [["Depot",&"depot"],["Generator",&"generator"],["Barracks",&"barracks"],["TankFactory",&"tank_factory"],["Temple",&"temple_of_science"],["Foundry",&"foundry"],["Mine",&"iron_mine"],["CoalMine",&"coal_mine"],["Rail",&"rail"],["Keep",&"keep"],["Chapterhouse",&"chapterhouse"],["Farm",&"farm"],["House",&"house"],["Forge",&"forge"]]:
		build_menu.get_node("Actions/"+pair[0]).pressed.connect(begin_global_placement.bind(pair[1]))
	build_menu.get_node("Actions/Pin").pressed.connect(toggle_pin)
	card.get_node("DeployTruck").pressed.connect(func(): game.pending_unit_command = "deploy"; game.notify("Click a site for the Depot. Only an empty Depot footprint is accepted; Shift queues."))
	card.get_node("FocusAssigned").pressed.connect(func():
		if is_instance_valid(shown) and is_instance_valid(shown.assigned_depot): game.get_node("CameraRig").focus_position(shown.assigned_depot.global_position))
	build_menu.get_node("Actions/Back").pressed.connect(func(): game.cancel_armed(); close_build())
	$Bottom/Body/Header/Focus.pressed.connect(func():
		if is_instance_valid(shown): game.get_node("CameraRig").focus_position(shown.global_position))
	$Bottom/Body/Header/Restart.pressed.connect(func(): get_tree().reload_current_scene())
	$Bottom/Body/Header/Menu.pressed.connect(func(): $PauseMenu.open())
func toggle_refuel() -> void:
	if not is_instance_valid(shown) or not shown.is_in_group("units"): return
	var enable: bool = not shown.auto_refuel
	for unit in selected_units():
		if unit.fuel_active(): unit.auto_refuel = enable
func selected_units() -> Array[Node3D]:
	return get_node("/root/SelectionManager").selected_units()
func selected_object() -> Node3D:
	var units := selected_units()
	# The primary unit (Tab steps it through the types, docs/HUD_HOTKEYS.md).
	if not units.is_empty(): return get_node("/root/SelectionManager").primary_of(units)
	var node = game.selected_building
	if not is_instance_valid(node) or not node.is_inside_tree(): return null
	# An enemy unit is shown read-only (docs/SELECTION_INSPECT.md).
	if node.is_in_group("units"): return node if node.team != "player" and node.health > 0 else null
	# So is a Forest or Coal tile, until it is cut or dug out (docs/CURSORS.md).
	if node.is_in_group("forest_cells") or node.is_in_group("coal_cells"): return node if node.remaining > 0 else null
	# A land mine, while it lies there and the viewer sees it (docs/MINES.md).
	if node.is_in_group("land_mines"): return node if node.health > 0 and node.is_visible_in_tree() else null
	return node if node.is_in_group("selectable_buildings") or node.is_in_group("construction_plans") else null
## Your selected buildings of the shown building's type (docs/SELECTION_INSPECT.md), the shown one first.
func same_buildings() -> Array[Node3D]:
	var nodes: Array[Node3D] = []
	if not is_instance_valid(shown): return nodes
	nodes.append(shown)
	if shown.get("team") != "player": return nodes
	for node in game.building_selection():
		if node != shown and node.get("team") == "player" and node.scene_file_path == shown.scene_file_path: nodes.append(node)
	return nodes
## Of those, the one whose production queue is shortest (the shown one on a tie): orders from the card go there,
## so several buildings share the work. Only buildings that can pay from a friendly Depot count.
func least_busy() -> Node3D:
	var best: Node3D = shown
	for node in same_buildings():
		if node.has_method("source_friendly") and not node.source_friendly(): continue
		if best.has_method("source_friendly") and not best.source_friendly(): best = node; continue
		if node.queue < best.queue: best = node
	return best
func selected_cargo() -> Node3D:
	var node = selected_object()
	return node if is_instance_valid(node) and node.is_in_group("units") and node.is_cargo_vehicle else null
func object_name(node: Node3D) -> String:
	if node.is_in_group("mines"): return "Coal Mine" if node.get("on_coal") == true else "Iron Mine"
	if node.is_in_group("production_buildings"): return node.stats.display_name
	if node.is_in_group("keeps"): return "Keep" if node.name == "Keep" else "%s · Keep" % node.name
	if node.is_in_group("depots"): return "Depot" if node.name == "Depot" else "%s · Depot" % node.name
	if node.is_in_group("energy_generators"): return "%s · Generator" % node.name
	if node.is_in_group("rail_trains"): return "Train"
	if node.is_in_group("farms"): return "Farm" if node.name == "Farm" else "%s · Farm" % node.name
	if node.is_in_group("houses"): return "House" if node.name == "House" else "%s · House" % node.name
	if node.is_cargo_vehicle: return "Cargo Vehicle"
	if node.is_depot_truck: return "Depot Truck"
	if node.get("farmer") == true: return "Farmer"
	return node.unit_stats.display_name if node.unit_stats != null else "Deforester"
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
	# A Fell box (docs/FELL.md) shows in the same outline.
	if game.fell_dragging and game.fell_drag_from.distance_to(game.fell_drag_to) >= game.FELL_DRAG:
		$SelectionBox.visible = true
		rect = Rect2(game.fell_drag_from,game.fell_drag_to-game.fell_drag_from).abs()
	$SelectionBox.position = rect.position
	$SelectionBox.size = rect.size
	desired_buttons.clear()
	update_contents()
	var units := selected_units()
	if units.size() > 1 and not global_build_open:
		commands.get_node("Title").text = "%d FRIENDLY UNITS SELECTED" % units.size()
		hint_text = "Right-click moves the group. Commands apply where each unit supports them; the card and stats show the outlined unit. Click a portrait to select only that unit, Shift-click to remove it. Ctrl-click keeps only that type, Ctrl+Shift-click removes that type. Tab and Shift+Tab step the card through the types."
	var group: Array[Node3D] = []
	if units.is_empty() and not global_build_open: group = same_buildings()
	if group.size() > 1:
		commands.get_node("Title").text = "%d %s SELECTED" % [group.size(),object_name(group[0]).to_upper()]
		hint_text = "Production goes to the selected building with the shortest queue. Power, rally points and generator settings apply to all of them. Click a portrait to keep only that building, Shift-click to remove it. Double-click a building selects your others of its type on screen; Shift-click adds or removes one."
		update_portraits(group)
	else: update_portraits(units)
	# A spectator only inspects (docs/MAIN_MENU.md): no commands, no Build page.
	if game.spectating:
		desired_buttons.clear()
		hint_text = "Spectating: click anything to inspect it. Esc opens the menu."
	$Bottom/Body/Header/GlobalBuild.visible = not game.spectating
	# Apply final visibility once. Hiding a pressed button cancels its GUI gesture.
	for button in card.get_children():
		if button is Button: button.visible = desired_buttons.has(str(button.name))
	for column in [info,context]:
		if column.tooltip_text != hint_text: column.tooltip_text = hint_text
	var prompt := pick_prompt()
	pick.visible = not prompt.is_empty()
	if pick.visible:
		card.visible = false; build_menu.visible = false
		if pick.get_node("Prompt").text != prompt: pick.get_node("Prompt").text = prompt
	# Load is a page of tiles. Its instructions and the manifest sit in the Context column. The Depot's
	# Make crates page uses the same tiles, without Clear or the manifest.
	var loading: bool = pick.visible and game.pending_unit_command == "load"
	var crating: bool = pick.visible and crate_page_open
	load_tiles.visible = loading or crating
	load_tiles.get_node("Clear").visible = loading
	pick.get_node("Prompt").visible = not (loading or crating)
	manifest_panel.visible = loading
	if loading: update_manifest_panel()
	if crating: update_crate_page()
	# The camera lets the map's edge scroll up past the bottom panel instead of stopping behind it.
	var rig = game.get_node_or_null("CameraRig")
	if rig != null and not is_equal_approx(rig.screen_bottom_inset,$Bottom.size.y): rig.screen_bottom_inset = $Bottom.size.y
	# B opens the build page; there, B is Barracks.
	$Bottom/Body/Header/GlobalBuild.disabled = global_build_open
	place_tiles()
	update_tip()
	update_depot_panels()
	if game.spectating:
		depot_panel.visible = false
		production_panel.visible = false
	update_feed()
	update_guide()
## The player's Depot whose panels show for the selected object: the Depot itself, the Depot a Generator or
## production building uses, or else the nearest of your Depots whose range covers the selected building,
## mine or plan. Units and other sides' buildings show none.
func context_depot(node: Node3D) -> Node3D:
	if not is_instance_valid(node): return null
	if node.is_in_group("depots"): return node if node.team == "player" and node.health > 0 else null
	if not (node.is_in_group("energy_generators") or node.is_in_group("production_buildings") or node.is_in_group("mines") or node.is_in_group("construction_plans")): return null
	if not node.is_in_group("mines") and node.get("team") != null and node.team != "player": return null
	var own = node.get("assigned_depot")
	if is_instance_valid(own) and own.team == "player" and own.health > 0: return own
	var best: Node3D = null
	for depot in get_tree().get_nodes_in_group("depots"):
		if depot.team != "player" or depot.health <= 0 or not SupplySource.covers(depot,node.global_position,"player"): continue
		if best == null or depot.global_position.distance_to(node.global_position) < best.global_position.distance_to(node.global_position): best = depot
	return best
func update_depot_panels() -> void:
	# The shown object may have been destroyed since update_contents last ran.
	var depot := context_depot(shown if is_instance_valid(shown) else null)
	var is_keep := depot != null and depot.is_in_group("keeps")
	update_production_panel(depot)
	depot_panel.visible = depot != null and not is_keep
	storage_panel.visible = depot != null
	# The alert feed sits under the storage panel while it shows.
	var feed_top: float = storage_panel.position.y+storage_panel.size.y+PANEL_GAP if storage_panel.visible else FEED_TOP
	if not is_equal_approx(feed.offset_top,feed_top): feed.offset_top = feed_top
	if depot == null:
		panel_depot = null
		return
	var playtest: Control = get_node_or_null("PlaytestPanel")
	var panel_top: float = playtest.position.y+playtest.size.y+PANEL_GAP if playtest != null and playtest.visible else 12.0
	if not is_equal_approx(depot_panel.offset_top,panel_top): depot_panel.offset_top = panel_top
	var body = depot_panel.get_node("Body")
	body.get_node("Title").text = "%s · ENERGY" % str(depot.name).to_upper()
	body.get_node("Stock/Value").text = "%s / %s E" % [grouped(depot.energy),grouped(depot.storage_capacity)]
	var ceiling: HSlider = body.get_node("CeilingSlider")
	var coal: HSlider = body.get_node("CoalSlider")
	ceiling.max_value = depot.storage_capacity
	coal.max_value = depot.COAL_RESERVE_MAX
	# The sliders write straight to the Depot with the same steps, so following the Depot each frame never
	# pulls back a drag, and shows changes made elsewhere.
	panel_depot = depot
	if ceiling.value != depot.energy_ceiling: ceiling.set_value_no_signal(depot.energy_ceiling)
	if coal.value != depot.coal_reserve: coal.set_value_no_signal(depot.coal_reserve)
	body.get_node("Ceiling/Value").text = "No ceiling" if depot.energy_ceiling >= depot.storage_capacity else "%s E" % grouped(depot.energy_ceiling)
	body.get_node("Coal/Value").text = grouped(depot.coal_reserve)
	var generators: Array[Node3D] = depot.assigned_generators()
	var rate: float = depot.generation_rate()
	var bar: ProgressBar = body.get_node("Rate")
	bar.max_value = maxf(depot.peak_generation_rate(),0.001)
	bar.value = rate
	body.get_node("Banking/Value").text = "+%.1f E/s" % rate if rate > 0 else ("0 E/s" if not generators.is_empty() else "No Generators")
	# Stopped: say why, from the first Generator that is not running.
	var note := ""
	if generators.is_empty(): note = "Build a Generator in this Depot's range to bank energy here."
	elif rate <= 0: note = generators[0].describe_state()
	var note_label: Label = body.get_node("Note")
	note_label.visible = not note.is_empty()
	note_label.text = note
	show_storage("%s storage" % depot.name,depot.stockpile,storage_panel.get_node("Storage"))
## Your production building's power slider, under the Depot panel (docs/PRODUCTION_POWER.md).
func update_production_panel(depot: Node3D) -> void:
	var building: Node3D = shown if is_instance_valid(shown) and shown.is_in_group("production_buildings") and shown.team == "player" and not shown.stats.unit_scenes.is_empty() and shown.stats.max_power > 1.0 else null
	production_panel.visible = building != null
	panel_building = building
	if building == null: return
	# Under the Depot panel when it shows, which sizes itself a frame after its contents change.
	var top: float = depot_panel.position.y+depot_panel.size.y+PANEL_GAP if depot != null and depot_panel.visible else 12.0
	if not is_equal_approx(production_panel.offset_top,top): production_panel.offset_top = top
	var body = production_panel.get_node("Body")
	body.get_node("Title").text = "%s · PRODUCTION SPEED" % building.stats.display_name.to_upper()
	var slider: HSlider = body.get_node("PowerSlider")
	slider.max_value = building.stats.max_power
	slider.step = building.stats.power_step
	if slider.value != building.power: slider.set_value_no_signal(building.power)
	body.get_node("Power/Value").text = "%.1fx %s" % [building.power,"pace" if depot != null and depot.is_in_group("keeps") else "energy"]
	# What the power means for the unit printing now, or the building's first unit.
	var scene: PackedScene = building.pending[0] if not building.pending.is_empty() else building.stats.unit_scenes[0]
	var unit = building.unit_stats_for(scene)
	var note := "%s: %s s for %s F (base %s s, %s F)" % [unit.display_name,_seconds(building.seconds_at_power(scene)),grouped(unit.food_cost),_seconds(unit.build_seconds),grouped(unit.food_cost)] if unit.food_cost > 0 else "%s: %s s for %s E (base %s s, %s E)" % [unit.display_name,_seconds(building.seconds_at_power(scene)),grouped(building.energy_at_power(scene)),_seconds(unit.build_seconds),grouped(unit.energy_cost)]
	if building.power_starved: note += "\nThe Depot is short of energy: printing at 1x."
	body.get_node("Note").text = note
static func _seconds(value: float) -> String:
	return ("%.1f" % value).trim_suffix(".0")
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
const DEPOT_PRODUCTS := {"infantry":"Deforester","truck":"Depot truck","cargo":"Cargo vehicle","train":"Train","forester_maiden":"Forester Maiden","warhound":"Warhound"}
## Rendered pictures of the units and buildings (docs/HUD_RENDERS.md), made by scripts/tools/render_hud_images.gd.
const RENDER_PATH := "res://assets/ui/renders/%s.png"
const PORTRAIT_PATH := "res://assets/ui/portraits/%s.png"
## Portraits composed for the frame itself, which fill it and trim to fit (docs/UNIT_PORTRAITS.md); every other
## portrait is a render, shown whole and centred (docs/HUD_RENDERS.md).
const COMPOSED_PORTRAITS := ["infantry"]
const GLYPH_TINT := Color(0.855,0.69,0.4)
func set_icon(id: String) -> void:
	var icon: TextureRect = info.get_node("Head/Icon")
	if id.is_empty(): icon.texture = null; return
	icon.texture = unit_image(id)
	# A render keeps its own colours; a glyph takes the HUD's gold.
	icon.modulate = Color.WHITE if has_render(id) else GLYPH_TINT
## A unit's or building's render where there is one, else its glyph.
func unit_image(id: String) -> Texture2D:
	var key := "image:"+id
	if not _icons.has(key): _icons[key] = load(RENDER_PATH % id) if has_render(id) else load("res://assets/ui/icons/%s.svg" % glyph_name(id))
	return _icons[key]
func has_render(id: String) -> bool:
	return ResourceLoader.exists(RENDER_PATH % id)
## The glyph for an id with no render, or for one with no glyph of its own.
static func glyph_name(id: String) -> String:
	if id in ["barracks","tank_factory"]: return "factory"
	if id == "pithead": return "mine"
	return id if ResourceLoader.exists("res://assets/ui/icons/%s.svg" % id) else "infantry"
## The shown unit's or building's portrait in the Ornament frame, a render from assets/ui/portraits
## (docs/UNIT_PORTRAITS.md); the frame's emblem where there is none.
func update_portrait(node) -> void:
	var frame: TextureRect = $Bottom/Body/Row/Ornament/Portrait
	var path := ""
	var id := ""
	if is_instance_valid(node) and (node.is_in_group("units") or node.is_in_group("selectable_buildings")):
		id = icon_name(node)
		# The Arthurian units have portraits by their unit id.
		var unit_id := str(node.unit_stats.unit_id) if node.is_in_group("units") and node.get("unit_stats") != null else ""
		if not unit_id.is_empty() and unit_id != id and ResourceLoader.exists(PORTRAIT_PATH % unit_id): id = unit_id
		path = PORTRAIT_PATH % id
	elif is_instance_valid(node) and node.is_in_group("land_mines"):
		id = "land_mine"
		path = PORTRAIT_PATH % id
	if path.is_empty() or not ResourceLoader.exists(path): frame.visible = false; return
	frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED if COMPOSED_PORTRAITS.has(id) else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if not _icons.has(path): _icons[path] = load(path)
	frame.texture = _icons[path]
	frame.visible = true
func icon_name(node: Node) -> String:
	if node.is_in_group("depots"): return "depot"
	if node.is_in_group("farms"): return "farm"
	if node.is_in_group("houses"): return "house"
	if node.is_in_group("mines"): return "mine" if str(node.scene_file_path).ends_with("site_mine.tscn") else "pithead"
	if node.is_in_group("research_buildings"):
		# The Foundry and Forge have their own models (docs/FOUNDRY_MODEL.md, docs/FORGE_MODEL.md).
		var building_id := str(node.stats.building_id) if node.get("stats") != null else ""
		return building_id if building_id in ["foundry","forge"] else "temple"
	if node.is_in_group("production_buildings"): return "barracks" if str(node.scene_file_path).ends_with("barracks.tscn") else "tank_factory"
	if node.is_in_group("energy_generators"): return "generator"
	if node.is_in_group("rail_trains"): return "train"
	if node.get("is_cargo_vehicle"): return "cargo"
	if node.get("is_depot_truck"): return "truck"
	return str(node.unit_stats.unit_id) if node.get("unit_stats") != null else "infantry"
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
func show_storage(title: String, stockpile: ResourceStockpile, section: Control = null) -> void:
	if section == null: section = info.get_node("Storage")
	section.visible = true
	section.get_node("Head/Label").text = title
	section.get_node("Legend").visible = true
	section.get_node("Head/Value").text = "%s / %s" % [grouped(stockpile.total()+stockpile.reserved),grouped(stockpile.capacity)]
	var segments = section.get_node("Track/Segments")
	for kind in RESOURCE_KINDS:
		var amount := stockpile.amount(kind)
		var segment: Control = segments.get_node(str(kind).capitalize())
		segment.visible = amount > 0
		segment.size_flags_stretch_ratio = maxf(amount,0.001)
		var entry := section.get_node("Legend/%s" % str(kind).capitalize())
		if kind == &"food":
			entry.visible = amount > 0 or (is_instance_valid(shown) and shown.is_in_group("keeps"))
		entry.get_node("Amount").text = "%s %s" % [str(kind).capitalize(),grouped(amount)]
	var crates_segment: Control = segments.get_node("Crates")
	crates_segment.visible = stockpile.reserved > 0
	crates_segment.size_flags_stretch_ratio = maxf(stockpile.reserved,0.001)
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
## The target classes in a weapon's flags (CombatResolver), as words.
func _classes(flags: int) -> String:
	var names: Array[String] = []
	for pair in [[CombatResolver.LIGHT,"light"],[CombatResolver.ARMOURED,"armour"],[CombatResolver.FLYER,"flyers"],[CombatResolver.BUILDING,"buildings"]]:
		if flags & pair[0]: names.append(pair[1])
	return ", ".join(names)
## `inspect` is an enemy unit: its stats and abilities only, not what it carries or where it is going.
func update_unit_sections(node: Node3D, inspect := false) -> void:
	var pairs := [["Speed","%.1f" % node.move_speed]]
	if node.vision > 0: pairs.append(["Vision","%.1f" % node.vision])
	var abilities: Array[String] = []
	if node.is_cargo_vehicle or node.is_depot_truck:
		abilities.append("Non-combat vehicle")
	elif node._attack_enabled:
		pairs.insert(1,["Range","%.0f–%.0f" % [node.min_attack_range,node.attack_range] if node.min_attack_range > 0 else "%.1f" % node.attack_range])
		pairs.insert(2,["Damage","%d / %.1fs" % [node.attack_damage,node.shot_interval]])
		if node.unit_stats != null:
			var stats: UnitStats = node.unit_stats
			if stats.heavy_target_damage >= 0:
				pairs.append(["Vs armour","%d / %.1fs" % [stats.heavy_target_damage,stats.heavy_target_interval]])
				pairs.append(["Splash","%.1f" % stats.splash_radius])
			if stats.second_damage >= 0: abilities.append("Second weapon %d / %.1fs at %.0f–%.0f vs %s" % [stats.second_damage,stats.second_interval,stats.second_min_range,stats.second_range,_classes(stats.second_targets)])
			if stats.targets != 15: abilities.append("Main weapon vs %s" % _classes(stats.targets))
			if stats.fire_while_moving: abilities.append("Fires while moving")
			if not stats.has_resolved_attack(): abilities.append("Fallback attack stats")
		var roof: Node = node.get_node_or_null("CloseDefense")
		if roof != null:
			# The stat grid is full on a Tank, so the roof gun goes on the abilities line.
			abilities.insert(0,"Roof gun %d / %.2fs at units within %.0f" % [roof.damage,roof.shot_interval,roof.attack_range])
	else: abilities.append("Unarmed worker" if node.can_gather else "Attack unavailable · unresolved stats")
	if node.get("armoured") == true: abilities.append("Armoured")
	if node.can_heal: abilities.append("Vitality Stimulus · %d HP/s at %.0f m, by itself (%d/%d HP reserve)" % [roundi(node.heal_hp/node.heal_interval),node.heal_range,node.med_reserve,node.med_reserve_capacity])
	if node.mobility_layer() == MobilityRules.Layer.AIR: abilities.append("Flies on a separate air layer")
	elif node.unit_stats != null and node.unit_stats.mobility != null and node.unit_stats.mobility.clears_forest: abilities.append("Clears forest")
	elif node.mobility_layer() == MobilityRules.Layer.FOREST: abilities.append("Moves through forest")
	var cost_energy: int = node.energy_cost
	var cost_iron: int = node.iron_cost
	var cost_food: int = node.food_cost
	var cost_wood: int = node.wood_cost
	if node.is_cargo_vehicle: cost_energy = node.supply_rules.cargo_energy_cost; cost_iron = node.supply_rules.cargo_iron_cost
	elif node.is_depot_truck:
		cost_energy = node.deployment_rules.truck_energy_cost; cost_iron = node.deployment_rules.truck_iron_cost
		pairs.append(["Deploys","%d E · %d I" % [node.deployment_rules.deployed_energy,node.deployment_rules.testing_starting_iron if node.deployment_rules.testing_starting_iron >= 0 and game.get("testing_iron_grant") != false else node.deployment_rules.deployed_iron]])
	if cost_food > 0 or cost_wood > 0:
		var cost_parts := PackedStringArray()
		if cost_food > 0: cost_parts.append("%d F" % cost_food)
		if cost_wood > 0: cost_parts.append("%d W" % cost_wood)
		if cost_iron > 0: cost_parts.append("%d I" % cost_iron)
		pairs.append(["Cost"," · ".join(cost_parts)])
	else:
		pairs.append(["Cost","%d E · %d I" % [cost_energy,cost_iron]])
	set_stats(pairs.slice(0,6))
	var line = context.get_node("Abilities")
	line.text = " · ".join(abilities)
	line.visible = not abilities.is_empty()
	if node.is_cargo_vehicle and not inspect:
		show_storage("Cargo · %d/%d crates" % [node.crates.size(),node.crate_slots()],node.stockpile)
		# Crate pips replace the loose-cargo legend unless the vehicle also carries loose cargo.
		var aboard = info.get_node("Storage/Aboard")
		info.get_node("Storage/Legend").visible = node.stockpile.total() > 0
		aboard.visible = not info.get_node("Storage/Legend").visible
		aboard.show_crates(node.crates,node.crate_slots())
		# A legacy route, or the current crate trip (pickup → delivery), with progress between them.
		var ends: Array = []
		if node.route_active and is_instance_valid(node.origin_depot) and is_instance_valid(node.destination_depot):
			ends = [[str(node.origin_depot.name),node.origin_depot.global_position],[str(node.destination_depot.name),node.destination_depot.global_position]]
		else:
			var stops: Array = node.shipment_stops()
			for i in range(stops.size()): ends.append([node.stop_title(stops[i],i == 0),stops[i].point])
		if not ends.is_empty():
			state_label.text = "%s → %s · %s" % [ends[0][0],ends[1][0],("repeating" if node.repeating else "once") if node.route_active else "trips: "+TRIP_LABELS[node.trips]]
			var route = context.get_node("Route")
			route.visible = true
			route.get_node("From").text = ends[0][0]
			route.get_node("To").text = ends[1][0]
			var to_origin: float = node.global_position.distance_to(ends[0][1])
			var to_destination: float = node.global_position.distance_to(ends[1][1])
			route.get_node("Bar").max_value = 1.0
			route.get_node("Bar").step = 0.0
			route.get_node("Bar").value = to_origin/maxf(0.001,to_origin+to_destination)
# One button per unit type in a mixed selection.
## Portraits replace the single unit's health, bars and details. Units are grouped by type, in the order the
## types were first selected. The unit the card shows (the primary, first of its type) is outlined; Tab moves it to
## the next type.
func update_portraits(units: Array[Node3D]) -> void:
	var many := units.size() > 1 and not global_build_open
	portraits.visible = many
	portrait_units.clear()
	# The single selection's health number, bars and details come back once the portraits go: they used to stay
	# hidden after any group selection, which hid every vehicle's fuel and the health number from then on.
	if not many:
		for id in ["HealthText","Bars","Details"]: info.get_node(id).visible = true
		return
	for id in ["Health","HealthText","Bars","Storage","Warning","Details"]: info.get_node(id).visible = false
	var manager = get_node("/root/SelectionManager")
	var types: Array[String] = manager.types_of(units)
	var primary: Node3D = manager.primary_of(units) if units[0].is_in_group("units") else units[0]
	for type in types:
		for unit in units:
			if unit.scene_file_path == type: portrait_units.append(unit)
	var slots := portraits.get_child_count()
	var more := portrait_units.size()-slots
	state_label.text = "Card shows %s (outlined)%s%s" % [object_name(primary)," · Tab: next type" if types.size() > 1 and primary.is_in_group("units") else ""," · %d more not shown" % more if more > 0 else ""]
	for i in slots:
		var button: Button = portraits.get_child(i)
		button.visible = i < portrait_units.size()
		if not button.visible: continue
		var unit: Node3D = portrait_units[i]
		var id := icon_name(unit)
		var image := unit_image(id)
		if button.icon != image:
			button.icon = image
			# A render shows in its own colours, a little brighter on hover; a glyph keeps the scene's gold.
			if has_render(id):
				button.add_theme_color_override("icon_normal_color",Color.WHITE)
				button.add_theme_color_override("icon_hover_color",Color(1.15,1.15,1.15))
				button.add_theme_color_override("icon_pressed_color",Color(0.85,0.85,0.85))
			else:
				button.add_theme_color_override("icon_normal_color",GLYPH_TINT)
				button.add_theme_color_override("icon_hover_color",Color(1,0.86,0.58))
				button.add_theme_color_override("icon_pressed_color",Color(0.72,0.6,0.38))
		var health: ProgressBar = button.get_node("Health")
		health.max_value = unit.max_health
		health.value = unit.health
		var ratio := float(unit.health)/maxf(unit.max_health,1)
		health.get_theme_stylebox("fill").bg_color = Color(0.364,0.674,0.469) if ratio > 0.6 else (Color(1,0.72,0.2) if ratio > 0.3 else Color(0.95,0.3,0.25))
		# The health as a number too (docs/SELECTION_PORTRAITS.md).
		var number := str(unit.health)
		if button.get_node("HealthText").text != number: button.get_node("HealthText").text = number
		button.get_node("Primary").visible = unit == primary
		var tip := "%s · Health %d / %d · %s\nClick: only this unit · Shift: remove it · Ctrl: only this type · Ctrl+Shift: remove this type" % [object_name(unit),unit.health,unit.max_health,unit.state] if unit.is_in_group("units") else "%s · Health %d / %d\nClick: only this building · Shift: remove it" % [object_name(unit),unit.health,unit.max_health]
		if button.tooltip_text != tip: button.tooltip_text = tip
## Click keeps only that unit selected; Shift-click drops it. With Ctrl the same goes for its whole type.
func pick_portrait(index: int) -> void:
	if index >= portrait_units.size() or not is_instance_valid(portrait_units[index]): return
	var picked: Node3D = portrait_units[index]
	var by_type := Input.is_key_pressed(KEY_CTRL)
	var remove := Input.is_key_pressed(KEY_SHIFT)
	if not picked.is_in_group("units"):
		var kept: Array[Node3D] = same_buildings()
		if remove: kept.erase(picked)
		else: kept = [picked]
		get_node("/root/SelectionManager").selection_changed(kept[0] if not kept.is_empty() else null,kept)
		return
	for unit in selected_units():
		var hit: bool = unit.scene_file_path == picked.scene_file_path if by_type else unit == picked
		unit.set_selected(not hit if remove else hit)
## The guide in the bottom panel while laying rail or placing a building (docs/PLACEMENT_GUIDE.md): the
## steps of track laying with the current one lit, or the placement colours with the one under the cursor lit; then
## the line about what is under the cursor, and the keys.
const RAIL_STEPS := ["Click the start","Click the end","Shape it, click to lay"]
const PLACE_STEPS := ["Builds here","Short of stock","Can't go here"]
const PLACE_COLOURS := [Color(0.2,1,0.4),Color(1,0.85,0.1),Color(1,0.15,0.1)]
const PLACE_STATES := ["ok","short","blocked"]
func update_guide() -> void:
	var guide: Control = $Bottom/Body/Row/Guide
	var rails = game.get_node_or_null("RailNetwork")
	var depots = game.get_node_or_null("DepotNetwork")
	var mode := ""
	if game.placing_rail and rails != null: mode = "rail"
	elif depots != null and depots.has_method("placement_active") and depots.placement_active(): mode = "place"
	# In the bottom panel, in place of the info and context columns, so it never covers the map.
	if guide.visible != not mode.is_empty(): guide.visible = not mode.is_empty()
	if info.visible != mode.is_empty(): info.visible = mode.is_empty()
	if context.visible != mode.is_empty(): context.visible = mode.is_empty()
	if mode.is_empty(): return
	var body := guide.get_node("Body")
	var current := 0
	if mode == "rail":
		current = 0 if not is_instance_valid(rails.route_from) else (1 if not is_instance_valid(rails.route_to) else 2)
		_set_text(body.get_node("Title"),"LAY RAIL")
		_set_text(body.get_node("Status"),rails.route_status())
		_set_text(body.get_node("Keys"),"Backspace takes back a pick  ·  Enter lays it  ·  Esc cancels")
	else:
		current = PLACE_STATES.find(depots.placement_state)
		_set_text(body.get_node("Title"),depots.placement_title)
		_set_text(body.get_node("Status"),depots.placement_text)
		_set_text(body.get_node("Keys"),"Click to place  ·  Esc cancels")
	for i in range(3):
		var step: Control = body.get_node("Steps/Step%d" % (i+1))
		step.get_node("Row/Number").visible = mode == "rail"
		step.get_node("Row/Swatch").visible = mode == "place"
		step.get_node("Row/Swatch").color = PLACE_COLOURS[i]
		_set_text(step.get_node("Row/Text"),(RAIL_STEPS if mode == "rail" else PLACE_STEPS)[i])
		# The current step is lit; steps done are green; the rest are dimmed.
		var tone := Color.WHITE if i == current else (Color(0.62,0.95,0.6,0.85) if mode == "rail" and i < current else Color(1,1,1,0.35))
		if step.modulate != tone: step.modulate = tone
	for arrow in ["Arrow1","Arrow2"]: body.get_node("Steps/"+arrow).visible = mode == "rail"
func _set_text(label: Label, text: String) -> void:
	if label.text != text: label.text = text
func update_feed() -> void:
	var now := Time.get_ticks_msec()/1000.0
	feed_points.clear()
	for entry in game.alerts:
		var alpha := warning_alpha(now-entry.time)
		if alpha > 0.0 and feed_points.size() < feed.get_child_count():
			var button: Button = feed.get_child(feed_points.size())
			if button.text != entry.text: button.text = entry.text
			button.modulate.a = alpha
			set_alert_style(button,entry.get("kind",""))
			feed_points.append(entry.point)
	for i in feed.get_child_count(): feed.get_child(i).visible = i < feed_points.size()
const ALERT_STYLES := {"attack": ["attack",Color(0.89,0.35,0.31)], "lost": ["cancel",Color(0.89,0.35,0.31)], "fuel": ["refuel",Color(0.941,0.698,0.29)], "rail": ["cancel",Color(0.941,0.698,0.29)]}
# Feed entries show an icon and colour for their alert kind.
func set_alert_style(button: Button, kind: String) -> void:
	var style: Array = ALERT_STYLES.get(kind,["focus",Color(0.855,0.69,0.4)])
	if not _icons.has(style[0]): _icons[style[0]] = load("res://assets/ui/icons/%s.svg" % style[0])
	button.icon = _icons[style[0]]
	button.add_theme_color_override("icon_normal_color",style[1])
	button.add_theme_color_override("icon_hover_color",style[1])
func focus_alert(index: int) -> void:
	if index < feed_points.size(): game.get_node("CameraRig").focus_position(feed_points[index])
## Command keys pressed with Shift already held (docs/MINIMAP_ORDERS.md). A button's shortcut needs an exact key
## match, so Shift+A matched nothing and the command never armed: the Shift-clicks meant to queue orders then
## panned the minimap or boxed a selection. No action is bound to Shift, so a Shift-held key that is some visible,
## enabled button's shortcut is sent again without Shift. The clicks that follow carry their own Shift and queue.
func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or not event.shift_pressed: return
	if event.keycode == KEY_SHIFT: return
	var plain: InputEventKey = event.duplicate()
	plain.shift_pressed = false
	for button in find_children("*","BaseButton",true,false):
		if button.shortcut == null or button.disabled or not button.is_visible_in_tree(): continue
		if button.shortcut.matches_event(plain):
			get_viewport().set_input_as_handled()
			get_viewport().push_input(plain)
			return
# Shortcuts only fire for visible, enabled buttons.
## The Depot whose train waits for the player to click its line (docs/RAIL_PLANNING.md).
var train_line_depot: Node3D
## Queues a train at the selected Depot. With more than one line of track reaching it, the player first clicks
## the line the train starts on.
func queue_train() -> void:
	if not network.owned_selected(): return
	var depot: Node3D = network.selected
	var reaching: Array = game.get_node("RailNetwork").depot_lines(depot)
	if reaching.size() > 1:
		train_line_depot = depot
		game.pending_unit_command = "train_line"
		game.notify("%s has %d rail lines: click the line the train starts on. Esc cancels." % [depot.name,reaching.size()])
		return
	if not depot.request_train(): game.notify("Depot lacks local train funds or queue space.")
func hotkey_text(button: Button) -> String:
	if button.shortcut == null or button.shortcut.events.is_empty() or not button.shortcut.events[0] is InputEventAction: return ""
	var action: StringName = button.shortcut.events[0].action
	if not InputMap.has_action(action): return ""
	for event in InputMap.action_get_events(action):
		if event is InputEventKey: return event.as_text_physical_keycode()
	return ""
## A Forest or Coal tile selected to inspect (docs/CURSORS.md): its size, what it holds, and what it is part of.
var _patch := {}
var _patch_at := -INF
var _patch_cell := Vector2i(-1,-1)
func show_cell(node: Node3D) -> void:
	var wood: bool = node.is_in_group("forest_cells")
	var ground = game.ground
	var side: float = ground.tile_size
	info.get_node("Health").visible = false
	name_label.text = "Forest tile" if wood else "Coal tile"
	commands.get_node("Title").text = "FOREST" if wood else "COAL DEPOSIT"
	info.get_node("HealthText").text = "%d / %d %s left" % [node.remaining,node.amount,"wood" if wood else "coal"]
	var whole := ""
	if wood:
		# The patch is counted again at most once a second, as felling changes it.
		var now := Time.get_ticks_msec()/1000.0
		if node.cell != _patch_cell or now-_patch_at > 1.0:
			_patch = ground.forest_patch(node.cell)
			_patch_at = now
			_patch_cell = node.cell
		whole = "This wood: %s%d tiles · %s%d wood" % ["over " if _patch.capped else "",_patch.tiles,"over " if _patch.capped else "",_patch.wood]
	else:
		whole = "This seam: %d coal left" % node.field_remaining()
	info.get_node("Details").text = "Tile %s × %s m · cell %d, %d\n%s" % [_metres(side),_metres(side),node.cell.x,node.cell.y,whole]
	hint_text = "Right-click with Deforesters to gather its wood, or Fell (F) to clear it without carrying the wood home." if wood else ("Build a Coal Mine on the seam, then Deforesters gather from the mine." if ground.harvesting_rules.coal_needs_mine else "Right-click with Deforesters to dig coal here.")
## A land mine's card (docs/MINES.md): read-only; enemies attack it from their own card.
func show_land_mine(node: Node3D) -> void:
	var own: bool = node.team == "player"
	name_label.text = "Land mine"
	set_icon("land_mine")
	commands.get_node("Title").text = "LAND MINE"
	state_label.text = "%s · %s" % [team_label(node),"armed" if node.armed else "arming"]
	info.get_node("Health").visible = true
	info.get_node("Health").max_value = node.max_health
	info.get_node("Health").value = node.health
	info.get_node("HealthText").text = "%d / %d HP" % [node.health,node.max_health]
	info.get_node("Details").text = "Sets off under an enemy ground unit within %.0f m: %d damage, %d to others within %.0f m. A train on it derails." % [node.rules.trigger_radius,node.rules.damage,roundi(node.rules.damage*node.rules.splash_share),node.rules.splash_radius]
	hint_text = "Yours: hidden from the other side once armed, except near its detectors." if own else "Detected: right-click it with units, or Attack (A) it, to shoot it before something drives over it."
func _metres(value: float) -> String:
	return str(int(value)) if is_equal_approx(value,roundf(value)) else "%.1f" % value
func update_contents() -> void:
	var node = selected_object()
	if node != shown:
		close_build()
		shown = node
	for bar in bars.get_children(): bar.visible = false
	bars.get_node("Fuel/Need").visible = false
	for section in ["Production","Route","Stats","Abilities"]: context.get_node(section).visible = false
	info.get_node("Storage").visible = false
	info.get_node("Storage/Aboard").visible = false
	info.get_node("Warning").visible = false
	state_label.text = ""
	set_icon("")
	update_portrait(node)
	hint_text = ""
	var show_build := global_build_open
	build_menu.visible = show_build
	card.visible = not show_build
	info.get_node("Health").visible = is_instance_valid(node)
	$Bottom/Body/Header/Focus.disabled = not is_instance_valid(node)
	var header: Label = $Bottom/Body/Header/Message
	header.text = game.outcome if not game.outcome.is_empty() else game.message
	# The outcome stays; any other message fades like the alert feed.
	header.modulate.a = 1.0 if not game.outcome.is_empty() else warning_alpha(Time.get_ticks_msec()/1000.0-game.message_time)
	if global_build_open and worksite_open:
		commands.get_node("Title").text = "WORKSITE · CHOOSE A BUILDING"
		refresh_global_menu()
		info.get_node("Health").visible = false
		name_label.text = "Worksite"
		var trucks := worksite_trucks()
		info.get_node("HealthText").text = "%d truck%s will fetch" % [trucks.size(),"" if trucks.size() == 1 else "s"]
		info.get_node("Details").text = "Place a building. The selected trucks\nbring exactly its materials from the\nnearest Depot, then Deforesters build it.\nShift places more and queues them."
		hint_text = "Each tile's key places that building. The trucks load exact amounts, deliver them to the footprint and go back until it is covered. Esc stops placing; Back returns to the truck."
		return
	if global_build_open:
		commands.get_node("Title").text = "GLOBAL BUILD · UNPAID PLANS"
		refresh_global_menu()
		info.get_node("Health").visible = false
		name_label.text = "Construction plans"
		info.get_node("HealthText").text = "%d pending" % get_tree().get_nodes_in_group("construction_plans").filter(func(p): return p.team == "player").size()
		info.get_node("Details").text = "Place on valid terrain, or on a pile.\nDeliver iron to the footprint, then\norder Deforesters to construct; a covering\nstockpile pays the energy as they build."
		hint_text = "B opens this page; each tile's key places that plan. Pin (P) makes new plans pay only from one Depot or deployed Cargo truck you pick on the map or minimap."
		return
	if is_instance_valid(node) and (node.is_in_group("forest_cells") or node.is_in_group("coal_cells")):
		show_cell(node)
		return
	if is_instance_valid(node) and node.is_in_group("land_mines"):
		show_land_mine(node)
		return
	if is_instance_valid(node) and node.is_in_group("construction_plans"):
		info.get_node("Health").visible = false
		name_label.text = node.spec.title+" plan"
		set_icon("plan")
		var payer_text: String = str(node.payer.name) if is_instance_valid(node.payer) else ("Unavailable" if node.pinned else "Auto covering stockpile")
		if node.kind == &"rail":
			info.get_node("HealthText").text = "Unpaid · no resources reserved"
			info.get_node("Details").text = "%s\nCost %d E / %d I\nPayer: %s\nDoes not block movement" % [node.state,node.spec.energy,node.spec.iron,payer_text]
			hint_text = "Rail completes when the tile is clear and one covering Depot can pay. Cancel is free."
		else:
			info.get_node("HealthText").text = ("Materials on site" if node.materials_covered() else "Needs materials on site") if not node.state.begins_with("Constructing") else node.state
			info.get_node("Details").text = "%s\n%s\nEnergy %d/%d from %s\n%s" % [node.site_text().replace(" · ","\n"),node.state,node.energy_paid,node.spec.energy,payer_text,"Does not block movement"]
			hint_text = "Unload a Cargo truck here, or right-click with a worker carrying iron, to pile materials on the footprint. Right-click with Deforesters to construct: 5 iron per saw blow, energy charged as they build. Cancel is free; piles stay."
		commands.get_node("Title").text = "PENDING CONSTRUCTION"
		show_button("CancelPlan","Cancel plan")
		return
	if not is_instance_valid(node):
		name_label.text = "Nothing selected"
		info.get_node("HealthText").text = "Select a unit or building"
		info.get_node("Details").text = "Minimap: left-click moves the camera, right-click orders selected units there.\nBlue: friendly · red: hostile\nGrey: neutral · gold: resources"
		commands.get_node("Title").text = "COMMAND CARD"
		hint_text = "Left-click selects. Drag selects units. Right-click gives orders. B opens the build page."
		return
	var units := selected_units()
	var group: Array[Node3D] = []
	if units.is_empty(): group = same_buildings()
	name_label.text = object_name(node) if units.size() <= 1 else "%d units selected" % units.size()
	if group.size() > 1: name_label.text = "%d × %s" % [group.size(),object_name(node)]
	info.get_node("Health").max_value = node.max_health
	info.get_node("Health").value = node.health
	info.get_node("HealthText").text = "Health %d / %d" % [node.health,node.max_health]
	set_icon(icon_name(node))
	if node.is_in_group("depots"):
		if node.is_in_group("keeps"):
			commands.get_node("Title").text = "KEEP · PRODUCTION"
			state_label.text = "%s · territory %.0f · %d Food · housing %s" % [team_label(node),node.rules.construction_radius,node.food,KnightHousing.text(get_tree(),node.team)]
			if node.team != "player": show_storage("Loose storage",node.stockpile)
			if node.queue > 0:
				var kind: String = node.pending[0] if not node.pending.is_empty() else ""
				var denom: float = maxf(0.1,node.current_seconds())
				show_progress("Training · "+DEPOT_PRODUCTS.get(kind,kind.capitalize()),"%d%%%s" % [roundi(node.progress/denom*100)," · %d more queued" % (node.queue-1) if node.queue > 1 else ""],node.progress/denom)
			info.get_node("Details").text = "Queue %d / %d%s" % [node.queue,node.queue_limit," · capture %d%%" % roundi(node.capture_progress/node.rules.capture_seconds*100) if node.capture_progress > 0 else ""]
			if node.team == "player":
				show_button("MakeCrates","Make crates")
				if node.can_cancel(): show_button("CancelPlan","Cancel production")
				var forester_stats: UnitStats = node.unit_stats_for_kind("forester_maiden")
				show_production("TrainForester",forester_stats.display_name,forester_stats.energy_cost,forester_stats.iron_cost,node,forester_stats.food_cost,forester_stats.wood_cost,forester_stats.unit_id)
				var hound_stats: UnitStats = node.unit_stats_for_kind("warhound")
				show_production("TrainWarhound",hound_stats.display_name,hound_stats.energy_cost,hound_stats.iron_cost,node,hound_stats.food_cost,hound_stats.wood_cost,hound_stats.unit_id)
				var balloon_button: Button = card.get_node("LaunchBalloon")
				var aboard: Array[Node3D] = node.balloon_crates()
				balloon_button.set_meta("detail","%d Wood. Takes up to %d full crates packed beside the Keep (%d ready) to a point you see, sets them down and is gone; inside a Keep's range it unloads into that Keep. 40 health: shot down, it drops nothing." % [KnightHousing.rules().balloon_wood_cost,KnightHousing.rules().balloon_crates,aboard.size()])
				show_button("LaunchBalloon","Launch balloon")
				var refusal: String = node.balloon_refusal()
				explain(balloon_button,not refusal.is_empty(),refusal)
				hint_text = "Keep stores Food, Wood and Iron locally and trains Forester Maidens and Warhounds. Found forward Keeps anywhere from 50 Wood and 50 Iron on site (B → K)."
		else:
			commands.get_node("Title").text = "DEPOT · PRODUCTION"
			state_label.text = "%s · territory %.0f · %+.1f E/s" % [team_label(node),node.rules.construction_radius,node.generation_rate()]
			# Your own Depot's storage shows in the top-right panel instead.
			if node.team != "player": show_storage("Loose storage",node.stockpile)
			if node.queue > 0:
				var kind: String = node.pending[0] if not node.pending.is_empty() else ""
				show_progress("Producing · "+DEPOT_PRODUCTS.get(kind,kind.capitalize()),"%d%%%s" % [roundi(node.progress/node.current_seconds()*100)," · %d more queued" % (node.queue-1) if node.queue > 1 else ""],node.progress/node.current_seconds())
			info.get_node("Details").text = "Queue %d / %d%s" % [node.queue,node.queue_limit," · capture %d%%" % roundi(node.capture_progress/node.rules.capture_seconds*100) if node.capture_progress > 0 else ""]
			if node.team == "player":
				show_button("MakeCrates","Make crates")
				if node.can_cancel(): show_button("CancelPlan","Cancel production")
				show_production("PrintTruck","Depot truck",node.rules.truck_energy_cost,node.rules.truck_iron_cost,node)
				show_production("PrintCargo","Cargo vehicle",network.supply_rules.cargo_energy_cost,network.supply_rules.cargo_iron_cost,node)
				var rails = game.get_node("RailNetwork").rules
				show_production("PrintTrain","Train",rails.cargo_energy_cost,rails.cargo_iron_cost,node)
				hint_text = "Production spends this Depot only. Train launch/load/unload needs friendly track within %.0f units. Build plans with B." % node.dropoff_range
	elif node.is_in_group("mines"):
		commands.get_node("Title").text = "SHARED MINE · IRON EXTRACTION"
		state_label.text = "Shared · any side can gather, repair or destroy"
		show_progress("Iron reserves","%s / %s" % [grouped(node.remaining),grouped(node.amount)],float(node.remaining)/maxi(1,node.amount))
		info.get_node("Details").text = "Shared access · no capture"
		hint_text = "Deforesters gather with right-click. Use its Repair card to repair this shared mine, or Attack to destroy it."
	elif node.is_in_group("research_buildings"): show_research_building(node)
	elif node.is_in_group("production_buildings"):
		commands.get_node("Title").text = node.stats.display_name.to_upper()+" · PRODUCTION"
		var payer = node.assigned_depot
		state_label.text = "%s · %s" % [team_label(node),("pays from "+str(payer.name)) if node.source_friendly() else "no friendly Depot in range"]
		if node.queue > 0 and not node.pending.is_empty():
			show_progress("Producing · "+node.unit_stats_for(node.pending[0]).display_name,"%d%%%s" % [roundi(node.fraction()*100)," · %d more queued" % (node.queue-1) if node.queue > 1 else ""],node.fraction())
		if is_instance_valid(payer):
			# A Keep pays in Food (docs/ARTHURIAN_KNIGHTS.md); a Depot in energy.
			var primary := ["Food",grouped(payer.food)] if payer.is_in_group("keeps") else ["Energy",grouped(payer.energy)]
			var rows := [primary,["Iron",grouped(payer.iron)],["Queue","%d / %d" % [node.queue,node.stats.queue_limit]]]
			if payer.is_in_group("keeps"): rows.append(["Housing",KnightHousing.text(get_tree(),node.team)])
			set_stats(rows)
		info.get_node("Details").text = "Pays from a friendly Depot or Keep whose range covers it:
the one shown while it can, else another that can."
		if node.source_friendly():
			for scene in node.stats.unit_scenes:
				var stats = node.unit_stats_for(scene)
				# The tile names the Depot that would pay: the current one, or another covering one that can.
				var pays = node.payer_for(stats.energy_cost,stats.iron_cost,stats.food_cost,stats.wood_cost)
				show_production(production_button_id(stats.unit_id),stats.display_name,stats.energy_cost,stats.iron_cost,pays if pays != null else node.assigned_depot,stats.food_cost,stats.wood_cost,stats.unit_id)
		hint_text = "Production pays from a friendly Depot (or Keep) whose range covers this building, picked for you: the one it has while that one can pay, otherwise the nearest covering one that can. Drone attacks and tentative abilities remain unspecified."
	elif node.is_in_group("energy_generators"):
		commands.get_node("Title").text = "GENERATOR · LOCAL POWER"
		var source = node.assigned_depot
		state_label.text = node.describe_state()
		set_stats([["Output","%.1f E/s" % node.output_rate()],["Burning",str(node.cycle_kind).capitalize() if not node.cycle_kind.is_empty() else "Waiting"],["Cycle","%.1f / %.1fs" % [node.cycle_elapsed,node.cycle_seconds]],["Fuel left",node.fuel_left_text()]])
		if is_instance_valid(source) and node.team != "player": show_storage("%s storage" % source.name,source.stockpile)
		info.get_node("Details").text = "Assigned Depot: %s" % (source.name if is_instance_valid(source) else "none")
		hint_text = "Burns fuel from the Depot whose range it stands in, and banks the energy there. Wood: 1 → %d E / %.1fs. Coal: 1 → %d E / %.1fs. Either uses wood first. Changes apply next cycle. It pauses at the Depot's energy ceiling or full storage, and leaves the Depot's coal reserve for vehicles." % [node.fuel_rules.wood_output,node.fuel_rules.wood_seconds,node.fuel_rules.coal_output,node.fuel_rules.coal_seconds]
		if node.team == "player":
			show_button("ToggleGenerator","Pause" if node.enabled else "Resume")
			set_card(card.get_node("ToggleGenerator"),"generator_pause" if node.enabled else "generator_resume")
			show_fuel_tile("BurnWood","Burn wood","wood",node.fuel_preference)
			show_fuel_tile("BurnCoal","Burn coal","coal",node.fuel_preference)
			show_fuel_tile("BurnEither","Burn either (wood first)","either",node.fuel_preference)
		if is_instance_valid(node.assigned_depot): show_button("FocusAssigned","Focus Depot")
	elif node.is_in_group("farms"):
		commands.get_node("Title").text = "FARM · FOOD"
		var tiller = node.worker if node.worker_busy() else null
		var status: String = ("tilled by "+str(tiller.name)) if tiller != null else "no Farmer"
		if node.raided: status = "enemy on the field: no Food"
		state_label.text = "%s · %s" % [team_label(node),status]
		set_stats([["Food a beat","%d / 1.2 s" % KnightHousing.rules().farm_food_per_beat],["Farmer","%d / 1" % (1 if tiller != null else 0)]])
		info.get_node("Details").text = "A field any unit can walk over. Its Farmer tills it and carries the Food to a Keep. While an enemy ground unit stands on it, it yields nothing."
		hint_text = "Right-click the Farm with one Forester Maiden: she becomes its Farmer for good and no longer builds, fells or fights. A Farm takes one Farmer. The Food goes to the nearest Keep."
	elif node.is_in_group("houses"):
		commands.get_node("Title").text = "HOUSE · HOUSING"
		state_label.text = "%s · %s" % [team_label(node),"+%d housing" % KnightHousing.rules().house_room if node.housed() else "outside every Keep's range: no housing"]
		set_stats([["Housing",KnightHousing.text(get_tree(),node.team)]])
		info.get_node("Details").text = "Housing counts for the whole side while the House stands inside one of its Keeps' range."
		hint_text = "Knights units take housing: Forester and Warhound 1, Marines and Sentinel 2, Azure Dragon 4. Each Keep gives %d, each House in a Keep's range %d." % [KnightHousing.rules().keep_room,KnightHousing.rules().house_room]
	elif node.team != "player":
		# An enemy unit shows only its health and stats: no state, orders, fuel or cargo (docs/SELECTION_INSPECT.md).
		state_label.text = team_label(node)
		info.get_node("Details").text = ""
		update_unit_sections(node,true)
		commands.get_node("Title").text = "%s UNIT · INSPECT" % team_label(node).to_upper()
		hint_text = "Enemy units show their health and stats here and never take your orders. Right-click with your own units to attack it."
	else:
		var nearest = nearest_depot(node)
		state_label.text = "%s · %s%s" % [team_label(node),node.state," · %d queued" % node.order_queue.size() if not node.order_queue.is_empty() else ""]
		var notes: Array[String] = []
		notes.append("Nearest %s: %s · %.1f units away" % ["Keep" if nearest.is_in_group("keeps") else "Depot",nearest.name,node.global_position.distance_to(nearest.global_position)] if nearest != null else "No friendly Depot or Keep")
		if node.fuel_rules != null: notes.append(fuel_note(node))
		if node.can_heal: notes.append("Medical reserve: %d / %d HP" % [node.med_reserve,node.med_reserve_capacity])
		if node.is_cargo_vehicle and not node.manifest.is_empty(): notes.append("Manifest: "+node.manifest_text())
		if node.can_gather:
			var sources := SupplySource.candidates(get_tree(),node.global_position,node.team)
			if not sources.is_empty(): notes.append("Pays from and delivers to %s (nearest)" % sources[0].name)
		info.get_node("Details").text = "\n".join(notes)
		update_bars(node)
		update_unit_sections(node)
		commands.get_node("Title").text = "UNIT · ORDERS"
		# An Air Balloon takes no orders (docs/AIR_BALLOON.md).
		if node.is_in_group("air_balloons"):
			info.get_node("Details").text = "Carrying %s
Flies only where its Keep sent it" % node.cargo_text()
			commands.get_node("Title").text = "AIR BALLOON"
			hint_text = "An Air Balloon flies its crates to where its Keep sent it, sets them down and is gone. It takes no orders. Shot down, it drops nothing."
			return
		show_button("Move","Move")
		show_button("Stop","Stop")
		if node.fuel_active():
			show_button("ToggleRefuel","Auto-refuel: %s" % ("on" if node.auto_refuel else "off"))
			set_card(card.get_node("ToggleRefuel"),"auto_refuel_on" if node.auto_refuel else "auto_refuel_off")
		if node.is_cargo_vehicle:
			show_button("DeployCargo","Pack up supplies" if node.deployed else "Deploy supplies")
			set_card(card.get_node("DeployCargo"),"pack_supplies" if node.deployed else "deploy_supplies")
			explain(card.get_node("DeployCargo"),not node.supply_transition.is_empty(),"Wait for deploying or packing to finish.")
			show_button("Load","Load crates")
			show_button("Unload","Unload crates")
			show_button("Trips","Trips: %s" % TRIP_LABELS[node.trips])
			set_card(card.get_node("Trips"),"trips_"+str(node.trips))
			if not node.is_in_group("rail_trains"): show_button("Worksite","Worksite")
			elif node.has_method("can_mine"): show_mine_tile(node)
			hint_text = "Worksite places a building and fetches exactly its materials. Right-click a build site to fetch for it. Load sets a manifest of crates, then picks a Depot. Unload at a Depot to unpack, or on open ground to set crates down. Shift queues stops. Trips: %s." % TRIP_LABELS[node.trips]
		elif node.is_depot_truck:
			show_button("DeployTruck","Deploy")
			hint_text = "Deploy on an empty Depot footprint. This vehicle does not carry transferable cargo."
		else:
			if node._attack_enabled: show_button("Attack","Attack")
			if node.get("farmer") == true:
				# A Farmer works only a Farm (docs/KNIGHTS_ECONOMY.md).
				show_button("Gather","Work an empty Farm")
			elif node.can_gather:
				show_button("Gather","Gather")
				show_button("Fell","Fell")
				card.get_node("Fell/Auto").visible = fell_autocast_on()
				show_button("Return","Deliver")
				show_button("DropMaterials","Drop")
				explain(card.get_node("DropMaterials"),node.cargo <= 0,"Nothing carried to drop.")
			if node.can_repair:
				show_button("Repair","Repair")
				card.get_node("Repair").tooltip_text = "Restore up to %d HP every %.1fs for %d energy / %d iron from the selected local supply source. No wood is spent." % [node.engineering_rules.repair_hp,node.engineering_rules.repair_interval,node.engineering_rules.repair_energy,node.engineering_rules.repair_iron]
			if node.can_heal:
				show_button("Heal","Heal")
				card.get_node("Heal").tooltip_text = "Vitality Stimulus: heal %d HP every %.1fs from the carried reserve (%d / %d HP), one point for one HP. Idle or attack-moving, it heals the most hurt friend within %.0f m by itself. The reserve refills inside a friendly Keep's range or beside a %s crate, %d points for %d. Does not heal vehicles." % [node.heal_hp,node.heal_interval,node.med_reserve,node.med_reserve_capacity,node.heal_range,str(node.med_refill_kind).capitalize(),node.med_refill_points,node.med_refill_cost]
			if node.can_heal and node.get("spell_rules") != null:
				var spells: SpellRules = node.spell_rules
				show_button("Mist","Mist")
				card.get_node("Mist").set_meta("detail","Mist · %d reserve points: for %.0f s, units inside an %.0f m circle can be seen only from within %.0f m. Cast up to %.0f m away." % [spells.mist_cost,spells.mist_seconds,spells.mist_radius,spells.mist_reveal,spells.cast_range])
				explain(card.get_node("Mist"),not node.spell_blocker("mist").is_empty(),node.spell_blocker("mist"))
				show_button("Slow","Slow")
				card.get_node("Slow").set_meta("detail","Slow · %d reserve points: enemy units within %.0f m move %d%% slower for %.0f s. Cast up to %.0f m away. Research it at a Forge." % [spells.slow_cost,spells.slow_radius,roundi((1.0-spells.slow_factor)*100),spells.slow_seconds,spells.cast_range])
				explain(card.get_node("Slow"),not node.spell_blocker("slow").is_empty(),node.spell_blocker("slow"))
			if node.can_capture_depots: show_button("Capture","Capture")
			if node.has_ability(&"derail"):
				show_button("Derail","Derail")
				explain(card.get_node("Derail"),node.derail_cooldown > 0.0,"Recharging: %d s" % ceili(node.derail_cooldown))
				if node.get("mine_rules") != null:
					show_button("BuyMine","Buy mine")
					var buy: Button = card.get_node("BuyMine")
					var buy_blocker: String = node.buy_mine_blocker()
					explain(buy,not buy_blocker.is_empty(),buy_blocker)
					if buy_blocker.is_empty(): buy.tooltip_text = "Buy mine (Q): %d iron from the covering stockpile. %d of %d mines aboard." % [node.mine_rules.iron_per_mine,node.mines,node.mine_rules.capacity]
					show_button("LayMine","Lay mine")
					var lay: Button = card.get_node("LayMine")
					var blocker: String = node.lay_mine_blocker()
					explain(lay,not blocker.is_empty(),blocker)
					if blocker.is_empty(): lay.tooltip_text = "Lay mine (E): click a point, track included. %d of %d mines aboard. It arms after %.0f s and is then hidden from the other side except near its detectors (Depots, Keeps, Drones, Warhounds). An enemy ground unit within %.0f m sets it off for %d damage; a train on it derails." % [node.mines,node.mine_rules.capacity,node.mine_rules.arm_seconds,node.mine_rules.trigger_radius,node.mine_rules.damage]
			hint_text = "Right-click to move, gather or attack. Workers pay from and deliver to the nearest stockpile unless you right-click a Depot. Build plans with B."
			if node.get("farmer") == true: hint_text = "A Farmer works its Farm for good and carries the Food to the nearest Keep. It does not build, fell or fight. If its Farm is lost, right-click an empty Farm."
# Card art that follows the state of a button. Unchanged art is not reassigned, so buttons do not redraw each frame.
func set_card(button: Button, id: String) -> void:
	var path := "res://assets/ui/command_cards/sl_%s.png" % id
	if not _icons.has(path): _icons[path] = load(path)
	if button.icon != _icons[path]: button.icon = _icons[path]
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
# The hint for the hovered control, once the pointer has rested on it. Hidden while a button is held,
# so a hint can never appear in the middle of a click.
func update_tip() -> void:
	var tip: PanelContainer = $Tip
	var hovered := get_viewport().gui_get_hovered_control()
	var mouse := get_viewport().get_mouse_position()
	var text := ""
	var control := hovered
	while control != null and text.is_empty():
		text = control.get_tooltip(mouse-control.get_global_position()) if control.is_inside_tree() else ""
		if text.is_empty(): control = control.get_parent_control()
	var now := Time.get_ticks_msec()/1000.0
	if control != _tip_control: _tip_control = control; _tip_since = now
	var show := control != null and now-_tip_since >= tip_delay and Input.get_mouse_button_mask() == 0
	if tip.visible != show: tip.visible = show
	if not show: return
	var label: Label = tip.get_node("Text")
	if label.text != text:
		label.text = text
		# Wide enough for the longest line, up to TIP_WIDTH; longer lines wrap.
		var widest := 0.0
		for line in text.split("
"): widest = maxf(widest,label.get_theme_font("font").get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,label.get_theme_font_size("font_size")).x)
		label.custom_minimum_size.x = minf(TIP_WIDTH,widest+2)
		tip.size = Vector2.ZERO
	var size := tip.get_combined_minimum_size()
	tip.size = size
	var viewport_size := get_viewport().get_visible_rect().size
	var at := mouse+Vector2(14,18)
	if at.x+size.x > viewport_size.x: at.x = mouse.x-size.x-6
	if at.y+size.y > viewport_size.y: at.y = mouse.y-size.y-8
	tip.position = at.max(Vector2.ZERO)
# Set a label with its hotkey; unchanged text isn't reassigned, so buttons don't relayout each frame.
# Unchanged text isn't reassigned, so buttons don't relayout every frame.
func set_label(button: Button, text: String) -> void:
	if button.text != text: button.text = text
# Production tiles: name over cost. Unaffordable costs turn amber and the tooltip says what's missing.
## The Temple of Science (docs/TEMPLE_OF_SCIENCE.md): its research, under way or to start.
func show_research_building(node: Node3D) -> void:
	commands.get_node("Title").text = node.stats.display_name.to_upper()+" · RESEARCH"
	if node.research.any(func(r): return r.level > 0): show_upgrade_building(node); return
	var payer = node.assigned_depot
	state_label.text = "%s · %s" % [team_label(node),("pays from "+str(payer.name)) if node.source_friendly() else "no friendly Depot in range"]
	if node.researching != null: show_progress("Researching · "+node.researching.display_name,"%d%% · %s s left" % [roundi(node.fraction()*100),_seconds(ceilf(node.seconds_left()))],node.fraction())
	if is_instance_valid(payer): set_stats([["Energy",grouped(payer.energy)],["Iron",grouped(payer.iron)]])
	var done_names: Array[String] = []
	for entry in node.research:
		if node.is_done(entry.research_id): done_names.append(entry.display_name)
	info.get_node("Details").text = ("Researched: "+", ".join(done_names)) if not done_names.is_empty() else "Research holds for every building and unit of yours.\nPays from a covering Depot when started."
	hint_text = "Research is paid when it starts, from a friendly Depot whose range covers the Temple. Cancel gives the cost back. One research at a time; a finished research holds for your whole side."
	if node.team != "player": return
	if node.researching != null: show_button("CancelPlan","Cancel research")
	for pair in [["Research",Research.MINING_TRAINS],["ResearchMines",Research.MINELAYING]]:
		_research_tile(node,pair[0],pair[1])
## One research tile on the Temple's card (docs/TEMPLE_OF_SCIENCE.md).
func _research_tile(node: Node3D, tile: String, id: StringName) -> void:
	var entry: ResearchStats = node.research_by_id(id)
	if entry == null: return
	var payer = node.assigned_depot
	var button: Button = card.get_node(tile)
	if node.is_done(id):
		desired_buttons.append(tile)
		button.add_theme_color_override("icon_normal_color",UNAFFORDABLE)
		set_tile(button,entry.display_name+" · researched",entry.summary)
		button.disabled = true
		return
	var pays = node.payer_for(entry.energy_cost,entry.iron_cost)
	show_production(tile,"Research "+entry.display_name+" (%s s)" % _seconds(entry.seconds),entry.energy_cost,entry.iron_cost,pays if pays != null else payer)
	var blocker: String = node.research_blocker(id)
	button.disabled = node.researching != null or (not blocker.is_empty() and pays != null)
	if not button.disabled: button.tooltip_text += "\n"+entry.summary
	elif node.researching != null: button.tooltip_text += "\nResearching now."
## The Foundry's or Forge's card (docs/UPGRADES.md): one tile per upgrade line, offering its next level.
func show_upgrade_building(node: Node3D) -> void:
	var payer = node.assigned_depot
	var keep: bool = node.stats.building_id == &"forge"
	state_label.text = "%s · %s" % [team_label(node),("pays from "+str(payer.name)) if node.source_friendly() else ("no friendly Keep in range" if keep else "no friendly Depot in range")]
	if node.researching != null: show_progress("Researching · "+node.researching.display_name,"%d%% · %s s left" % [roundi(node.fraction()*100),_seconds(ceilf(node.seconds_left()))],node.fraction())
	if is_instance_valid(payer): set_stats([["Food",grouped(payer.food)],["Iron",grouped(payer.iron)]] if keep else [["Energy",grouped(payer.energy)],["Iron",grouped(payer.iron)]])
	var lines: Array[StringName] = []
	var plain: Array[ResearchStats] = []
	for entry in node.research:
		if entry.level > 0 and not entry.line in lines: lines.append(entry.line)
		elif entry.level <= 0: plain.append(entry)
	var levels: Array[String] = []
	for line in lines: levels.append("%s %d/%d" % [_line_title(node,line),Upgrades.level(node,node.team,line),Upgrades.LEVELS])
	info.get_node("Details").text = "Levels: "+" · ".join(levels)
	hint_text = "Each line has three levels, researched in order. Attack adds 10%% of base weapon damage a level; armour takes 1 off every hit a level, never below 1. Paid when started from a covering %s; Cancel gives it back. One research at a time; levels hold for your whole side." % ("Keep" if keep else "Depot")
	if node.team != "player": return
	if node.researching != null: show_button("CancelPlan","Cancel research")
	for i in range(mini(lines.size(),4)):
		var line := lines[i]
		var id := "Upgrade%d" % (i+1)
		var button: Button = card.get_node(id)
		set_card(button,"upgrade_"+str(line))
		var have := Upgrades.level(node,node.team,line)
		if have >= Upgrades.LEVELS:
			desired_buttons.append(id)
			if button.has_meta("research"): button.remove_meta("research")
			button.add_theme_color_override("icon_normal_color",UNAFFORDABLE)
			set_tile(button,"%s · all %d levels" % [_line_title(node,line),Upgrades.LEVELS],"Researched in full.")
			button.disabled = true
			continue
		var entry: ResearchStats = node.research_by_id(Upgrades.research_id(line,have+1))
		if entry == null: continue
		button.set_meta("research",entry.research_id)
		var pays = node.payer_for(entry.energy_cost,entry.iron_cost,entry.food_cost)
		show_production(id,"Research "+entry.display_name+" (%s s)" % _seconds(entry.seconds),entry.energy_cost,entry.iron_cost,pays if pays != null else payer,entry.food_cost)
		var blocker: String = node.research_blocker(entry.research_id)
		button.disabled = node.researching != null or (not blocker.is_empty() and pays != null)
		if not button.disabled: button.tooltip_text += "\n"+entry.summary
		elif node.researching != null: button.tooltip_text += "\nResearching now."
		elif not blocker.is_empty(): button.tooltip_text += "\n"+blocker
	# Research that is not an upgrade line, such as the Forge's Slow (docs/MIST_AND_SLOW.md).
	for i in range(plain.size()):
		if lines.size()+i >= 4: break
		var entry := plain[i]
		var id := "Upgrade%d" % (lines.size()+i+1)
		var button: Button = card.get_node(id)
		set_card(button,"research_"+String(entry.research_id))
		if node.is_done(entry.research_id):
			desired_buttons.append(id)
			if button.has_meta("research"): button.remove_meta("research")
			button.add_theme_color_override("icon_normal_color",UNAFFORDABLE)
			set_tile(button,entry.display_name+" · researched",entry.summary)
			button.disabled = true
			continue
		button.set_meta("research",entry.research_id)
		var pays = node.payer_for(entry.energy_cost,entry.iron_cost,entry.food_cost)
		show_production(id,"Research "+entry.display_name+" (%s s)" % _seconds(entry.seconds),entry.energy_cost,entry.iron_cost,pays if pays != null else payer,entry.food_cost)
		var blocker: String = node.research_blocker(entry.research_id)
		button.disabled = node.researching != null or (not blocker.is_empty() and pays != null)
		if not button.disabled: button.tooltip_text += "\n"+entry.summary
		elif node.researching != null: button.tooltip_text += "\nResearching now."
## "Infantry Weapons" from the line's level-1 entry.
func _line_title(node: Node3D, line: StringName) -> String:
	var entry: ResearchStats = node.research_by_id(Upgrades.research_id(line,1))
	return entry.display_name.trim_suffix(" I") if entry != null else str(line)
## A train's Mine iron tile: open once Mining Trains is researched (docs/TEMPLE_OF_SCIENCE.md).
func show_mine_tile(node: Node3D) -> void:
	show_button("MineIron","Mine iron")
	explain(card.get_node("MineIron"),not node.can_mine(),"Research Mining Trains at a Temple of Science first.")
func show_production(id: String, title: String, energy_cost: int, iron_cost: int, payer: Node, food_cost := 0, wood_cost := 0, unit_id: StringName = &"") -> void:
	desired_buttons.append(id)
	var button: Button = card.get_node(id)
	var missing := []
	if is_instance_valid(payer):
		if payer.energy < energy_cost: missing.append("%d more energy" % (energy_cost-payer.energy))
		if payer.stockpile.amount(&"food") < food_cost: missing.append("%d more food" % (food_cost-payer.stockpile.amount(&"food")))
		if payer.stockpile.amount(&"wood") < wood_cost: missing.append("%d more wood" % (wood_cost-payer.stockpile.amount(&"wood")))
		if payer.iron < iron_cost: missing.append("%d more iron" % (iron_cost-payer.iron))
	# Knights training waits for housing (docs/KNIGHTS_ECONOMY.md).
	if not unit_id.is_empty() and not KnightHousing.room(get_tree(),"player",unit_id): missing.append("housing (%s used): build a House in a Keep's range" % KnightHousing.text(get_tree(),"player"))
	var cost_text := "%d E · %d I" % [energy_cost,iron_cost]
	if food_cost > 0 or wood_cost > 0:
		var parts := PackedStringArray()
		if food_cost > 0: parts.append("%d F" % food_cost)
		if wood_cost > 0: parts.append("%d W" % wood_cost)
		if energy_cost > 0: parts.append("%d E" % energy_cost)
		if iron_cost > 0: parts.append("%d I" % iron_cost)
		cost_text = " · ".join(parts)
	if missing.is_empty():
		button.remove_theme_color_override("icon_normal_color")
		set_tile(button,title,"%s · from %s" % [cost_text,payer.name if is_instance_valid(payer) else "the paying Depot"])
	else:
		button.add_theme_color_override("icon_normal_color",UNAFFORDABLE)
		set_tile(button,title,"%s · needs %s" % [cost_text," and ".join(missing)])
# Disabled actions stay visible and explain why.
func explain(button: Button, disabled: bool, reason: String) -> void:
	button.disabled = disabled
	if button.has_meta("label"): set_tile(button,label_of(button),reason if disabled else str(button.get_meta("detail","")))
	elif disabled: button.tooltip_text = reason
	elif button.tooltip_text == reason: button.tooltip_text = ""
func close_build() -> void:
	global_build_open = false
	worksite_open = false
	crate_page_open = false
	game.global_plan_kind = &""
	if game.pending_unit_command == "pin": game.pending_unit_command = ""
	game.placing_rail = false
	game.placing_depot = false
	game.placing_generator = false
	game.placing_structure = &""
	network.clear_builder()
## Selected player units that can fell.
func fellers() -> Array:
	return get_tree().get_nodes_in_group("units").filter(func(u): return u.team == "player" and u.is_selected and u.can_gather and not u.is_cargo_vehicle and not u.is_depot_truck)
## True when every selected unit that can fell has autocast on.
func fell_autocast_on() -> bool:
	var units := fellers()
	return not units.is_empty() and units.all(func(u): return u.fell_autocast)
## Autocast Fell on for the selection, or off when it is already on for all of it.
func toggle_fell_autocast() -> void:
	var units := fellers()
	if units.is_empty(): return
	var on := not fell_autocast_on()
	for unit in units: unit.set_fell_autocast(on)
	card.get_node("Fell/Auto").visible = on
	game.notify("Autocast Fell on: idle Deforesters fell the trees round where they are left." if on else "Autocast Fell off.")
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
			# Only a stockpile the player chose stays the drop-off for later trips.
			unit.return_explicit = unit.supply_payer_explicit
# The Load page: a manifest of crates for the selected vehicles (docs/CRATE_MANIFESTS.md).
func edit_manifest(kind: StringName, fill := false) -> void:
	var changed := false
	for unit in selected_units():
		if unit.is_cargo_vehicle and (unit.manifest_fill(kind) if fill else unit.manifest_add(kind)): changed = true
	if not changed: game.notify("The manifest is full. Clear it to change the mix.")
func lower_manifest(kind: StringName, every := false) -> void:
	var changed := false
	for unit in selected_units():
		if unit.is_cargo_vehicle and unit.manifest_remove(kind,every): changed = true
	if not changed: game.notify("No %s crates on the manifest to take off." % kind)
func clear_manifest() -> void:
	for unit in selected_units():
		if unit.is_cargo_vehicle: unit.manifest.clear()
func update_manifest_panel() -> void:
	var vehicle := selected_cargo()
	manifest_panel.get_node("Head/Value").text = "%d / %d crates" % [vehicle.manifest_total(),vehicle.crate_slots()]
	var planned: Array[Dictionary] = []
	for kind in ResourceStockpile.KINDS:
		for i in range(vehicle.manifest.get(kind,0)): planned.append({kind = kind, amount = ResourceStockpile.CRATE})
	manifest_panel.get_node("Pips").show_crates(planned,vehicle.crate_slots())
	for pair in [["Iron","Iron"],["Energy","Energy"],["Wood","Wood"],["Coal","Coal"],["Food","Food"]]:
		set_tile(load_tiles.get_node(pair[0]),pair[1]+" crate","Adds one crate to the manifest. Shift fills every free slot.\nRight-click takes one off; Shift+right-click takes them all off.")
		load_tiles.get_node(pair[0]).disabled = false
	load_tiles.get_node("Food").visible = has_arthurian_faction()
	set_tile(load_tiles.get_node("Clear"),"Clear manifest","Removes every crate from the manifest.")
func show_fuel_tile(id: String, label: String, mode: String, current: String) -> void:
	show_button(id,label)
	var button: Button = card.get_node(id)
	if mode == current: button.remove_theme_color_override("icon_normal_color")
	else: button.add_theme_color_override("icon_normal_color",UNSELECTED)

## The Worksite page: the build page for the selected trucks (docs/TRUCK_WORKSITES.md).
func open_worksite() -> void:
	if worksite_trucks().is_empty(): return
	close_build()
	game.cancel_armed()
	global_build_open = true
	worksite_open = true
	shown = selected_object()
	refresh_global_menu()
	game.notify("Worksite: choose a building, then place it. The selected trucks fetch exactly its materials.")
func worksite_trucks() -> Array[Node3D]:
	var trucks: Array[Node3D] = []
	for unit in selected_units():
		if unit.is_cargo_vehicle and not unit.is_in_group("rail_trains"): trucks.append(unit)
	return trucks
## The Depot's Make crates page: each resource tile sets down one full crate beside it.
func open_crate_page() -> void:
	if not is_instance_valid(shown) or not shown.is_in_group("depots"): return
	game.cancel_armed()
	crate_page_open = true
	game.notify("Make crates: each tile sets down a full %d-unit crate beside %s. Shift makes five. Esc closes." % [ResourceStockpile.CRATE,shown.name])
const CRATE_BATCH := 5
func make_crates(kind: StringName, batch := false) -> int:
	if not is_instance_valid(shown) or not shown.is_in_group("depots"): return 0
	var made := 0
	for i in range(CRATE_BATCH if batch else 1):
		if shown.stockpile.amount(kind) < ResourceStockpile.CRATE:
			if made == 0: game.notify("%s needs %d %s for a crate." % [shown.name,ResourceStockpile.CRATE,kind])
			break
		if CrateYard.pack(shown,kind) == null:
			if made == 0: game.notify("No open tile beside %s for a crate." % shown.name)
			break
		made += 1
	if made > 0: game.notify("%d %s crate%s set down beside %s." % [made,kind,"" if made == 1 else "s",shown.name])
	return made
func update_crate_page() -> void:
	for pair in [["Iron",&"iron"],["Energy",&"energy"],["Wood",&"wood"],["Coal",&"coal"],["Food",&"food"]]:
		var button: Button = load_tiles.get_node(pair[0])
		if pair[1] == &"food":
			button.visible = has_arthurian_faction() or (is_instance_valid(shown) and shown.stockpile.amount(&"food") > 0)
		var short: bool = shown.stockpile.amount(pair[1]) < ResourceStockpile.CRATE
		set_tile(button,pair[0]+" crate","Sets down a full %d-unit %s crate beside the %s. Shift makes %d." % [ResourceStockpile.CRATE,pair[1],"Keep" if is_instance_valid(shown) and shown.is_in_group("keeps") else "Depot",CRATE_BATCH])
		explain(button,short,"Needs %d %s here." % [ResourceStockpile.CRATE,pair[1]])
func open_global_build() -> void:
	close_build()
	game.pending_unit_command = ""
	global_build_open = true
	shown = selected_object()
	refresh_global_menu()
func begin_global_placement(kind: StringName) -> void:
	game.pending_unit_command = ""
	game.placing_rail = false; game.placing_depot = false; game.placing_generator = false; game.placing_structure = &""
	game.global_plan_kind = &""
	if kind == &"rail":
		# Track connects two buildings: the player picks them and the game suggests the path (docs/RAIL_PLANNING.md).
		game.placing_rail = true
		game.notify(game.RAIL_HELP)
		return
	game.global_plan_kind = kind
	game.notify("Click valid terrain to place an unpaid %s plan. Esc cancels placement; existing plans remain." % network.plan_spec(kind).title)
func refresh_global_menu() -> void:
	build_menu.get_node("Actions/Pin").visible = not worksite_open
	build_menu.get_node("Actions/Rail").visible = not worksite_open and build_kind_offered(&"rail")
	var arthurian := knights_build() and not worksite_open
	build_menu.get_node("Actions/Keep").visible = arthurian
	build_menu.get_node("Actions/Chapterhouse").visible = arthurian
	build_menu.get_node("Actions/Farm").visible = arthurian
	build_menu.get_node("Actions/House").visible = arthurian
	build_menu.get_node("Actions/Forge").visible = arthurian
	for pair in [[&"depot","Depot"],[&"generator","Generator"],[&"barracks","Barracks"],[&"tank_factory","TankFactory"],[&"temple_of_science","Temple"],[&"foundry","Foundry"]]:
		build_menu.get_node("Actions/"+pair[1]).visible = build_kind_offered(pair[0])
	if worksite_open:
		build_menu.get_node("Bank").text = "DELIVERS: EXACT MATERIALS"
		build_menu.get_node("Bank").tooltip_text = "The selected trucks load exactly what the building needs and unload it on the footprint. A covering stockpile pays the energy as Deforesters build."
		for pair in [[&"depot","Depot"],[&"generator","Generator"],[&"barracks","Barracks"],[&"tank_factory","TankFactory"],[&"temple_of_science","Temple"],[&"foundry","Foundry"],[&"iron_mine","Mine"],[&"coal_mine","CoalMine"]]:
			var spec: Dictionary = network.plan_spec(pair[0])
			var button: Button = build_menu.get_node("Actions/"+pair[1])
			button.disabled = false
			set_tile(button,spec.title+" worksite","%d E · %d I · the trucks bring the %d iron; energy is paid as Deforesters build" % [spec.energy,spec.iron,spec.iron])
		return
	var pin_name := str(global_payer.name) if global_pinned and SupplySource.available(global_payer,"player") else ""
	if not global_pinned: build_menu.get_node("Bank").text = "PAYS: AUTO (NEAREST)"
	elif pin_name.is_empty(): build_menu.get_node("Bank").text = "PAYS: PIN LOST · PLANS WAIT"
	else: build_menu.get_node("Bank").text = "PAYS: %s ONLY" % pin_name.to_upper()
	build_menu.get_node("Bank").tooltip_text = "One covering Depot or deployed Cargo truck pays each plan's energy as Deforesters build it. Iron must be delivered to the footprint first. Rails pay fully from Depots. No pooled resources."
	set_card(build_menu.get_node("Actions/Pin"),"unpin_payer" if global_pinned else "pin_payer")
	set_tile(build_menu.get_node("Actions/Pin"),"Unpin payer (back to Auto)" if global_pinned else "Pin payer","New plans pay from the nearest covering stockpile that can pay." if global_pinned else "Pick one Depot or deployed Cargo truck on the map or minimap; new plans pay only from it.")
	for pair in [[&"depot","Depot"],[&"generator","Generator"],[&"barracks","Barracks"],[&"tank_factory","TankFactory"],[&"temple_of_science","Temple"],[&"foundry","Foundry"],[&"iron_mine","Mine"],[&"coal_mine","CoalMine"],[&"rail","Rail"],[&"keep","Keep"],[&"chapterhouse","Chapterhouse"],[&"farm","Farm"],[&"house","House"],[&"forge","Forge"]]:
		var spec: Dictionary = network.plan_spec(pair[0])
		var button: Button = build_menu.get_node("Actions/"+pair[1])
		button.disabled = false
		if pair[0] == &"rail":
			var rails = game.get_node("RailNetwork")
			set_tile(button,"Maglev track","%d I straight · %d I curve · laid end to end, Depot-paid" % [rails.cost("straight"),rails.cost("curve")])
		elif pair[0] == &"keep":
			set_tile(button,spec.title,"%d W · %d I · site materials only, no Keep range needed" % [spec.wood,spec.iron])
		elif pair[0] == &"chapterhouse":
			set_tile(button,spec.title,"%d F · %d W · %d I · from a covering Keep's stock, else Wood & Iron on site" % [spec.food,spec.wood,spec.iron])
		elif pair[0] == &"forge":
			set_tile(button,spec.title,"%d W · %d I · from a covering Keep's stock, else on site · researches Arms and Mail" % [spec.wood,spec.iron])
		elif pair[0] == &"farm":
			set_tile(button,spec.title,"%d W · inside a Keep's range, from its stock · one Forester tills it for Food" % spec.wood)
		elif pair[0] == &"house":
			set_tile(button,spec.title,"%d W · +%d housing while inside a Keep's range" % [spec.wood,KnightHousing.rules().house_room])
		else: set_tile(button,spec.title,"%d E · %d I · iron delivered to the site, energy as built" % [spec.energy,spec.iron])
func toggle_pin() -> void:
	if not global_pinned:
		game.global_plan_kind = &""
		game.pending_unit_command = "pin"
		game.notify("Pin: choose a paying Depot or deployed Cargo truck on the map or minimap.")
		return
	global_pinned = false; global_payer = null
	game.notify("New plans pay from the nearest covering Depot or deployed Cargo truck that can pay.")

# Map picking for Load, Unload and Pin: the card becomes a prompt, and eligible stops pulse on the minimap.
func pick_prompt() -> String:
	if crate_page_open:
		if is_instance_valid(shown) and shown.is_in_group("depots") and shown.team == "player": return "MAKE CRATES"
		crate_page_open = false
	match game.pending_unit_command:
		"load":
			if selected_cargo() != null: return "LOAD · CHOOSE A STOP"
		"unload":
			if selected_cargo() != null: return "UNLOAD · CHOOSE A STOP\nLeft-click a Depot on the map or minimap to unpack there, a build site to deliver its materials, or open ground to set crates down. Shift queues. Right-click or Esc cancels."
		"pin":
			if global_build_open: return "PIN A PAYER\nLeft-click a Depot or deployed Cargo truck on the map or minimap. New plans pay only from it. Right-click or Esc cancels."
	return ""
func pick_stops() -> Array[Node3D]:
	var stops: Array[Node3D] = []
	if pick_prompt().is_empty() or crate_page_open: return stops
	var vehicle := selected_cargo()
	for group in ["depots","mobile_supplies"]:
		for node in get_tree().get_nodes_in_group(group):
			if (SupplySource.available(node,"player") if game.pending_unit_command == "pin" else vehicle.shipment_endpoint(node)): stops.append(node)
	if game.pending_unit_command == "unload":
		for plan in get_tree().get_nodes_in_group("construction_plans"):
			if vehicle.stop_valid("unload",plan,plan.global_position): stops.append(plan)
	return stops
func pick_stop(stop: Node3D, queued := false) -> void:
	var mode: String = game.pending_unit_command
	if not pick_stops().has(stop):
		game.notify("Pick a friendly Depot%s." % (" or deployed Cargo truck" if mode == "pin" or not selected_cargo().is_in_group("rail_trains") else ""))
		return
	if mode == "pin":
		global_payer = stop; global_pinned = true
		game.pending_unit_command = ""
		game.notify("New plans pay only from %s. Press Pin again for Auto." % stop.name)
		return
	var ordered := 0
	for unit in selected_units():
		if unit.is_cargo_vehicle and unit.stop_valid(mode,stop,stop.global_position):
			game.give_order(unit,{kind = mode, target = stop, point = stop.global_position},queued)
			ordered += 1
	if ordered == 0: game.notify("Can't %s at %s." % [mode,stop.name]); return
	game.notify("%s at %s %s." % [mode.capitalize(),stop.name,"queued" if queued else "ordered"])
	if not queued: game.pending_unit_command = ""
