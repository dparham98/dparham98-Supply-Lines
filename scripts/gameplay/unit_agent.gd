extends Node3D
## Infantry combines engineering work and ranged combat. Visuals remains a replaceable scene.
signal died(unit: Node3D)
@export var team := "player":
	set(value):
		team = value
		if is_node_ready(): _paint_team()
@export var is_depot_truck := false
@export var is_cargo_vehicle := false
@export var can_construct := false
@export var can_repair := false
@export var engineering_rules: EngineeringRules
var repair_payer: Node3D
@export var can_heal := false
@export var heal_range := 9.0
@export var heal_hp := 10
@export var heal_interval := 1.0
@export var med_reserve_capacity := 200
## The reserve refills from a covering friendly Keep or an adjacent crate: `med_refill_points` points for
## `med_refill_cost` of `med_refill_kind` every `med_refill_interval` s. A cost of 0 refills for nothing.
@export var med_refill_kind := &"food"
@export var med_refill_cost := 1
@export var med_refill_points := 5
@export var med_refill_interval := 1.0
## Idle or attack-moving, a healer heals the most hurt friend within `heal_range` by itself.
@export var heal_autocast := true
var med_reserve := 0
var _med_refill_timer := 0.0
var _heal_scan := 0.0
## The attack-move a healer left to heal by itself, resumed when the patient is done.
var _heal_resume := Vector3.INF
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
## Authored vehicles start fuelled; Depot/production spawns clear this so new vehicles start empty.
@export var start_fuelled := true
var auto_refuel := true
@export_range(0,1,0.05) var desired_fuel_fraction := 1.0
## Pinned refuel stockpile; when unset the nearest covering friendly source with coal is used.
var fuel_source: Node3D
var fuel_source_explicit := false
var refuel_from: Node3D
var out_of_fuel := false
## A flyer that ran out of coal is on the ground where it stopped (FuelRules.coal_per_second_airborne).
var fuel_landed := false
var _flight_height := -1.0
var _refuel_credit := 0.0
@export var unit_stats: UnitStats
## Explicit compatibility policy while historical combat notation is unresolved.
@export var use_prototype_combat_for_unresolved_stats := true
var vision := 0.0
var energy_cost := 0
var iron_cost := 0
var food_cost := 0
var wood_cost := 0
var abilities: Array[StringName] = []
var _attack_enabled := true
@export var max_health := 100
@export var move_speed := 7.0
## How fast the body turns while travelling, in degrees a second (docs/PATHING.md). Unit stats set it.
@export var turn_rate := 360.0
@export var attack_range := 12.0
## The main weapon cannot fire nearer than this (UnitStats.min_attack_range).
@export var min_attack_range := 0.0
## Armour class (CombatResolver.target_class). Taken from UnitStats.armoured; trains and trucks set it on their scenes.
@export var armoured := false
## The weapon of the shot being resolved: 0 the main weapon, 1 the second (UnitStats.second_*).
var firing_weapon := 0
@export var attack_damage := 16
@export var shot_interval := 0.7
## What a shot looks like in flight; empty uses the map's plain tracer.
@export var projectile_scene: PackedScene
@export var carry_capacity := 10
## One saw blow per extraction (docs/INFANTRY_MODEL.md).
@export var harvest_interval := 1.2
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
## The current attack order was forced onto a friendly (the Attack command clicked on one).
var attack_forced := false
## Shift-queued orders (docs/COMMAND_QUEUE.md): {kind, target, point}. The next starts when the unit goes idle.
var order_queue: Array[Dictionary] = []
## What the worker gathers from. Giving it anything new drops the coal it was cutting a way to.
var source: Node3D:
	set(value):
		source = value
		_dig_source = null
## The coal a worker goes back to once the tree in its way is felled (see _cut_way_in).
var _dig_source: Node3D
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
	med_reserve = med_reserve_capacity if can_heal else 0
	add_to_group("units")
	_units_changed()
	if team == "enemy": add_to_group("enemies")
	var cell = ground.get_tile_at_position(global_position)
	grid_position = ground.nearest_actor_cell(cell if cell != null else Vector2i(250,250),mobility_layer(),_owner_key())
	global_position = ground.tile_to_world(grid_position)
	_claim(grid_position)
	if start_fuelled and fuel_active(): fuel = fuel_rules.reserve_capacity
	_paint_team()
	_update_display()
## The marker on the ground under the unit and the team paint on its model (docs/TEAM_MARKERS.md)
## take its side's colour. The marker shows only while the unit is selected.
func _paint_team() -> void:
	var marker := get_node_or_null("Visuals/TeamMarker") as GeometryInstance3D
	if marker:
		marker.set_instance_shader_parameter(&"team_color",preload("res://scripts/units/team_colors.gd").of(team))
		marker.visible = is_selected
	preload("res://scripts/components/team_paint.gd").apply(get_node_or_null("Visuals/Model"),team)
func set_selected(value: bool) -> void:
	is_selected = value and team == "player"
	var marker := get_node_or_null("Visuals/TeamMarker") as Node3D
	if marker: marker.visible = is_selected
## The name it claims cells under. Built once: movement asks for it hundreds of times a frame.
var _owner_name := ""
func _owner_key() -> String:
	if _owner_name.is_empty(): _owner_name = "agent_%s" % get_instance_id()
	return _owner_name
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
	if _farmer_refuses(): return
	_stop_route()
	order = "move"
	order_target = null
	source = null
	move_goal = point
	state = "Moving"
## A Farmer (docs/KNIGHTS_ECONOMY.md): a Forester sent to a Farm, for good. It works only that Farm; when the Farm is
## lost it may take over an empty Farm and nothing else. It never builds, fells or fights.
var farmer := false
## The Farm a Farmer works, or null once that Farm is lost.
var farm: Node3D
var _farm_resume := 0.0
## True, with the reason as the state, when a Farmer is given any order but working a Farm.
func _farmer_refuses() -> bool:
	if not farmer: return false
	state = "A Farmer works only a Farm"
	return true
func command_gather(node: Node3D) -> void:
	if not can_gather or is_depot_truck or is_cargo_vehicle or not is_instance_valid(node): return
	if farmer:
		if not node.is_in_group("farms"): _farmer_refuses(); return
		if is_instance_valid(farm) and farm != node and farm.health > 0 and not farm.is_queued_for_deletion():
			state = "A Farmer stays on its Farm"; return
	# A Farm takes one worker (docs/KNIGHTS_ECONOMY.md).
	if node.has_method("take_worker") and not node.take_worker(self):
		state = "Farm already has a worker"
		game.notify("%s already has a worker: a Farm takes one." % node.name,team)
		return
	if node.is_in_group("farms") and KnightHousing.rules().farmers_permanent:
		farmer = true
		farm = node
		fell_autocast = false
	_stop_route()
	order = "gather"
	source = node
	order_target = node
	state = "To "+str(node.resource_kind)
	if cargo > 0 and cargo_kind != node.resource_kind: _head_home()
	_work_timer = 0
## Fell (docs/FELL.md): cut a roughly straight lane of trees to a clicked cell, then the Forest within
## fell_radius_cells of it; or, given `area`, every Forest cell in that box. No wood is kept, and the worker keeps
## any load it already carries.
var _fell_origin := Vector2i(-1,-1)
## Autocast: while idle with no orders, fell the Forest within autocast_fell_radius_cells of where it was left,
## one cell at a time, nearest first. The player switches it with a right-click on the Fell card.
var fell_autocast := false
## The cell it was left at, round which it fells; a new order moves it.
var _auto_home := Vector2i(-1,-1)
var _auto_wait := 0.0
func set_fell_autocast(on: bool) -> void:
	fell_autocast = on and can_gather and not is_cargo_vehicle and not is_depot_truck and not farmer
	_auto_home = Vector2i(-1,-1)
	_auto_wait = 0.0
## Looks for Forest round its spot about once a second (ten after a tree it could not reach). Each pick is a
## Fell of that one cell, so the lane to it stays inside the circle and nothing round it is cut.
func _auto_fell(delta: float) -> void:
	_auto_wait -= delta
	if _auto_wait > 0: return
	_auto_wait = 1.0
	var here = ground.get_tile_at_position(global_position)
	if here == null: return
	if _auto_home.x < 0: _auto_home = here
	var reach: int = ground.harvesting_rules.autocast_fell_radius_cells
	var best := Vector2i(-1,-1)
	var best_distance := INF
	for z in range(_auto_home.y-reach,_auto_home.y+reach+1):
		for x in range(_auto_home.x-reach,_auto_home.x+reach+1):
			var cell := Vector2i(x,z)
			if _auto_home.distance_squared_to(cell) > reach*reach or ground.forest_amount(cell) <= 0: continue
			var d := Vector2(cell-here).length_squared()
			if d < best_distance: best_distance = d; best = cell
	if best.x < 0: return
	command_fell(best,Rect2i(best,Vector2i.ONE))
	if order != "fell": return
	state = "Auto-felling"
	# Straight on to the next cell once this one is down.
	_auto_wait = 0.0
