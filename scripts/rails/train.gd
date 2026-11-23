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
## Off the track after a Derailer destroyed the piece under it (docs/DERAILER.md): it stays where it fell, tipped over.
var derailed := false
const DERAIL_SLEW := 22.0
const DERAIL_ROLL := 30.0
const LINE_SENTINEL := Vector2i(-2,-2)
## Mining Trains (docs/TEMPLE_OF_SCIENCE.md): once its side has the research, a train ordered to an Iron Mine joined
## by track runs there, digs iron itself until it is full, unloads at the nearest connected friendly Depot and goes
## back, until the mine is worked out or it is given another order.
var mining_mine: Node3D
## "to_mine", "digging", "to_depot" or "unloading"; "" while not mining.
var mining_stage := ""
## The Depot it is taking the iron to.
var mining_depot: Node3D
## Iron dug but not yet whole.
var _dig_owed := 0.0
## Iron this train has delivered from mining since its order.
var mined_delivered := 0
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
	if route_request_valid(origin,destination,energy,iron,wood,coal): stop_mining()
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
	if derailed: return
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
	stop_mining()
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
	if derailed:
		_update_display()
		return
	if _checked_revision != rail_network.revision: _rail_changed()
	if is_mining():
		_mining_process(delta)
		_place_consist()
		_animate(delta)
		return
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
	# A line that sets off against the way the train last ran is a reversal: the train's far end now
	# leads, so the run starts there and the consist stays where it stands (it then runs backwards).
	var before: Dictionary = _line if not _line.is_empty() else _rest_line
	var tail := Vector3.INF
	var model := $Visuals.get_node_or_null("Model")
	if not before.is_empty() and model != null and model.has_method("length"):
		var was: Vector3 = RailLine.point(before,_s)[1]
		var now: Vector3 = RailLine.point(track,track.start)[1]
		if was.x*now.x+was.z*now.z < 0.0: tail = RailLine.point(before,model.chord_back(before,_s,model.length()))[0]
	_line = track
	_s = track.start
	if tail != Vector3.INF: _s = minf(track.total,RailLine.nearest(track,tail,track.start))
	_goal = track.total
	_route = [LINE_SENTINEL]
	_moving_to = Vector2i(-1,-1)
	_retry = 0.5
	# Forks along the way set their switches for this run.
	for span in track.get("spans",[]): span.piece.set_route(span.lane)
	return true
func _route_to_point(point: Vector3) -> bool:
	if derailed: return false
	var hit: Dictionary = rail_network.nearest_piece(point,6.0)
	if hit.is_empty() or not is_instance_valid(piece): return false
	var route: Array = rail_network.chain(piece,hit.piece,team,lane,hit.lane)
	if route.is_empty(): return false
	return _follow(rail_network.line(route,along,hit.distance,consist_length()+2.0))
func _plan(goal: Vector2i) -> bool:
	return _route_to_point(ground.tile_to_world(goal))
## A train loads and unloads anywhere on track touching a Depot's rail ring (docs/RAIL_PLANNING.md), which is
## wider than the ground loading area.
func stop_reach(target: Node3D) -> float:
	if target.is_in_group("depots") and target.get("rules") != null:
		return rail_network.depot_reach(target)+rail_network.probe("straight").half_width()+0.1
	return target.dropoff_range
func _route_to_interaction(target: Node3D, radius: float) -> bool:
	return _route_near(target,radius)
func _route_near(target: Node3D, _radius: float) -> bool:
	if derailed or not is_instance_valid(piece): return false
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
		# A line that reverses at a fork goes on with its next leg, the train backing into the other lane.
		var then: Dictionary = _line.get("then",{})
		if not then.is_empty() and then.spans.all(func(span): return is_instance_valid(span.piece) and rail_network.pieces.has(span.piece)):
			_follow(then)
			return
		_rest_line = _line
		_line = {}
		_route.clear()
