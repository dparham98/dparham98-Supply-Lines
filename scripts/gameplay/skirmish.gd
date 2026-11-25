extends Node3D
@export var starting_ore := 0
@export var tracer_scene: PackedScene
@export var pile_scene: PackedScene
## Vehicles burn and refuel coal (docs/FUEL_BATCH.md). Earlier-batch exercise scenes turn this off.
@export var vehicle_fuel_required := false
## Testing coal grant until coal extraction exists: a shared coal pile at Entities/Resources/TestingCoalPoint.
@export var testing_coal_amount := 0
## Development-only playtest panel on F10 (docs/PLAYTEST_TOOLS.md). Needs a debug build.
@export var playtest_tools := false
## Whether Depots take the DepotRules testing iron grant. The balanced map turns it off so a match starts
## with no iron (docs/BALANCED_MAP.md).
@export var testing_iron_grant := true
## Whether vehicles built at Depots and factories, or spawned from the playtest panel, start with a full
## tank (FuelRules.full_tanks_for). The balanced map turns it off: they start empty and fill from Depot coal.
@export var testing_full_tanks := true
func drop_material(unit: Node3D) -> Node3D:
	if not unit.can_gather or unit.cargo <= 0 or unit.cargo_kind not in [&"iron",&"wood",&"coal",&"food"]: return null
	var pile = pile_scene.instantiate()
	pile.material_kind = str(unit.cargo_kind); pile.amount = unit.cargo
	pile.position = unit.global_position
	get_node("Entities/Resources").add_child(pile,true)
	unit.cargo = 0
	unit.state = "Materials dropped"
	return pile

# Compatibility alias: starting Depot iron only, never a global pool.
var ore: int:
	get: return depot.iron if is_instance_valid(depot) else 0
	set(value):
		if is_instance_valid(depot): depot.iron = value
var global_plan_kind: StringName = &""
## The selected building shows its team marker (docs/TEAM_MARKERS.md).
const Rally = preload("res://scripts/production/rally.gd")
## The selected building, or an enemy unit being inspected (docs/SELECTION_INSPECT.md). Your buildings of one type
## can be selected together: selected_buildings holds them all, selected_building is the first.
var selected_buildings: Array[Node3D] = []
var selected_building: Node3D:
	set(value):
		for node in _marked(): _show_team_marker(node,false)
		selected_building = value
		if not selected_buildings.has(value):
			selected_buildings.clear()
			if is_instance_valid(value) and value.is_in_group("selectable_buildings") and value.get("team") == "player": selected_buildings.append(value)
		for node in _marked(): _show_team_marker(node,true)
func _marked() -> Array[Node3D]:
	var nodes: Array[Node3D] = selected_buildings.filter(func(node): return is_instance_valid(node))
	if is_instance_valid(selected_building) and not nodes.has(selected_building): nodes.append(selected_building)
	return nodes
## Selects your buildings of one type together; the first is the one the card shows.
func select_buildings(nodes: Array[Node3D]) -> void:
	for node in _marked(): _show_team_marker(node,false)
	selected_buildings = nodes.duplicate()
	selected_building = nodes[0] if not nodes.is_empty() else null
## The selected buildings still standing.
func building_selection() -> Array[Node3D]:
	var nodes: Array[Node3D] = selected_buildings.filter(func(node): return is_instance_valid(node) and node.is_inside_tree())
	return nodes
var pending_unit_command := ""
## Track laying (docs/RAIL_PLANNING.md). Leaving it, however it is left, drops any track still only planned.
var placing_rail := false:
	set(value):
		placing_rail = value
		if not value and is_inside_tree() and has_node("RailNetwork"): $RailNetwork.drop_route()
var placing_depot := false
var placing_generator := false
var placing_structure: StringName = &""
var ore_delivered := 0
var wood_delivered := 0
var units_printed := 0
var enemies_killed := 0
var outcome := ""
## Set by the main menu's match (docs/MAIN_MENU.md, MatchSetup.apply). Spectating: an AI plays each side and the HUD
## only inspects. Sandbox: no opponent, so neither side can win.
var spectating := false
var sandbox := false
## Each side's faction. Only the Cyborgs exist yet; rosters will be picked by faction later.
var factions := {"player": &"cyborgs", "enemy": &"cyborgs"}
@export var message := "Select your Deforester, then right-click the marked iron deposit."
@onready var depot: Node3D = get_node_or_null("Entities/Buildings/Depot") if has_node("Entities/Buildings/Depot") else get_node_or_null("Entities/Buildings/Keep")
@onready var ground = $Terrain/Ground
@onready var hud = $Interface
func _ready() -> void:
	message_time = Time.get_ticks_msec()/1000.0
	if is_instance_valid(depot) and not depot.is_in_group("keeps") and depot.rules.testing_starting_iron < 0: ore = starting_ore
	if testing_coal_amount > 0 and has_node("Entities/Resources/TestingCoalPoint"):
		var pile = pile_scene.instantiate()
		pile.name = "TestingCoalPile"
		pile.material_kind = "coal"; pile.amount = testing_coal_amount
		pile.position = get_node("Entities/Resources/TestingCoalPoint").position
		get_node("Entities/Resources").add_child(pile)
	if is_instance_valid(depot): $DepotNetwork.select_depot(depot)
	var setup = get_node_or_null("/root/MatchSetup")
	if setup != null: setup.apply(self)
## The AI playing the West start while spectating, or null.
func player_ai() -> Node:
	var node = get_node_or_null("PlayerAI")
	return node if node != null and node.process_mode != Node.PROCESS_MODE_DISABLED else null
