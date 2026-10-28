extends Node3D
## Infantry combines engineering work and ranged combat. Visuals remains a replaceable scene.
signal died(unit: Node3D)
@export var team := "player"
@export var is_depot_truck := false
@export var is_cargo_vehicle := false
@export var can_construct := false
@export var can_repair := false
@export var engineering_rules: EngineeringRules
var repair_payer: Node3D
@export var can_gather := true
@export var can_capture_depots := true
@export var deployment_rules: DepotRules
var return_depot: Node3D
var return_explicit := false
var supply_payer: Node3D
var supply_payer_explicit := false
@export var fuel_rules: FuelRules
var fuel: float = 0.0:
	set(value): fuel = clampf(value,0,fuel_rules.reserve_capacity if fuel_rules != null else 0.0)
@export var unit_stats: UnitStats
## Explicit compatibility policy while historical combat notation is unresolved.
@export var use_prototype_combat_for_unresolved_stats := true
var vision := 0.0
var energy_cost := 0
var iron_cost := 0
var abilities: Array[StringName] = []
var _attack_enabled := true
@export var max_health := 100
@export var move_speed := 7.0
@export var attack_range := 12.0
@export var attack_damage := 16
@export var shot_interval := 0.7
@export var carry_capacity := 10
@export var harvest_interval := 0.6
@export var harvest_amount := 5
@export var interaction_range := 4.0
var health := 100
var is_selected := false
var cargo := 0
var cargo_kind: StringName = &"iron"
var state := "Idle"
var grid_position := Vector2i.ZERO
var order := "idle"
var order_target: Node3D
var source: Node3D
var move_goal := Vector3.ZERO
var _route: Array[Vector2i] = []
var _claimed: Array[Vector2i] = []
var _moving_to := Vector2i(-1,-1)
var _cooldown := 0.0
var _work_timer := 0.0
var _retry := 0.0
var _dead := false
@onready var ground = get_tree().get_first_node_in_group("terrain_grid")
@onready var game = get_tree().get_first_node_in_group("skirmish")
func _ready() -> void:
	apply_unit_stats()
	health = max_health
	add_to_group("units")
	if team == "enemy": add_to_group("enemies")
	var cell = ground.get_tile_at_position(global_position)
	grid_position = ground.nearest_actor_cell(cell if cell != null else Vector2i(250,250),mobility_layer(),_owner_key())
	global_position = ground.tile_to_world(grid_position)
	_claim(grid_position)
	_update_display()
func set_selected(value: bool) -> void:
	is_selected = value and team == "player"
	$SelectionRing.visible = is_selected
func _owner_key() -> String:
	return "agent_%s" % get_instance_id()
func _is_ours(cell: Vector2i) -> bool:
	if mobility_layer() == MobilityRules.Layer.AIR: return ground.air_occupancy.get(cell) == _owner_key()
	return ground.is_tile_in_bounds(cell) and ground.tiles[cell.y*500+cell.x].occupied_by == _owner_key()
func _claim(cell: Vector2i) -> void:
	if mobility_layer() == MobilityRules.Layer.AIR: ground.set_air_occupant(cell,_owner_key(),true)
	else: ground.set_tile_feature(cell,"occupied_by",_owner_key())
	if not _claimed.has(cell): _claimed.append(cell)
func _release(cell: Vector2i) -> void:
	if mobility_layer() == MobilityRules.Layer.AIR: ground.set_air_occupant(cell,_owner_key(),false)
	elif _is_ours(cell): ground.set_tile_feature(cell,"occupied_by",null)
	_claimed.erase(cell)
func _stop_route() -> void:
	_route.clear()
	_moving_to = Vector2i(-1,-1)
	# Snap to the current occupied cell when changing orders mid-step.
	var cell = ground.get_tile_at_position(global_position)
	for claimed in _claimed.duplicate():
		if claimed != cell: _release(claimed)
	if cell != null:
		grid_position = cell
		_claim(cell)
	_retry = 0
func command_move(point: Vector3) -> void:
	_stop_route()
	order = "move"
	order_target = null
	source = null
	move_goal = point
	state = "Moving"
func command_gather(node: Node3D) -> void:
	if not can_gather or is_depot_truck or is_cargo_vehicle or not is_instance_valid(node): return
	_stop_route()
	order = "gather"
	source = node
	order_target = node
	state = "To "+str(node.resource_kind)
	if cargo > 0 and cargo_kind != node.resource_kind: order = "return"
	_work_timer = 0
func command_attack(node: Node3D) -> void:
	if is_depot_truck or is_cargo_vehicle or not _attack_enabled or not CombatResolver.can_hit(self,node): return
	_stop_route()
	order = "attack"
	order_target = node
	source = null
	state = "Attacking"