var _fell_area := Rect2i()
## True once a worker could not walk to the lane's first tree: it then cuts every tree on the line.
var _fell_whole := false
var _fell_goal := Vector2i(-1,-1)
## Cells given up on: no way to them even through the trees.
var _fell_skip := {}
func command_fell(cell: Vector2i, area := Rect2i()) -> void:
	if _farmer_refuses(): return
	if not can_gather or is_depot_truck or is_cargo_vehicle or not ground.is_tile_in_bounds(cell): return
	_stop_route()
	order = "fell"
	_dig_source = null
	_fell_origin = cell
	_fell_area = area
	_fell_whole = false
	_fell_skip = {}
	source = _next_fell()
	order_target = source
	state = "To fell"
	_work_timer = 0
	if source == null: order = "idle"; state = "Felled"
## What is left to fell from where the worker stands: the lane to the clicked cell, then the patch round it; or
## the nearest Forest cell left in the box.
func _fell_target(here: Vector2i) -> Vector2i:
	if not _fell_area.has_area() and not _fell_skip.has(_fell_origin):
		if ground.forest_amount(_fell_origin) > 0 or not FellLane.lane(ground,here,_fell_origin,Rect2i(),_fell_whole).is_empty(): return _fell_origin
	var reach: int = ground.harvesting_rules.fell_radius_cells
	var box := _fell_area if _fell_area.has_area() else Rect2i(_fell_origin-Vector2i.ONE*reach,Vector2i.ONE*(reach*2+1))
	var best := Vector2i(-1,-1)
	var best_distance := INF
	for z in range(box.position.y,box.end.y):
		for x in range(box.position.x,box.end.x):
			var cell := Vector2i(x,z)
			if _fell_skip.has(cell) or ground.forest_amount(cell) <= 0: continue
			if not _fell_area.has_area() and _fell_origin.distance_squared_to(cell) > reach*reach: continue
			var d := Vector2(cell-here).length_squared()
			if d < best_distance: best_distance = d; best = cell
	return best
func _next_fell() -> Node3D:
	var here = ground.get_tile_at_position(global_position)
	if here == null: return null
	_fell_goal = _fell_target(here)
	if _fell_goal.x < 0: return null
	# A tree already in reach needs no lane.
	if ground.forest_amount(_fell_goal) > 0 and global_position.distance_to(ground.tile_to_world(_fell_goal)) <= interaction_range: return ground.forest_source(_fell_goal)
	var lane := FellLane.lane(ground,here,_fell_goal,Rect2i(),_fell_whole)
	return ground.forest_source(lane[0] if not lane.is_empty() else _fell_goal)
func _fell(delta: float) -> void:
	if not is_instance_valid(source) or source.remaining <= 0:
		source = _next_fell()
		order_target = source
		if source == null: order = "idle"; state = "Trees unreachable" if not _fell_skip.is_empty() else "Felled"; return
	if global_position.distance_to(source.global_position) > interaction_range:
		if _retry <= 0:
			state = "To fell"
			if not _route_to_interaction(source,interaction_range):
				# No walk to the lane's first tree: cut every tree on the line, and give the cell up if that fails too.
				if _fell_whole: _fell_skip[_fell_goal] = true
				_fell_whole = not _fell_whole
				source = null
		return
	state = "Felling"
	_face(source.global_position)
	_work_timer += delta
	if _work_timer >= harvest_interval:
		_work_timer = 0
		# The wood is left where it falls.
		source.extract(harvest_amount,team)
## `forced`: the player's explicit Attack command, which may target friendly units and buildings.
func command_attack(node: Node3D, forced := false) -> void:
	if _farmer_refuses(): return
	if is_depot_truck or is_cargo_vehicle or not _attack_enabled or not CombatResolver.can_attack(self,node,forced): return
	attack_forced = forced
	if carrying() and is_instance_valid(game): game.notify("A Deforester carrying cargo can't fire: drop it (X) first.")
	_stop_route()
	order = "attack"
	order_target = node
	source = null
	state = "Attacking"
## Attack-move: travel to a point, stopping to fire at anything that comes into range.
func command_attack_move(point: Vector3) -> void:
	if _farmer_refuses(): return
	if is_depot_truck or is_cargo_vehicle or not _attack_enabled: command_move(point); return
	command_move(point)
	order = "attack_move"
	state = "Attack-moving"
## Depot Truck: drive to a validated site, then deploy there (checked again on arrival).
func command_deploy_at(point: Vector3) -> void:
	if not is_depot_truck: return
	_stop_route()
	order = "deploy"
	order_target = null
	source = null
	move_goal = point
	state = "To deploy site"
func command_return(target: Node3D = null) -> void:
	if _farmer_refuses(): return
	return_depot = target
	return_explicit = is_instance_valid(target)
	_stop_route()
	source = null
	order = "return"
	state = "Returning "+str(cargo_kind)
func _process(delta: float) -> void:
	if _dead: return
	if derail_cooldown > 0.0: derail_cooldown = maxf(0.0,derail_cooldown-delta)
	if mine_rules != null: _mine_load_tick(delta)
	fuel_tick(delta)
	_ease_flight(delta)
	if can_heal:
		MedicalWork.refill_tick(self,delta)
		_autocast_heal(delta)
	_order_process(delta)
	_animate(delta)
## The Visuals model when it carries a character animator (scripts/components/character_animator.gd).
func _animator() -> Node3D:
	var model := $Visuals.get_node_or_null("Model")
	return model if model != null and model.has_method("set_motion") else null
var _animated_from := Vector3.INF
var _animated_yaw := 0.0
var _aimed_frame := -2
## Vehicle rigs (scripts/components/vehicle_rig.gd) open their hatches and show their load; vehicles override.
func _hatches_open() -> bool: return false
func _load_fraction() -> float: return 0.0
## Tell the model what this frame looked like. A vehicle rig gets its travel (speed and heading
## change), hatches and load; a character gets run, aim, work with its cycle period, or idle.
func _animate(delta: float = 1.0/60) -> void:
	var here := global_position
	var yaw: float = $Visuals.rotation.y
	var rig := $Visuals.get_node_or_null("Model")
	if rig != null and rig.has_method("set_drive"):
		var moved: bool = _animated_from != Vector3.INF
		rig.set_drive(here.distance_to(_animated_from)/delta if moved and delta > 0.0 else 0.0,angle_difference(_animated_yaw,yaw) if moved else 0.0,delta)
		rig.set_hatches(_hatches_open())
		rig.set_load(_load_fraction())
		_animated_from = here; _animated_yaw = yaw
		return
	var model := _animator()
	if model == null: _animated_from = here; _animated_yaw = yaw; return
	var kind: StringName = &"idle"
	var value := 0.0
	if _animated_from != Vector3.INF and here != _animated_from: kind = &"run"; value = move_speed
	elif _aimed_frame == Engine.get_process_frames(): kind = &"aim"
	elif state in ["Gathering","Felling","Farming"] or state.begins_with("Constructing"): kind = &"work"; value = harvest_interval
	elif state.begins_with("Repairing"): kind = &"work"; value = engineering_rules.repair_interval if engineering_rules else 0.0
	model.set_motion(kind,value)
	if kind == &"work" and _work_timer == 0.0 and model.has_method("sync_work"): model.sync_work()
	_animated_from = here; _animated_yaw = yaw
# Orders, movement and combat for one frame. Callers tick fuel first.
func _order_process(delta: float) -> void:
	if order == "idle" and not order_queue.is_empty() and not out_of_fuel: _start_next_order()
	# A Farmer left idle goes back to its Farm.
	if farmer and order == "idle" and is_instance_valid(farm) and farm.health > 0 and not farm.is_queued_for_deletion():
		_farm_resume -= delta
		if _farm_resume <= 0.0: _farm_resume = 1.0; command_gather(farm)
	_cooldown = maxf(0,_cooldown-delta)
	_retry = maxf(0,_retry-delta)
	_scan_wait -= delta
	if order == "attack" and (not is_instance_valid(order_target) or not _may_hit(order_target)):
		_stop_route()
		order = "idle"
		state = "Attack target lost"
		_update_display()
		return
	# A freed target cannot be passed to the typed checks below, so drop the order first.
	if order in ["repair","heal"] and not is_instance_valid(order_target):
		_stop_route()
		state = "Repair target lost" if order == "repair" else "Patient lost"
		var resume := order == "heal" and _heal_resume != Vector3.INF
		order = "idle"; order_target = null
		if resume: _heal_done(state)
		_update_display()
		return
	if order == "repair" and (not EngineeringWork.repairable(order_target,team) or not SupplySource.available(repair_payer,team)):
		_stop_route()
		_repair(delta)
		_update_display()
		return
	if order == "heal" and not MedicalWork.can_heal(order_target,team):
		_stop_route()
		_heal(delta)
		_update_display()
		return
	if order == "return" and return_explicit and not _crate_receiver(return_depot) and not SupplySource.can_receive(return_depot,team):
		_stop_route(); state = "Delivery paused · selected supply source unavailable"; _update_display(); return
	if order == "gather": _source_left()
	if order == "gather" and is_instance_valid(source) and not source.can_extract(team):
		_stop_route()
		_gather(delta)
		_update_display()
		return
	if order == "attack_move":
		# A worker with its hands full keeps walking rather than stopping for a fight it cannot join.
		var foe: Node3D = _acquire() if not carrying() else null
		if is_instance_valid(foe):
			_stop_route()
			state = "Attack-moving · engaging"
			_shoot(foe)
			_update_display()
			return
	if not _route.is_empty() or _moving_to.x >= 0:
		if is_instance_valid(order_target) and ((order == "attack" and in_attack_range(order_target) and team_sees(order_target)) or (order == "repair" and global_position.distance_to(order_target.global_position) <= engineering_rules.repair_range) or (order == "heal" and global_position.distance_to(order_target.global_position) <= heal_range)):
			_stop_route()
		else:
			_walk(delta)
			_fire_during_movement()
			_update_display()
			return
	match order:
		"attack_move":
			if global_position.distance_to(move_goal) < 1.5: order = "idle"; state = "Attack-move complete"
			elif _retry <= 0:
				if not _route_to_point(move_goal): state = "No route"; order = "idle"
		"deploy":
			if global_position.distance_to(move_goal) < 2.0:
				order = "idle"
				game.get_node("DepotNetwork").deploy_truck(self,move_goal)
			elif _retry <= 0:
				if not _route_to_point(move_goal): state = "Deploy site unreachable"; order = "idle"
		"move":
			if global_position.distance_to(move_goal) < 1.5: order = "idle"
			elif _retry <= 0:
				if not _route_to_point(move_goal): state = "No route"; order = "idle"
		"gather": _gather(delta)
		"fell": _fell(delta)
		"return": _return_cargo()
		"attack": _attack_order()
		"repair": _repair(delta)
		"heal": _heal(delta)
		"capture": _capture_order()
		"construct": _construct(delta)
		"derail": _derail_order(delta)
		"lay_mine": _lay_mine_order(delta)
		_:
			var unreachable := state == "Trees unreachable"
			state = "Out of fuel · landed" if fuel_landed else "Idle"
			# Hold ground and defend even when deselected; working units keep working.
			var enemy = _acquire()
			if enemy: _shoot(enemy)
			elif fell_autocast and order_queue.is_empty() and not out_of_fuel:
				if unreachable: _auto_wait = 10.0
				_auto_fell(delta)
	_update_display()