func armed() -> bool:
	return not global_plan_kind.is_empty() or placing_rail or placing_depot or placing_generator or not placing_structure.is_empty() or not pending_unit_command.is_empty()
# Esc, pausing and paused clicks drop any armed command or placement.
func cancel_armed() -> void:
	global_plan_kind = &""
	if is_instance_valid(hud): hud.crate_page_open = false
	placing_rail = false
	placing_depot = false
	placing_generator = false
	placing_structure = &""
	pending_unit_command = ""
	fell_dragging = false
	$DepotNetwork.clear_builder()
## When the header message last changed, for its fade (docs/HUD_POLISH.md).
var message_time := 0.0
## A message for the player; one about another side's doings (`team`, the enemy player's) is not shown.
func notify(text: String, team := "player") -> void:
	if team != "player": return
	message = text
	message_time = Time.get_ticks_msec()/1000.0
# Positioned alerts for the HUD feed, newest first. A key repeats at most every ALERT_REPEAT_SECONDS.
var alerts: Array[Dictionary] = []
var _alert_times := {}
const ALERT_REPEAT_SECONDS := 10.0
const ALERT_LIMIT := 8
func alert(text: String, at: Vector3, key := "", kind := "") -> void:
	var now := Time.get_ticks_msec()/1000.0
	if not key.is_empty():
		if now-_alert_times.get(key,-INF) < ALERT_REPEAT_SECONDS: return
		for old in _alert_times.keys():
			if now-_alert_times[old] >= ALERT_REPEAT_SECONDS: _alert_times.erase(old)
		_alert_times[key] = now
	alerts.push_front({text = text, point = at, time = now, kind = kind})
	if alerts.size() > ALERT_LIMIT: alerts.resize(ALERT_LIMIT)
# Map overlay hooks: when something was last hit, and resources arriving at a stockpile.
var attacked_at := {}
signal resources_delivered(target: Node3D, kind: StringName, amount: int)
const ATTACK_MARK_SECONDS := 3.0
func mark_attacked(target: Node3D) -> void:
	var now := Time.get_ticks_msec()/1000.0
	if attacked_at.size() > 64:
		for id in attacked_at.keys():
			if now-attacked_at[id] > ATTACK_MARK_SECONDS: attacked_at.erase(id)
	attacked_at[target.get_instance_id()] = now
func recently_attacked(target: Node3D) -> bool:
	return Time.get_ticks_msec()/1000.0-attacked_at.get(target.get_instance_id(),-INF) <= ATTACK_MARK_SECONDS
func delivered(target: Node3D, kind: StringName, amount: int) -> void:
	resources_delivered.emit(target,kind,amount)
func unit_died(unit: Node3D) -> void:
	if unit.team == "enemy": enemies_killed += 1; notify("Hostile eliminated.")
	elif unit.team == "player": alert("%s lost" % hud.object_name(unit),unit.global_position,"","lost")
func _process(_delta: float) -> void:
	# First Contact's goal; a map with an enemy player is won by beating it (docs/ENEMY_AI.md).
	if enemy_player() == null and not sandbox and ore_delivered > 0 and units_printed > 0 and enemies_killed > 0: outcome = "VICTORY — gather, print, fight complete!"
	# Spectating, the side whose AI has nothing left loses; the AIs' own messages are written for a player.
	if spectating:
		var west := player_ai()
		var east := enemy_player()
		if west != null and west.defeated: outcome = "EAST AI WINS — the West has nothing left."
		elif east != null and east.defeated: outcome = "WEST AI WINS — the East has nothing left."
		return
	var players := 0
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.team == "player": players += 1
	var recovery := false
	for local in get_tree().get_nodes_in_group("depots"):
		if local.team != "player": continue
		if local.is_in_group("keeps"):
			if local.queue > 0 or local.food >= 30: recovery = true
		elif local.queue > 0 or ((local.energy >= local.rules.depot_energy_cost or local.generation_rate() > 0) and local.iron >= local.rules.depot_iron_cost): recovery = true
	for local in get_tree().get_nodes_in_group("depots"):
		if local.team == "player" and local.construction_infantry_pending: recovery = true
	for building in get_tree().get_nodes_in_group("production_buildings"):
		if not building.source_friendly(): continue
		if building.queue > 0: recovery = true
		for scene in building.stats.unit_scenes:
			var stats = building.unit_stats_for(scene)
			var labor_ok: bool = building.assigned_depot.food >= stats.food_cost if stats.food_cost > 0 else (building.assigned_depot.energy >= stats.energy_cost or building.assigned_depot.generation_rate() > 0)
			if labor_ok and building.assigned_depot.iron >= stats.iron_cost: recovery = true
	if players == 0 and not recovery: outcome = "DEFEAT — no units or local production funds remaining."
## The track piece type being laid, and which of its ends joins the track.
## Track-laying keys (docs/RAIL_PLANNING.md): Enter lays the suggested path and Backspace takes back the second
## building, or the first when there is no second. They belong to track laying while it is armed: button shortcuts
## run before _unhandled_input and the Build page stays open while laying.
const RAIL_KEYS := [KEY_ENTER,KEY_KP_ENTER,KEY_BACKSPACE]
func _input(event: InputEvent) -> void:
	if not placing_rail or not event is InputEventKey or not event.pressed: return
	if not event.physical_keycode in RAIL_KEYS: return
	get_viewport().set_input_as_handled()
	if not event.echo: _rail_key(event.physical_keycode)
