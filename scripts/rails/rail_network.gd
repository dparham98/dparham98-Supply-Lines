extends Node
## The maglev network (docs/MAGLEV_TRACKS.md): authored straight and curve pieces laid end to end.
## Pieces connect where their ends meet head-on; trains follow the joined centre lines. All the joined
## pieces form a line, which belongs to every team with a Depot connected to it (any piece within the
## Depot's loading range) and is powered by those Depots' energy. Pieces mark the tiles under them so
## buildings keep off. Ground units cross tracks freely; trains do not take part in ground occupancy.
signal changed
@export var rules: RailRules
@export var straight_scene: PackedScene
@export var curve_scene: PackedScene
@export var fork_left_scene: PackedScene
@export var fork_right_scene: PackedScene
@export var train_scene: PackedScene
## The ring drawn round each rail target while track is planned: amber, green once the plan touches it.
@export var target_ring_scene: PackedScene = preload("res://scenes/ui/rail_target_ring.tscn")
## Snap distance from the cursor to a free end of an existing piece.
@export var snap_distance := 4.0
const SAMPLE := 0.5
const JOIN_EPSILON := 0.05
var revision := 0
var pieces: Array[Node3D] = []
var subscribed: Dictionary = {}
var _probes := {}
var _ghost_materials := {}
var _lines := {}
var _lines_key := ""
var _poll_left := 0.0
var _announced_depots := ""
## Planned track not laid yet (docs/RAIL_PLANNING.md): {kind, transform, cells, ghost}, in the order placed.
var pending: Array[Dictionary] = []
var _model_scales := {}
## The two targets the player picked to connect (docs/RAIL_PLANNING.md); the plan is the path suggested
## between them.
var route_from: Node3D
var route_to: Node3D
## Where the player dragged the suggested track through, or null for the shortest path.
var route_via = null
## True when the last drag point had no open path through it; the track keeps its last shape.
var route_blocked := false
var _drag_tried = null
var _router
## Target rings shown while planning, keyed by the target's instance id.
var _target_rings := {}
## Upkeep owed by each line, keyed by the line's lowest piece id; whole units are paid as they accrue.
var _upkeep_owed := {}
@onready var ground = get_tree().get_first_node_in_group("terrain_grid")
@onready var game = get_parent()
func _ready() -> void: add_to_group("rail_network")
func _exit_tree() -> void:
	for p in _probes.values(): p.free()
	_probes.clear()
## A piece instance used only for geometry (never in the tree).
func probe(kind: String) -> Node3D:
	if not _probes.has(kind): _probes[kind] = scene_for(kind).instantiate()
	return _probes[kind]
func scene_for(kind: String) -> PackedScene:
	return {"straight":straight_scene,"curve":curve_scene,"fork_left":fork_left_scene,"fork_right":fork_right_scene}[kind]
## Total track in a piece: a fork counts both its lanes.
func piece_length(kind: String) -> float: return probe(kind).total_length()
func cost(kind: String) -> int: return ceili(piece_length(kind)*rules.rail_iron_cost)
# ---- ownership
## Whether the piece's line has a living Depot of `team` connected to it.
## A line with no Depot on it at all, such as one from a mine to a build site (docs/RAIL_PLANNING.md),
## belongs to the side whose Depot paid for it.
func friendly_piece(piece, team: String) -> bool:
	if not connected_depots(piece,team).is_empty(): return true
	if not is_instance_valid(piece) or piece.is_queued_for_deletion(): return false
	var entry = lines().get(piece.get_instance_id())
	if entry == null or not entry.depots.is_empty(): return false
	for other in entry.pieces:
		if is_instance_valid(other) and is_instance_valid(other.assigned_depot) and other.assigned_depot.team == team: return true
	return false
func _depots() -> Array[Node]:
	return get_tree().get_nodes_in_group("depots") if is_inside_tree() else []
func _depot_key() -> String:
	var key := ""
	for depot in _depots(): key += "|%d:%s:%d" % [depot.get_instance_id(),depot.team,1 if depot.health > 0 else 0]
	return key
func _network_key() -> String:
	return str(revision)+_depot_key()
## Joined pieces as lines: piece id to {pieces, depots}, rebuilt when track or Depots change.
func lines() -> Dictionary:
	var key := _network_key()
	if key == _lines_key: return _lines
	_lines_key = key
	_lines = {}
	for start in pieces:
		if not is_instance_valid(start) or _lines.has(start.get_instance_id()): continue
		var entry := {pieces = [start], depots = []}
		_lines[start.get_instance_id()] = entry
		var head := 0
		while head < entry.pieces.size():
			var piece: Node3D = entry.pieces[head]; head += 1
			for index in range(piece.end_count()):
				var link := connection(piece,index)
				if link.is_empty() or _lines.has(link.piece.get_instance_id()): continue
				_lines[link.piece.get_instance_id()] = entry
				entry.pieces.append(link.piece)
		for depot in _depots():
			if depot.health <= 0: continue
			for piece in entry.pieces:
				if not stop_on(piece,depot).is_empty(): entry.depots.append(depot); break
	return _lines
## Living Depots of `team` connected to this piece's line.
func connected_depots(piece, team: String) -> Array:
	if not is_instance_valid(piece) or piece.is_queued_for_deletion(): return []
	var entry = lines().get(piece.get_instance_id())
	if entry == null: return []
	return entry.depots.filter(func(depot): return is_instance_valid(depot) and depot.team == team)
## The nearest connected Depot that has energy to run a train at `at`, or null.
func power_source(piece, at: Vector3, team: String) -> Node3D:
	var best: Node3D = null
	for depot in connected_depots(piece,team):
		if depot.energy >= 1 and (best == null or depot.global_position.distance_squared_to(at) < best.global_position.distance_squared_to(at)): best = depot
	return best
func powered(piece, team: String) -> bool:
	return is_instance_valid(piece) and power_source(piece,piece.global_position,team) != null
## Compatibility with cell callers: the piece under this tile.
func piece_at_cell(cell: Vector2i):
	if not ground.is_tile_in_bounds(cell): return null
	var rail = ground.tiles[cell.y*500+cell.x].get("rail")
	return rail if is_instance_valid(rail) else null
func friendly(cell: Vector2i, team: String) -> bool:
	return friendly_piece(piece_at_cell(cell),team)
