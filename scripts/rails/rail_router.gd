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
## The bound for a search through a cursor point, which runs again as the cursor moves: on Two Lakes no open path
## through a point needed more than about 10500, and one that runs out keeps the track's last shape.
var via_expansions := 15000
## States the last search expanded (tests and timing).
var last_expanded := 0
## Before searching, the open ground round each end and the cursor point is flooded, up to this many cells. A flood
## that runs out first is a closed pocket (walled in by trees, water or buildings): when it does not hold the other
## end, no track can join them and the search is not run. Track needs a chain of open cells, so this never turns
## down a path that exists.
var pocket_cap := 4000
## The same for the cursor point, which is flooded afresh at each search.
var via_pocket_cap := 1200
## Pockets found for the current picks, keyed by end; dropped by forget() and when laid track changes.
var _pockets := {}
var _pockets_revision := -1
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
	_ground_xf = ground.global_transform
	_ground_inverse = _ground_xf.affine_inverse()
	_size = ground.grid_size
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
			for i in range(17): samples.append(xf*piece.local_point(length*i/16.0))
			_moves[heading*3+m] = {delta = Vector2i(roundi(out.position.x/step),roundi(out.position.z/step)), heading = _heading_of(out.out), length = length, samples = samples, transform = xf, extent = _extent(samples)}
## How far a move's centre line reaches from its start, across the ground.
static func _extent(samples: Array[Vector3]) -> float:
	var far := 0.0
	for sample in samples: far = maxf(far,Vector2(sample.x,sample.z).length())
	return far
static func _heading_of(direction: Vector3) -> int:
	var best := 0
	for i in range(4):
		if (DIRECTIONS[i] as Vector3).dot(direction) > (DIRECTIONS[best] as Vector3).dot(direction): best = i
	return best
## World position of a lattice point.
func world(point: Vector2i) -> Vector3:
	return _ground_xf*Vector3(point.x*step,0,point.y*step)
func _cell(position: Vector3) -> Vector2i:
	var local: Vector3 = _ground_inverse*position
	return Vector2i(floori(local.x/ground.tile_size+_size.x*0.5),floori(local.z/ground.tile_size+_size.y*0.5))
## The cells a move from `point` covers, as offsets from the start cell, worked out once per lattice phase.
func _move_cells(point: Vector2i, key: int) -> Array:
	var phase := Vector2i(posmod(point.x,period),posmod(point.y,period))
	var id := (phase.x*period+phase.y)*12+key
	if not _cells.has(id):
		_move_offsets(phase,key,id)
	return _cells[id]
## Works out the cells a move from lattice phase `phase` covers, as offsets from its start cell (`_cells`), and,
## for the search, as offsets into the cell grid with the box they span (`_indices`).
func _move_offsets(phase: Vector2i, key: int, id: int) -> void:
	var origin := world(phase)
	var move: Dictionary = _moves[key]
	var kind: String = MOVES[key%3].kind
	var xf: Transform3D = move.transform
	xf.origin += origin
	var base := _cell(origin)
	var offsets: Array[Vector2i] = []
	for cell in network.cells_for(kind,xf): offsets.append(cell-base)
	_cells[id] = offsets
	var low := Vector2i(1000000,1000000)
	var high := -low
	var indices := PackedInt32Array()
	for offset in offsets:
		low = low.min(offset)
		high = high.max(offset)
		indices.append(offset.y*_size.x+offset.x)
	_indices[id] = [indices,offsets,low,high]