const RAIL_HELP := "Click two buildings (Depots, mines or build sites) to connect; the suggested track follows the cursor and is green when a Depot can pay for it. Click (or Enter) lays it; Backspace undoes; Esc stops. Click a wreck of your track to rebuild it."
func _rail_key(key: int) -> void:
	var rails = $RailNetwork
	if key == KEY_BACKSPACE:
		if is_instance_valid(rails.route_to):
			rails.clear_plan(); rails.route_to = null
			notify("Click the building to connect %s to." % rails.target_name(rails.route_from))
		else:
			rails.drop_route()
			notify("Click a Depot, mine or build site to connect.")
	else: lay_route()
## Lays the suggested track; leaves rail mode once it is down.
func lay_route() -> void:
	var laid: Array[Node3D] = $RailNetwork.commit_plan(_rail_pin())
	if not laid.is_empty():
		placing_rail = false
## The pinned payer for track, or null.
func _rail_pin():
	return hud.global_payer if hud.global_pinned and is_instance_valid(hud.global_payer) else null
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE: cancel_armed()
	# Actor selection takes precedence over armed world actions.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if (not global_plan_kind.is_empty() or placing_depot or placing_generator or not placing_structure.is_empty() or pending_unit_command == "move") and get_node("/root/SelectionManager").switch_at(event.position):
			get_viewport().set_input_as_handled()
			return
	if not global_plan_kind.is_empty() and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var camera := get_viewport().get_camera_3d()
		var point = Plane(Vector3.UP,0).intersects_ray(camera.project_ray_origin(event.position),camera.project_ray_normal(event.position))
		if point != null: place_global_plan(point,event.shift_pressed)
		get_viewport().set_input_as_handled()
		return
	# The suggested track follows the cursor (docs/RAIL_PLANNING.md).
	if placing_rail and event is InputEventMouseMotion:
		var camera := get_viewport().get_camera_3d()
		$RailNetwork.cursor = Plane(Vector3.UP,0).intersects_ray(camera.project_ray_origin(event.position),camera.project_ray_normal(event.position))
	if placing_rail and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var camera := get_viewport().get_camera_3d()
		var point = Plane(Vector3.UP,0).intersects_ray(camera.project_ray_origin(event.position),camera.project_ray_normal(event.position))
		# A click picks a building to connect; the second pick suggests the track, which then follows the cursor.
		# With a track suggested, a click lays it (docs/RAIL_PLANNING.md).
		if point != null:
			var rails = $RailNetwork
			# A click on a wreck of your track rebuilds it (docs/DERAILER.md).
			var wreck = rails.wreck_at(point) if rails.pending.is_empty() else null
			if wreck != null:
				if rails.rebuild(wreck,_rail_pin()) != null: placing_rail = false
			elif is_instance_valid(rails.route_to) and not rails.pending.is_empty(): lay_route()
			else: notify(rails.pick_target(rails.pick_at(point)))
		get_viewport().set_input_as_handled()
		return
	if (placing_depot or placing_generator or not placing_structure.is_empty()) and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var camera := get_viewport().get_camera_3d()
		var point = Plane(Vector3.UP,0).intersects_ray(camera.project_ray_origin(event.position),camera.project_ray_normal(event.position))
		if point != null:
			var success: bool = $DepotNetwork.construct_production(point,placing_structure) if not placing_structure.is_empty() else ($DepotNetwork.construct_generator(point) if placing_generator else $DepotNetwork.construct(point))
			if success:
				placing_rail = false
				placing_depot = false
				placing_generator = false
				placing_structure = &""
		get_viewport().set_input_as_handled()
		return
	# Fell also takes a box: drag across the trees to fell (docs/FELL.md).
	if pending_unit_command == "fell" and fell_dragging and event is InputEventMouseMotion:
		fell_drag_to = event.position
	if pending_unit_command == "fell" and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			fell_dragging = true
			fell_drag_from = event.position
			fell_drag_to = event.position
		elif fell_dragging:
			fell_dragging = false
			if fell_drag_from.distance_to(event.position) < FELL_DRAG: issue_card_order(fell_drag_from,event.shift_pressed)
			else: order_fell_box(fell_drag_from,event.position,event.shift_pressed)
		get_viewport().set_input_as_handled()
		return
	if not pending_unit_command.is_empty() and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		issue_card_order(event.position,event.shift_pressed)
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_RIGHT: return
	# A spectator gives no orders.
	if spectating: return
	# Right-click cancels an armed command or placement instead of giving an order.
	if armed():
		cancel_armed(); notify("Command cancelled.")
		get_viewport().set_input_as_handled()
		return
	issue_order(event.position,event.shift_pressed)
	get_viewport().set_input_as_handled()
## Places the armed plan. From a truck's Worksite page (docs/TRUCK_WORKSITES.md) the selected trucks
## also fetch its materials; Shift keeps placing and queues their fetches.
func place_global_plan(point: Vector3, queued := false) -> Node3D:
	var worksite: bool = hud.worksite_open
	var payer: Node3D = hud.global_payer if not worksite and is_instance_valid(hud.global_payer) else null
	var plan = $DepotNetwork.queue_plan(point,global_plan_kind,payer,hud.global_pinned and not worksite,not worksite)
	if plan == null: return null
	if worksite:
		var trucks: Array[Node3D] = hud.worksite_trucks()
		for truck in trucks: give_order(truck,{kind = "fetch", target = plan},queued)
		var materials := PackedStringArray()
		for kind in plan.materials(): materials.append("%d %s" % [plan.materials()[kind],kind])
		notify("%s worksite placed. %s %s, then order Deforesters to construct it." % [plan.spec.title,"The truck brings" if trucks.size() == 1 else "%d trucks bring" % trucks.size()," and ".join(materials)])
		if not queued:
			global_plan_kind = &""
			hud.close_build()
		return plan
	# Rail stays armed so a line can be laid tile by tile; Esc or right-click finishes.
	if global_plan_kind != &"rail": global_plan_kind = &""
	return plan
