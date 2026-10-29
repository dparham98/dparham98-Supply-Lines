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
func drop_material(unit: Node3D) -> Node3D:
	if not unit.can_gather or unit.cargo <= 0 or unit.cargo_kind not in [&"iron",&"wood",&"coal"]: return null
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
var selected_building: Node3D
var pending_unit_command := ""
var placing_rail := false
var placing_depot := false
var placing_generator := false
var placing_structure: StringName = &""
var ore_delivered := 0
var wood_delivered := 0
var units_printed := 0
var enemies_killed := 0
var outcome := ""
@export var message := "Select your infantry, then right-click the marked iron deposit."
@onready var depot = $Entities/Buildings/Depot
@onready var ground = $Terrain/Ground
@onready var hud = $Interface
func _ready() -> void:
	if depot.rules.testing_starting_iron < 0: ore = starting_ore
	if testing_coal_amount > 0 and has_node("Entities/Resources/TestingCoalPoint"):
		var pile = pile_scene.instantiate()
		pile.name = "TestingCoalPile"
		pile.material_kind = "coal"; pile.amount = testing_coal_amount
		pile.position = get_node("Entities/Resources/TestingCoalPoint").position
		get_node("Entities/Resources").add_child(pile)
	$DepotNetwork.select_depot(depot)
func armed() -> bool:
	return not global_plan_kind.is_empty() or placing_rail or placing_depot or placing_generator or not placing_structure.is_empty() or not pending_unit_command.is_empty()
# Esc, pausing and paused clicks drop any armed command or placement.
func cancel_armed() -> void:
	global_plan_kind = &""
	placing_rail = false
	placing_depot = false
	placing_generator = false
	placing_structure = &""
	pending_unit_command = ""
	$DepotNetwork.clear_builder()
func notify(text: String) -> void:
	message = text
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
	if ore_delivered > 0 and units_printed > 0 and enemies_killed > 0: outcome = "VICTORY — gather, print, fight complete!"
	var players := 0
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.team == "player": players += 1
	var recovery := false
	for local in get_tree().get_nodes_in_group("depots"):
		if local.team == "player" and (local.queue > 0 or ((local.energy >= local.rules.depot_energy_cost or local.generation_rate() > 0) and local.iron >= local.rules.depot_iron_cost)): recovery = true
	for local in get_tree().get_nodes_in_group("depots"):
		if local.team == "player" and local.construction_infantry_pending: recovery = true
	for building in get_tree().get_nodes_in_group("production_buildings"):
		if not building.source_friendly(): continue
		if building.queue > 0: recovery = true
		for scene in building.stats.unit_scenes:
			var stats = building.unit_stats_for(scene)
			if (building.assigned_depot.energy >= stats.energy_cost or building.assigned_depot.generation_rate() > 0) and building.assigned_depot.iron >= stats.iron_cost: recovery = true
	if players == 0 and not recovery: outcome = "DEFEAT — no units or local production funds remaining."
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE: cancel_armed()
	# Actor selection takes precedence over armed world actions.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if (not global_plan_kind.is_empty() or placing_rail or placing_depot or placing_generator or not placing_structure.is_empty() or pending_unit_command == "move") and get_node("/root/SelectionManager").switch_at(event.position):
			get_viewport().set_input_as_handled()
			return
	if not global_plan_kind.is_empty() and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var camera := get_viewport().get_camera_3d()
		var point = Plane(Vector3.UP,0).intersects_ray(camera.project_ray_origin(event.position),camera.project_ray_normal(event.position))
		if point != null and $DepotNetwork.queue_plan(point,global_plan_kind,hud.global_payer if is_instance_valid(hud.global_payer) else null,hud.global_pinned) != null:
			global_plan_kind = &""
		get_viewport().set_input_as_handled()
		return
	if placing_rail and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var camera := get_viewport().get_camera_3d()
		var point = Plane(Vector3.UP,0).intersects_ray(camera.project_ray_origin(event.position),camera.project_ray_normal(event.position))
		if point != null: $RailNetwork.build(point)
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
	if not pending_unit_command.is_empty() and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		issue_card_order(event.position,event.shift_pressed)
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_RIGHT: return
	issue_order(event.position,event.shift_pressed)
	get_viewport().set_input_as_handled()
## The friendly crate under the pointer, if any.
func pick_crate(screen: Vector2) -> Node3D:
	var crate := pick_target(screen,"supply_crates")
	return crate if is_instance_valid(crate) and crate.team == "player" else null