## Per move from each lattice phase: [grid index offsets, cell offsets, lowest offset, highest offset].
var _indices := {}
## Moves the search may not make, {Vector3i(point.x, point.y, move key): true}. A tile centre exactly on a piece's
## edge can round either way, so a move's cells worked out once per lattice phase can differ by a tile from the
## laid piece's own: a path can then hold a piece that can't be laid. The enemy player checks each found piece
## against the laid piece's cells and forbids the ones that fail before searching again (docs/ENEMY_AI.md).
var forbidden := {}
## Cells the search treats as blocked though the ground is clear, {Vector2i: true}: the enemy player keeps its track
## off unfinished build sites, which a piece over them would never let finish (docs/ENEMY_AI.md).
var blocked := {}
func _move_clear(point: Vector2i, key: int) -> bool:
	if not forbidden.is_empty() and forbidden.has(Vector3i(point.x,point.y,key)): return false
	var phase := Vector2i(posmod(point.x,period),posmod(point.y,period))
	var id := (phase.x*period+phase.y)*12+key
	if not _indices.has(id): _move_offsets(phase,key,id)
	var entry: Array = _indices[id]
	var base := _cell(world(point))
	var low: Vector2i = base+entry[2]
	var high: Vector2i = base+entry[3]
	if low.x < 0 or low.y < 0 or high.x >= _size.x or high.y >= _size.y: return false
	var start := base.y*_size.x+base.x
	var offsets: Array = entry[1]
	var indices: PackedInt32Array = entry[0]
	for i in range(indices.size()):
		var index := start+indices[i]
		var known := _clear[index]
		if known == 2:
			_one[0] = base+offsets[i]
			known = 1 if network.ground_clear(_one) else 0
			_clear[index] = known
		if known == 0: return false
	return true