# Queue an order behind the current one, or start it now when idle.
func queue_order(entry: Dictionary) -> void:
	if entry.kind in ["load","unload"] and is_instance_valid(entry.get("target")):
		entry = entry.duplicate()
		entry["requires_target"] = not entry.target.is_in_group("supply_crates")
	if order == "idle" and order_queue.is_empty() and not out_of_fuel: run_order(entry)
	else: order_queue.append(entry)
func run_order(entry: Dictionary) -> void:
	# An order moves the spot autocast Fell works round to wherever the unit is next left.
	_auto_home = Vector2i(-1,-1)
	match entry.kind:
		"move": command_move(entry.point)
		"attack": command_attack(entry.target,entry.get("forced",false))
		"gather": command_gather(entry.target)
		"fell": command_fell(entry.cell,entry.get("area",Rect2i()))
		"return": command_return(entry.get("target"))
		"repair": command_repair(entry.target)
		"heal": command_heal(entry.target)
		"capture": command_capture(entry.target)
		"construct": command_construct(entry.target)
		"derail": command_derail(entry.target)
		"lay_mine": command_lay_mine(entry.point)
		"attack_move": command_attack_move(entry.point)
		"deploy": command_deploy_at(entry.point)
		"load", "unload":
			var target = entry.get("target")
			if entry.get("requires_target",false) and not is_instance_valid(target): return
			if has_method("command_"+entry.kind): call("command_"+entry.kind,target if is_instance_valid(target) else null,entry.get("point"))
func _start_next_order() -> void:
	# Skip entries whose target is gone or that the unit refuses, such as an unreachable attack.
	while order == "idle" and not order_queue.is_empty():
		var entry: Dictionary = order_queue.pop_front()
		if entry.kind in ["attack","gather","repair","heal","capture","construct","fetch","load","unload","derail"] and not is_instance_valid(entry.get("target")) and not (entry.kind in ["load","unload"] and entry.get("point") != null): continue
		run_order(entry)
func order_point(entry: Dictionary) -> Variant:
	if entry.kind in ["move","attack_move","deploy"]: return entry.point
	var target = entry.get("target")
	return target.global_position if is_instance_valid(target) else entry.get("point")
# Destinations for the current order, then each queued order, for the dashed queue path (map_overlay.gd).
func waypoint_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	var current = null
	if order in ["move","attack_move","deploy"]: current = move_goal
	elif order == "return" and is_instance_valid(return_depot): current = return_depot.global_position
	elif order in ["load","unload"]: current = get("job_point")
	elif order != "idle" and is_instance_valid(order_target): current = order_target.global_position
	if current != null: points.append(current)
	for entry in order_queue:
		var point = order_point(entry)
		if point != null: points.append(point)
	return points
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
	return _route_to_standing(target,radius)
## To the nearest open cell within `radius` of the target, not standing on `keep_off`.
func _route_to_standing(target: Node3D, radius: float, keep_off := Rect2i()) -> bool:
	_retry = 0.5
	var path: Array[Vector2i] = preload("res://scripts/units/interaction_approach.gd").path(self,target,radius,keep_off)
	if path.is_empty():
		_retry = 1.0
		return false
	path.remove_at(0)
	_route = path
	return true
## Set while trees stand between the builder and a site it has no way to touch: it fells them instead of
## working from the old reach of the site's centre (docs/BUILDER_TOUCH.md, docs/COAL_MINES.md).
var _site_blocked := false
## To the nearest cell touching a build site's footprint; failing that, it fells the trees on a roughly straight
## line to the site (docs/COAL_MINES.md); failing that, anywhere in the old reach of its centre.
func _route_to_site(keep_off: Rect2i) -> bool:
	_retry = 0.5
	var path: Array[Vector2i] = Approach.touch_path(self,keep_off)
	_site_blocked = false
	if path.is_empty():
		source = _lane_tree(keep_off)
		if source != null:
			_site_blocked = true
			_retry = 0
			state = "Felling a way to the build site"
			return true
		return _route_to_standing(order_target,_construct_reach(),keep_off)
	path.remove_at(0)
	_route = path
	return true
## The first tree to fell on a roughly straight line from here to `rect` (docs/FELL.md), or null.
func _lane_tree(rect: Rect2i) -> Node3D:
	var here = ground.get_tile_at_position(global_position)
	if here == null: return null
	var to: Vector2i = rect.position+rect.size/2
	var lane := FellLane.lane(ground,here,to,rect)
	return null if lane.is_empty() else ground.forest_source(lane[0])
## Walks to the tree in `source` and fells it, leaving the wood where it falls; any load stays aboard. `source`
## is null once the tree is down, or when there is no way to it.
func _clear_tree(delta: float, doing: String) -> void:
	if global_position.distance_to(source.global_position) > interaction_range:
		_work_timer = 0
		if _retry <= 0:
			state = doing
			if not _route_to_interaction(source,interaction_range):
				source = null
				_retry = 3.0
		return
	if not _route.is_empty() or _moving_to.x >= 0: _stop_route()
	state = doing
	_face(source.global_position)
	_work_timer += delta
	if _work_timer < harvest_interval: return
	_work_timer = 0
	source.extract(harvest_amount,team)
	if source.remaining <= 0:
		source = null
		_retry = 0
## Toward the nearest open cell to the target; the order stops the walk once the target is in range.
func _route_toward(target: Node3D) -> bool:
	var center = ground.get_tile_at_position(target.global_position)
	if center == null: return false
	if _plan(ground.nearest_actor_cell(center,mobility_layer(),_owner_key())): return true
	_retry = 1
	return false
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
const CoalApproach := preload("res://scripts/terrain/coal_approach.gd")
const FellLane := preload("res://scripts/terrain/fell_lane.gd")
const Approach := preload("res://scripts/units/interaction_approach.gd")
## Route cells looked ahead for a straight run, and half the width of the lane a run must keep clear.
const AIM_LOOKAHEAD := 32
const LANE_HALF_WIDTH := 0.35
## Travel along the route (docs/PATHING.md). `_moving_to` is the cell being headed for: the farthest
## of the next route cells in a straight, clear lane, so open ground is crossed in straight runs rather
## than cell to cell. The unit claims each cell as it crosses into it and lets go of the one it left.
func _walk(delta: float) -> void:
	if _moving_to.x < 0:
		_moving_to = _route.pop_front()
		_aim_ahead()
	var point: Vector3 = ground.tile_to_world(_moving_to)
	var step := move_speed*delta*_turn_speed(_turn_toward(point,delta))
	if fuel_active():
		powered_by = _depot_power()
		if powered_by == null:
			if out_of_fuel or fuel <= 0:
				_mark_out_of_fuel()
				state = "Out of fuel · order paused"
				return
			if fuel_rules.coal_per_movement_unit > 0: step = minf(step,fuel/fuel_rules.coal_per_movement_unit)
	var before := global_position
	var next := global_position.move_toward(point,step)
	# An empty tank keeps a vehicle inside Depot power: it stops at the edge rather than drive out and be
	# stranded (docs/FUEL_BATCH.md, Staying in range). The order waits until it has fuel.
	if fuel_active() and powered_by != null and fuel <= 0 and _depot_power(next) == null:
		if state != NO_FUEL_EDGE and team == "player" and game.has_method("alert"): game.alert("%s has no fuel to leave Depot range" % game.hud.object_name(self),global_position,"edge:%d" % get_instance_id(),"fuel")
		state = NO_FUEL_EDGE
		return
	var cell = ground.get_tile_at_position(next)
	if cell != null and not _is_ours(cell):
		if not ground.can_traverse(cell,mobility_layer(),_owner_key()):
			_route.clear()
			_moving_to = Vector2i(-1,-1)
			_retry = 0.5
			state = "Waiting for route"
			return
		_claim(cell)
		for claimed in _claimed.duplicate():
			if claimed != cell: _release(claimed)
		grid_position = cell
	global_position = next
	if cell != null and cell != ground.get_tile_at_position(before): _aim_ahead()
	if fuel_active(): _pay_for_move(before.distance_to(global_position))
	if unit_stats != null and unit_stats.mobility != null and unit_stats.mobility.clears_forest:
		var entered = ground.get_tile_at_position(global_position)
		if entered != null: ground.clear_forest(entered)
	if global_position.distance_to(point) < 0.001:
		# The route's last cell must be exact, including goals on an interaction-radius boundary.
		global_position = point
		_moving_to = Vector2i(-1,-1)
		if not _route.is_empty():
			_moving_to = _route.pop_front()
			_aim_ahead()