func pick_target(screen: Vector2, group: String, _radius := 34.0) -> Node3D:
	var camera := get_viewport().get_camera_3d()
	var closest: Node3D
	var distance := INF
	for node in get_tree().get_nodes_in_group(group):
		var d: float = preload("res://scripts/units/selection_bounds.gd").hit_distance(node,camera,screen)
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
func issue_order(screen: Vector2, queued := false) -> void:
	var enemy := pick_target(screen,"enemies")
	var resource := pick_target(screen,"resources",48)
	var dropoff := pick_target(screen,"depots",50)
	var mobile := pick_target(screen,"mobile_supplies",34)
	if is_instance_valid(mobile) and mobile.team == "player": dropoff = mobile
	var building := pick_target(screen,"selectable_buildings",50)
	var crate := pick_crate(screen)
	var camera := get_viewport().get_camera_3d()
	var point = Plane(Vector3.UP,0).intersects_ray(camera.project_ray_origin(screen),camera.project_ray_normal(screen))
	var selected := 0
	var forest_ordered := false
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.team != "player" or not unit.is_selected: continue
		selected += 1
		if enemy: give_order(unit,{kind = "attack", target = enemy},queued)
		elif crate and unit.is_cargo_vehicle and not unit.is_in_group("rail_trains"): give_order(unit,{kind = "load", target = crate, point = crate.global_position},queued)
		elif crate and unit.can_gather and unit.cargo > 0 and crate.accepts(unit.cargo_kind): give_order(unit,{kind = "return", target = crate},queued)
		elif point != null and ground.get_tile_at_position(point) != null and ground.get_terrain(ground.get_tile_at_position(point)) == 3 and unit.can_gather:
			give_order(unit,{kind = "gather", target = ground.forest_source(ground.get_tile_at_position(point))},queued)
			forest_ordered = true
		elif dropoff and dropoff.is_in_group("mobile_supplies") and unit.can_gather: give_order(unit,{kind = "return", target = dropoff},queued)
		elif resource: give_order(unit,{kind = "gather", target = resource},queued)
		elif dropoff and dropoff.team == unit.team and unit.cargo > 0: give_order(unit,{kind = "return", target = dropoff},queued)
		elif building and building.team == unit.team and building.health < building.max_health and unit.can_repair: give_order(unit,{kind = "repair", target = building},queued)
		elif building and building.is_in_group("capturable_buildings") and building.team != unit.team and unit.can_capture_depots: give_order(unit,{kind = "capture", target = building},queued)
		elif building and CombatResolver.can_hit(unit,building): give_order(unit,{kind = "attack", target = building},queued)
		elif dropoff and dropoff.team == unit.team: give_order(unit,{kind = "return", target = dropoff},queued)
		elif point != null and unit.can_gather and ground.get_tile_at_position(point) != null and ground.get_terrain(ground.get_tile_at_position(point)) == 5:
			notify("Build an Iron Mine on this deposit before gathering iron.")
		elif point != null:
			var cell = ground.get_tile_at_position(point)
			if cell != null and ground.can_traverse(cell,unit.mobility_layer(),unit._owner_key()): give_order(unit,{kind = "move", point = point},queued)
			else: notify("That terrain is blocked. Right-click open land, resources, or a hostile.")
	if selected == 0: notify("Left-click an infantry unit first.")
	elif queued: notify("Order queued. Shift-right-click adds more; a plain order replaces the queue.")
	elif enemy: notify("Attack order: approach and fire at range.")
	elif crate: notify("Crate order: vehicles load it; workers deliver into it or gather from it.")
	elif forest_ordered: notify("Harvest wood from the forest tile and deliver it to a friendly Depot.")
	elif resource: notify("Gather %s and deliver to a friendly Depot." % resource.resource_kind)
	elif dropoff: notify("Return carried resources or repair this Depot.")
func show_shot(start: Vector3, end: Vector3, team: String) -> void:
	var shot = tracer_scene.instantiate()
	add_child(shot)
	shot.configure(start,end,team)

func issue_card_order(screen: Vector2, queued := false) -> void:
	var target: Node3D
	if pending_unit_command == "attack":
		target = pick_target(screen,"enemies")
		if target == null:
			var building = pick_target(screen,"selectable_buildings",50)
			if is_instance_valid(building) and (building.is_in_group("mines") or building.team not in ["player","neutral"]): target = building
	elif pending_unit_command == "gather":
		target = pick_target(screen,"resources",48)
		if target == null:
			var camera := get_viewport().get_camera_3d()
			var point = Plane(Vector3.UP,0).intersects_ray(camera.project_ray_origin(screen),camera.project_ray_normal(screen))
			if point != null and ground.get_tile_at_position(point) != null:
				var cell = ground.get_tile_at_position(point)
				if ground.get_terrain(cell) == 5: notify("Build an Iron Mine on this deposit before gathering iron."); return
				target = ground.forest_source(cell)
	elif pending_unit_command == "repair": target = pick_target(screen,"selectable_buildings",50)
	elif pending_unit_command == "capture": target = pick_target(screen,"capturable_buildings",50)
	elif pending_unit_command in ["load","unload"]:
		# Crate stops: a crate, a friendly Depot, or a deployed Cargo vehicle under the pointer.
		target = pick_crate(screen)
		if target == null:
			target = pick_target(screen,"depots",50)
			var mobile := pick_target(screen,"mobile_supplies",34)
			if is_instance_valid(mobile) and mobile.get("deployed") == true: target = mobile
	var ground_point = Plane(Vector3.UP,0).intersects_ray(get_viewport().get_camera_3d().project_ray_origin(screen),get_viewport().get_camera_3d().project_ray_normal(screen))
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
				notify("Can't deploy there: the 8 × 8 footprint must be empty buildable land."); return
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
	var camera := get_viewport().get_camera_3d()
	var point = Plane(Vector3.UP,0).intersects_ray(camera.project_ray_origin(screen),camera.project_ray_normal(screen))
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.team != "player" or not unit.is_selected: continue
		if pending_unit_command == "move":
			if point != null: give_order(unit,{kind = "move", point = point},queued)
		else: give_order(unit,{kind = pending_unit_command, target = target},queued)
	# Shift keeps the command armed so several targets can be queued.
	notify(pending_unit_command.capitalize()+(" order queued. Shift-click adds more; Esc stops." if queued else " order issued."))
	if not queued: pending_unit_command = ""