func command_return(target: Node3D = null) -> void:
	return_depot = target
	return_explicit = is_instance_valid(target)
	_stop_route()
	source = null
	order = "return"
	state = "Returning "+str(cargo_kind)
func _process(delta: float) -> void:
	if _dead: return
	_cooldown = maxf(0,_cooldown-delta)
	_retry = maxf(0,_retry-delta)
	if order == "attack" and (not is_instance_valid(order_target) or not CombatResolver.can_hit(self,order_target)):
		_stop_route()
		order = "idle"
		state = "Attack target lost"
		_update_display()
		return
	if order == "repair" and (not is_instance_valid(order_target) or order_target.health <= 0 or (order_target.team != team and not order_target.is_in_group("mines")) or not SupplySource.available(repair_payer,team)):
		_stop_route()
		_repair(delta)
		_update_display()
		return
	if order == "return" and return_explicit and not SupplySource.can_receive(return_depot,team):
		_stop_route(); state = "Delivery paused · selected supply source unavailable"; _update_display(); return
	if order == "gather" and is_instance_valid(source) and not source.can_extract(team):
		_stop_route()
		_gather(delta)
		_update_display()
		return
	if not _route.is_empty() or _moving_to.x >= 0:
		if is_instance_valid(order_target) and ((order == "attack" and global_position.distance_to(order_target.global_position) <= attack_range) or (order == "repair" and global_position.distance_to(order_target.global_position) <= engineering_rules.repair_range)):
			_stop_route()
		else:
			_walk(delta)
			_fire_during_movement()
			_update_display()
			return
	match order:
		"move":
			if global_position.distance_to(move_goal) < 1.5: order = "idle"
			elif _retry <= 0:
				if not _route_to_point(move_goal): state = "No route"; order = "idle"
		"gather": _gather(delta)
		"return": _return_cargo()
		"attack": _attack_order()
		"repair": _repair(delta)
		"capture": _capture_order()
		_:
			state = "Idle"
			# Hold ground and defend even when deselected; working units keep working.
			var enemy = _nearest_opponent()
			if enemy: _shoot(enemy)
	_update_display()
func _route_to_point(point: Vector3) -> bool:
	var cell = ground.get_tile_at_position(point)
	if cell == null: return false
	var goal: Vector2i = ground.nearest_actor_cell(cell,mobility_layer(),_owner_key())
	return _plan(goal)
func _plan(goal: Vector2i) -> bool:
	_retry = 0.5
	var current = ground.get_tile_at_position(global_position)
	if current == goal: return true
	var path: Array[Vector2i] = ground.actor_path(current,goal,mobility_layer(),_owner_key())
	if path.size() < 2: return false
	path.remove_at(0)
	_route = path
	return true
func _route_to_interaction(target: Node3D, radius: float) -> bool:
	_retry = 0.5
	var path: Array[Vector2i] = preload("res://scripts/units/interaction_approach.gd").path(self,target,radius)
	if path.is_empty():
		_retry = 1.0
		return false
	path.remove_at(0)
	_route = path
	return true
func _route_near(target: Node3D, radius: float) -> bool:
	var center = ground.get_tile_at_position(target.global_position)
	if center == null: return false
	# Nearby approach cells are searched in rings, with a terrain-safe path to each.
	for r in range(ceili(radius)-1,0,-1):
		for offset in [Vector2i(r,0),Vector2i(-r,0),Vector2i(0,r),Vector2i(0,-r),Vector2i(r/2,r/2),Vector2i(-r/2,-r/2)]:
			var cell: Vector2i = center + offset
			if ground.can_traverse(cell,mobility_layer(),_owner_key()) and _plan(cell): return true
	_retry = 1
	return false
func _walk(delta: float) -> void:
	if _moving_to.x < 0:
		var next: Vector2i = _route[0]
		if not ground.can_traverse(next,mobility_layer(),_owner_key()):
			_route.clear()
			_retry = 0.5
			state = "Waiting for route"
			return
		_claim(next)
		_moving_to = next
		_route.remove_at(0)
	var point: Vector3 = ground.tile_to_world(_moving_to)
	_face(point)
	global_position = global_position.move_toward(point,move_speed*delta)
	if unit_stats != null and unit_stats.mobility != null and unit_stats.mobility.clears_forest:
		var entered = ground.get_tile_at_position(global_position)
		if entered != null: ground.clear_forest(entered)
	if global_position.distance_to(point) < 0.001:
		# A completed cell must be exact, including goals on an interaction-radius boundary.
		global_position = point
		for cell in _claimed.duplicate():
			if cell != _moving_to: _release(cell)
		grid_position = _moving_to
		_moving_to = Vector2i(-1,-1)