## Head for the farthest of the next route cells reachable in a straight, clear lane. When even the next
## cell is not (something moved into the lane, or the unit stopped off centre beside an obstacle), plan
## again from its own cell and go back through that cell's centre.
func _aim_ahead() -> void:
	var cells: Array[Vector2i] = [_moving_to]
	cells.append_array(_route.slice(0,AIM_LOOKAHEAD))
	# The last cell first, then a halving search between the nearest clear cell and the first blocked one.
	var best := cells.size()-1
	if not _lane_clear(global_position,ground.tile_to_world(cells[best])):
		best = -1
		if _lane_clear(global_position,ground.tile_to_world(cells[0])):
			best = 0
			var blocked := cells.size()-1
			while blocked-best > 1:
				var mid := (best+blocked)/2
				if _lane_clear(global_position,ground.tile_to_world(cells[mid])): best = mid
				else: blocked = mid
	if best >= 0:
		_moving_to = cells[best]
		_route = _route.slice(best)
		return
	# The cells before the aim were dropped, so plan again from here, through this cell's centre.
	var here = ground.get_tile_at_position(global_position)
	if here == null: return
	var goal: Vector2i = _route.back() if not _route.is_empty() else _moving_to
	var path: Array[Vector2i] = ground.actor_path(here,goal,mobility_layer(),_owner_key())
	if path.is_empty():
		_route.clear()
		_moving_to = here
		_retry = 0.5
		state = "Waiting for route"
		return
	path.remove_at(0)
	_route = path
	_moving_to = here
## Every cell under a lane LANE_HALF_WIDTH either side of the straight line is open to this unit.
func _lane_clear(from: Vector3, to: Vector3) -> bool:
	var run := Vector3(to.x-from.x,0,to.z-from.z)
	var length := run.length()
	if length < 0.01: return true
	var side := Vector3(-run.z,0,run.x)/length*LANE_HALF_WIDTH
	var layer := mobility_layer()
	var key := _owner_key()
	return ground.segment_open(from,to,layer,key) and ground.segment_open(from+side,to+side,layer,key) and ground.segment_open(from-side,to-side,layer,key)
## Turn the body toward a point at turn_rate; returns how far it still is from facing it, in radians.
func _turn_toward(point: Vector3, delta: float) -> float:
	var offset := point-global_position
	if Vector2(offset.x,offset.z).length_squared() < 0.0001: return 0.0
	var heading := atan2(-offset.x,-offset.z)
	var yaw: float = $Visuals.rotation.y
	var error := angle_difference(yaw,heading)
	var turn := deg_to_rad(turn_rate)*delta
	$Visuals.rotation.y = heading if absf(error) <= turn else wrapf(yaw+signf(error)*turn,-PI,PI)
	return absf(angle_difference($Visuals.rotation.y,heading))
## Full speed within 20 degrees of the heading, slowing to a turn on the spot at 90 degrees or more.
func _turn_speed(error: float) -> float:
	return clampf((PI*0.5-error)/(PI*0.5-deg_to_rad(20.0)),0.0,1.0)
## Whether the gather source still holds anything. A dug-out coal cell hands the worker on to the next cell of
## its field (docs/BALANCED_MAP.md), and a cut-out Forest cell to the nearest Forest cell near it
## (docs/FOREST_HAND_ON.md); iron sources have no next cell, so they end as before.
func _source_left() -> bool:
	# The tree that stood in the way of the coal is down (or gone): back to the coal.
	if is_instance_valid(_dig_source) and (not is_instance_valid(source) or source.remaining <= 0):
		var coal := _dig_source
		source = coal
		order_target = coal
	if not is_instance_valid(source): return false
	if source.remaining <= 0 and source.has_method("next_source"):
		var next: Node3D = source.next_source(global_position)
		if next != null: source = next; order_target = next
	return source.remaining > 0
## Starts a trip home with a load. A worker whose drop-off the player did not choose picks the nearest one
## afresh each trip, so moving it to another resource does not leave it walking back to the old stockpile.
func _head_home() -> void:
	order = "return"
	if not return_explicit: return_depot = null
func _gather(delta: float) -> void:
	# A tree in the way of a coal mine: felled where it stands, then back to the mine.
	if is_instance_valid(_dig_source) and _dig_source.is_in_group("mines") and is_instance_valid(source) and source.remaining > 0:
		var mine := _dig_source
		_clear_tree(delta,"Felling a way to the coal")
		if not is_instance_valid(source):
			source = mine
			order_target = mine
		return
	_source_left()
	if not is_instance_valid(source) or source.remaining <= 0:
		if cargo > 0: _head_home()
		else: order = "idle"; state = str(source.resource_kind).capitalize()+" depleted" if is_instance_valid(source) else "Source unavailable"
		return
	if source.get("raided") == true:
		# The enemy stands on the field: a Farmer waits by it, and takes home what it carries.
		if cargo > 0: _head_home()
		else: state = "Enemy on the Farm"
		return
	if not source.can_extract(team):
		if cargo > 0: _head_home()
		else: order = "idle"; state = "A working mine is required before extracting iron"
		return
	if cargo == 0: cargo_kind = source.resource_kind
	if cargo_kind != source.resource_kind or cargo >= carry_capacity:
		_head_home()
		return
	# A Farm is tilled from its near edge or anywhere on the field, so the walk to the Keep stays short.
	var field: Rect2i = source.field_rect() if source.has_method("field_rect") else Rect2i()
	if field.has_area():
		if Approach.distance_to_rect(ground,global_position,field) > Approach.TOUCH:
			if _retry <= 0:
				state = "To food"
				_retry = 0.5
				var path: Array[Vector2i] = Approach.touch_path(self,field)
				if path.is_empty(): _retry = 1.0; state = "Food unreachable"
				else: path.remove_at(0); _route = path
			return
	elif global_position.distance_to(source.global_position) > interaction_range:
		if _retry <= 0:
			state = "Felling a way to the coal" if is_instance_valid(_dig_source) else "To "+str(source.resource_kind)
			if not _route_to_interaction(source,interaction_range) and not _cut_way_in(): state = "Coal unreachable" if is_instance_valid(_dig_source) else str(source.resource_kind).capitalize()+" unreachable"
		return
	state = "Farming" if source.is_in_group("farms") else "Gathering"
	_face(source.global_position)
	_work_timer += delta
	if _work_timer >= harvest_interval:
		_work_timer = 0
		cargo += source.extract(mini(harvest_amount,carry_capacity-cargo),team)
		# A cell that runs out hands the worker on to the next one (coal, wood) before it walks home part-loaded.
		if cargo >= carry_capacity or not _source_left(): _head_home()
## Coal that no open path leads to (docs/BALANCED_MAP.md, docs/COAL_MINES.md): the worker fells the tree in its
## way and then goes back to the coal. One tree at a time, so the way is worked out again as the forest changes.
## False when there is nothing to cut: the coal is not behind forest, or no way through exists.
func _cut_way_in() -> bool:
	# While felling, the source is a tree; the way is still worked out to the coal behind it.
	var goal: Node3D = _dig_source if is_instance_valid(_dig_source) else source
	# A coal mine: the trees on a roughly straight line to its footprint.
	if is_instance_valid(goal) and goal.is_in_group("mines") and goal.get("on_coal") == true and not goal.cells.is_empty():
		var low: Vector2i = goal.cells[0]
		var high: Vector2i = goal.cells[0]
		for cell in goal.cells:
			low = Vector2i(mini(low.x,cell.x),mini(low.y,cell.y))
			high = Vector2i(maxi(high.x,cell.x),maxi(high.y,cell.y))
		var tree := _lane_tree(Rect2i(low,high-low+Vector2i.ONE))
		if tree == null:
			_retry = 3.0
			return false
		source = tree
		order_target = tree
		_dig_source = goal
		_retry = 0
		state = "Felling a way to the coal"
		return true
	if not is_instance_valid(goal) or not goal.has_method("field_remaining"): return false
	var here = ground.get_tile_at_position(global_position)
	if here == null: return false
	var way: Dictionary = CoalApproach.way(ground,here,goal.cell,interaction_range,mobility_layer(),_owner_key())
	if way.is_empty():
		# The search costs some milliseconds: a worker with no way in looks again less often.
		_retry = 3.0
		return false
	var coal: Node3D = ground.coal_source(way.coal)
	if coal == null: return false
	if way.fell.is_empty():
		# Other coal of the field can be reached as the ground stands.
		if coal == source: return false
		source = coal
		order_target = coal
		_retry = 0
		state = "To coal"
		return true
	var tree: Node3D = ground.forest_source(way.fell[0])
	if tree == null: return false
	if tree == source:
		# The tree it already cannot reach is still the best way in: wait for the way to clear.
		_retry = 3.0
		return false
	source = tree
	order_target = tree
	_dig_source = coal
	_retry = 0
	state = "Felling a way to the coal"
	return true
