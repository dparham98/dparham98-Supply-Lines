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
func notify(text: String) -> void:
	message = text
func unit_died(unit: Node3D) -> void:
	if unit.team == "enemy": enemies_killed += 1; notify("Hostile eliminated.")
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
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		global_plan_kind = &""
		placing_rail = false
		placing_depot = false
		placing_generator = false
		placing_structure = &""
		pending_unit_command = ""
		$DepotNetwork.clear_builder()
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
		issue_card_order(event.position)
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_RIGHT: return
	issue_order(event.position)
	get_viewport().set_input_as_handled()
func pick_target(screen: Vector2, group: String, _radius := 34.0) -> Node3D:
	var camera := get_viewport().get_camera_3d()
	var closest: Node3D
	var distance := INF
	for node in get_tree().get_nodes_in_group(group):
		var d: float = preload("res://scripts/units/selection_bounds.gd").hit_distance(node,camera,screen)
		if d < distance: distance = d; closest = node
	return closest
func issue_order(screen: Vector2) -> void:
	var enemy := pick_target(screen,"enemies")
	var resource := pick_target(screen,"resources",48)
	var dropoff := pick_target(screen,"depots",50)
	var mobile := pick_target(screen,"mobile_supplies",34)
	if is_instance_valid(mobile) and mobile.team == "player": dropoff = mobile
	var building := pick_target(screen,"selectable_buildings",50)
	var camera := get_viewport().get_camera_3d()
	var point = Plane(Vector3.UP,0).intersects_ray(camera.project_ray_origin(screen),camera.project_ray_normal(screen))
	var selected := 0
	var forest_ordered := false
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.team != "player" or not unit.is_selected: continue
		selected += 1
		if enemy: unit.command_attack(enemy)
		elif point != null and ground.get_tile_at_position(point) != null and ground.get_terrain(ground.get_tile_at_position(point)) == 3 and unit.can_gather:
			unit.command_gather(ground.forest_source(ground.get_tile_at_position(point)))
			forest_ordered = true
		elif dropoff and dropoff.is_in_group("mobile_supplies") and unit.can_gather: unit.command_return(dropoff)
		elif resource: unit.command_gather(resource)
		elif dropoff and dropoff.team == unit.team and unit.cargo > 0: unit.command_return(dropoff)
		elif building and building.team == unit.team and building.health < building.max_health and unit.can_repair: unit.command_repair(building)
		elif building and building.is_in_group("capturable_buildings") and building.team != unit.team and unit.can_capture_depots: unit.command_capture(building)
		elif building and CombatResolver.can_hit(unit,building): unit.command_attack(building)
		elif dropoff and dropoff.team == unit.team: unit.command_return(dropoff)
		elif point != null and unit.can_gather and ground.get_tile_at_position(point) != null and ground.get_terrain(ground.get_tile_at_position(point)) == 5:
			notify("Build an Iron Mine on this deposit before gathering iron.")
		elif point != null:
			var cell = ground.get_tile_at_position(point)
			if cell != null and ground.can_traverse(cell,unit.mobility_layer(),unit._owner_key()): unit.command_move(point)
			else: notify("That terrain is blocked. Right-click open land, resources, or a hostile.")
	if selected == 0: notify("Left-click an infantry unit first.")
	elif enemy: notify("Attack order: approach and fire at range.")
	elif forest_ordered: notify("Harvest wood from the forest tile and deliver it to a friendly Depot.")
	elif resource: notify("Gather %s and deliver to a friendly Depot." % resource.resource_kind)
	elif dropoff: notify("Return carried resources or repair this Depot.")
func show_shot(start: Vector3, end: Vector3, team: String) -> void:
	var shot = tracer_scene.instantiate()
	add_child(shot)
	shot.configure(start,end,team)

func issue_card_order(screen: Vector2) -> void:
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
	if pending_unit_command != "move" and not is_instance_valid(target):
		notify("Click an appropriate target for "+pending_unit_command+".")
		return
	var camera := get_viewport().get_camera_3d()
	var point = Plane(Vector3.UP,0).intersects_ray(camera.project_ray_origin(screen),camera.project_ray_normal(screen))
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.team != "player" or not unit.is_selected: continue
		if pending_unit_command == "attack": unit.command_attack(target)
		elif pending_unit_command == "gather": unit.command_gather(target)
		elif pending_unit_command == "repair": unit.command_repair(target)
		elif pending_unit_command == "capture": unit.command_capture(target)
		elif point != null: unit.command_move(point)
	notify(pending_unit_command.capitalize()+" order issued.")
	pending_unit_command = ""