## The friendly crate under the pointer, if any.
## `screen` in the picking helpers below is the pointer's screen position, or a MapPick from the minimap.
func pick_crate(screen) -> Node3D:
	var crate := pick_target(screen,"supply_crates")
	return crate if is_instance_valid(crate) and crate.team == "player" else null
func pick_target(screen, group: String, _radius := 34.0) -> Node3D:
	var camera := get_viewport().get_camera_3d()
	var closest: Node3D
	var distance := INF
	for node in get_tree().get_nodes_in_group(group):
		var d: float = pick_distance(node,camera,screen)
		if d < distance: distance = d; closest = node
	return closest
## A minimap click standing in for the pointer (docs/MINIMAP_ORDERS.md): a ground point, and how near a
## marker must be to it to be picked.
class MapPick:
	var point: Vector3
	var radius: float
	func _init(at: Vector3, within: float) -> void:
		point = at
		radius = within
## Gives the order a click at `point` would give: a right-click order, or with `card` the waiting command's.
## The map's own order rules run, with the minimap point in place of the pointer.
func issue_map_order(point: Vector3, radius: float, card: bool, queued := false) -> void:
	var pick := MapPick.new(point,radius)
	if card: issue_card_order(pick,queued)
	else: issue_order(pick,queued)
## The ground under the pointer, or the minimap's point.
func ground_at(screen):
	if screen is MapPick: return screen.point
	var camera := get_viewport().get_camera_3d()
	return Plane(Vector3.UP,0).intersects_ray(camera.project_ray_origin(screen),camera.project_ray_normal(screen))
const SelectionBounds = preload("res://scripts/units/selection_bounds.gd")
const FellLane = preload("res://scripts/terrain/fell_lane.gd")
## How near `node` is to the pointer, or INF when it is missed. From the minimap it is the ground distance
## from the point to the node's model bounds, so a large building is picked anywhere on its footprint.
func pick_distance(node: Node3D, camera: Camera3D, screen) -> float:
	if not screen is MapPick: return SelectionBounds.hit_distance(node,camera,screen)
	# The other side's things hidden by fog of war cannot be picked from the minimap either.
	var fog := fog_of_war()
	if fog != null and not fog.shows(node): return INF
	var at := Vector2(screen.point.x,screen.point.z)
	var d := Vector2(node.global_position.x,node.global_position.z).distance_to(at)
	for mesh in SelectionBounds.meshes(node):
		var box: AABB = mesh.global_transform*mesh.get_aabb()
		var nearest := at.clamp(Vector2(box.position.x,box.position.z),Vector2(box.end.x,box.end.z))
		d = minf(d,nearest.distance_to(at))
	return d if d <= screen.radius else INF
## A damaged vehicle of yours under the pointer, for Infantry to repair (docs/VEHICLE_REPAIR.md).
func pick_vehicle_to_repair(screen) -> Node3D:
	var camera := get_viewport().get_camera_3d()
	var closest: Node3D
	var distance := INF
	for node in get_tree().get_nodes_in_group("units"):
		if node.get("team") != "player" or node.health >= node.max_health or not EngineeringWork.is_vehicle(node): continue
		var d: float = pick_distance(node,camera,screen)
		if d < distance: distance = d; closest = node
	return closest
## A damaged friendly non-vehicle unit under the pointer, for Grail Sentinels to heal.
func pick_unit_to_heal(screen) -> Node3D:
	var camera := get_viewport().get_camera_3d()
	var closest: Node3D
	var distance := INF
	for node in get_tree().get_nodes_in_group("units"):
		if not MedicalWork.can_heal(node,"player"): continue
		var d: float = pick_distance(node,camera,screen)
		if d < distance: distance = d; closest = node
	return closest
## A friendly unit or building under the pointer, for forced fire with the Attack command.
func pick_friendly(screen: Vector2) -> Node3D:
	var camera := get_viewport().get_camera_3d()
	var closest: Node3D
	var distance := INF
	for group in ["units","selectable_buildings"]:
		for node in get_tree().get_nodes_in_group(group):
			if node.get("team") != "player" or not node.has_method("take_damage"): continue
			var d: float = SelectionBounds.hit_distance(node,camera,screen)
			if d < distance: distance = d; closest = node
	return closest
# Shift-held orders join each unit's queue; plain orders replace it (docs/COMMAND_QUEUE.md).
signal order_given(kind: String, point: Vector3, target: Node3D, queued: bool)
func give_order(unit: Node3D, entry: Dictionary, queued: bool) -> void:
	var target: Node3D = entry.get("target")
	order_given.emit(entry.kind,target.global_position if is_instance_valid(target) else entry.get("point",Vector3.ZERO),target if is_instance_valid(target) else null,queued)
	if queued: unit.queue_order(entry)
	else:
		unit.order_queue.clear()
		unit.run_order(entry)
## Your selected building that takes a rally point, when no units are selected (docs/RALLY_POINTS.md).
func rally_building() -> Node3D:
	if not is_instance_valid(selected_building) or selected_building.get("team") != "player" or not "rally_points" in selected_building: return null
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.team == "player" and unit.is_selected: return null
	return selected_building