## Workers can deliver into a friendly crate on the map (docs/CRATE_CONTAINERS.md).
func _crate_receiver(node) -> bool:
	return is_instance_valid(node) and node.is_in_group("supply_crates") and not node.is_queued_for_deletion() and node.team == team
func _deliver_to_crate(crate: Node3D) -> void:
	if global_position.distance_to(crate.global_position) > crate.dropoff_range:
		if _retry <= 0:
			state = "Delivering to crate"
			if not _route_to_interaction(crate,crate.dropoff_range): state = "Crate unreachable"
		return
	if cargo > 0:
		var accepted: int = crate.receive(cargo_kind,cargo)
		if accepted > 0: game.delivered(crate,cargo_kind,accepted)
		cargo -= accepted
		if cargo > 0:
			# Full or holding another resource: move on to the nearest crate next to it that fits.
			for other in CrateYard.crates_near(get_tree(),crate.global_position,CrateYard.CLUSTER_RADIUS,team):
				if other.accepts(cargo_kind): return_depot = other; return
			state = "Crate full · carrying remainder"; return
	order = "gather" if _source_left() else "idle"
	if order == "idle": state = "Delivered to crate"
func _return_cargo() -> void:
	var depot = return_depot
	if _crate_receiver(depot): _deliver_to_crate(depot); return
	if return_explicit and is_instance_valid(depot) and depot.is_in_group("supply_crates"):
		_stop_route(); state = "Delivery paused · crate gone"; return
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
		if accepted > 0 and game.has_method("delivered"): game.delivered(depot,cargo_kind,accepted)
		if team != "player": pass
		elif cargo_kind == &"wood": game.wood_delivered += accepted
		elif cargo_kind == &"iron": game.ore_delivered += accepted
		cargo -= accepted
		if cargo > 0: state = "Stockpile full · carrying remainder"; return
	order = "gather" if _source_left() else "idle"
func _attack_order() -> void:
	if not _attack_enabled:
		order = "idle"
		state = "Attack unspecified"
		return
	if not is_instance_valid(order_target) or not _may_hit(order_target):
		order = "idle"
		state = "Idle"
		return
	if in_attack_range(order_target) and team_sees(order_target):
		if carrying(): state = "Carrying cargo · drop it (X) to fire"; return
		state = "Firing"
		_shoot(order_target)
	elif global_position.distance_to(order_target.global_position) < min_attack_range and team_sees(order_target):
		# Too close for the main gun: back off until the target is at its minimum range.
		if _retry <= 0:
			state = "Backing off · too close for main gun"
			var away := global_position-order_target.global_position
			away.y = 0.0
			if away.length_squared() < 0.01: away = global_transform.basis.z
			if not _route_to_point(order_target.global_position+away.normalized()*(min_attack_range+2.0)): state = "Too close for main gun"
	elif _retry <= 0:
		state = "Pursuing"
		if not _route_toward(order_target): state = "Target unreachable"
## Forced fire counts only for the attack order's own target.
func _forced_on(target: Node3D) -> bool:
	return attack_forced and order == "attack" and target == order_target
func _may_hit(target: Node3D) -> bool:
	return CombatResolver.can_attack(self,target,_forced_on(target)) and fires_at(target)
## Between the minimum range and the range of a weapon that fires at the target's class.
func in_attack_range(target: Node3D) -> bool:
	return weapon_for(target) >= 0
## The weapon to fire at `target` from here: the second weapon when it suits the target's class and the target is in
## its range band, else the main weapon when it fires at that class and is in range; -1 when neither can.
func weapon_for(target: Node3D) -> int:
	var d := global_position.distance_to(target.global_position)
	var cls := CombatResolver.target_class(target)
	if unit_stats != null and unit_stats.second_damage >= 0 and unit_stats.second_targets & cls and d <= unit_stats.second_range and d >= unit_stats.second_min_range: return 1
	if (unit_stats == null or unit_stats.targets & cls) and d <= attack_range and d >= min_attack_range: return 0
	return -1
## Whether any of its weapons fires at the target's class, at some range.
func fires_at(target: Node3D) -> bool:
	if unit_stats == null: return true
	var cls := CombatResolver.target_class(target)
	return bool(unit_stats.targets & cls) or (unit_stats.second_damage >= 0 and bool(unit_stats.second_targets & cls))
## Its longest reach, over both weapons.
func weapon_reach() -> float:
	if unit_stats != null and unit_stats.second_damage >= 0: return maxf(attack_range,unit_stats.second_range)
	return attack_range
## The nearest unit in range it may shoot. Only units near it are looked at (the skirmish's UnitGrid): asking every
## unit on the map, as every unit does every frame, slowed big battles to a crawl.
## How often, in seconds, a unit looks round for something to shoot when it has nothing in its sights (docs/COMBAT_BATCH.md,
## Targeting in big battles). It keeps shooting what it last found while that stays in range, and looks again at once
## when that target dies or leaves; a new enemy walking into range is noticed within this time.
const TARGET_SCAN_SECONDS := 0.2
var _scan_wait := 0.0
var _sighted: Node3D
var _had_sight := false
func _acquire() -> Node3D:
	if _had_sight and is_instance_valid(_sighted) and in_attack_range(_sighted) and CombatResolver.can_hit(self,_sighted) and team_sees(_sighted):
		# A building in its sights gives way to a unit that comes into range (docs/COMBAT_BATCH.md, Buildings as targets).
		if not _sighted.is_in_group("selectable_buildings"): return _sighted
		if _scan_wait > 0.0: return _sighted
		_scan_wait = TARGET_SCAN_SECONDS
		var nearer := _nearest_opponent()
		if nearer != null: _sighted = nearer
		return _sighted
	if _had_sight or _scan_wait <= 0.0:
		_scan_wait = TARGET_SCAN_SECONDS
		_sighted = _nearest_opponent()
		_had_sight = _sighted != null
		return _sighted
	return null
## Whether this unit's side sees `target` now (docs/SEE_TO_SHOOT.md): the fog of war's answer, which counts what
## the side's units and buildings see. A map with no fog sees everything. A unit fires only at what its side sees.
var _fog: Node
var _fog_looked := false
func team_sees(target: Node3D) -> bool:
	if not is_instance_valid(target): return false
	# A mine is hidden once armed: seen only while one of the side's detectors covers it (docs/MINES.md).
	if target.is_in_group("land_mines") and not target.detected_by(team): return false
	if not _fog_looked or (_fog != null and not is_instance_valid(_fog)):
		_fog = get_tree().get_first_node_in_group("fog_of_war") if is_inside_tree() else null
		_fog_looked = true
	return _fog == null or _fog.visible_to(team,target.global_position)
func _nearest_opponent() -> Node3D:
	var closest: Node3D
	var distance := weapon_reach()
	var nearby: Array = game.units_near(global_position,distance) if is_instance_valid(game) and game.has_method("units_near") else get_tree().get_nodes_in_group("units")
	for unit in nearby:
		if not is_instance_valid(unit) or unit.team == team: continue
		var d := global_position.distance_to(unit.global_position)
		if d >= distance or not in_attack_range(unit): continue
		if not CombatResolver.can_hit(self,unit): continue
		if not team_sees(unit): continue
		closest = unit; distance = d
	if closest != null: return closest
	# With no unit in range it turns on the nearest hostile building, as an attack order on it would (docs/COMBAT_BATCH.md,
	# Buildings as targets). Shared mines are left alone; units come first.
	for building in get_tree().get_nodes_in_group("selectable_buildings")+get_tree().get_nodes_in_group("land_mines"):
		if not is_instance_valid(building) or building.is_in_group("mines") or building.get("team") in [null,team,"neutral"]: continue
		var d := global_position.distance_to(building.global_position)
		if d >= distance or not in_attack_range(building): continue
		if not CombatResolver.can_hit(self,building): continue
		if not team_sees(building): continue
		closest = building; distance = d
	return closest
func _face(point: Vector3) -> void:
	var offset := point-global_position
	if offset.length_squared() > 0.001: $Visuals.rotation.y = atan2(-offset.x,-offset.z)
## The model's turret component when the Visuals model has one (scripts/components/turret_aim.gd).
func _turret() -> Node3D:
	var model := $Visuals.get_node_or_null("Model")
	return model if model != null and model.has_method("aim_at") else null
## A worker carrying cargo has its hands full and cannot fire (docs/INFANTRY_LOAD.md); it drops the load (X) to
## fight.
func carrying() -> bool:
	return can_gather and not is_cargo_vehicle and not is_depot_truck and cargo > 0
