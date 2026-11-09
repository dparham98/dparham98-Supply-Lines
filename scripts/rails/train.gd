extends "res://scripts/economy/cargo_vehicle.gd"
## A maglev train (docs/MAGLEV_TRACKS.md). It lives on the track network: its position is a piece
## and a distance along it, it moves along sampled centre lines between Depot loading stops, and the
## consist model places the engine and cars on that line. Trains take no part in ground occupancy.
var _checked_revision := -1
var waiting_for_rail := false
## Current track position.
var piece: Node3D
var along := 0.0
## The line being followed, the front sled's distance along it, and where it ends.
var _line := {}
var _s := 0.0
var _goal := 0.0
var _rest_line := {}
const LINE_SENTINEL := Vector2i(-2,-2)
@onready var rail_network = get_tree().get_first_node_in_group("rail_network")
func _ready() -> void:
	super._ready()
	add_to_group("rail_trains")
	can_gather = false; can_capture_depots = false
	rail_network.changed.connect(_rail_changed)
	snap_to_track()
# Trains do not claim ground cells.
func _claim(_cell: Vector2i) -> void: pass
func _release(_cell: Vector2i) -> void: pass
## Puts the train on the nearest piece; a train off any track stays where it is and waits.
func snap_to_track() -> void:
	var hit: Dictionary = rail_network.nearest_piece(global_position,20.0)
	if hit.is_empty(): piece = null; return
	piece = hit.piece; along = hit.distance
	global_position = piece.point_at(along)
	_rest_line = rail_network.line([{piece = piece, enter = -1}],along,-1.0,consist_length()+2.0)
	_s = _rest_line.get("start",0.0)
func on_friendly_track() -> bool:
	return is_instance_valid(piece) and rail_network.friendly_piece(piece,team)
func consist_length() -> float:
	var model := $Visuals.get_node_or_null("Model")
	return model.length() if model != null and model.has_method("length") else 8.0
func route_connected() -> bool:
	if not endpoints_friendly() or not on_friendly_track(): return false
	return not rail_network.line_to_depot(piece,along,origin_depot,team).is_empty() and not rail_network.line_to_depot(piece,along,destination_depot,team).is_empty()
func start_supply_route(origin: Node3D, destination: Node3D, energy: int, iron: int, repeat_route: bool, wood: int = 0, coal: int = 0) -> bool:
	if not super.start_supply_route(origin,destination,energy,iron,repeat_route,wood,coal): return false
	waiting_for_rail = not route_connected()
	_checked_revision = rail_network.revision
	if waiting_for_rail: state = "Route assigned · waiting for friendly rails"
	check_round_trip_fuel()
	return true
var fuel_warning := ""
func trip_endpoints() -> Array:
	if route_active: return [origin_depot,destination_depot] if endpoints_friendly() else []
	return shipment_pair()
var _trip_key := ""
## Estimated coal for current position -> pickup Depot -> delivery Depot -> pickup Depot.
func estimated_round_trip_fuel() -> float:
	var pair := trip_endpoints()
	if fuel_rules == null or pair.is_empty() or not is_instance_valid(piece): return -1
	var to_origin: Dictionary = rail_network.line_to_depot(piece,along,pair[0],team)
	if to_origin.is_empty(): return -1
	var stop_a: Dictionary = rail_network.spawn_stop(pair[0])
	if stop_a.is_empty(): return -1
	var leg: Dictionary = rail_network.line_to_depot(stop_a.piece,stop_a.distance,pair[1],team)
	if leg.is_empty(): return -1
	return ((to_origin.total-to_origin.start)+2*(leg.total-leg.start))*fuel_rules.coal_per_movement_unit
func check_round_trip_fuel() -> void:
	fuel_warning = ""
	if not fuel_active() or trip_endpoints().is_empty(): return
	var needed := estimated_round_trip_fuel()
	if needed < 0: fuel_warning = "Round-trip fuel unknown until rails connect."
	elif needed > fuel: fuel_warning = "Round trip needs about %.0f coal; tank holds %.1f." % [needed,fuel]
	if not fuel_warning.is_empty(): game.notify("Train fuel warning: "+fuel_warning)