## Right-click on the ground or the minimap sets the rally point; on a resource or forest the workers gather
## there; on the building itself it is cleared. Shift adds a stop.
func set_rally(screen, queued := false) -> void:
	var building := rally_building()
	# Every selected building of the type takes the same rally (docs/SELECTION_INSPECT.md).
	var rallied: Array[Node3D] = building_selection().filter(func(node): return node.get("team") == "player" and "rally_points" in node)
	if not rallied.has(building): rallied.append(building)
	var clicked = pick_target(screen,"selectable_buildings",50) if not screen is MapPick else null
	if clicked != null and rallied.has(clicked):
		for node in rallied: node.rally_points.clear()
		notify("Rally point cleared: new units stay by %s." % ("their buildings" if rallied.size() > 1 else building.name)); return
	var point = ground_at(screen)
	var cell = ground.get_tile_at_position(point) if point != null else null
	if cell == null: notify("Right-click on the map to set a rally point."); return
	var target: Node3D = pick_target(screen,"resources",48)
	if target == null and ground.get_terrain(cell) == 3: target = ground.forest_source(cell)
	for node in rallied: Rally.add(node,point,target,queued)
	order_given.emit("move",point,target,queued)
	notify("Rally %s: new units %s." % ["stop added" if queued else "point set","gather here (workers) or go here" if target != null else "go here"])
func _coal_plan_at(cell: Vector2i) -> Node3D:
	var field: Dictionary = ground.coal_field_at(cell)
	if field.is_empty(): return null
	for plan in get_tree().get_nodes_in_group("construction_plans"):
		if not is_instance_valid(plan) or plan.finished or plan.kind != &"coal_mine" or plan.team != "player": continue
		if field.get("cells",[]).has(plan.start): return plan
	return null
func issue_order(screen, queued := false) -> void:
	# From the minimap a click lands near markers rather than on them, so the orders that only make sense
	# when aimed at a model are left out (docs/MINIMAP_ORDERS.md).
	var from_map: bool = screen is MapPick
	if rally_building() != null: set_rally(screen,queued); return
	var enemy := pick_target(screen,"enemies")
	var resource := pick_target(screen,"resources",48)
	var dropoff := pick_target(screen,"depots",50)
	var mobile := pick_target(screen,"mobile_supplies",34)
	if is_instance_valid(mobile) and mobile.team == "player": dropoff = mobile
	var building := pick_target(screen,"selectable_buildings",50)
	var plan := pick_target(screen,"construction_plans",50)
	if is_instance_valid(plan) and (plan.finished or plan.kind == &"rail"): plan = null
	var crate := pick_crate(screen)
	var vehicle := pick_vehicle_to_repair(screen)
	var patient := pick_unit_to_heal(screen)
	var point = ground_at(screen)
	if plan == null and point != null:
		var coal_cell = ground.get_tile_at_position(point)
		if coal_cell != null and ground.get_terrain(coal_cell) == 6 and ground.harvesting_rules.coal_needs_mine:
			plan = _coal_plan_at(coal_cell)
	var selected := 0
	var forest_ordered := false
	var coal_ordered: Node3D
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.team != "player" or not unit.is_selected: continue
		selected += 1
		if enemy: give_order(unit,{kind = "attack", target = enemy},queued)
		# Build sites: trucks unload what they carry onto the site; workers construct (delivering carried cargo first).
		elif plan and unit.is_cargo_vehicle and not unit.is_in_group("rail_trains"): give_order(unit,{kind = "fetch", target = plan},queued)
		elif plan and unit.can_construct and not unit.is_cargo_vehicle and not unit.is_depot_truck: give_order(unit,{kind = "construct", target = plan},queued)
		elif crate and unit.is_cargo_vehicle and not unit.is_in_group("rail_trains"): give_order(unit,{kind = "load", target = crate, point = crate.global_position},queued)
		elif crate and unit.can_gather and unit.cargo > 0 and crate.accepts(unit.cargo_kind): give_order(unit,{kind = "return", target = crate},queued)
		# A damaged vehicle of yours: workers repair it, unless they are bringing cargo to it.
		elif vehicle and vehicle != unit and unit.can_repair and not (unit.cargo > 0 and vehicle == dropoff): give_order(unit,{kind = "repair", target = vehicle},queued)
		elif patient and patient != unit and unit.can_heal: give_order(unit,{kind = "heal", target = patient},queued)
		elif point != null and ground.get_tile_at_position(point) != null and ground.get_terrain(ground.get_tile_at_position(point)) == 3 and unit.can_gather:
			give_order(unit,{kind = "gather", target = ground.forest_source(ground.get_tile_at_position(point))},queued)
			forest_ordered = true
		elif point != null and ground.get_tile_at_position(point) != null and ground.get_terrain(ground.get_tile_at_position(point)) == 6 and unit.can_gather:
			# Coal comes through a mine on the seam; where the old rule is on, straight from the cell.
			if ground.harvesting_rules.coal_needs_mine:
				var seam_mine = ground.coal_mine_at(ground.get_tile_at_position(point))
				if seam_mine != null: give_order(unit,{kind = "gather", target = seam_mine},queued)
				else: notify("Build a Mine on this coal seam before gathering coal.")
			else:
				coal_ordered = ground.coal_source(ground.get_tile_at_position(point))
				give_order(unit,{kind = "gather", target = coal_ordered},queued)
		elif dropoff and dropoff.is_in_group("mobile_supplies") and unit.can_gather: give_order(unit,{kind = "return", target = dropoff},queued)
		elif resource: give_order(unit,{kind = "gather", target = resource},queued)
		elif dropoff and dropoff.team == unit.team and unit.cargo > 0: give_order(unit,{kind = "return", target = dropoff},queued)
		elif building and building.team == unit.team and building.health < building.max_health and unit.can_repair: give_order(unit,{kind = "repair", target = building},queued)
		elif building and building.is_in_group("capturable_buildings") and building.team != unit.team and unit.can_capture_depots: give_order(unit,{kind = "capture", target = building},queued)
		elif building and CombatResolver.can_hit(unit,building): give_order(unit,{kind = "attack", target = building},queued)
		elif dropoff and dropoff.team == unit.team and not from_map: give_order(unit,{kind = "return", target = dropoff},queued)
		elif point != null and unit.can_gather and ground.get_tile_at_position(point) != null and ground.get_terrain(ground.get_tile_at_position(point)) in [5,7]:
			notify("Build an Iron Mine on this deposit before gathering iron.")
		elif point != null:
			var cell = ground.get_tile_at_position(point)
			if cell != null and ground.can_traverse(cell,unit.mobility_layer(),unit._owner_key()): give_order(unit,{kind = "move", point = point},queued)
			else: notify("That terrain is blocked. Right-click open land, resources, or a hostile.")
	if selected == 0: notify("Left-click a Deforester first.")
	elif queued: notify("Order queued. Shift-right-click adds more; a plain order replaces the queue.")
	elif enemy: notify("Attack order: approach and fire at range.")
	elif plan: notify("Build site: Cargo vehicles fetch exactly the materials it lacks; Deforesters construct from the pile.")
	elif crate: notify("Crate order: vehicles load it; workers deliver into it or gather from it.")
	elif forest_ordered: notify("Harvest wood from the forest tile and deliver it to a friendly Depot.")
	elif is_instance_valid(coal_ordered): notify("Dig coal and deliver it to a friendly Depot. %d left in this field; workers fell any trees in their way and move on through it cell by cell." % coal_ordered.field_remaining())
	elif resource: notify("Gather %s and deliver to a friendly Depot." % resource.resource_kind)
	elif dropoff and not from_map: notify("Return carried resources or repair this Depot.")