func _gather(delta: float) -> void:
	if not is_instance_valid(source) or source.remaining <= 0:
		if cargo > 0: order = "return"
		else: order = "idle"; state = str(source.resource_kind).capitalize()+" depleted" if is_instance_valid(source) else "Source unavailable"
		return
	if not source.can_extract(team):
		if cargo > 0: order = "return"
		else: order = "idle"; state = "A working mine is required before extracting iron"
		return
	if cargo == 0: cargo_kind = source.resource_kind
	if cargo_kind != source.resource_kind or cargo >= carry_capacity:
		order = "return"
		return
	if global_position.distance_to(source.global_position) > interaction_range:
		if _retry <= 0:
			state = "To "+str(source.resource_kind)
			if not _route_to_interaction(source,interaction_range): state = str(source.resource_kind).capitalize()+" unreachable"
		return
	state = "Gathering"
	_face(source.global_position)
	_work_timer += delta
	if _work_timer >= harvest_interval:
		_work_timer = 0
		cargo += source.extract(mini(harvest_amount,carry_capacity-cargo),team)
		if cargo >= carry_capacity or source.remaining <= 0: order = "return"
func _return_cargo() -> void:
	var depot = return_depot
	if not SupplySource.can_receive(depot,team):
		if return_explicit:
			_stop_route(); state = "Delivery paused · selected supply source unavailable"; return
		depot = null
		var distance := INF
		for group in ["depots","mobile_supplies"]:
			for candidate in get_tree().get_nodes_in_group(group):
				if SupplySource.can_receive(candidate,team) and global_position.distance_to(candidate.global_position) < distance:
					depot = candidate; distance = global_position.distance_to(candidate.global_position)
		return_depot = depot
	if not is_instance_valid(depot): order = "idle"; state = "No available supply stockpile"; return
	if global_position.distance_to(depot.global_position) > depot.dropoff_range:
		if _retry <= 0:
			state = "Delivering to "+str(depot.name)
			if not _route_to_interaction(depot,depot.dropoff_range): state = "Supply stockpile unreachable"
		return
	if cargo > 0:
		var accepted: int = depot.stockpile.deposit(cargo_kind,cargo)
		if cargo_kind == &"wood": game.wood_delivered += accepted
		elif cargo_kind == &"iron": game.ore_delivered += accepted
		cargo -= accepted
		if cargo > 0: state = "Stockpile full · carrying remainder"; return
	order = "gather" if is_instance_valid(source) and source.remaining > 0 else "idle"
func _attack_order() -> void:
	if not _attack_enabled:
		order = "idle"
		state = "Attack unspecified"
		return
	if not is_instance_valid(order_target) or not CombatResolver.can_hit(self,order_target):
		order = "idle"
		state = "Idle"
		return
	if global_position.distance_to(order_target.global_position) <= attack_range:
		state = "Firing"
		_shoot(order_target)
	elif _retry <= 0:
		state = "Pursuing"
		if not _route_near(order_target,attack_range): state = "Target unreachable"
func _nearest_opponent() -> Node3D:
	var closest: Node3D
	var distance := attack_range
	for unit in get_tree().get_nodes_in_group("units"):
		if not CombatResolver.can_hit(self,unit): continue
		var d := global_position.distance_to(unit.global_position)
		if d < distance: closest = unit; distance = d
	return closest
func _face(point: Vector3) -> void:
	var offset := point-global_position
	if offset.length_squared() > 0.001: $Visuals.rotation.y = atan2(-offset.x,-offset.z)
func _shoot(target: Node3D) -> void:
	if is_depot_truck or is_cargo_vehicle or not _attack_enabled or _cooldown > 0 or not CombatResolver.can_hit(self,target) or global_position.distance_to(target.global_position) > attack_range: return
	_cooldown = CombatResolver.interval_for(self,target)
	_face(target.global_position)
	var target_height: Vector3 = target.get_node("Visuals").position if target.has_node("Visuals") else Vector3.ZERO
	game.show_shot(global_position+Vector3.UP*1.7+$Visuals.position,target.global_position+Vector3.UP*1.7+target_height,team)
	CombatResolver.strike(self,target)
func _fire_during_movement() -> void:
	if unit_stats == null or not unit_stats.fire_while_moving or not _attack_enabled: return
	# Keep navigation/facing under the movement order; firing does not redirect the route.
	var facing: float = $Visuals.rotation.y
	var target = _nearest_opponent()
	if target: _shoot(target)
	$Visuals.rotation.y = facing