## The piece under it is destroyed (`RailNetwork.destroy`): the train leaves the track, tips over where it is and loses
## a share of its health. Its cargo stays aboard. Re-railing is not in yet.
func derail() -> void:
	if derailed: return
	derailed = true
	_place_consist()
	_stop_route()
	_route.clear()
	if route_active and not route_paused: pause_supply_route()
	stop_mining()
	state = "Derailed"
	# Slewed off the line and rolled onto its side, so it reads as off the rails from the camera above.
	$Visuals.rotation.y += deg_to_rad(DERAIL_SLEW)
	$Visuals.rotation.z = deg_to_rad(DERAIL_ROLL)
	$Visuals.position.y -= 0.6
	take_damage(roundi(max_health*rail_network.rules.derail_damage))
# ---- mining (docs/TEMPLE_OF_SCIENCE.md)
func is_mining() -> bool:
	return not mining_stage.is_empty()
## Whether this train's side has researched Mining Trains.
func can_mine() -> bool:
	return Research.has(self,team,Research.MINING_TRAINS)
func _mine_ok(mine) -> bool:
	return is_instance_valid(mine) and mine.is_inside_tree() and not mine.is_queued_for_deletion() and mine.is_in_group("mines") and mine.health > 0
## Why this train cannot mine `mine` now, or "" when it can.
func mine_blocker(mine) -> String:
	if not can_mine(): return "Research Mining Trains at a Temple of Science first."
	if not _mine_ok(mine): return "Choose an Iron Mine."
	if mine.get("on_coal") == true: return "Mining Trains dig iron; this is a coal mine."
	if mine.remaining <= 0: return "This mine is worked out."
	if derailed: return "A derailed train cannot mine."
	if not on_friendly_track(): return "The train needs friendly track with a Depot on it."
	if rail_network.mine_stops(mine,team).is_empty(): return "Lay track to this mine first: the train stops on track in the mine's ring."
	if not at_mine(mine) and rail_network.line_to_mine(piece,along,mine,team,0.0,lane).is_empty(): return "This train's track does not reach that mine."
	return ""
## Starts the mining loop at `mine`. Cargo already aboard is unloaded first.
func command_mine(mine: Node3D) -> bool:
	var blocker := mine_blocker(mine)
	if not blocker.is_empty():
		game.notify(blocker)
		return false
	order_queue.clear()
	_clear_fetch()
	pack_supplies()
	cancel_supply_route()
	_stop_route()
	mining_mine = mine
	mining_stage = "to_depot" if stockpile.total() > 0 else "to_mine"
	mining_depot = null
	mined_delivered = 0
	_dig_owed = 0.0
	transfer_timer = 0
	_retry = 0
	order = "mine_rail"
	order_target = mine
	state = "To %s · mining" % mine.name
	return true
func stop_mining() -> void:
	if not is_mining(): return
	mining_stage = ""
	mining_mine = null
	mining_depot = null
	_dig_owed = 0.0
	transfer_timer = 0
	_stop_route()
	if order == "mine_rail":
		order = "idle"
		order_target = null
## Right-click on a mine with a train: mine it.
func command_gather(node: Node3D) -> void:
	if is_instance_valid(node) and node.is_in_group("mines"): command_mine(node)
	else: game.notify("Trains load and unload at friendly Depots.")
func run_order(entry: Dictionary) -> void:
	if entry.kind == "mine_rail": command_mine(entry.get("target"))
	else: super.run_order(entry)
## How near a mine's centre the train must stand to dig: on track inside the mine's ring.
func _mine_radius(mine: Node3D) -> float:
	return rail_network.target_reach(mine)+rail_network.probe("straight").half_width()+0.1
func at_mine(mine: Node3D) -> bool:
	if not _mine_ok(mine): return false
	return Vector2(global_position.x,global_position.z).distance_to(Vector2(mine.global_position.x,mine.global_position.z)) <= _mine_radius(mine)
func at_depot(depot: Node3D) -> bool:
	return friendly_route_depot(depot) and global_position.distance_to(depot.global_position) <= stop_reach(depot)