func show_shot(start: Vector3, end: Vector3, team: String, projectile: PackedScene = null) -> Node3D:
	var shot = (projectile if projectile != null else tracer_scene).instantiate()
	add_child(shot)
	shot.configure(start,end,team)
	# Under fog of war (docs/FOG_OF_WAR.md) the other side's shots show only where the player can see them land
	# or leave.
	var fog := fog_of_war()
	if fog != null and team != fog.viewer and not fog.visible_to(fog.viewer,start) and not fog.visible_to(fog.viewer,end): shot.visible = false
	return shot
## Units bucketed by where they stand, for "who is near me" questions (UnitGrid, docs/COMBAT_BATCH.md).
const UnitGrid = preload("res://scripts/combat/unit_grid.gd")
var _unit_grid := UnitGrid.new()
## Units standing within about `radius` of `point`, perhaps with a few just beyond and some freed (UnitGrid).
func units_near(point: Vector3, radius: float) -> Array:
	return _unit_grid.near(get_tree(),point,radius)
## Whether an effect at `point` could be seen: on the screen, or within `margin` (a share of the screen's size) of
## its edge. Death clips and shell bursts nobody can see are skipped: each is tens to hundreds of animated pieces,
## and in a big battle most of them happened off screen. Without a window (the headless checks) all count as seen.
func in_view(point: Vector3, margin := 0.2) -> bool:
	if DisplayServer.get_name() == "headless": return true
	var camera := get_viewport().get_camera_3d()
	if camera == null: return true
	if camera.is_position_behind(point): return false
	var screen := get_viewport().get_visible_rect()
	return screen.grow_individual(screen.size.x*margin,screen.size.y*margin,screen.size.x*margin,screen.size.y*margin).has_point(camera.unproject_position(point))
## A unit joined or left the "units" group.
func units_changed() -> void:
	_unit_grid.changed()
## The map's fog of war (docs/FOG_OF_WAR.md), or null on a map without one.
## The enemy player on this map (docs/ENEMY_AI.md), or null.
func enemy_player() -> Node:
	return get_node_or_null("EnemyPlayer")
func fog_of_war() -> Node:
	return get_tree().get_first_node_in_group("fog_of_war")

## A Fell box being dragged, in screen pixels (docs/FELL.md). Shorter drags are clicks.
const FELL_DRAG := 6.0
var fell_dragging := false
var fell_drag_from := Vector2.ZERO
var fell_drag_to := Vector2.ZERO
## Fell across the cells under a dragged screen box: the grid box round the four corners on the ground.
func order_fell_box(from: Vector2, to: Vector2, queued := false) -> void:
	var camera := get_viewport().get_camera_3d()
	var low := Vector2i(ground.grid_size)
	var high := Vector2i(-1,-1)
	for corner in [from,Vector2(to.x,from.y),to,Vector2(from.x,to.y)]:
		var point = Plane(Vector3.UP,0).intersects_ray(camera.project_ray_origin(corner),camera.project_ray_normal(corner))
		if point == null: continue
		var cell: Vector2i = ground.clamped_tile_at(point)
		low = Vector2i(mini(low.x,cell.x),mini(low.y,cell.y))
		high = Vector2i(maxi(high.x,cell.x),maxi(high.y,cell.y))
	if high.x < 0: return
	var area := Rect2i(low,high-low+Vector2i.ONE)
	var middle: Vector2i = area.position+area.size/2
	order_fell(middle,area,ground.tile_to_world(middle),queued)