func piece_at(point: Vector3):
	var cell = ground.get_tile_at_position(point)
	return null if cell == null else piece_at_cell(cell)
## The piece whose centre line passes nearest `point`, within `limit`, with its distance along.
func nearest_piece(point: Vector3, limit := INF) -> Dictionary:
	var best := {}
	var best_gap := limit
	for piece in pieces:
		if not is_instance_valid(piece): continue
		var hit: Dictionary = piece.nearest(point)
		if hit.gap < best_gap: best_gap = hit.gap; best = {piece = piece, distance = hit.distance, gap = hit.gap, lane = hit.lane}
	return best
# ---- registration
## Tiles whose centres lie on a piece of `kind` at transform `xf`: within half the width of the
## centre line and between the ends, so joined pieces never share a tile.
func cells_for(kind: String, xf: Transform3D) -> Array[Vector2i]:
	var p: Node3D = probe(kind)
	var found := {}
	var reach: float = p.half_width()
	var inverse := xf.affine_inverse()
	for lane in range(p.lane_count()):
		var total: float = p.length(lane)
		var steps := maxi(4,int(total/0.25))
		for i in range(steps+1):
			var centre_point: Vector3 = xf*p.local_point(minf(total-0.001,total*i/steps),lane)
			var centre = ground.get_tile_at_position(centre_point)
			if centre == null: continue
			var span := int(ceil(reach))+1
			for dx in range(-span,span+1):
				for dz in range(-span,span+1):
					var cell: Vector2i = centre+Vector2i(dx,dz)
					if found.has(cell) or not ground.is_tile_in_bounds(cell): continue
					if p.local_inside(inverse*ground.tile_to_world(cell)): found[cell] = true
	var result: Array[Vector2i] = []
	for cell in found: result.append(cell)
	return result
## Open buildable land for every tile under the piece, with no other track there.
func ground_clear(cells: Array[Vector2i], ignore = null) -> bool:
	if cells.is_empty(): return false
	for cell in cells:
		if not ground.is_tile_in_bounds(cell) or ground.get_terrain(cell) not in [0,2]: return false
		var tile: Dictionary = ground.tiles[cell.y*500+cell.x]
		if not tile.buildable or (tile.occupied_by != null and not str(tile.occupied_by).begins_with("agent_")): return false
		var rail = tile.get("rail")
		if is_instance_valid(rail) and rail != ignore: return false
	return true
func register(piece: Node3D) -> bool:
	if not is_instance_valid(piece.assigned_depot): return false
	var cells := cells_for(piece.kind,piece.global_transform)
	if not ground_clear(cells,piece): return false
	piece.cells = cells
	for cell in cells: ground.tiles[cell.y*500+cell.x]["rail"] = piece
	pieces.append(piece)
	var id: int = piece.assigned_depot.get_instance_id()
	if not subscribed.has(id):
		subscribed[id] = true
		piece.assigned_depot.ownership_changed.connect(_owner_changed)
		piece.assigned_depot.tree_exiting.connect(_owner_changed)
	_announce()
	return true
func unregister(piece: Node3D) -> void:
	if not pieces.has(piece): return
	pieces.erase(piece)
	if is_instance_valid(ground):
		for cell in piece.cells:
			if ground.is_tile_in_bounds(cell) and ground.tiles[cell.y*500+cell.x].get("rail") == piece: ground.tiles[cell.y*500+cell.x].erase("rail")
	_announce()
func _owner_changed() -> void:
	for piece in pieces:
		if is_instance_valid(piece): piece.update_color()
	_announce()
func _announce() -> void:
	revision += 1
	changed.emit()
# ---- connectivity
## The piece and end that meets `piece`'s end `index` head-on, or {}.
func connection(piece: Node3D, index: int) -> Dictionary:
	var end: Dictionary = piece.ends()[index]
	for other in pieces:
		if other == piece or not is_instance_valid(other): continue
		var other_ends: Array[Dictionary] = other.ends()
		for j in range(other_ends.size()):
			if other_ends[j].position.distance_to(end.position) <= JOIN_EPSILON and other_ends[j].out.dot(end.out) < -0.99: return {piece = other, end = j}
	return {}
## Free ends of friendly pieces: {piece, end, position, out}.
func free_ends(team := "player") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for piece in pieces:
		if not friendly_piece(piece,team): continue
		var ends: Array[Dictionary] = piece.ends()
		for i in range(ends.size()):
			if connection(piece,i).is_empty(): result.append({piece = piece, end = i, position = ends[i].position, out = ends[i].out})
	return result
func _state(piece: Node3D, lane: int, enter: int) -> String:
	return "%d:%d:%d" % [piece.get_instance_id(),lane,enter]
## Everywhere a train starting on `start`'s `lane` can run over friendly track, in breadth-first order.
## A state is a piece, a lane and the end it was entered by, so a train through a fork takes the entry
## and one exit, and can never pass from one exit to the other.
func _search(start: Node3D, team: String, start_lane := 0) -> Dictionary:
	var seen := {}
	if not friendly_piece(start,team): return seen
	var first := _state(start,start_lane,-1)
	seen[first] = {piece = start, lane = start_lane, enter = -1, from = ""}
	var frontier: Array[String] = [first]
	var head := 0
	while head < frontier.size():
		var key := frontier[head]; head += 1
		var state: Dictionary = seen[key]
		var ends: Array = state.piece.lane_ends(state.lane)
		var exits: Array = ends if state.enter == -1 else ([ends[1]] if state.enter == ends[0] else [ends[0]])
		for exit_end in exits:
			var link := connection(state.piece,exit_end)
			if link.is_empty() or not friendly_piece(link.piece,team): continue
			for lane in link.piece.lanes_at(link.end):
				var next := _state(link.piece,lane,link.end)
				if seen.has(next): continue
				seen[next] = {piece = link.piece, lane = lane, enter = link.end, from = key}
				frontier.append(next)
	return seen
func _found(seen: Dictionary, goal: Node3D, goal_lane: int) -> String:
	for key in seen:
		if seen[key].piece == goal and (goal_lane < 0 or seen[key].lane == goal_lane): return key
	return ""
func reachable(start: Node3D, goal: Node3D, team: String, start_lane := 0) -> bool:
	return is_instance_valid(goal) and not _found(_search(start,team,start_lane),goal,-1).is_empty()