func take_damage(amount: int) -> void:
	if _dead: return
	health = maxi(0,health-maxi(0,amount))
	_update_display()
	if health <= 0:
		game.drop_material(self)
		_dead = true
		for cell in _claimed.duplicate(): _release(cell)
		remove_from_group("units")
		remove_from_group("enemies")
		died.emit(self)
		game.unit_died(self)
		queue_free()
func _exit_tree() -> void:
	if is_instance_valid(ground):
		for cell in _claimed.duplicate(): _release(cell)
func _update_display() -> void:
	$Status.text = ("DEPOT TRUCK" if is_depot_truck else (unit_stats.display_name.to_upper() if unit_stats != null else ("INFANTRY" if team == "player" else "HOSTILE")))+"  %d/%d" % [health,max_health]
	$Cargo.visible = cargo > 0
	$Cargo.text = "%d %s" % [cargo,str(cargo_kind)]

## Call before spawning/ready. Resources are never mutated by runtime health or cooldowns.
func apply_unit_stats() -> void:
	if unit_stats == null: return
	var errors := unit_stats.validation_errors()
	if not errors.is_empty():
		push_error("Invalid unit stats: " + str(errors))
		return
	max_health = unit_stats.max_health
	move_speed = unit_stats.movement_speed
	vision = unit_stats.vision
	energy_cost = unit_stats.energy_cost
	iron_cost = unit_stats.iron_cost
	abilities = unit_stats.abilities.duplicate()
	if unit_stats.attack_range >= 0: attack_range = unit_stats.attack_range
	if unit_stats.has_resolved_attack():
		attack_damage = unit_stats.damage
		shot_interval = unit_stats.attack_interval
		_attack_enabled = true
	else:
		_attack_enabled = use_prototype_combat_for_unresolved_stats

func has_ability(ability_id: StringName) -> bool:
	return abilities.has(ability_id)


func command_repair(target: Node3D, payer: Node3D = null) -> void:
	if not can_repair or engineering_rules == null or not is_instance_valid(target) or not target.is_in_group("selectable_buildings") or (target.team != team and not target.is_in_group("mines")) or target.health <= 0: return
	_stop_route()
	order_target = target
	source = null
	repair_payer = payer if is_instance_valid(payer) else (supply_payer if supply_payer_explicit else EngineeringWork.payer_for(target,team))
	_work_timer = 0
	order = "repair"
	state = "Repair ordered"
	game.notify("Repair %s; payer %s only." % [target.name,repair_payer.name if is_instance_valid(repair_payer) else "unavailable"])
func _repair(delta: float) -> void:
	if not is_instance_valid(order_target) or not order_target.is_in_group("selectable_buildings") or (order_target.team != team and not order_target.is_in_group("mines")) or order_target.health <= 0:
		order = "idle"; state = "Repair target lost"; return
	if order_target.health >= order_target.max_health: order = "idle"; state = "Repair complete"; return
	if not SupplySource.available(repair_payer,team):
		_work_timer = 0; state = "Repair paused · payer lost"; return
	if global_position.distance_to(order_target.global_position) > engineering_rules.repair_range:
		_work_timer = 0
		if _retry <= 0:
			state = "To repair target"
			if not _route_near(order_target,engineering_rules.repair_range): state = "Repair target unreachable"
		return
	state = "Repairing · payer "+str(repair_payer.name)
	_face(order_target.global_position)
	_work_timer += delta
	if _work_timer >= engineering_rules.repair_interval:
		_work_timer = 0
		if not EngineeringWork.tick(self,order_target,repair_payer): state = "Repair paused · local funds unavailable"
func command_capture(target: Node3D) -> void:
	if not can_capture_depots or is_depot_truck or is_cargo_vehicle or not is_instance_valid(target) or not target.is_in_group("capturable_buildings"): return
	_stop_route()
	source = null
	order_target = target
	order = "capture"
	state = "To capture target"
func _capture_order() -> void:
	if not is_instance_valid(order_target) or order_target.health <= 0: order = "idle"; state = "Capture target lost"; return
	if order_target.team == team:
		order = "idle"; state = "Capture complete"
		return
	var radius: float = order_target.rules.capture_radius
	if global_position.distance_to(order_target.global_position) > radius:
		if _retry <= 0 and not _route_near(order_target,radius): state = "Capture target unreachable"
	else: state = "Capturing · stay uncontested"

func mobility_layer() -> int:
	return unit_stats.mobility.layer if unit_stats != null and unit_stats.mobility != null else MobilityRules.Layer.GROUND
func selection_point() -> Vector3:
	return global_position+Vector3.UP*0.5+$Visuals.position
