extends "res://scripts/economy/cargo_vehicle.gd"
## A maglev train (docs/MAGLEV_TRACKS.md): one self-powered cargo car. It lives on the track network:
## its position is a piece, a lane and a distance along it, it moves along sampled centre lines between
## Depot loading stops, and the model rides that line. It burns no fuel, drawing energy from a Depot
## connected to its line. Trains take no part in ground occupancy.
var _checked_revision := -1
var waiting_for_rail := false
## Set when a running route lost its connection, so the waiting text says why.
var power_lost := false
## Current track position.
var piece: Node3D
var along := 0.0
var lane := 0
## Energy owed for distance already travelled; whole units are paid as they accrue.
var _power_owed := 0.0
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
	# Trains authored in a map load before all of its track has registered.
	if game.is_node_ready(): snap_to_track()
	else: snap_to_track.call_deferred()
# Trains do not claim ground cells.
func _claim(_cell: Vector2i) -> void: pass
func _release(_cell: Vector2i) -> void: pass
## Puts the train on the nearest piece; a train off any track stays where it is and waits.
func snap_to_track() -> void:
	if not is_inside_tree(): return
	var hit: Dictionary = rail_network.nearest_piece(global_position,20.0)
	if hit.is_empty(): piece = null; return
	piece = hit.piece; along = hit.distance; lane = hit.lane
	global_position = piece.point_at(along,lane)
	_rest_line = rail_network.line([{piece = piece, enter = -1, lane = lane}],along,-1.0,consist_length()+2.0)
	_s = _rest_line.get("start",0.0)
	_place_consist()
func on_friendly_track() -> bool:
	return is_instance_valid(piece) and rail_network.friendly_piece(piece,team)
func consist_length() -> float:
	var model := $Visuals.get_node_or_null("Model")
	return model.length() if model != null and model.has_method("length") else 8.0
func route_connected() -> bool:
	if not endpoints_friendly() or not on_friendly_track(): return false
	return not rail_network.line_to_depot(piece,along,origin_depot,team,0.0,lane).is_empty() and not rail_network.line_to_depot(piece,along,destination_depot,team,0.0,lane).is_empty()
func start_supply_route(origin: Node3D, destination: Node3D, energy: int, iron: int, repeat_route: bool, wood: int = 0, coal: int = 0) -> bool:
	if not super.start_supply_route(origin,destination,energy,iron,repeat_route,wood,coal): return false
	waiting_for_rail = not route_connected()
	_checked_revision = rail_network.revision
	if waiting_for_rail: state = "Route assigned · waiting for friendly rails"
	return true
func trip_endpoints() -> Array:
	if route_active: return [origin_depot,destination_depot] if endpoints_friendly() else []
	return shipment_pair()
## The connected Depot that would power this train now, or null.
func power_source() -> Node3D:
	return rail_network.power_source(piece,global_position,team) if on_friendly_track() else null
func _rail_changed() -> void:
	_checked_revision = rail_network.revision
	# The piece under the train may be leaving the tree right now; it stops counting as soon as it unregisters.
	if (not is_instance_valid(piece) or not rail_network.pieces.has(piece)) and game.is_node_ready():
		_stop_route()
		snap_to_track()
	# A line through a piece that has gone can no longer be followed.
	for span in _line.get("spans",[]):
		if not is_instance_valid(span.piece) or not rail_network.pieces.has(span.piece):
			_stop_route()
			break
	if not route_active or route_paused: return
	var connected := route_connected()
	if waiting_for_rail:
		if connected:
			waiting_for_rail = false
			power_lost = false
			state = "Rails connected · route starting"
	elif not connected:
		# Keeps the cargo and carries on by itself once the rail is connected again.
		waiting_for_rail = true
		power_lost = true
		_stop_route()
		state = "No power · cargo retained"
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
	power_lost = false
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
	if route_active and waiting_for_rail and not route_paused:
		if not endpoints_friendly(): pause_supply_route()
		else:
			if not advance_supplies(delta):
				state = "No power · cargo retained" if power_lost else "Route assigned · waiting for friendly rails"
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
	# Forks along the way set their switches for this run.
	for span in track.get("spans",[]): span.piece.set_route(span.lane)
	return true
func _route_to_point(point: Vector3) -> bool:
	var hit: Dictionary = rail_network.nearest_piece(point,6.0)
	if hit.is_empty() or not is_instance_valid(piece): return false
	var route: Array = rail_network.chain(piece,hit.piece,team,lane,hit.lane)
	if route.is_empty(): return false
	return _follow(rail_network.line(route,along,hit.distance,consist_length()+2.0))
func _plan(goal: Vector2i) -> bool:
	return _route_to_point(ground.tile_to_world(goal))
func _route_to_interaction(target: Node3D, radius: float) -> bool:
	return _route_near(target,radius)
func _route_near(target: Node3D, _radius: float) -> bool:
	if not is_instance_valid(piece): return false
	_retry = 0.5
	return _follow(rail_network.line_to_depot(piece,along,target,team,consist_length()+2.0,lane))
func _stop_route() -> void:
	_route.clear()
	_moving_to = Vector2i(-1,-1)
	_retry = 0
	if not _line.is_empty():
		_rest_line = _line
		_line = {}
func _walk(delta: float) -> void:
	if _line.is_empty(): _route.clear(); return
	var source := power_source()
	if source == null:
		state = "No power · cargo retained"
		return
	var before := _s
	_s = minf(_goal,_s+move_speed*delta)
	_pay_for_power(source,_s-before)
	var here: Array = RailLine.point(_line,_s)
	global_position = here[0]
	$Visuals.rotation.y = atan2(-here[1].x,-here[1].z)
	var hit: Dictionary = rail_network.locate(_line,_s)
	if not hit.is_empty(): piece = hit.piece; along = hit.distance; lane = hit.lane
	if _s >= _goal-0.001:
		_rest_line = _line
		_line = {}
		_route.clear()
func _pay_for_power(source: Node3D, distance: float) -> void:
	_power_owed += distance*rail_network.rules.train_energy_per_metre
	var whole := floori(_power_owed)
	if whole <= 0: return
	_power_owed -= whole
	source.energy -= mini(whole,source.energy)
func _update_display() -> void:
	super._update_display()
	$Status.text = "TRAIN · %d/%d · %s" % [health,max_health,state]
func _exit_tree() -> void:
	if is_instance_valid(rail_network) and rail_network.changed.is_connected(_rail_changed): rail_network.changed.disconnect(_rail_changed)
	super._exit_tree()
