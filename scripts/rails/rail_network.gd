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
func friendly_piece(piece, team: String) -> bool:
	return not connected_depots(piece,team).is_empty()
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
	return hit if hit.gap <= depot.dropoff_range else {}
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
func spawn_stop(depot: Node3D) -> Dictionary:
	for stop in loading_stops(depot,depot.team):
		return {piece = stop.piece, lane = stop.lane, distance = stop.distance, position = stop.piece.point_at(stop.distance,stop.lane)}
	return {}
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
	for end in free_ends("player"):
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
				if Vector2(at.x,at.z).distance_to(centre) <= depot.dropoff_range: return true
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
	game.notify("%s laid from %s for %d iron. R switches piece; Esc finishes." % [kind.capitalize(),payer.name,cost(kind)])
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
	var preview = game.get_node_or_null("RailPreview")
	if preview == null: return
	var active: bool = game.placing_rail
	preview.visible = active
	if not active: return
	var camera := game.get_viewport().get_camera_3d()
	var mouse := game.get_viewport().get_mouse_position()
	var point = Plane(Vector3.UP,0).intersects_ray(camera.project_ray_origin(mouse),camera.project_ray_normal(mouse))
	if point == null: preview.visible = false; return
	var kind: String = game.rail_kind()
	var spot := placement(kind,point,game.rail_heading,game.rail_join())
	if spot.is_empty(): preview.visible = false; return
	var payer := payer_for(kind,spot.transform,game.get_node("Interface").global_payer if game.get_node("Interface").global_pinned else null)
	for child in preview.get_children():
		var show: bool = child.name.to_snake_case() == kind
		child.visible = show
		if not show: continue
		child.global_transform = spot.transform
		_tint_ghost(child,payer != null)
	preview.get_node("Status").global_position = spot.transform*probe(kind).local_point(probe(kind).length()*0.5)+Vector3.UP*2.0
	preview.get_node("Status").text = "%s · %d iron · %s%s" % [game.rail_piece.to_upper(),cost(kind),"payer "+payer.name if payer != null else "BLOCKED / NO DEPOT"," · snapped" if spot.snapped else ""]
## Depots can appear, fall or run out of energy without the track changing.
func _poll_power() -> void:
	var depots := _depot_key()
	if depots != _announced_depots:
		_announced_depots = depots
		_announce()
	for piece in pieces:
		if is_instance_valid(piece): piece.update_color()
func _tint_ghost(ghost: Node3D, valid: bool) -> void:
	var colour := Color(0.3,1.0,0.5,0.45) if valid else Color(1.0,0.2,0.15,0.45)
	for item in ghost.find_children("*","MeshInstance3D",true,false):
		var key := item.get_instance_id()
		if not _ghost_materials.has(key):
			var material := StandardMaterial3D.new()
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			item.material_override = material
			_ghost_materials[key] = material
		_ghost_materials[key].albedo_color = colour