## Whether `unit` has a tree to fell for this order: in the box; or on its line to `cell`, or round `cell`.
func _fell_has_trees(unit: Node3D, cell: Vector2i, area: Rect2i) -> bool:
	var reach: int = ground.harvesting_rules.fell_radius_cells
	var box := area if area.has_area() else Rect2i(cell-Vector2i.ONE*reach,Vector2i.ONE*(reach*2+1))
	for z in range(box.position.y,box.end.y):
		for x in range(box.position.x,box.end.x):
			var at := Vector2i(x,z)
			if ground.forest_amount(at) > 0 and (area.has_area() or cell.distance_squared_to(at) <= reach*reach): return true
	if area.has_area(): return false
	var here = ground.get_tile_at_position(unit.global_position)
	return here != null and not FellLane.lane(ground,here,cell).is_empty()
## Fell to `cell`, or across `area`, for the selected workers (docs/FELL.md).
func order_fell(cell: Vector2i, area: Rect2i, point: Vector3, queued := false) -> void:
	var workers: Array[Node3D] = []
	var trees := false
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.team != "player" or not unit.is_selected or not unit.can_gather or unit.is_depot_truck or unit.is_cargo_vehicle: continue
		workers.append(unit)
		# A queued order starts from wherever the queue leaves the worker, so it is not checked.
		trees = trees or queued or _fell_has_trees(unit,cell,area)
	if workers.is_empty(): return
	if not trees:
		alert("No trees to fell in that box." if area.has_area() else "Nothing to fell: the way there is already open.",point)
		return
	for unit in workers: give_order(unit,{kind = "fell", cell = cell, area = area, point = point},queued)
	notify("Fell %s. %s" % ["queued" if queued else "ordered","Shift-click adds more; Esc stops." if queued else "The wood is left where it falls."])
	if not queued: pending_unit_command = ""
