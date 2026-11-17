extends RefCounted
## Suggests a track path between two rail targets (docs/RAIL_PLANNING.md). The search runs on a lattice of half
## a straight's length: a straight moves two steps ahead, and a 90-degree curve, whose radius is two and a half
## straights, moves five steps ahead and five aside. States are a lattice point and one of four headings. The
## path starts where its first piece touches the first target's ring and ends once a piece touches the second's,
## over open buildable land clear of other track. It is the shortest such path in track length.
const DIRECTIONS := [Vector3(1,0,0),Vector3(0,0,1),Vector3(-1,0,0),Vector3(0,0,-1)]
## The moves from a state: the piece, which of its ends joins, and the end it leaves by.
const MOVES := [{kind = "straight", join = 0, leave = 1},{kind = "curve", join = 0, leave = 1},{kind = "curve", join = 1, leave = 0}]
## Upper bound on states expanded before the search gives up.
var max_expansions := 60000
var network
var ground
var step := 2.4
## The lattice repeats against the 1 m cell grid every `period` steps, so a move's cells relative to its start
## cell depend only on the start's lattice position modulo the period.
var period := 5
## Per heading and move: {delta: Vector2i lattice offset, heading: int, length, samples: centre-line points
## relative to the start}.
var _moves := {}
## Cells a move covers, relative to its start cell, keyed by lattice phase, heading and move.
var _cells := {}
## Per cell for one search: 2 not read yet, 1 where track may be laid (the network's own rule), 0 not.
var _clear := PackedByteArray()
var _one: Array[Vector2i] = [Vector2i.ZERO]
var _size := Vector2i.ZERO
func _init(rail_network) -> void:
	network = rail_network
	ground = rail_network.ground
	step = network.probe("straight").length()*0.5
	period = 1
	for p in range(1,51):
		var span: float = p*step/ground.tile_size
		if absf(span-roundf(span)) < 0.001: period = p; break
	for heading in range(4):
		for m in range(MOVES.size()):
			var move: Dictionary = MOVES[m]
			var xf: Transform3D = network.transform_for(move.kind,Vector3.ZERO,DIRECTIONS[heading],move.join)
			var out: Dictionary = network._world_end(move.kind,xf,move.leave)
			var piece: Node3D = network.probe(move.kind)
			var samples: Array[Vector3] = []
			var length: float = piece.length()
			for i in range(9): samples.append(xf*piece.local_point(length*i/8.0))
			_moves[heading*3+m] = {delta = Vector2i(roundi(out.position.x/step),roundi(out.position.z/step)), heading = _heading_of(out.out), length = length, samples = samples, transform = xf}
static func _heading_of(direction: Vector3) -> int:
	var best := 0
	for i in range(4):
		if (DIRECTIONS[i] as Vector3).dot(direction) > (DIRECTIONS[best] as Vector3).dot(direction): best = i
	return best
## World position of a lattice point.
func world(point: Vector2i) -> Vector3:
	return ground.to_global(Vector3(point.x*step,0,point.y*step))
func _cell(position: Vector3) -> Vector2i:
	var local: Vector3 = ground.to_local(position)
	return Vector2i(floori(local.x/ground.tile_size+_size.x*0.5),floori(local.z/ground.tile_size+_size.y*0.5))
## The cells a move from `point` covers, as offsets from the start cell, worked out once per lattice phase.
func _move_cells(point: Vector2i, key: int) -> Array:
	var phase := Vector2i(posmod(point.x,period),posmod(point.y,period))
	var id := (phase.x*period+phase.y)*12+key
	if not _cells.has(id):
		var origin := world(phase)
		var move: Dictionary = _moves[key]
		var kind: String = MOVES[key%3].kind
		var xf: Transform3D = move.transform
		xf.origin += origin
		var base := _cell(origin)
		var offsets: Array[Vector2i] = []
		for cell in network.cells_for(kind,xf): offsets.append(cell-base)
		_cells[id] = offsets
	return _cells[id]
func _move_clear(point: Vector2i, key: int) -> bool:
	var base := _cell(world(point))
	for offset in _move_cells(point,key):
		var cell: Vector2i = base+offset
		if cell.x < 0 or cell.y < 0 or cell.x >= _size.x or cell.y >= _size.y: return false
		var index := cell.y*_size.x+cell.x
		if _clear[index] == 2:
			_one[0] = cell
			_clear[index] = 1 if network.ground_clear(_one) else 0
		if _clear[index] == 0: return false
	return true