func _shoot(target: Node3D) -> void:
	if is_depot_truck or is_cargo_vehicle or not _attack_enabled or carrying() or not _may_hit(target) or not in_attack_range(target) or not team_sees(target): return
	# A turret tracks the target between shots; a unit without one turns its whole body as it fires.
	var turret := _turret()
	if turret: turret.aim_at(target.global_position)
	_aimed_frame = Engine.get_process_frames()
	var animator := _animator()
	# A clip whose shot lands partway through starts early, so its flash meets the shot.
	var lead: float = animator.shot_lead() if animator and animator.has_method("shot_lead") else 0.0
	var weapon := weapon_for(target)
	if animator and animator.has_method("use_weapon"): animator.use_weapon(weapon)
	if _cooldown > 0:
		if lead > 0.0 and _cooldown <= lead and not animator.acting():
			animator.play_action(&"shoot",lead-_cooldown)
			_aim_body(target,turret,animator)
		return
	# A turret fires only once it is round on the target (docs/TURRET_AIM.md); the reload is done meanwhile.
	if turret and turret.has_method("on_target") and not turret.on_target(): return
	firing_weapon = weapon
	_cooldown = CombatResolver.interval_for(self,target,weapon)
	if animator and (lead <= 0.0 or not animator.acting()): animator.play_action(&"shoot",lead)
	_aim_body(target,turret,animator)
	var target_height: Vector3 = target.get_node("Visuals").position if target.has_node("Visuals") else Vector3.ZERO
	var model := $Visuals.get_node_or_null("Model")
	var muzzle: Vector3 = model.muzzle_position() if model != null and model.has_method("muzzle_position") else global_position+Vector3.UP*1.7+$Visuals.position
	if turret and turret.has_method("fire"): turret.fire()
	var end := _shot_end(muzzle,target,target.global_position+Vector3.UP*1.7+target_height)
	var shot: Node3D
	if model != null and model.has_method("show_weapon_shot"):
		shot = model.show_weapon_shot(game,end,team)
	else:
		shot = game.show_shot(muzzle,end,team,projectile_scene)
	var forced := _forced_on(target)
	# A shell or grenade hurts when it gets there; a shooter gone by then takes its shot with it.
	if shot != null and shot.get("damage_on_impact") == true:
		shot.target = weakref(target)
		shot.on_impact = _strike_on_impact.bind(target,forced,shot,weapon)
	else: CombatResolver.strike(self,target,forced)
	if is_instance_valid(target) and game.has_method("mark_attacked"): game.mark_attacked(target)
	if is_instance_valid(target) and target.is_in_group("selectable_buildings") and target.get("team") == "player" and team != "player" and game.has_method("alert"):
		game.alert("%s under attack" % target.name,target.global_position,"attack:%d" % target.get_instance_id(),"attack")
## A shell's or grenade's damage, when it bursts: the target if it is still there, and splash round the burst. The
## target may have died or gone meanwhile, so it is untyped: a freed Node3D fails a typed argument before this
## body can check it.
func _strike_on_impact(target, forced: bool, shot, weapon := 0) -> void:
	var point: Vector3 = shot.impact_point() if is_instance_valid(shot) else (target.global_position if is_instance_valid(target) else global_position)
	firing_weapon = weapon
	CombatResolver.strike_at(self,target if is_instance_valid(target) else null,point,forced)
## Where a modelled projectile stops: on the near face of the target's body, so its impact is not buried inside.
func _shot_end(muzzle: Vector3, target: Node3D, fallback: Vector3) -> Vector3:
	if projectile_scene == null: return fallback
	var parts := preload("res://scripts/units/selection_bounds.gd").meshes(target)
	if parts.is_empty(): return fallback
	var box: AABB = parts[0].global_transform*parts[0].get_aabb()
	for part in parts: box = box.merge(part.global_transform*part.get_aabb())
	var aim := box.get_center()
	# A long barrel can reach past a close target; the round then goes off at the muzzle.
	var from := Vector2(global_position.x,global_position.z)
	if box.has_point(muzzle) or from.distance_to(Vector2(aim.x,aim.z)) < from.distance_to(Vector2(muzzle.x,muzzle.z)): return muzzle
	var hit: Variant = box.intersects_segment(muzzle,aim)
	return hit if hit != null else aim
# Turn so the gun line runs through the target when the model knows where its gun points; otherwise face it.
func _aim_body(target: Node3D, turret: Node3D, animator: Node) -> void:
	if turret != null: return
	if animator and animator.has_method("aim_yaw"): $Visuals.rotation.y = animator.aim_yaw(to_local(target.global_position))
	else: _face(target.global_position)
func _fire_during_movement() -> void:
	if unit_stats == null or not unit_stats.fire_while_moving or not _attack_enabled: return
	# Keep navigation/facing under the movement order; firing does not redirect the route.
	var facing: float = $Visuals.rotation.y
	var target = _acquire()
	if target and _in_moving_arc(target,facing): _shoot(target)
	$Visuals.rotation.y = facing
## Whether a unit on the move, its hull at `facing`, may fire at `target`: inside its moving-fire arc.
func _in_moving_arc(target: Node3D, facing: float) -> bool:
	if unit_stats == null or unit_stats.moving_fire_arc >= 360.0: return true
	var to: Vector3 = target.global_position-global_position
	return absf(angle_difference(facing,atan2(-to.x,-to.z))) <= deg_to_rad(unit_stats.moving_fire_arc*0.5)
func take_damage(amount: int) -> void:
	if _dead: return
	# Armour upgrades take 1 a level off every hit, never below 1 (docs/UPGRADES.md).
	amount = Upgrades.after_armour(self,amount)
	health = maxi(0,health-maxi(0,amount))
	_update_display()
	if health <= 0:
		game.drop_material(self)
		_dead = true
		for cell in _claimed.duplicate(): _release(cell)
		remove_from_group("units")
		_units_changed()
		remove_from_group("enemies")
		died.emit(self)
		game.unit_died(self)
		_leave_corpse()
		queue_free()
## Unit death clips playing at once at most, and the group their models join while they play.
const DEATH_CLIPS_MAX := 12
const DYING := &"dying_models"
## A model with a death clip stays behind to play it out. The unit itself is gone at once, so a
## corpse cannot be selected, targeted or walked into.
func _leave_corpse() -> void:
	var model := $Visuals.get_node_or_null("Model")
	if model == null or not model.has_method("has_death_clip") or not model.has_death_clip(): return
	# Off screen nobody sees it: the model goes with the unit (skirmish.in_view).
	if is_instance_valid(game) and game.has_method("in_view") and not game.in_view(global_position): return
	# In a big fight only so many play at once (DEATH_CLIPS_MAX): each is tens to hundreds of animated pieces. The
	# rest go at once, as off-screen deaths do (docs/PERFORMANCE.md).
	if get_tree().get_node_count_in_group(DYING) >= DEATH_CLIPS_MAX: return
	model.reparent(game)
	model.add_to_group(DYING)
	model.play_death()
## Tell the skirmish's unit grid (units_near) that the "units" group changed.
func _units_changed() -> void:
	if is_instance_valid(game) and game.has_method("units_changed"): game.units_changed()
func _exit_tree() -> void:
	_units_changed()
	if is_instance_valid(ground):
		for cell in _claimed.duplicate(): _release(cell)
## What the labels last showed, so a frame where nothing changed writes nothing (every unit asks every frame).
var _displayed := []
func _update_display() -> void:
	var shown := [health,max_health,cargo,cargo_kind,is_depot_truck,team,unit_stats]
	if shown == _displayed: return
	_displayed = shown
	$Status.text = ("DEPOT TRUCK" if is_depot_truck else (unit_stats.display_name.to_upper() if unit_stats != null else ("INFANTRY" if team == "player" else "HOSTILE")))+"  %d/%d" % [health,max_health]
	$Cargo.visible = cargo > 0
	$Cargo.text = "%d %s" % [cargo,str(cargo_kind)]
	_show_back_load()
## The load on a worker's back (docs/INFANTRY_LOAD.md): the model's BackLoad holds one hidden load per kind
## (Iron, Wood, Coal); the one it carries shows while it carries anything.
var _back_load: Node3D
var _back_shown := ""
## The Visuals child count when BackLoad was last looked for: most units have none, and searching the whole
## model for it every time was a real cost in a big battle. A model added or swapped under Visuals looks again.
var _back_searched := -1
func _show_back_load() -> void:
	if not is_instance_valid(_back_load) and _back_searched != $Visuals.get_child_count():
		_back_searched = $Visuals.get_child_count()
		_back_load = $Visuals.find_child("BackLoad",true,false)
		_back_shown = "?"
	if not is_instance_valid(_back_load): return
	var kind := str(cargo_kind).capitalize() if cargo > 0 else ""
	if kind == _back_shown: return
	_back_shown = kind
	for child in _back_load.get_children(): child.visible = str(child.name) == kind

## Call before spawning/ready. Resources are never mutated by runtime health or cooldowns.
func apply_unit_stats() -> void:
	if unit_stats == null: return
	var errors := unit_stats.validation_errors()
	if not errors.is_empty():
		push_error("Invalid unit stats: " + str(errors))
		return
	max_health = unit_stats.max_health
	move_speed = unit_stats.movement_speed
	turn_rate = unit_stats.turn_rate
	vision = unit_stats.vision
	energy_cost = unit_stats.energy_cost
	iron_cost = unit_stats.iron_cost
	food_cost = unit_stats.food_cost
	wood_cost = unit_stats.wood_cost
	abilities = unit_stats.abilities.duplicate()
	if unit_stats.attack_range >= 0: attack_range = unit_stats.attack_range
	min_attack_range = unit_stats.min_attack_range
	armoured = unit_stats.armoured
	if unit_stats.has_resolved_attack():
		attack_damage = unit_stats.damage
		shot_interval = unit_stats.attack_interval
		_attack_enabled = true
	else:
		_attack_enabled = use_prototype_combat_for_unresolved_stats

func has_ability(ability_id: StringName) -> bool:
	return abilities.has(ability_id)