func issue_card_order(screen, queued := false) -> void:
	var from_map: bool = screen is MapPick
	var target: Node3D
	# Pin: the build page's paying stockpile.
	# The line a train queued at a Depot with several starts on (docs/RAIL_PLANNING.md).
	if pending_unit_command == "train_line":
		var depot: Node3D = hud.train_line_depot
		var point = ground_at(screen)
		var piece: Node3D = $RailNetwork.depot_line_at(depot,point) if is_instance_valid(depot) and point != null else null
		if piece == null: notify("Click one of %s's rail lines for the train." % (depot.name if is_instance_valid(depot) else "the Depot")); return
		pending_unit_command = ""
		if not depot.request_train(piece): notify("Depot lacks local train funds or queue space.")
		return
	# Launch balloon (docs/AIR_BALLOON.md): the selected Keep sends its packed crates to the clicked point.
	if pending_unit_command == "launch_balloon":
		var keep: Node3D = selected_building
		var point = ground_at(screen)
		if not is_instance_valid(keep) or not keep.is_in_group("keeps") or keep.team != "player": pending_unit_command = ""; return
		if point == null: notify("Click the map where the balloon should set its crates down."); return
		if keep.launch_balloon(point) and not queued: pending_unit_command = ""
		return
	# Lay mine (docs/MINES.md): the selected Derailers carrying mines go to the clicked point and lay one.
	if pending_unit_command == "lay_mine":
		var spot = ground_at(screen)
		if spot == null: notify("Click the map where the mine should go."); return
		var sent := 0
		for unit in get_tree().get_nodes_in_group("units"):
			if unit.team != "player" or not unit.is_selected or not unit.has_method("lay_mine_blocker") or not unit.lay_mine_blocker().is_empty(): continue
			give_order(unit,{kind = "lay_mine", point = spot},queued)
			sent += 1
		notify("Lay mine order issued." if sent > 0 else "No selected Derailer carries a mine.")
		if not queued or sent == 0: pending_unit_command = ""
		return
	if pending_unit_command == "pin":
		target = pick_target(screen,"depots",50)
		var stockpile := pick_target(screen,"mobile_supplies",34)
		if is_instance_valid(stockpile) and SupplySource.available(stockpile,"player"): target = stockpile
		if is_instance_valid(target): hud.pick_stop(target,queued)
		else: notify("Click a friendly Depot or deployed Cargo truck to pin it.")
		return
	if pending_unit_command == "attack":
		target = pick_target(screen,"enemies")
		if target == null:
			var building = pick_target(screen,"selectable_buildings",50)
			if is_instance_valid(building) and (building.team not in ["player","neutral"] or (building.is_in_group("mines") and not (from_map and building.team == "player"))): target = building
		# Nothing hostile under the pointer: the Attack command fires on a friendly unit or building. From the
		# minimap it attack-moves instead.
		if target == null and not from_map: target = pick_friendly(screen)
	elif pending_unit_command == "gather":
		target = pick_target(screen,"resources",48)
		if target == null:
			var point = ground_at(screen)
			if point != null and ground.get_tile_at_position(point) != null:
				var cell = ground.get_tile_at_position(point)
				if ground.get_terrain(cell) in [5,7]: notify("Build an Iron Mine on this deposit before gathering iron."); return
				if ground.get_terrain(cell) == 6 and ground.harvesting_rules.coal_needs_mine:
					target = ground.coal_mine_at(cell)
					if target == null: notify("Build a Mine on this coal seam before gathering coal."); return
				else: target = ground.coal_source(cell) if ground.get_terrain(cell) == 6 else ground.forest_source(cell)
	elif pending_unit_command == "fell":
		# Fell takes any spot: the trees on a roughly straight line to it are felled (docs/FELL.md).
		var point = ground_at(screen)
		if point != null and ground.get_tile_at_position(point) != null: order_fell(ground.get_tile_at_position(point),Rect2i(),point,queued)
		return
	elif pending_unit_command == "repair":
		target = pick_vehicle_to_repair(screen)
		if target == null: target = pick_target(screen,"selectable_buildings",50)
	elif pending_unit_command == "heal":
		target = pick_unit_to_heal(screen)
	elif pending_unit_command == "capture": target = pick_target(screen,"capturable_buildings",50)
	elif pending_unit_command == "mine_rail":
		# Mine iron (docs/TEMPLE_OF_SCIENCE.md) takes an Iron Mine; trains only.
		target = pick_target(screen,"mines",50)
		if target == null: notify("Click an Iron Mine joined to the train's track."); return
	elif pending_unit_command == "derail":
		# Derail takes a piece of track, anyone's (docs/DERAILER.md).
		var on = ground_at(screen)
		var hit: Dictionary = $RailNetwork.nearest_piece(on,$RailNetwork.probe("straight").half_width()+0.8) if on != null else {}
		if hit.is_empty(): notify("Click a piece of rail to destroy."); return
		target = hit.piece
	elif pending_unit_command in ["load","unload"]:
		# Crate stops: a crate, a friendly Depot, or a deployed Cargo vehicle under the pointer.
		target = pick_crate(screen)
		if target == null:
			target = pick_target(screen,"depots",50)
			var mobile := pick_target(screen,"mobile_supplies",34)
			if is_instance_valid(mobile) and mobile.get("deployed") == true: target = mobile
			# Unload also lands on a queued build site.
			var site := pick_target(screen,"construction_plans",50)
			if pending_unit_command == "unload" and is_instance_valid(site) and not site.finished and site.kind != &"rail": target = site
	var ground_point = ground_at(screen)
	# Attack on open ground is attack-move.
	if pending_unit_command == "attack" and not is_instance_valid(target) and ground_point != null:
		for unit in get_tree().get_nodes_in_group("units"):
			if unit.team == "player" and unit.is_selected: give_order(unit,{kind = "attack_move", point = ground_point},queued)
		notify("Attack-move %s. Units fire at anything in range on the way." % ("queued" if queued else "ordered"))
		if not queued: pending_unit_command = ""
		return
	# Deploy: only a valid footprint is accepted, so invalid sites can't be queued.
	if pending_unit_command == "deploy":
		if ground_point == null: return
		var accepted := 0
		for unit in get_tree().get_nodes_in_group("units"):
			if unit.team != "player" or not unit.is_selected or not unit.is_depot_truck: continue
			if not $DepotNetwork.can_deploy_at(unit,ground_point):
				var spaced: String = "" if $DepotNetwork.depot_spacing_ok(ground_point,unit.team,unit) else ", "+$DepotNetwork.spacing_reason()
				notify("Can't deploy there: the Depot footprint must be empty buildable land%s." % spaced); return
			give_order(unit,{kind = "deploy", point = ground_point},queued)
			accepted += 1
		if accepted > 0:
			notify("Deploy %s." % ("queued" if queued else "ordered"))
			if not queued: pending_unit_command = ""
		return
	# Load and Unload also take open ground: crates are picked up near, or set down at, that point.
	if pending_unit_command in ["load","unload"]:
		if not is_instance_valid(target) and ground_point == null: return
		var ordered := 0
		for unit in get_tree().get_nodes_in_group("units"):
			if unit.team != "player" or not unit.is_selected or not unit.is_cargo_vehicle: continue
			var point_or_target: Vector3 = target.global_position if is_instance_valid(target) else ground_point
			if not unit.stop_valid(pending_unit_command,target if is_instance_valid(target) and not (target.is_in_group("supply_crates") and pending_unit_command == "unload") else null,point_or_target):
				notify("Trains load and unload at friendly Depots." if unit.is_in_group("rail_trains") else "Can't %s there." % pending_unit_command); continue
			give_order(unit,{kind = pending_unit_command, target = target if is_instance_valid(target) else null, point = point_or_target},queued)
			ordered += 1
		if ordered > 0:
			notify(pending_unit_command.capitalize()+(" order queued. Shift-click adds more; Esc stops." if queued else " order issued."))
			if not queued: pending_unit_command = ""
		return
	if pending_unit_command != "move" and not is_instance_valid(target):
		notify("Click an appropriate target for "+pending_unit_command+".")
		return
	var point = ground_at(screen)
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.team != "player" or not unit.is_selected: continue
		if pending_unit_command == "move":
			if point != null: give_order(unit,{kind = "move", point = point},queued)
		elif pending_unit_command == "attack" and target.get("team") == unit.team: give_order(unit,{kind = "attack", target = target, forced = true},queued)
		elif pending_unit_command == "derail" and not unit.has_ability(&"derail"): continue
		elif pending_unit_command == "mine_rail" and not unit.is_in_group("rail_trains"): continue
		elif pending_unit_command == "heal" and not unit.can_heal: continue
		else: give_order(unit,{kind = pending_unit_command, target = target},queued)
	# Shift keeps the command armed so several targets can be queued.
	notify(pending_unit_command.capitalize()+(" order queued. Shift-click adds more; Esc stops." if queued else " order issued."))
	if not queued: pending_unit_command = ""
func _show_team_marker(building: Node3D, shown: bool) -> void:
	if not is_instance_valid(building): return
	var marker := building.get_node_or_null("Visuals/TeamMarker") as GeometryInstance3D
	if marker == null: return
	marker.set_instance_shader_parameter(&"team_color",preload("res://scripts/units/team_colors.gd").of(str(building.get("team"))))
	marker.visible = shown