func _read_clear() -> void:
	_size = ground.grid_size
	_clear.resize(_size.x*_size.y)
	_clear.fill(2)
## Whether a move from `point` comes within `reach` of `centre` along its centre line.
func _touches(point: Vector2i, key: int, centre: Vector3, reach: float) -> bool:
	var origin := world(point)
	for sample in _moves[key].samples:
		var at: Vector3 = origin+sample
		if Vector2(at.x-centre.x,at.z-centre.z).length() <= reach: return true
	return false
## The suggested path from `from` to `to` as planned pieces [{kind, transform}], or [] when there is none.
## `from_reach` and `to_reach` are the rings' radii plus half the track's width.
func find(from: Node3D, to: Node3D, from_reach: float, to_reach: float) -> Array[Dictionary]:
	_read_clear()
	var goal: Vector3 = to.global_position
	var start_centre: Vector3 = from.global_position
	var local_start: Vector3 = ground.to_local(start_centre)
	var span := int(ceil(from_reach/step))
	var centre_point := Vector2i(roundi(local_start.x/step),roundi(local_start.z/step))
	# Open set as a binary heap of [f, state]; state = (x, z, heading) packed into a key.
	var heap: Array = []
	var best_g := {}
	var came := {}
	for dx in range(-span,span+1):
		for dz in range(-span,span+1):
			var point := centre_point+Vector2i(dx,dz)
			var at := world(point)
			if Vector2(at.x-start_centre.x,at.z-start_centre.z).length() > from_reach: continue
			for heading in range(4):
				var key := _state_key(point,heading)
				best_g[key] = 0.0
				_push(heap,[_estimate(at,goal,to_reach),key,point,heading])
	var expanded := 0
	var closed := {}
	while not heap.is_empty() and expanded < max_expansions:
		var entry: Array = _pop(heap)
		var key: int = entry[1]
		if closed.has(key): continue
		closed[key] = true
		expanded += 1
		var point: Vector2i = entry[2]
		var heading: int = entry[3]
		var g: float = best_g[key]
		for m in range(3):
			var move_key := heading*3+m
			if not _move_clear(point,move_key): continue
			var move: Dictionary = _moves[move_key]
			var next: Vector2i = point+move.delta
			var next_key := _state_key(next,move.heading)
			var next_g: float = g+move.length
			if _touches(point,move_key,goal,to_reach):
				came[next_key] = [key,point,move_key]
				return _path(came,next_key)
			if best_g.has(next_key) and best_g[next_key] <= next_g: continue
			best_g[next_key] = next_g
			came[next_key] = [key,point,move_key]
			_push(heap,[next_g+_estimate(world(next),goal,to_reach),next_key,next,move.heading])
	return []
func _state_key(point: Vector2i, heading: int) -> int:
	return ((point.x+1000)*4000+(point.y+1000))*4+heading
func _estimate(at: Vector3, goal: Vector3, reach: float) -> float:
	return maxf(0.0,Vector2(at.x-goal.x,at.z-goal.z).length()-reach)
func _path(came: Dictionary, last: int) -> Array[Dictionary]:
	var reversed: Array[Dictionary] = []
	var key := last
	while came.has(key):
		var link: Array = came[key]
		var point: Vector2i = link[1]
		var move_key: int = link[2]
		var xf: Transform3D = _moves[move_key].transform
		xf.origin += world(point)
		reversed.append({kind = MOVES[move_key%3].kind, transform = xf})
		key = link[0]
	reversed.reverse()
	# Shortest paths do not cross themselves; refuse the rare one that would rather than lay overlapping track.
	var used := {}
	for piece in reversed:
		for cell in network.cells_for(piece.kind,piece.transform):
			if used.has(cell): return []
			used[cell] = true
	return reversed
static func _push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i := heap.size()-1
	while i > 0:
		var parent := (i-1)/2
		if heap[parent][0] <= item[0]: break
		heap[i] = heap[parent]
		i = parent
	heap[i] = item
static func _pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.is_empty(): return top
	var i := 0
	var n := heap.size()
	while true:
		var child := i*2+1
		if child >= n: break
		if child+1 < n and heap[child+1][0] < heap[child][0]: child += 1
		if heap[child][0] >= last[0]: break
		heap[i] = heap[child]
		i = child
	heap[i] = last
	return top