func command_repair(target: Node3D, payer: Node3D = null) -> void:
	if _farmer_refuses(): return
	if not can_repair or engineering_rules == null or target == self or not EngineeringWork.repairable(target,team): return
	_stop_route()
	order_target = target
	source = null
	# Without an explicit payer, pay from the nearest stockpile covering this unit, as delivery does.
	var nearest := SupplySource.candidates(get_tree(),global_position,team)
	# A vehicle needs a stockpile covering both ends, so take the nearest one that does.
	if EngineeringWork.is_vehicle(target): nearest.assign(nearest.filter(func(node): return SupplySource.covers(node,target.global_position,team)))
	repair_payer = payer if is_instance_valid(payer) else (supply_payer if supply_payer_explicit else (nearest[0] if not nearest.is_empty() else EngineeringWork.payer_for(target,team)))
	_work_timer = 0
	order = "repair"
	state = "Repair ordered"
	game.notify("Repair %s; payer %s only." % [target.name,repair_payer.name if is_instance_valid(repair_payer) else "unavailable"],team)
func _repair(delta: float) -> void:
	if not is_instance_valid(order_target) or not EngineeringWork.repairable(order_target,team):
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
func command_heal(target: Node3D) -> void:
	if _farmer_refuses(): return
	if not can_heal or target == self or not MedicalWork.can_heal(target,team): return
	_stop_route()
	order_target = target
	source = null
	_work_timer = 0.0
	_heal_resume = Vector3.INF
	order = "heal"
	state = "Healing ordered"
## Heals by itself: idle or attack-moving with reserve left, it takes the most hurt friend within heal range.
func _autocast_heal(delta: float) -> void:
	if not heal_autocast or med_reserve <= 0 or not order in ["idle","attack_move"]: return
	_heal_scan -= delta
	if _heal_scan > 0.0: return
	_heal_scan = 0.5
	var patient := MedicalWork.most_hurt(self)
	if patient == null: return
	var resume := move_goal if order == "attack_move" else Vector3.INF
	command_heal(patient)
	_heal_resume = resume
## A heal ended: back to the attack-move it left, if it left one.
func _heal_done(note: String) -> void:
	order = "idle"; state = note
	if _heal_resume != Vector3.INF:
		var goal := _heal_resume
		_heal_resume = Vector3.INF
		command_attack_move(goal)
func _heal(delta: float) -> void:
	if not is_instance_valid(order_target) or not order_target.is_in_group("units") or order_target.get("team") != team or order_target.health <= 0:
		_heal_done("Patient lost"); return
	if order_target.health >= order_target.max_health:
		_heal_done("Patient at full health"); return
	if EngineeringWork.is_vehicle(order_target):
		_heal_done("Cannot heal vehicles"); return
	if global_position.distance_to(order_target.global_position) > heal_range:
		_work_timer = 0.0
		if _retry <= 0:
			state = "To patient"
			if not _route_near(order_target,heal_range): state = "Patient unreachable"
		return
	_face(order_target.global_position)
	_work_timer += delta
	if _work_timer < heal_interval:
		if not state.begins_with("Healing"): state = "Healing %s" % order_target.name
		return
	_work_timer = 0.0
	var note := MedicalWork.tick(self,order_target)
	if note.is_empty(): state = "Healing %s" % order_target.name
	elif _heal_resume != Vector3.INF: _heal_done(note)
	else: state = note
## Build at a queued site (docs/SITE_CONSTRUCTION.md): carried materials the site needs go onto its
## pile first, then the worker builds them in at its work pace, 5 per saw blow.
func command_construct(plan: Node3D) -> void:
	if _farmer_refuses(): return
	if not can_construct or is_depot_truck or is_cargo_vehicle or not is_instance_valid(plan) or not plan.is_in_group("construction_plans") or plan.finished or plan.kind == &"rail": return
	_stop_route()
	source = null
	_site_blocked = false
	order = "construct"
	order_target = plan
	_work_timer = 0
	state = "To build site"
func _construct_reach() -> float:
	return order_target.dropoff_range+2.0
func _construct(delta: float) -> void:
	if not is_instance_valid(order_target) or not order_target.is_in_group("construction_plans") or order_target.finished:
		source = null
		order = "idle"; state = "Construction complete" if is_instance_valid(order_target) and order_target.finished else "Build site lost"; return
	# A tree in the way of the site (_route_to_site).
	if is_instance_valid(source) and source.remaining > 0:
		_clear_tree(delta,"Felling a way to the build site")
		return
	# Builders stand within reach but off the footprint: one standing on it keeps the site from being clear.
	var keep_off: Rect2i = order_target.footprint()
	var here = ground.get_tile_at_position(global_position)
	var on_site: bool = here != null and keep_off.has_point(here)
	# A builder starts as soon as it touches the footprint, from whichever side it comes (docs/BUILDER_TOUCH.md).
	# One that cannot reach the edge works from anywhere in the old reach, at the end of its walk.
	var touching: bool = not on_site and Approach.distance_to_rect(ground,global_position,keep_off) <= Approach.TOUCH
	var in_reach: bool = touching or (not _site_blocked and _route.is_empty() and _moving_to.x < 0 and global_position.distance_to(order_target.global_position) <= _construct_reach())
	if on_site or not in_reach:
		_work_timer = 0
		if _retry <= 0:
			state = "Stepping off the build site" if on_site else "To build site"
			if not _route_to_site(keep_off): state = "No room beside the build site" if on_site else "Build site unreachable"
		return
	if not _route.is_empty() or _moving_to.x >= 0: _stop_route()
	_face(order_target.global_position)
	if cargo > 0 and order_target.shortfall(cargo_kind) > 0:
		cargo -= order_target.receive(cargo_kind,cargo)
		state = "Materials delivered to site"
	_work_timer += delta
	if _work_timer < harvest_interval:
		if not state.begins_with("Constructing") and not state.begins_with("Waiting") and state != "Materials delivered to site": state = "Constructing"
		return
	_work_timer = 0
	var waited: String = order_target.work(self,harvest_amount)
	if waited == "Built" or order_target.finished: order = "idle"; state = "Construction complete"
	elif waited.is_empty(): state = "Constructing"
	else: state = waited
func command_capture(target: Node3D) -> void:
	if _farmer_refuses(): return
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

## Minelaying (item 9 of the balance handoff, docs/MINES.md). Once its side has researched Minelaying at a Temple
## of Science, a Derailer carries up to `mine_rules.capacity` mines. Stopped inside a friendly Depot's range or by a
## deployed Cargo truck, it loads them one at a time for `iron_per_mine` iron each from that stockpile, the way it
## refuels. Lay mine sends it to a point, where it works `lay_seconds` and leaves a mine (`mine_scene`).
@export var mine_rules: MineRules
@export var mine_scene: PackedScene
var mines := 0
var _mine_load_timer := 0.0
var _lay_point := Vector3.ZERO
func can_carry_mines() -> bool:
	return mine_rules != null and mine_scene != null and has_ability(&"derail") and Research.has(self,team,Research.MINELAYING)
## Why it cannot lay a mine now, or "" when it can.
func lay_mine_blocker() -> String:
	if mine_rules == null or not has_ability(&"derail"): return "Only a Derailer lays mines."
	if not Research.has(self,team,Research.MINELAYING): return "Research Minelaying at a Temple of Science first."
	if mines <= 0: return "No mines aboard. Stop inside a friendly Depot's range, or by a deployed Cargo truck, to load them for %d iron each." % mine_rules.iron_per_mine
	return ""
## The friendly stockpile it would load from here: a covering Depot or deployed Cargo truck with the iron.
func mine_source() -> Node3D:
	if not is_inside_tree(): return null
	for source in SupplySource.candidates(get_tree(),global_position,team):
		if source.get("stockpile") != null and source.stockpile.amount(&"iron") >= mine_rules.iron_per_mine: return source
	return null
func _mine_load_tick(delta: float) -> void:
	if not can_carry_mines() or mines >= mine_rules.capacity or not is_stopped() or order != "idle":
		_mine_load_timer = 0.0
		return
	_mine_load_timer += delta
	if _mine_load_timer < mine_rules.load_seconds: return
	_mine_load_timer = 0.0
	var source := mine_source()
	if source != null and source.stockpile.withdraw(&"iron",mine_rules.iron_per_mine) == mine_rules.iron_per_mine: mines += 1
func command_lay_mine(point: Vector3) -> void:
	var blocker := lay_mine_blocker()
	if not blocker.is_empty(): state = blocker; return
	_stop_route()
	order_target = null
	source = null
	_lay_point = point
	_work_timer = 0.0
	order = "lay_mine"
	state = "To lay a mine"
func _lay_mine_order(delta: float) -> void:
	if mines <= 0: order = "idle"; state = "No mines aboard"; return
	var flat := Vector2(global_position.x-_lay_point.x,global_position.z-_lay_point.z).length()
	if flat > 2.5:
		_work_timer = 0.0
		if _retry <= 0:
			state = "To lay a mine"
			if not _route_to_point(_lay_point): order = "idle"; state = "Mine site unreachable"
		return
	_work_timer += delta
	state = "Laying a mine · %d%%" % roundi(minf(1.0,_work_timer/mine_rules.lay_seconds)*100)
	if _work_timer < mine_rules.lay_seconds: return
	_work_timer = 0.0
	mines -= 1
	var mine: Node3D = mine_scene.instantiate()
	mine.team = team
	mine.rules = mine_rules
	game.get_node("Entities").add_child(mine)
	# On the point clicked, which may be track it can stand beside but not on.
	mine.global_position = Vector3(_lay_point.x,0.0,_lay_point.z)
	order = "idle"
	state = "Mine laid · %d left" % mines