## Pieces from `start` to `goal` as [{piece, enter, lane}] where `enter` is the end the train comes
## in by (-1 for the starting piece). Empty when not connected.
func chain(start: Node3D, goal: Node3D, team: String, start_lane := 0, goal_lane := -1) -> Array:
	if not is_instance_valid(goal): return []
	var seen := _search(start,team,start_lane)
	var key := _found(seen,goal,goal_lane)
	if key.is_empty(): return []
	var result: Array = []
	while not key.is_empty():
		var entry: Dictionary = seen[key]
		result.push_front({piece = entry.piece, enter = entry.enter, lane = entry.lane})
		key = entry.from
	return result
# ---- lines for trains
## Samples a piece's centre line from distance `from_d` to `to_d` (either direction) into `points`.
func _sample(piece: Node3D, from_d: float, to_d: float, points: PackedVector3Array, lane := 0) -> void:
	var span := to_d-from_d
	var steps := maxi(1,int(absf(span)/SAMPLE))
	for i in range(steps+1):
		var p: Vector3 = piece.point_at(from_d+span*i/steps,lane)
		if points.is_empty() or points[points.size()-1].distance_to(p) > 0.001: points.append(p)
## A line {points, cum, total, start, spans} along a chain, starting `start_d` along the first piece and ending
## `end_d` along the last (the whole piece when -1), with up to `tail` metres of track behind the
## start so a long train has somewhere to stand.
func line(chain_pieces: Array, start_d: float, end_d := -1.0, tail := 0.0) -> Dictionary:
	var points := PackedVector3Array()
	if chain_pieces.is_empty(): return {}
	var first: Node3D = chain_pieces[0].piece
	var first_lane: int = chain_pieces[0].get("lane",0)
	# Direction through the first piece: toward the end that joins the next piece, else toward end 1.
	var forward := true
	if chain_pieces.size() > 1:
		var next: Dictionary = chain_pieces[1]
		var joined := connection(first,first.lane_ends(first_lane)[1])
		forward = not joined.is_empty() and joined.piece == next.piece and joined.end == next.enter
	elif end_d >= 0.0: forward = end_d >= start_d
	var behind := PackedVector3Array()
	_tail(first,start_d,forward,tail,behind,first_lane)
	for i in range(behind.size()-1,-1,-1): points.append(behind[i])
	var spans: Array[Dictionary] = []
	for k in range(chain_pieces.size()):
		var entry: Dictionary = chain_pieces[k]
		var piece: Node3D = entry.piece
		var lane: int = entry.get("lane",0)
		var total: float = piece.length(lane)
		var from_d: float
		var to_d: float
		if k == 0:
			from_d = start_d
			to_d = total if forward else 0.0
		else:
			forward = entry.enter == piece.lane_ends(lane)[0]
			from_d = 0.0 if forward else total
			to_d = total if forward else 0.0
		if k == chain_pieces.size()-1 and end_d >= 0.0: to_d = end_d
		var begin := maxi(0,points.size()-1)
		_sample(piece,from_d,to_d,points,lane)
		spans.append({piece = piece, lane = lane, from_d = from_d, to_d = to_d, begin = begin, end = points.size()-1})
	var cum := PackedFloat32Array()
	var running := 0.0
	for i in range(points.size()):
		if i > 0: running += points[i-1].distance_to(points[i])
		cum.append(running)
	var start_offset: float = cum[behind.size()-1] if behind.size() > 0 else 0.0
	return {points = points, cum = cum, total = running, start = start_offset, spans = spans}
## Which piece and lane a point `s` along a line is on: {piece, lane, distance}, or {}.
static func locate(track: Dictionary, s: float) -> Dictionary:
	var spans: Array = track.get("spans",[])
	var cum: PackedFloat32Array = track.cum
	for span in spans:
		if s > cum[span.end]+0.0001 and span != spans[spans.size()-1]: continue
		var width: float = cum[span.end]-cum[span.begin]
		var t := 0.0 if width <= 0.0001 else clampf((s-cum[span.begin])/width,0.0,1.0)
		return {piece = span.piece, lane = span.lane, distance = lerpf(span.from_d,span.to_d,t)}
	return {}
## Track behind a point: walks back through connected pieces up to `wanted` metres, farthest first.
func _tail(piece: Node3D, d: float, forward: bool, wanted: float, out: PackedVector3Array, start_lane := 0) -> void:
	var remaining := wanted
	var current := piece
	var lane := start_lane
	var at := d
	var dir_forward := forward
	var collected := PackedVector3Array()
	while remaining > 0.0 and is_instance_valid(current):
		var total: float = current.length(lane)
		var back_end := 0.0 if dir_forward else total
		var available := absf(at-back_end)
		var take := minf(available,remaining)
		var target := at-take if dir_forward else at+take
		var segment := PackedVector3Array()
		_sample(current,at,target,segment,lane)
		for i in range(1,segment.size()): collected.append(segment[i])
		remaining -= take
		if remaining <= 0.0 or take < available: break
		var link := connection(current,current.lane_ends(lane)[0 if dir_forward else 1])
		if link.is_empty(): break
		current = link.piece
		lane = current.lanes_at(link.end)[0]
		# Walking back from the end we arrived at: entering at a lane's far end means distance falls from its full length.
		dir_forward = link.end == current.lane_ends(lane)[1]
		at = current.length(lane) if dir_forward else 0.0
	for p in collected: out.append(p)
## Position and tangent at `s` along a line, extrapolating straight past either end.
static func line_point(track: Dictionary, s: float) -> Array:
	var points: PackedVector3Array = track.points
	var cum: PackedFloat32Array = track.cum
	if points.size() < 2: return [points[0] if points.size() == 1 else Vector3.ZERO,Vector3.FORWARD]
	var i := 1
	var lo := 1
	var hi := points.size()-1
	while lo < hi:
		var mid := (lo+hi)/2
		if cum[mid] < s: lo = mid+1
		else: hi = mid
	i = clampi(lo,1,points.size()-1)
	var a: Vector3 = points[i-1]; var b: Vector3 = points[i]
	var seg := cum[i]-cum[i-1]
	var t := 0.0 if seg <= 0.0001 else (s-cum[i-1])/seg
	var tangent := (b-a).normalized()
	return [a+(b-a)*t,tangent]
