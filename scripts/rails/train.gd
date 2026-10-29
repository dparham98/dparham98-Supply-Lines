extends "res://scripts/economy/cargo_vehicle.gd"
var _checked_revision := -1
var waiting_for_rail := false
@onready var rail_network = get_tree().get_first_node_in_group("rail_network")
func _ready() -> void:
	super._ready()
	add_to_group("rail_trains")
	can_gather = false; can_capture_depots = false
	rail_network.changed.connect(_rail_changed)
func route_connected() -> bool:
	if not endpoints_friendly(): return false
	var cell = ground.get_tile_at_position(global_position)
	return cell != null and not rail_network.path_to_depot(cell,origin_depot,team,_owner_key(),false).is_empty() and not rail_network.path_to_depot(cell,destination_depot,team,_owner_key(),false).is_empty()
func start_supply_route(origin: Node3D, destination: Node3D, energy: int, iron: int, repeat_route: bool, wood: int = 0, coal: int = 0) -> bool:
	if not super.start_supply_route(origin,destination,energy,iron,repeat_route,wood,coal): return false
	# Store any valid friendly endpoint pair; topology controls execution only.
	waiting_for_rail = not route_connected()
	_checked_revision = rail_network.revision
	if waiting_for_rail: state = "Route assigned · waiting for friendly rails"
	check_round_trip_fuel()
	return true
var fuel_warning := ""
## The pickup and delivery Depots of the current trip: a route, or a Load and Unload pair
## from the current order, the queue or the last pickup. Empty when there is no pair.
func trip_endpoints() -> Array:
	if route_active: return [origin_depot,destination_depot] if endpoints_friendly() else []
	return shipment_pair()
var _trip_key := ""
## Estimated coal for current position -> pickup Depot -> delivery Depot -> pickup Depot.
## Returns -1 when there is no trip or the rails do not currently connect it.
func estimated_round_trip_fuel() -> float:
	var pair := trip_endpoints()
	if fuel_rules == null or pair.is_empty(): return -1
	var cell = ground.get_tile_at_position(global_position)
	if cell == null: return -1
	var to_origin: Array[Vector2i] = rail_network.path_to_depot(cell,pair[0],team,_owner_key(),false)
	if to_origin.is_empty(): return -1
	var leg: Array[Vector2i] = rail_network.path_to_depot(to_origin[-1],pair[1],team,_owner_key(),false)
	if leg.is_empty(): return -1
	return (_path_length(to_origin)+2*_path_length(leg))*fuel_rules.coal_per_movement_unit
func _path_length(path: Array[Vector2i]) -> float:
	var length := 0.0
	for i in range(1,path.size()): length += ground.tile_to_world(path[i-1]).distance_to(ground.tile_to_world(path[i]))
	return length
## Warn but allow (approved default): the route is kept even when the tank cannot cover it.
func check_round_trip_fuel() -> void:
	fuel_warning = ""
	if not fuel_active() or trip_endpoints().is_empty(): return
	var needed := estimated_round_trip_fuel()
	if needed < 0: fuel_warning = "Round-trip fuel unknown until rails connect."
	elif needed > fuel: fuel_warning = "Round trip needs about %.0f coal; tank holds %.1f." % [needed,fuel]
	if not fuel_warning.is_empty(): game.notify("Train fuel warning: "+fuel_warning)
func _rail_changed() -> void:
	_checked_revision = rail_network.revision
	if not route_active or route_paused: return
	var connected := route_connected()
	if waiting_for_rail:
		if connected:
			waiting_for_rail = false
			state = "Rails connected · route starting"
	elif not connected:
		pause_supply_route()
		state = "Rail connection lost · resume explicitly"
func resume_supply_route() -> bool:
	if _dead or health <= 0 or not route_active or not endpoints_friendly(): return super.resume_supply_route()
	# Initially unconnected assignments may resume waiting; a cut active line needs repair.
	if not waiting_for_rail and not route_connected():
		route_error = "Repair friendly rails to both Depot loading areas before resuming."
		return false
	if not super.resume_supply_route(): return false
	waiting_for_rail = not route_connected()
	if waiting_for_rail: state = "Route assigned · waiting for friendly rails"
	return true
func cancel_supply_route() -> void:
	waiting_for_rail = false
	super.cancel_supply_route()
func _process(delta: float) -> void:
	if _dead: return
	if _checked_revision != rail_network.revision: _rail_changed()
	# Re-estimate the round trip whenever a Load/Unload pair changes.
	var pair := trip_endpoints()
	var key := "" if pair.is_empty() else "%d:%d" % [pair[0].get_instance_id(),pair[1].get_instance_id()]
	if key != _trip_key:
		_trip_key = key
		if not route_active: check_round_trip_fuel()
	if route_active and waiting_for_rail and not route_paused:
		if not endpoints_friendly(): pause_supply_route()
		else:
			fuel_tick(delta)
			if not advance_supplies(delta):
				state = "Route assigned · waiting for friendly rails"
				_update_display()
			return
	super._process(delta)
func _route_to_point(point: Vector3) -> bool:
	var cell = ground.get_tile_at_position(point)
	return cell != null and _plan(cell)
func _plan(goal: Vector2i) -> bool:
	_retry = 0.5
	var current = ground.get_tile_at_position(global_position)
	var path: Array[Vector2i] = rail_network.path(current,goal,team,_owner_key())
	if path.is_empty(): return false
	path.remove_at(0)
	_route = path
	return true
func _route_to_interaction(target: Node3D, radius: float) -> bool:
	# Trains still choose reachable friendly loading rails, never ordinary ground cells.
	return _route_near(target,radius)
func _route_near(target: Node3D, _radius: float) -> bool:
	_retry = 0.5
	var cell = ground.get_tile_at_position(global_position)
	var path: Array[Vector2i] = rail_network.path_to_depot(cell,target,team,_owner_key())
	if path.is_empty(): return false
	path.remove_at(0)
	_route = path
	return true
func _walk(delta: float) -> void:
	var current = ground.get_tile_at_position(global_position)
	var next: Vector2i = _moving_to if _moving_to.x >= 0 else (_route[0] if not _route.is_empty() else current)
	if not rail_network.friendly(current,team) or not rail_network.friendly(next,team):
		if route_active: pause_supply_route()
		else: _stop_route(); order = "idle"
		state = "Rail unavailable · cargo retained"
		return
	super._walk(delta)
func _update_display() -> void:
	super._update_display()
	$Status.text = "TRAIN · %d/%d · %s" % [health,max_health,state]
func _exit_tree() -> void:
	if is_instance_valid(rail_network) and rail_network.changed.is_connected(_rail_changed): rail_network.changed.disconnect(_rail_changed)
	super._exit_tree()