func _cell_clear(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= _size.x or cell.y >= _size.y: return false
	var index := cell.y*_size.x+cell.x
	if _clear[index] == 2:
		_one[0] = cell
		_clear[index] = 1 if network.ground_clear(_one) else 0
	return _clear[index] == 1
## Forgets the pockets found so far: the picks changed.
func forget() -> void: _pockets.clear()
## The closed pocket of open cells round `seeds` as {cell: true} (empty when none of them is open), or null when
## the flood reaches `pocket_cap` cells: open ground. Cached under `key` unless it is null.
func _pocket(seeds: Array, key, cap := pocket_cap):
	if network.revision != _pockets_revision:
		_pockets.clear()
		_pockets_revision = network.revision
	if key != null and _pockets.has(key): return _pockets[key]
	var seen := {}
	var queue: Array[Vector2i] = []
	for cell in seeds:
		if not seen.has(cell) and _cell_clear(cell):
			seen[cell] = true
			queue.append(cell)
	var result = seen
	var i := 0
	while i < queue.size():
		if seen.size() >= cap: result = null; break
		var cell: Vector2i = queue[i]
		i += 1
		for next in [cell+Vector2i(1,0),cell+Vector2i(-1,0),cell+Vector2i(0,1),cell+Vector2i(0,-1)]:
			if not seen.has(next) and _cell_clear(next):
				seen[next] = true
				queue.append(next)
	if key != null: _pockets[key] = result
	return result
## Cells within `radius` of `centre`.
func _disc(centre: Vector3, radius: float) -> Array:
	var cells: Array = []
	var middle := _cell(centre)
	var span := int(ceil(radius/ground.tile_size))+1
	for dx in range(-span,span+1):
		for dz in range(-span,span+1):
			var cell := middle+Vector2i(dx,dz)
			var at: Vector3 = ground.to_global(Vector3((cell.x-_size.x*0.5+0.5)*ground.tile_size,0,(cell.y-_size.y*0.5+0.5)*ground.tile_size))
			if Vector2(at.x-centre.x,at.z-centre.z).length() <= radius: cells.append(cell)
	return cells
static func _holds(pocket: Dictionary, cells: Array) -> bool:
	for cell in cells:
		if pocket.has(cell): return true
	return false
## Whether no track can join `starts` to `goal` (by way of `via`): one of them is in a closed pocket of open ground
## that does not hold the other end, or has no open ground at all.
func _hopeless(starts: Array, goal: Dictionary, via) -> bool:
	var start_cells: Array = []
	for start in starts: start_cells.append(_cell(world(start[0])))
	var goal_cells: Array = []
	var states: Dictionary = goal.get("states",{})
	if states.is_empty(): goal_cells = _disc(goal.centre,goal.reach)
	for key in states:
		var packed: int = key/4
		goal_cells.append(_cell(world(Vector2i(packed/4000-1000,packed%4000-1000))))
	var start_key = "s%s:%d" % [starts[0][0],starts.size()] if not starts.is_empty() else null
	var goal_key := "g%s:%.2f:%d" % [goal.centre,goal.reach,states.size()]
	var ends := [[start_cells,start_key,goal_cells],[goal_cells,goal_key,start_cells]]
	if via != null: ends.append([_disc(via,step),null,start_cells])
	for end in ends:
		var pocket = _pocket(end[0],end[1],pocket_cap if end[1] != null else via_pocket_cap)
		if pocket != null and not _holds(pocket,end[2]): return true
	return false
## The ground's transform and its inverse, read at each search rather than asked for at every step.
var _ground_xf := Transform3D.IDENTITY
var _ground_inverse := Transform3D.IDENTITY
func _read_clear() -> void:
	_ground_xf = ground.global_transform
	_ground_inverse = _ground_xf.affine_inverse()
	if ground.grid_size != _size:
		_cells.clear()
		_indices.clear()
	_size = ground.grid_size
	_clear.resize(_size.x*_size.y)
	_clear.fill(2)
	for cell in blocked:
		if cell.x >= 0 and cell.y >= 0 and cell.x < _size.x and cell.y < _size.y: _clear[cell.y*_size.x+cell.x] = 0
## Whether a move from `point` comes within `reach` of `centre` along its centre line.
func _touches(point: Vector2i, key: int, centre: Vector3, reach: float) -> bool:
	var origin := world(point)
	var move: Dictionary = _moves[key]
	if Vector2(origin.x-centre.x,origin.z-centre.z).length() > reach+move.extent: return false
	for sample in move.samples:
		var at: Vector3 = origin+sample
		if Vector2(at.x-centre.x,at.z-centre.z).length() <= reach: return true
	return false
## Every lattice state inside a ring: [point, heading, null] for each heading.
func ring_starts(centre: Vector3, reach: float) -> Array:
	var starts: Array = []
	var local_start: Vector3 = ground.to_local(centre)
	var span := int(ceil(reach/step))
	var centre_point := Vector2i(roundi(local_start.x/step),roundi(local_start.z/step))
	for dx in range(-span,span+1):
		for dz in range(-span,span+1):
			var point := centre_point+Vector2i(dx,dz)
			var at := world(point)
			if Vector2(at.x-centre.x,at.z-centre.z).length() > reach: continue
			for heading in range(4): starts.append([point,heading,null])
	return starts
## The lattice point at `position`, or null when it is not on the lattice (track laid off it cannot be joined).
func lattice_point(position: Vector3):
	var local: Vector3 = ground.to_local(position)/step
	var point := Vector2i(roundi(local.x),roundi(local.z))
	if absf(local.x-point.x) > 0.02 or absf(local.z-point.y) > 0.02: return null
	return point
func heading_of(direction: Vector3) -> int: return _heading_of(direction)
func state_key(point: Vector2i, heading: int) -> int: return _state_key(point,heading)
## The shortest open path from any of `starts` ([point, heading, tag]: the first piece leaves `point` heading
## that way) to `goal`: {centre, reach}, a ring the last piece touches, or with `states` ({state key: tag}) one
## of those exact states, the last piece arriving at the point heading that way (docs/RAIL_PLANNING.md, joining
## track). Returns {path, start, goal}: the pieces and the tags of the start and goal states used, or {}.
func route(starts: Array, goal: Dictionary, via = null) -> Dictionary:
	var job := begin(starts,goal,via)
	advance(job,-1)
	return job.found
## The same search, run a little at a time so a long one does not hold the frame up (docs/RAIL_PLANNING.md, following
## the cursor): begin() sets it up, advance() works on it, and once `job.done` is true `job.found` is what route()
## would have returned. Only one search runs at once: beginning another drops the last.
func begin(starts: Array, goal: Dictionary, via = null) -> Dictionary:
	_read_clear()
	last_expanded = 0
	if _hopeless(starts,goal,via): return {done = true, found = {}}
	var job := {done = false, found = {}, goal = goal.centre, reach = goal.reach, states = goal.get("states",{}), via = via,
		tags = {}, heap = [], best_g = {}, came = {}, closed = {}, expanded = 0,
		budget = max_expansions if via == null else mini(max_expansions,via_expansions)}
	var start_passed: bool = via == null
	for start in starts:
		var key := _state_key(start[0],start[1])*2+int(start_passed)
		job.best_g[key] = 0.0
		job.tags[key] = start[2] if start.size() > 2 else null
		_push(job.heap,[_estimate_via(world(start[0]),job.goal,job.reach,via,start_passed),key,start[0],start[1],start_passed])
	return job
## Works on `job` for about `usec` microseconds (all of it when negative). Returns whether it is done.
func advance(job: Dictionary, usec: int) -> bool:
	if job.done: return true
	var found := _search(job,Time.get_ticks_usec()+usec if usec >= 0 else -1)
	if found.get("pending",false): return false
	job.done = true
	if found.is_empty(): return true
	var path: Array[Dictionary] = found.path
	# Shortest paths do not cross themselves; refuse the rare one that would rather than lay overlapping track.
	var used := {}
	for piece in path:
		for cell in piece.cells:
			if used.has(cell): return true
			used[cell] = true
	job.found = {path = path, start = found.start, goal = found.goal}
	return true
## A* by track length from any of the job's starts ([point, heading, tag]) until a piece comes within `goal.reach`
## of `goal.centre`, or arrives at one of `goal.states`, having first come within a lattice step of `via` when one
## is given: each state also records whether the track has passed `via` yet. Returns {path, point, heading, start,
## goal} for the state after the last piece and the tags of the start and goal, {} when none, or {pending = true}
## when `until` (a Time.get_ticks_usec() time; -1 for none) comes first.
func _search(job: Dictionary, until: int) -> Dictionary:
	var goal: Vector3 = job.goal
	var reach: float = job.reach
	var states: Dictionary = job.states
	var via = job.via
	var tags: Dictionary = job.tags
	# Open set as a binary heap of [f, key, point, heading, passed]; the key packs all three.
	var heap: Array = job.heap
	var best_g: Dictionary = job.best_g
	var came: Dictionary = job.came
	var closed: Dictionary = job.closed
	var budget: int = job.budget
	var expanded: int = job.expanded
	while not heap.is_empty() and expanded < budget:
		if until >= 0 and expanded%32 == 0 and Time.get_ticks_usec() >= until:
			job.expanded = expanded
			return {pending = true}
		var entry: Array = _pop(heap)
		var key: int = entry[1]
		if closed.has(key): continue
		closed[key] = true
		expanded += 1
		last_expanded = expanded
		var point: Vector2i = entry[2]
		var heading: int = entry[3]
		var passed: bool = entry[4]
		var g: float = best_g[key]
		for m in range(3):
			var move_key := heading*3+m
			if not _move_clear(point,move_key): continue
			var move: Dictionary = _moves[move_key]
			var next: Vector2i = point+move.delta
			var next_passed: bool = passed or (via != null and _touches(point,move_key,via,step))
			var next_key := _state_key(next,move.heading)*2+int(next_passed)
			var next_g: float = g+move.length
			var arrived: bool = states.has(_state_key(next,move.heading)) if not states.is_empty() else _touches(point,move_key,goal,reach)
			if next_passed and arrived:
				came[next_key] = [key,point,move_key]
				var first := next_key
				while came.has(first): first = came[first][0]
				return {path = _path(came,next_key), point = next, heading = move.heading, start = tags.get(first), goal = states.get(_state_key(next,move.heading))}
			if best_g.has(next_key) and best_g[next_key] <= next_g: continue
			best_g[next_key] = next_g
			came[next_key] = [key,point,move_key]
			_push(heap,[next_g+_estimate_via(world(next),goal,reach,via,next_passed),next_key,next,move.heading,next_passed])
	job.expanded = expanded
	return {}
## Admissible estimate: straight to the goal ring, or by way of the via point when it is still to come.
func _estimate_via(at: Vector3, goal: Vector3, reach: float, via, passed: bool) -> float:
	if passed: return _estimate(at,goal,reach)
	var to_via: float = maxf(0.0,Vector2(at.x-via.x,at.z-via.z).length()-step)
	return to_via+_estimate(via,goal,reach)
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
		# The cells it covers are known from its lattice phase, so laying it does not work them out again.
		var base := _cell(world(point))
		var cells: Array[Vector2i] = []
		for offset in _move_cells(point,move_key): cells.append(base+offset)
		reversed.append({kind = MOVES[move_key%3].kind, transform = xf, cells = cells, move = Vector3i(point.x,point.y,move_key)})
		key = link[0]
	reversed.reverse()
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