# ---- stops
## Where a train stops for a Depot on a piece: nearest centre-line point within the loading radius.
func stop_on(piece: Node3D, depot: Node3D, lane := -1) -> Dictionary:
	var hit: Dictionary = piece.nearest(depot.global_position,lane)
	return hit if hit.gap <= depot_reach(depot)+piece.half_width() else {}
## A Depot's rail ring: where track connects to it and trains are built, load and unload (docs/RAIL_PLANNING.md).
func depot_reach(depot: Node3D) -> float:
	return depot.rules.construction_radius*rules.depot_reach_fraction
## Every lane of friendly track in `depot`'s loading area: {piece, lane, distance}.
func loading_stops(depot: Node3D, team: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not is_instance_valid(depot) or depot.health <= 0 or depot.team != team: return result
	for piece in pieces:
		if not friendly_piece(piece,team): continue
		for lane in range(piece.lane_count()):
			var stop := stop_on(piece,depot,lane)
			if not stop.is_empty(): result.append({piece = piece, lane = lane, distance = stop.distance})
	return result
func loading_pieces(depot: Node3D, team: String) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for stop in loading_stops(depot,team):
		if not result.has(stop.piece): result.append(stop.piece)
	return result
## The shortest line from a train at `from_piece`/`from_d` to a stop in `depot`'s loading area, or {}.
func line_to_depot(from_piece: Node3D, from_d: float, depot: Node3D, team: String, tail := 0.0, from_lane := 0) -> Dictionary:
	var best := {}
	for stop in loading_stops(depot,team):
		var route := chain(from_piece,stop.piece,team,from_lane,stop.lane)
		if route.is_empty(): continue
		var track := line(route,from_d,stop.distance,tail)
		if track.is_empty(): continue
		var travel: float = track.total-track.start
		if best.is_empty() or travel < best.total-best.start: best = track
	return best
## Where a new train stands: in the Depot's loading area, on the line through `on_piece` when one was chosen
## (docs/RAIL_PLANNING.md) and it still reaches the Depot, else on any line that does.
func spawn_stop(depot: Node3D, on_piece: Node3D = null) -> Dictionary:
	var stops := loading_stops(depot,depot.team)
	if is_instance_valid(on_piece) and lines().has(on_piece.get_instance_id()):
		var chosen = lines()[on_piece.get_instance_id()]
		var on_line := stops.filter(func(stop): return is_same(lines().get(stop.piece.get_instance_id()),chosen))
		if not on_line.is_empty(): stops = on_line
	for stop in stops:
		return {piece = stop.piece, lane = stop.lane, distance = stop.distance, position = stop.piece.point_at(stop.distance,stop.lane)}
	return {}
## The separate lines of track that reach `depot`'s loading area, one piece of each (its first loading piece).
func depot_lines(depot: Node3D) -> Array[Node3D]:
	var seen := []
	var result: Array[Node3D] = []
	for stop in loading_stops(depot,depot.team):
		var entry = lines().get(stop.piece.get_instance_id())
		if seen.any(func(other): return is_same(other,entry)): continue
		seen.append(entry)
		result.append(stop.piece)
	return result
## The laid piece of one of `depot`'s lines nearest `point` within `within` metres, or null: the line a train
## queued there will start on.
func depot_line_at(depot: Node3D, point: Vector3, within := 3.0) -> Node3D:
	var reaching := depot_lines(depot)
	var best: Node3D = null
	var best_gap := within
	for piece in pieces:
		if not is_instance_valid(piece) or not friendly_piece(piece,depot.team): continue
		var entry = lines().get(piece.get_instance_id())
		var line_piece: Node3D = null
		for other in reaching:
			if is_same(lines().get(other.get_instance_id()),entry): line_piece = other
		if line_piece == null: continue
		var total: float = piece.length()
		for i in range(17):
			var at: Vector3 = piece.point_at(total*i/16.0,0)
			var gap := Vector2(at.x-point.x,at.z-point.z).length()
			if gap <= best_gap: best_gap = gap; best = line_piece
	return best
# ---- placement
## Transform for a piece of `kind` placed from `point`: snapped onto the nearest free friendly end,
## else free on the tile under the cursor heading `heading`. `join` is the piece's end that meets the
## track: true or 1 lays a curve from its far end so it bends the other way. Returns
## {transform, snapped, entry} or {} when the point is off the map.
func placement(kind: String, point: Vector3, heading: Vector3, join = 0) -> Dictionary:
	var entry_position := point
	var entry_out := heading.normalized()
	var snapped := false
	var cell = ground.get_tile_at_position(point)
	if cell == null: return {}
	entry_position = ground.tile_to_world(cell)
	var nearest := {}
	for end in free_ends("player")+pending_free_ends():
		var gap: float = Vector2(end.position.x,end.position.z).distance_to(Vector2(point.x,point.z))
		if gap <= snap_distance and (nearest.is_empty() or gap < nearest.gap): nearest = {end = end, gap = gap}
	if not nearest.is_empty():
		entry_position = nearest.end.position
		entry_out = nearest.end.out
		snapped = true
	return {transform = transform_for(kind,entry_position,entry_out,join), snapped = snapped, entry = entry_position}
## The piece transform that puts its end `join` at `entry`, facing back along travel `direction`.
func transform_for(kind: String, entry: Vector3, direction: Vector3, join = 0) -> Transform3D:
	var flat := Vector3(direction.x,0,direction.z).normalized()
	var end: Dictionary = probe(kind).local_end(int(join))
	var turned := Basis(Vector3.UP,(end.out as Vector3).signed_angle_to(-flat,Vector3.UP))
	return Transform3D(turned,entry-turned*(end.position as Vector3))
## Whether a piece at `xf` is connected: it joins friendly track head-on or lies in a Depot's loading range.
func connects(kind: String, xf: Transform3D, team := "player") -> bool:
	var p: Node3D = probe(kind)
	var open := free_ends(team)
	for index in range(p.end_count()):
		var end: Dictionary = p.local_end(index)
		var at: Vector3 = xf*(end.position as Vector3)
		var out: Vector3 = (xf.basis*(end.out as Vector3)).normalized()
		for free in open:
			if free.position.distance_to(at) <= JOIN_EPSILON and free.out.dot(out) < -0.99: return true
	for depot in _depots():
		if depot.team != team or depot.health <= 0: continue
		var centre := Vector2(depot.global_position.x,depot.global_position.z)
		for lane in range(p.lane_count()):
			var total: float = p.length(lane)
			for i in range(maxi(8,int(total/0.25))+1):
				var at: Vector3 = xf*p.local_point(total*i/maxi(8,int(total/0.25)),lane)
				if Vector2(at.x,at.z).distance_to(centre) <= depot_reach(depot)+p.half_width(): return true
	return false
## Whether `payer` can lay this piece here: a living friendly Depot whose territory covers every
## tile under it, open land with no other track, connected to a Depot, and the iron for it.
func can_place(kind: String, xf: Transform3D, payer, check_funds := true) -> bool:
	if not is_instance_valid(payer) or not payer.is_in_group("depots") or payer.team != "player" or payer.health <= 0: return false
	var cells := cells_for(kind,xf)
	if not ground_clear(cells) or not connects(kind,xf): return false
	for cell in cells:
		if ground.tile_to_world(cell).distance_to(payer.global_position) > payer.rules.construction_radius: return false
	return not check_funds or payer.iron >= cost(kind)
## The Depot that pays: the pin when set, else the nearest covering Depot that can afford it.
func payer_for(kind: String, xf: Transform3D, pinned = null) -> Node3D:
	if pinned != null: return pinned if can_place(kind,xf,pinned) else null
	var centre: Vector3 = xf*probe(kind).local_point(probe(kind).length()*0.5)
	for source in SupplySource.candidates(get_tree(),centre,"player"):
		if source.is_in_group("depots") and can_place(kind,xf,source): return source
	return null
## Lays a piece, charging its payer. Returns the piece or null.
func place(kind: String, point: Vector3, heading: Vector3, join = 0, pinned = null) -> Node3D:
	var spot := placement(kind,point,heading,join)
	if spot.is_empty(): return null
	var payer := payer_for(kind,spot.transform,pinned)
	if payer == null:
		game.notify("%s must start in a Depot's loading range or join connected track, on open land inside one Depot territory, with %d iron there." % [kind.capitalize(),cost(kind)])
		return null
	return lay(kind,spot.transform,payer)
## Lays a piece for a payer that has already been checked, charging it.
func lay(kind: String, xf: Transform3D, payer: Node3D) -> Node3D:
	if not payer.spend_local(rules.rail_energy_cost,cost(kind)): game.notify("Paying Depot lacks local rail resources."); return null
	var piece = scene_for(kind).instantiate()
	piece.assigned_depot = payer
	piece.transform = xf
	var parent: Node = game.get_node("Entities/Rails") if game.has_node("Entities/Rails") else game
	parent.add_child(piece,true)
	if not is_instance_valid(piece) or piece.is_queued_for_deletion():
		payer.stockpile.deposit(&"iron",cost(kind))
		game.notify("Track could not be laid there.")
		return null
	game.notify("%s laid from %s for %d iron." % [kind.capitalize(),payer.name,cost(kind)])
	return piece
## Legacy entry: lays a straight at a point heading +X (tests and tools).
func build(point: Vector3) -> bool:
	var depots = game.get_node("DepotNetwork")
	return place("straight",point,Vector3.RIGHT,false,depots.selected if depots.owned_selected() and depots.selected.is_in_group("depots") else null) != null
# ---- preview
func _process(delta: float) -> void:
	_poll_left -= delta
	if _poll_left <= 0.0:
		_poll_left = 0.5
		_poll_power()
		charge_upkeep(0.5)
	var preview = game.get_node_or_null("RailPreview")
	if preview == null: return
	var active: bool = game.placing_rail
	preview.visible = active
	show_target_rings(active)
	if not active: return
	# Only the label follows the cursor; the path itself is drawn by the planned pieces.
	for child in preview.get_children(): child.visible = child.name == "Status"
	var camera := game.get_viewport().get_camera_3d()
	var mouse := game.get_viewport().get_mouse_position()
	var point = Plane(Vector3.UP,0).intersects_ray(camera.project_ray_origin(mouse),camera.project_ray_normal(mouse))
	if point == null: preview.visible = false; return
	preview.get_node("Status").global_position = point+Vector3.UP*2.0
	if is_instance_valid(route_from) and is_instance_valid(route_to) and cursor != null: follow_cursor(cursor,delta)
	preview.get_node("Status").text = route_status()
## The cursor label while connecting buildings.
func route_status() -> String:
	if not is_instance_valid(route_from): return "RAIL · click a Depot, mine or build site"
	if not is_instance_valid(route_to): return "FROM %s · click the building to connect" % target_name(route_from).to_upper()
	if pending.is_empty(): return "NO OPEN PATH · click another building"
	var hud = game.get_node("Interface")
	var blocker := plan_blocker(hud.global_payer if hud.global_pinned else null)
	return ("NO PATH THROUGH HERE · " if route_blocked else "")+"%d PIECE%s · %d IRON · %s" % [pending.size(),"" if pending.size() == 1 else "S",plan_cost(),"CLICK LAYS IT" if blocker.is_empty() else "NOT ENOUGH IRON"]
func target_name(node: Node3D) -> String:
	if node.is_in_group("construction_plans"): return "%s site" % node.spec.title
	if node.is_in_group("mines"): return "Mine"
	return String(node.name)
## Depots can appear, fall or run out of energy without the track changing.
func _poll_power() -> void:
	var depots := _depot_key()
	if depots != _announced_depots:
		_announced_depots = depots
		_announce()
	for piece in pieces:
		if is_instance_valid(piece): piece.update_color()
## The scale a preview model was saved with: the same as the laid track's model. Setting a global transform
## replaces it, so it is read once, before the first placement, and applied again every time.
func model_scale(model: Node3D) -> Vector3:
	var key := model.get_instance_id()
	if not _model_scales.has(key): _model_scales[key] = model.scale
	return _model_scales[key]
func _tint_ghost(ghost: Node3D, valid: bool, invalid_colour := Color(1.0,0.2,0.15,0.45)) -> void:
	var colour := Color(0.3,1.0,0.5,0.45) if valid else invalid_colour
	for item in ghost.find_children("*","MeshInstance3D",true,false):
		var key := item.get_instance_id()
		if not _ghost_materials.has(key):
			var material := StandardMaterial3D.new()
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			item.material_override = material
			_ghost_materials[key] = material
		_ghost_materials[key].albedo_color = colour
# ---- planning (docs/RAIL_PLANNING.md)
## Track is planned piece by piece first and laid all at once. A plan can be committed only when the track it
## forms, with any laid track it joins, connects two targets: friendly Depots, mines or unfinished build sites.
## Planned pieces need not be in any Depot's range; the Depot that pays must have all the iron.
func _pending_end(entry: Dictionary, index: int) -> Dictionary:
	var end: Dictionary = probe(entry.kind).local_end(index)
	var xf: Transform3D = entry.transform
	return {position = xf*(end.position as Vector3), out = (xf.basis*(end.out as Vector3)).normalized()}
func _ends_meet(a: Dictionary, b: Dictionary) -> bool:
	return a.position.distance_to(b.position) <= JOIN_EPSILON and a.out.dot(b.out) < -0.99
## Ends of planned pieces that meet nothing yet: {piece = null, pending, end, position, out}.
func pending_free_ends() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i in range(pending.size()):
		for index in range(probe(pending[i].kind).end_count()):
			var end := _pending_end(pending[i],index)
			if _meets_anything(end,i).is_empty(): result.append({piece = null, pending = i, end = index, position = end.position, out = end.out})
	return result
## What an end meets head-on: {pending} for another planned piece, {piece, end} for laid track, or {}.
func _meets_anything(end: Dictionary, skip := -1) -> Dictionary:
	for j in range(pending.size()):
		if j == skip: continue
		for other in range(probe(pending[j].kind).end_count()):
			if _ends_meet(end,_pending_end(pending[j],other)): return {pending = j}
	for piece in pieces:
		if not is_instance_valid(piece): continue
		var piece_ends: Array[Dictionary] = piece.ends()
		for index in range(piece_ends.size()):
			if _ends_meet(end,piece_ends[index]): return {piece = piece, end = index}
	return {}
func _world_end(kind: String, xf: Transform3D, index: int) -> Dictionary:
	var end: Dictionary = probe(kind).local_end(index)
	return {position = xf*(end.position as Vector3), out = (xf.basis*(end.out as Vector3)).normalized()}
## Adds a planned piece at the cursor, snapped like a laid one. Returns "" or why it was refused.
func plan_piece(kind: String, point: Vector3, heading: Vector3, join = 0) -> String:
	var spot := placement(kind,point,heading,join)
	if spot.is_empty(): return "Off the map."
	var xf: Transform3D = spot.transform
	var refused := plan_refusal(kind,xf)
	if not refused.is_empty(): return refused
	pending.append({kind = kind, transform = xf, cells = cells_for(kind,xf), ghost = _plan_ghost(kind,xf)})
	_tint_plan()
	return ""
## Why a piece of `kind` at `xf` cannot be planned, or "": it needs open land with no laid or planned track,
## and after the first piece it must join the plan at a free end.
func plan_refusal(kind: String, xf: Transform3D) -> String:
	var cells := cells_for(kind,xf)
	if not ground_clear(cells): return "Track needs open land with no other track."
	for entry in pending:
		for cell in cells:
			if entry.cells.has(cell): return "Track would cross the planned track."
	if not pending.is_empty():
		var joins := false
		for index in range(probe(kind).end_count()):
			if _meets_anything(_world_end(kind,xf,index)).has("pending"): joins = true
		if not joins: return "Plan the next piece from a free end of the planned track."
	return ""
## A copy of the preview's model for a planned piece, kept until the plan is laid or dropped.
func _plan_ghost(kind: String, xf: Transform3D) -> Node3D:
	var preview = game.get_node_or_null("RailPreview")
	if preview == null: return null
	var model: Node3D = preview.get_node_or_null(kind.to_pascal_case())
	if model == null: return null
	var ghost: Node3D = model.duplicate()
	ghost.name = "PlannedTrack"
	var parent: Node = game.get_node("Entities/Rails") if game.has_node("Entities/Rails") else game
	parent.add_child(ghost,true)
	ghost.visible = true
	ghost.global_transform = xf.scaled_local(model_scale(model))
	# The copy gets its own materials, so tinting it leaves the cursor preview alone.
	for item in ghost.find_children("*","MeshInstance3D",true,false): item.material_override = null
	return ghost
## Removes the last planned piece.
func unplan_last() -> void:
	if pending.is_empty(): return
	var entry: Dictionary = pending.pop_back()
	if is_instance_valid(entry.ghost): entry.ghost.queue_free()
	_tint_plan()
## Drops the whole plan.
func clear_plan() -> void:
	for entry in pending:
		if is_instance_valid(entry.ghost): entry.ghost.queue_free()
	pending.clear()
## Drops the plan and both picked buildings.
func drop_route() -> void:
	clear_plan()
	route_from = null
	route_to = null
	route_via = null
	route_blocked = false
	_drag_tried = null
	cursor = null
## Whether `point` is on or beside the suggested track, within `within` metres of its centre line.
func near_plan(point: Vector3, within := 4.0) -> bool:
	for entry in pending:
		var p: Node3D = probe(entry.kind)
		var total: float = p.length()
		for i in range(17):
			var at: Vector3 = (entry.transform as Transform3D)*p.local_point(total*i/16.0)
			if Vector2(at.x-point.x,at.z-point.z).length() <= within: return true
	return false
## Pulls the suggested track through `point` (docs/RAIL_PLANNING.md): the path is found again from the first
## building, through the point, to the second, adding pieces as needed. When no open path passes there, the
## track keeps its last shape. Returns whether the track now passes through the point.
func drag_route(point: Vector3) -> bool:
	if not is_instance_valid(route_from) or not is_instance_valid(route_to): return false
	var flat := Vector3(point.x,0,point.z)
	if _drag_tried != null and flat.distance_to(_drag_tried) < 1.2: return not route_blocked
	_drag_tried = flat
	if suggest_route(route_from,route_to,flat) == 0:
		route_blocked = true
		return false
	route_via = flat
	route_blocked = false
	return true
## Seconds until the cursor may move the suggested track again; longer after a slow search.
var _follow_left := 0.0
## The ground under the mouse while laying track, set by mouse motion (skirmish.gd), or null.
var cursor = null
## Once both buildings are picked, the suggested track follows the cursor (docs/RAIL_PLANNING.md): it is found
## again through the point under it, adding pieces as needed. Over either picked building's ring it is the
## shortest track; over the track itself it keeps its shape. A search that takes long waits longer before the
## next, so a long route does not hold the frame up.
func follow_cursor(point: Vector3, delta: float) -> void:
	_follow_left -= delta
	if _follow_left > 0.0: return
	var flat := Vector3(point.x,0,point.z)
	for end in [route_from,route_to]:
		if Vector2(flat.x-end.global_position.x,flat.z-end.global_position.z).length() <= target_reach(end):
			if route_via != null or route_blocked:
				route_via = null
				route_blocked = false
				_drag_tried = null
				_timed_search(func(): suggest_route(route_from,route_to))
			return
	if near_plan(flat,1.5): return
	if _drag_tried != null and flat.distance_to(_drag_tried) < 1.2: return
	_timed_search(func(): drag_route(flat))
func _timed_search(search: Callable) -> void:
	var started := Time.get_ticks_usec()
	search.call()
	_follow_left = maxf(0.05,(Time.get_ticks_usec()-started)/1000000.0*3.0)
## The rail target whose ring holds `point`, the nearest centre first, or null.
func target_at(point: Vector3, team := "player") -> Node3D:
	var best: Node3D = null
	var best_gap := INF
	for target in plan_target_candidates(team):
		var gap := Vector2(point.x-target.global_position.x,point.z-target.global_position.z).length()
		if gap <= target_reach(target) and gap < best_gap: best = target; best_gap = gap
	return best
## Picks a building to connect. The first pick starts a route; the second suggests the path between them and
## plans it. A pick after that starts again. Returns what to tell the player.
func pick_target(target: Node3D) -> String:
	if target == null: return "Click a Depot, mine or build site to connect."
	if not is_instance_valid(route_from) or is_instance_valid(route_to):
		drop_route()
		route_from = target
		return "Connecting from %s: click the building to connect it to." % target_name(target)
	if target == route_from: return "Click a different building to connect %s to." % target_name(target)
	route_to = target
	route_via = null
	if suggest_route(route_from,route_to) == 0:
		return "No open path from %s to %s. Click another building, or Backspace to choose again." % [target_name(route_from),target_name(target)]
	var hud = game.get_node_or_null("Interface")
	var blocker := plan_blocker(hud.global_payer if hud != null and hud.global_pinned else null)
	return "Suggested track: %d piece%s, %d iron. It follows the cursor; %s" % [pending.size(),"" if pending.size() == 1 else "s",plan_cost(),"click to lay it." if blocker.is_empty() else blocker]
## Replaces the plan with the shortest open path of straights and curves from `from` to `to`, touching both
## rings, and through `via` when one is given. Returns the number of pieces, 0 when there is no open path. With
## no path through `via`, the plan is left as it was.
func suggest_route(from: Node3D, to: Node3D, via = null) -> int:
	if _router == null: _router = preload("res://scripts/rails/rail_router.gd").new(self)
	var width: float = probe("straight").half_width()
	var path: Array[Dictionary] = _router.find(from,to,target_reach(from)+width,target_reach(to)+width,via)
	if path.is_empty() and via != null: return 0
	clear_plan()
	for piece in path:
		pending.append({kind = piece.kind, transform = piece.transform, cells = cells_for(piece.kind,piece.transform), ghost = _plan_ghost(piece.kind,piece.transform)})
	_tint_plan()
	return path.size()
func plan_cost() -> int:
	var total := 0
	for entry in pending: total += cost(entry.kind)
	return total
## Laid pieces whose line the plan joins.
func joined_pieces() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for i in range(pending.size()):
		for index in range(probe(pending[i].kind).end_count()):
			var meets := _meets_anything(_pending_end(pending[i],index),i)
			if not meets.has("piece"): continue
			for piece in lines()[meets.piece.get_instance_id()].pieces:
				if is_instance_valid(piece) and not result.has(piece): result.append(piece)
	return result
## The radius of a target's ring. Track connects once its edge touches the ring: its centre line within the
## radius plus half the track's width. A Depot's ring is where trains are built, load and unload, so a train can
## be built on any track that connects to it; other targets take half their footprint plus the connect reach.
func target_reach(node: Node3D) -> float:
	if node.is_in_group("depots") and node.get("rules") != null: return depot_reach(node)
	var size := Vector2i(2,2)
	var depots = game.get_node_or_null("DepotNetwork")
	if node.is_in_group("construction_plans"): size = node.spec.size
	elif node.is_in_group("depots") and depots != null: size = depots.depot_size()
	elif node.is_in_group("mines") and depots != null: size = depots.engineering_rules.mine_footprint
	return maxf(size.x,size.y)*0.5*ground.tile_size+rules.connect_reach
## Everything planned track can connect to for `team`.
func plan_target_candidates(team := "player") -> Array[Node3D]:
	var result: Array[Node3D] = []
	for depot in _depots():
		if depot.team == team and depot.health > 0: result.append(depot)
	for mine in get_tree().get_nodes_in_group("mines"):
		if mine.get("health") == null or mine.health > 0: result.append(mine)
	for plan in get_tree().get_nodes_in_group("construction_plans"):
		if not plan.finished and plan.kind != &"rail": result.append(plan)
	return result
func _plan_passes(target: Node3D, reach: float) -> bool:
	var centre := Vector2(target.global_position.x,target.global_position.z)
	for entry in pending:
		var p: Node3D = probe(entry.kind)
		for lane in range(p.lane_count()):
			var total: float = p.length(lane)
			var steps := maxi(4,int(total/0.5))
			for i in range(steps+1):
				var at: Vector3 = (entry.transform as Transform3D)*p.local_point(total*i/steps,lane)
				if Vector2(at.x,at.z).distance_to(centre) <= reach+p.half_width(): return true
	return false
## The targets the plan, with the laid track it joins, connects.
func plan_targets(team := "player") -> Array[Node3D]:
	var result: Array[Node3D] = []
	if pending.is_empty(): return result
	var laid := joined_pieces()
	for target in plan_target_candidates(team):
		var reach := target_reach(target)
		var hit := _plan_passes(target,reach)
		for piece in laid:
			if hit: break
			if piece.nearest(target.global_position).gap <= reach+piece.half_width(): hit = true
		if hit: result.append(target)
	return result
## While track is planned, rings every target at its reach: amber, green once the plan connects it. Rings go
## when track laying ends.
func show_target_rings(active: bool) -> void:
	var seen := {}
	if active:
		var connected := plan_targets()
		for target in plan_target_candidates():
			var key := target.get_instance_id()
			seen[key] = true
			var ring = _target_rings.get(key)
			if not is_instance_valid(ring):
				ring = target_ring_scene.instantiate()
				add_child(ring)
				_target_rings[key] = ring
			var reach := target_reach(target)
			ring.global_position = target.global_position+Vector3.UP*0.2
			ring.scale = Vector3(reach,1,reach)
			var lit: bool = connected.has(target) or target == route_from or target == route_to
			ring.get_node("Open").visible = not lit
			ring.get_node("Connected").visible = lit
	for key in _target_rings.keys():
		if seen.has(key): continue
		if is_instance_valid(_target_rings[key]): _target_rings[key].queue_free()
		_target_rings.erase(key)
## The Depot that pays for the plan: the pin when it can, else the connected Depot with all the iron nearest
## the plan's first piece, else the nearest friendly Depot with it.
func plan_payer(pinned = null) -> Node3D:
	var need := plan_cost()
	var energy := rules.rail_energy_cost*pending.size()
	var affords := func(depot) -> bool: return is_instance_valid(depot) and depot.is_in_group("depots") and depot.team == "player" and depot.health > 0 and depot.iron >= need and depot.energy >= energy
	if pinned != null: return pinned if affords.call(pinned) else null
	var start: Vector3 = (pending[0].transform as Transform3D).origin if not pending.is_empty() else Vector3.ZERO
	var best: Node3D = null
	for target in plan_targets():
		if target.is_in_group("depots") and affords.call(target) and (best == null or target.global_position.distance_squared_to(start) < best.global_position.distance_squared_to(start)): best = target
	if best != null: return best
	for depot in _depots():
		if affords.call(depot) and (best == null or depot.global_position.distance_squared_to(start) < best.global_position.distance_squared_to(start)): best = depot
	return best
## "" when the plan can be laid, else why not.
func plan_blocker(pinned = null) -> String:
	if pending.is_empty(): return "Plan some track first."
	var targets := plan_targets()
	if targets.size() < 2: return "Planned track must connect two targets (Depots, mines or build sites); it connects %d." % targets.size()
	if plan_payer(pinned) == null: return "No Depot has the %d iron for this track." % plan_cost()
	return ""
## Lays every planned piece at once, charging one Depot. Returns the pieces laid.
func commit_plan(pinned = null) -> Array[Node3D]:
	var laid: Array[Node3D] = []
	var blocker := plan_blocker(pinned)
	if not blocker.is_empty(): game.notify(blocker); return laid
	var payer := plan_payer(pinned)
	var need := plan_cost()
	if not payer.spend_local(rules.rail_energy_cost*pending.size(),need): game.notify("Paying Depot lacks local rail resources."); return laid
	var parent: Node = game.get_node("Entities/Rails") if game.has_node("Entities/Rails") else game
	var refund := 0
	var plan := pending.duplicate()
	clear_plan()
	for entry in plan:
		var piece = scene_for(entry.kind).instantiate()
		piece.assigned_depot = payer
		piece.transform = entry.transform
		parent.add_child(piece,true)
		if is_instance_valid(piece) and not piece.is_queued_for_deletion(): laid.append(piece)
		else: refund += cost(entry.kind)
	if refund > 0: payer.stockpile.deposit(&"iron",refund)
	var note := " %d could not be laid; their iron went back." % (plan.size()-laid.size()) if refund > 0 else ""
	game.notify("%d track pieces laid from %s for %d iron.%s" % [laid.size(),payer.name,need-refund,note])
	return laid
## Green when the plan can be laid, red when no Depot can pay for it.
func _tint_plan() -> void:
	var hud = game.get_node_or_null("Interface")
	var ready := plan_blocker(hud.global_payer if hud != null and hud.global_pinned else null).is_empty()
	for entry in pending:
		if is_instance_valid(entry.ghost): _tint_ghost(entry.ghost,ready)
# ---- upkeep (docs/RAIL_PLANNING.md)
## The energy a second this piece's line costs now: upkeep_per_100m for its length, and that again times
## upkeep_per_running_train for every train running on it. Lines with no Depot cost nothing; they have no
## power either.
func upkeep_rate(piece) -> float:
	if not is_instance_valid(piece): return 0.0
	var entry = lines().get(piece.get_instance_id())
	if entry == null or entry.depots.is_empty(): return 0.0
	var metres := 0.0
	for other in entry.pieces:
		if is_instance_valid(other): metres += other.total_length()
	var running := 0
	for train in get_tree().get_nodes_in_group("rail_trains"):
		if is_instance_valid(train.piece) and entry.pieces.has(train.piece) and not train._route.is_empty(): running += 1
	return rules.upkeep_per_100m*metres/100.0*(1.0+rules.upkeep_per_running_train*running)
## Charges every line's upkeep for `seconds` from its Depots, the fullest first.
func charge_upkeep(seconds: float) -> void:
	var done := []
	for piece in pieces:
		if not is_instance_valid(piece): continue
		var entry = lines().get(piece.get_instance_id())
		if entry == null or done.has(entry) or entry.depots.is_empty(): continue
		done.append(entry)
		var key := piece.get_instance_id()
		for other in entry.pieces:
			if is_instance_valid(other): key = mini(key,other.get_instance_id())
		var owed: float = _upkeep_owed.get(key,0.0)+upkeep_rate(piece)*seconds
		var whole := floori(owed)
		if whole > 0:
			var sources: Array = entry.depots.filter(func(depot): return is_instance_valid(depot) and depot.energy > 0)
			sources.sort_custom(func(a,b): return a.energy > b.energy)
			for depot in sources:
				var take: int = mini(whole,depot.energy)
				depot.energy -= take
				whole -= take
				owed -= take
				if whole <= 0: break
			# What no Depot could pay is dropped, not carried: a line with no energy simply has no power.
			owed = minf(owed,0.999)
		_upkeep_owed[key] = owed