## Where to take the iron: the connected friendly Depot with the shortest line from here, one with room first.
## [depot, line, has room]; the line is {} when the train already stands at that Depot.
func _delivery() -> Array:
	var best := []
	if not on_friendly_track(): return best
	for depot in rail_network.connected_depots(piece,team):
		if not friendly_route_depot(depot): continue
		var room: bool = depot.stockpile.space() > 0
		if at_depot(depot) and room: return [depot,{},true]
		var track: Dictionary = rail_network.line_to_depot(piece,along,depot,team,consist_length()+2.0,lane)
		if track.is_empty(): continue
		if best.is_empty() or (room and not best[2]) or (room == best[2] and rail_network.travel(track) < rail_network.travel(best[1])): best = [depot,track,room]
	return best
func _mining_process(delta: float) -> void:
	_retry = maxf(0,_retry-delta)
	if not _route.is_empty() or _moving_to.x >= 0:
		_walk(delta)
		_update_display()
		return
	var mine := mining_mine
	match mining_stage:
		"to_mine":
			if not _mine_ok(mine) or mine.remaining <= 0:
				_mining_over("Mine worked out" if _mine_ok(mine) else "Mine gone")
			elif at_mine(mine):
				mining_stage = "digging"
				state = "Mining iron at %s" % mine.name
			elif _retry <= 0:
				_retry = 1.0
				if _follow(rail_network.line_to_mine(piece,along,mine,team,consist_length()+2.0,lane)): state = "To %s · mining" % mine.name
				else: state = "No track to %s · waiting" % mine.name
		"digging":
			var space := stockpile.space()
			if not _mine_ok(mine) or mine.remaining <= 0 or space <= 0:
				if stockpile.total() > 0:
					mining_stage = "to_depot"
					mining_depot = null
				else: _mining_over("Mine worked out" if _mine_ok(mine) else "Mine gone")
			else:
				_dig_owed += rail_network.rules.train_mine_rate*delta
				var whole := mini(floori(_dig_owed),space)
				if whole > 0:
					_dig_owed -= whole
					stockpile.deposit(&"iron",mine.extract(whole,team))
				state = "Mining iron at %s · %d / %d" % [mine.name,stockpile.total(),stockpile.capacity]
		"to_depot":
			if is_instance_valid(mining_depot) and at_depot(mining_depot):
				mining_stage = "unloading"
				transfer_timer = 0
			elif _retry <= 0:
				_retry = 1.0
				var pick := _delivery()
				if pick.is_empty(): state = "No connected Depot · cargo retained"
				else:
					mining_depot = pick[0]
					if pick[1].is_empty():
						mining_stage = "unloading"
						transfer_timer = 0
					else:
						_follow(pick[1])
						state = "To %s · delivering iron" % mining_depot.name
		"unloading":
			if not at_depot(mining_depot):
				mining_stage = "to_depot"
				mining_depot = null
			elif mining_depot.stockpile.space() <= 0:
				transfer_timer = 0
				state = "%s full · cargo retained" % mining_depot.name
			else:
				transfer_timer += delta
				state = "Unloading iron · %.1fs" % maxf(0,supply_rules.transfer_seconds-transfer_timer)
				if transfer_timer >= supply_rules.transfer_seconds:
					transfer_timer = 0
					for kind in ResourceStockpile.KINDS:
						var moved: int = ResourceStockpile.transfer(stockpile,mining_depot.stockpile,kind,stockpile.amount(kind))
						if moved <= 0: continue
						game.delivered(mining_depot,kind,moved)
						if kind == &"iron": mined_delivered += moved
					if stockpile.total() <= 0:
						if _mine_ok(mine) and mine.remaining > 0: mining_stage = "to_mine"
						else: _mining_over("Mine worked out · iron delivered")
	_update_display()
func _mining_over(text: String) -> void:
	stop_mining()
	state = text
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