func _rail_changed() -> void:
	_checked_revision = rail_network.revision
	if not is_instance_valid(piece): snap_to_track()
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
func deploy_supplies() -> bool:
	if not on_friendly_track(): return false
	return super.deploy_supplies()
func supplies_available() -> bool:
	if not on_friendly_track(): return false
	return deployed and supply_transition.is_empty() and health > 0 and not _dead and (not route_active or route_paused) and _route.is_empty() and _moving_to.x < 0
func _process(delta: float) -> void:
	if _dead: return
	if _checked_revision != rail_network.revision: _rail_changed()
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
			_place_consist()
			return
	super._process(delta)
	_place_consist()
func _place_consist() -> void:
	var model := $Visuals.get_node_or_null("Model")
	if model == null or not model.has_method("place"): return
	var track: Dictionary = _line if not _line.is_empty() else _rest_line
	if track.is_empty(): return
	model.place(track,_s,_load_fraction())
# ---- movement along the line
func _follow(track: Dictionary) -> bool:
	if track.is_empty(): return false
	_line = track
	_s = track.start
	_goal = track.total
	_route = [LINE_SENTINEL]
	_moving_to = Vector2i(-1,-1)
	_retry = 0.5
	return true
func _route_to_point(point: Vector3) -> bool:
	var hit: Dictionary = rail_network.nearest_piece(point,6.0)
	if hit.is_empty() or not is_instance_valid(piece): return false
	var route: Array = rail_network.chain(piece,hit.piece,team)
	if route.is_empty(): return false
	return _follow(rail_network.line(route,along,hit.distance,consist_length()+2.0))
func _plan(goal: Vector2i) -> bool:
	return _route_to_point(ground.tile_to_world(goal))
func _route_to_interaction(target: Node3D, radius: float) -> bool:
	return _route_near(target,radius)
func _route_near(target: Node3D, _radius: float) -> bool:
	if not is_instance_valid(piece): return false
	_retry = 0.5
	return _follow(rail_network.line_to_depot(piece,along,target,team,consist_length()+2.0))
func _stop_route() -> void:
	_route.clear()
	_moving_to = Vector2i(-1,-1)
	_retry = 0
	if not _line.is_empty():
		_rest_line = _line
		_line = {}
func _walk(delta: float) -> void:
	if _line.is_empty(): _route.clear(); return
	if not on_friendly_track():
		if route_active: pause_supply_route()
		else: _stop_route(); order = "idle"
		state = "Rail unavailable · cargo retained"
		return
	var step := move_speed*delta
	if fuel_active():
		if out_of_fuel or fuel <= 0:
			_mark_out_of_fuel()
			state = "Out of fuel · order paused"
			return
		if fuel_rules.coal_per_movement_unit > 0: step = minf(step,fuel/fuel_rules.coal_per_movement_unit)
	var before := _s
	_s = minf(_goal,_s+step)
	if fuel_active(): burn_fuel(_s-before)
	var here: Array = RailLine.point(_line,_s)
	global_position = here[0]
	$Visuals.rotation.y = atan2(-here[1].x,-here[1].z)
	var hit: Dictionary = rail_network.nearest_piece(global_position,3.0)
	if not hit.is_empty(): piece = hit.piece; along = hit.distance
	if _s >= _goal-0.001:
		_rest_line = _line
		_line = {}
		_route.clear()
func _update_display() -> void:
	super._update_display()
	$Status.text = "TRAIN · %d/%d · %s" % [health,max_health,state]
func _exit_tree() -> void:
	if is_instance_valid(rail_network) and rail_network.changed.is_connected(_rail_changed): rail_network.changed.disconnect(_rail_changed)
	super._exit_tree()