## Derail (docs/DERAILER.md): the unit goes to a piece of track and destroys it, derailing any train on it.
## Seconds until it can derail again.
var derail_cooldown := 0.0
func command_derail(target: Node3D) -> void:
	if _farmer_refuses(): return
	if not has_ability(&"derail") or not is_instance_valid(target) or not target.is_in_group("rails"): return
	if derail_cooldown > 0.0: state = "Derail recharging · %d s" % ceili(derail_cooldown); return
	_stop_route()
	source = null
	order_target = target
	order = "derail"
	_work_timer = 0.0
	state = "To the track"
## Where on the piece the Derailer works: its middle.
func derail_spot() -> Vector3:
	return order_target.point_at(order_target.length()*0.5)
func _derail_order(delta: float) -> void:
	if not is_instance_valid(order_target) or not order_target.is_inside_tree() or order_target.is_queued_for_deletion():
		order = "idle"; state = "Track gone"; return
	var spot := derail_spot()
	var reach: float = order_target.half_width()+2.5
	if Vector2(global_position.x,global_position.z).distance_to(Vector2(spot.x,spot.z)) > reach:
		_work_timer = 0.0
		if _retry <= 0 and not _route_to_point(spot) and not _route_near(order_target,reach):
			order = "idle"; state = "Track unreachable"
		return
	_stop_route()
	var rules = game.get_node("RailNetwork").rules
	_work_timer += delta
	state = "Breaking track · %d%%" % roundi(minf(1.0,_work_timer/maxf(0.01,rules.derail_seconds))*100)
	if _work_timer < rules.derail_seconds: return
	game.get_node("RailNetwork").destroy(order_target,team)
	derail_cooldown = rules.derail_cooldown
	order = "idle"
	state = "Track destroyed"
func mobility_layer() -> int:
	return unit_stats.mobility.layer if unit_stats != null and unit_stats.mobility != null else MobilityRules.Layer.GROUND
func selection_point() -> Vector3:
	return global_position+Vector3.UP*0.5+$Visuals.position

## Vehicle fuel (economy stage 5). Tank fuel is separate from transferable stockpile coal.
func fuel_active() -> bool:
	return fuel_rules != null and fuel_rules.consumes_fuel and is_instance_valid(game) and game.get("vehicle_fuel_required") == true
## Depot power (docs/FUEL_BATCH.md): inside a friendly Depot's range a vehicle moves on that Depot's energy,
## fuel_rules.depot_energy_per_metre, instead of its tank. A Depot with no energy left powers nothing.
var powered_by: Node3D
var _depot_power_owed := 0.0
func _depot_power(at = null) -> Node3D:
	if fuel_rules.depot_energy_per_metre <= 0: return null
	var point: Vector3 = global_position if at == null else at
	for depot in get_tree().get_nodes_in_group("depots"):
		if depot.energy > 0 and SupplySource.covers(depot,point,team): return depot
	return null
const NO_FUEL_EDGE := "No fuel · can't leave Depot range"
func _pay_for_move(distance: float) -> void:
	if not is_instance_valid(powered_by):
		burn_fuel(distance)
		return
	_depot_power_owed += distance*fuel_rules.depot_energy_per_metre
	var whole := floori(_depot_power_owed)
	if whole > 0: _depot_power_owed -= powered_by.stockpile.withdraw(&"energy",whole)
func burn_fuel(distance: float) -> void:
	fuel -= distance*fuel_rules.coal_per_movement_unit
	if fuel <= 0.0001: fuel = 0; _mark_out_of_fuel()
func _mark_out_of_fuel() -> void:
	if not out_of_fuel and team == "player" and game.has_method("alert"): game.alert("%s out of fuel" % game.hud.object_name(self),global_position,"","fuel")
	out_of_fuel = true
func fuel_low() -> bool:
	return fuel_active() and fuel < fuel_rules.reserve_capacity*fuel_rules.low_fuel_fraction
func fuel_target() -> float:
	return fuel_rules.reserve_capacity*desired_fuel_fraction
func is_stopped() -> bool:
	return out_of_fuel or (_route.is_empty() and _moving_to.x < 0)
## How near a stopped vehicle must be to a coal crate on the ground to refuel from it.
const CRATE_REFUEL_RANGE := 4.0
## Fuel sources (docs/FUEL_BATCH.md): a covering Depot's coal; a deployed Cargo vehicle's coal, its coal crates
## and then its own tank (take_coal); or a friendly coal crate on the ground beside the vehicle.
func can_refuel_from(node) -> bool:
	if not is_instance_valid(node) or node == self: return false
	if node.is_in_group("supply_crates"):
		return node.team == team and node.resource_kind == &"coal" and node.amount > 0 and node.global_position.distance_to(global_position) <= CRATE_REFUEL_RANGE
	if not SupplySource.covers(node,global_position,team): return false
	return (node.coal_on_hand() if node.has_method("coal_on_hand") else node.stockpile.amount(&"coal")) > 0
func _draw_fuel(node) -> bool:
	if node.is_in_group("supply_crates"): return node.extract(1,team) == 1
	if node.has_method("take_coal"): return node.take_coal()
	return node.stockpile.withdraw(&"coal",1) == 1
func set_fuel_source(node: Node3D) -> void:
	fuel_source = node
	fuel_source_explicit = is_instance_valid(node)
func choose_fuel_source() -> Node3D:
	if fuel_source_explicit: return fuel_source if can_refuel_from(fuel_source) else null
	# Nearest covering source with coal, ties by instance id as in SupplySource.candidates.
	var best: Node3D
	var best_distance := INF
	for group in ["depots","mobile_supplies","supply_crates"]:
		for candidate in get_tree().get_nodes_in_group(group):
			var d: float = candidate.global_position.distance_squared_to(global_position)
			if d > best_distance or (is_equal_approx(d,best_distance) and candidate.get_instance_id() > best.get_instance_id()): continue
			if can_refuel_from(candidate): best = candidate; best_distance = d
	return best
## Whole coal units move from exactly one source into the tank; fractional rate time is banked.
func fuel_tick(delta: float) -> void:
	refuel_from = null
	if not fuel_active(): return
	_airborne_burn(delta)
	# Depot power moves a vehicle whose tank is empty.
	if out_of_fuel and _depot_power() != null: out_of_fuel = false
	if not auto_refuel or not is_stopped() or fuel_target()-fuel < 1:
		_refuel_credit = 0
		if out_of_fuel and fuel > 0 and (not auto_refuel or fuel_target()-fuel < 1): out_of_fuel = false
		return
	var from := choose_fuel_source()
	if from == null:
		_refuel_credit = 0
		if out_of_fuel and fuel > 0: out_of_fuel = false # Resume on a partial tank once no source can add more.
		return
	refuel_from = from
	_refuel_credit += fuel_rules.refuel_coal_per_second*delta
	while _refuel_credit >= 1 and fuel_target()-fuel >= 1:
		if not _draw_fuel(from): break
		fuel += 1
		_refuel_credit -= 1
	if fuel_target()-fuel < 1:
		_refuel_credit = 0
		out_of_fuel = false
	elif out_of_fuel: state = "Refuelling from %s · order paused" % from.name
## A flyer burns coal by the second while in the air; empty, it lands where it is. Refuelled (as any vehicle is, from a
## covering Depot, a deployed Cargo truck or a coal crate beside it), it takes off again.
func _airborne_burn(delta: float) -> void:
	if fuel_rules.coal_per_second_airborne <= 0: return
	if fuel_landed:
		if fuel > 0 and not out_of_fuel: fuel_landed = false
		return
	fuel -= fuel_rules.coal_per_second_airborne*delta
	if fuel <= 0.0001:
		fuel = 0
		_mark_out_of_fuel()
		fuel_landed = true
		_stop_route()
		state = "Out of fuel · landed"
## The Visuals' flying height eases down to the ground when landed and back up after refuelling.
func _ease_flight(delta: float) -> void:
	if fuel_rules == null or fuel_rules.coal_per_second_airborne <= 0: return
	if _flight_height < 0: _flight_height = $Visuals.position.y
	var goal := 0.4 if fuel_landed else _flight_height
	$Visuals.position.y = move_toward($Visuals.position.y,goal,4.0*delta)
func fuel_summary() -> String:
	if fuel_rules == null: return ""
	if not fuel_active(): return "Fuel reserve %.0f / %.0f · not required here" % [fuel,fuel_rules.reserve_capacity]
	var text := "Fuel %.1f / %.0f coal" % [fuel,fuel_rules.reserve_capacity]
	if is_instance_valid(powered_by) and _depot_power() == powered_by: text += " · running on %s power" % powered_by.name
	if fuel_landed: text += " · OUT OF FUEL · landed"
	elif out_of_fuel: text += " · OUT OF FUEL"
	elif fuel_low(): text += " · LOW FUEL"
	var from := "nearest in range"
	if is_instance_valid(refuel_from): from = str(refuel_from.name)
	elif fuel_source_explicit and is_instance_valid(fuel_source): from = str(fuel_source.name)+" (pinned)"
	return text+"\nAuto-refuel %s · source %s" % ["on" if auto_refuel else "off",from]
