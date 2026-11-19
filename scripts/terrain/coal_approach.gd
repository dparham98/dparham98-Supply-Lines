extends RefCounted
## How a worker gets to coal that no open path leads to (docs/BALANCED_MAP.md): the fewest Forest cells to fell,
## and among those the shortest walk. The search runs from the coal outward and only over the ground round the
## field, so it stays small however large the map is. Nothing here changes the terrain.

## Cells searched beyond the field and the worker's reach. The forest belts round coal are 9 to 12 cells deep.
const MARGIN := 32
## Cost of felling one Forest cell: more than any walk inside the searched ground.
const FELL := 100000
const UNSEEN := 2147483647
## Border cells tried, nearest first, for a worker that starts outside the searched ground. Each is a
## whole-map path search, so only a few: a worker that finds none looks again later (_cut_way_in).
const ENTRY_TRIES := 8
const OPEN := 1
const FOREST := 2
const CLOSED := 3
const Grid := preload("res://scripts/terrain/terrain_grid.gd")

## The way for a unit standing on `from` to the field `cell` belongs to: {coal: the Coal cell to dig, fell: the
## Forest cells to cut, in walking order}. `fell` is empty when some coal of the field can be reached as the
## ground stands. Returns {} when the field holds no coal or nothing leads to it.
static func way(ground: Node3D, from: Vector2i, cell: Vector2i, reach: float, layer: int, owner: String) -> Dictionary:
	var live: Array[Vector2i] = []
	for other in ground.coal_field_at(cell).get("cells",[]):
		if ground.coal_amount(other) > 0: live.append(other)
	if live.is_empty(): return {}
	var span := ceili(reach)
	var low: Vector2i = live[0]
	var high: Vector2i = live[0]
	for other in live:
		low = Vector2i(mini(low.x,other.x),mini(low.y,other.y))
		high = Vector2i(maxi(high.x,other.x),maxi(high.y,other.y))
	var grow := Vector2i.ONE*(span+MARGIN)
	var box := Rect2i(low-grow,high-low+Vector2i.ONE+grow*2).intersection(Rect2i(Vector2i.ZERO,ground.grid_size))
	var goals: Array[Vector2i] = []
	for coal in live:
		for z in range(coal.y-span,coal.y+span+1):
			for x in range(coal.x-span,coal.x+span+1):
				var at := Vector2i(x,z)
				if box.has_point(at) and Vector2(at-coal).length() <= reach+0.0001: goals.append(at)
	var result := _search(ground,from,box,goals,layer,owner)
	if result.is_empty(): return {}
	var stand: Vector2i = result.stand
	var dig := Vector2i(-1,-1)
	for other in live:
		var d := Vector2(stand-other).length()
		if d > reach+0.0001: continue
		if other == cell:
			dig = other
			break
		if dig.x < 0 or d < Vector2(stand-dig).length(): dig = other
	return {} if dig.x < 0 else {"coal": dig, "fell": result.fell}

## The minimum-tree lane from `from` to touch `rect` (or step onto `rect` when `touch` is false).
static func way_to_rect(ground: Node3D, from: Vector2i, rect: Rect2i, layer: int, owner: String, touch := true) -> Dictionary:
	var goals: Array[Vector2i] = []
	if touch:
		for z in range(rect.position.y-1,rect.end.y+1):
			for x in range(rect.position.x-1,rect.end.x+1):
				var at := Vector2i(x,z)
				if not rect.has_point(at) and ground.is_tile_in_bounds(at): goals.append(at)
	else:
		for z in range(rect.position.y,rect.end.y):
			for x in range(rect.position.x,rect.end.x):
				var at := Vector2i(x,z)
				if ground.is_tile_in_bounds(at): goals.append(at)
	var box := _box_around(ground,from,rect.position,rect.size,MARGIN+2)
	return _search(ground,from,box,goals,layer,owner)

## Fallback minimum-tree lane to any cell within `reach` of `rect`'s centre, used when no touching cell is usable.
static func way_to_reach(ground: Node3D, from: Vector2i, rect: Rect2i, reach: float, layer: int, owner: String) -> Dictionary:
	var centre: Vector3 = ground.tile_to_world(rect.position)+Vector3(rect.size.x*0.5-0.5,0,rect.size.y*0.5-0.5)
	var mid: Vector2i = rect.position+rect.size/2
	var span := ceili(reach)+maxi(rect.size.x,rect.size.y)
	var goals: Array[Vector2i] = []
	for z in range(mid.y-span,mid.y+span+1):
		for x in range(mid.x-span,mid.x+span+1):
			var at := Vector2i(x,z)
			if ground.is_tile_in_bounds(at) and not rect.has_point(at) and ground.tile_to_world(at).distance_to(centre) <= reach+0.0001:
				goals.append(at)
	var box := _box_around(ground,from,rect.position,rect.size,span+MARGIN)
	return _search(ground,from,box,goals,layer,owner)

## The minimum-tree lane from `from` to touch any valid 2 x 2 mine spot on the coal field `cell` belongs to.
static func way_to_seam(ground: Node3D, from: Vector2i, cell: Vector2i, layer: int, owner: String) -> Dictionary:
	var cells: Array = ground.coal_field_at(cell).get("cells",[])
	if cells.is_empty(): return {}
	var live := {}
	for other in cells:
		if ground.coal_amount(other) > 0: live[other] = true
	if live.is_empty(): return {}
	var goals: Array[Vector2i] = []
	var seen := {}
	var low := Vector2i(ground.grid_size)
	var high := Vector2i.ZERO
	for spot in cells:
		if not (live.has(spot) and live.has(spot+Vector2i(1,0)) and live.has(spot+Vector2i(0,1)) and live.has(spot+Vector2i(1,1))): continue
		for dz in range(-1,3):
			for dx in range(-1,3):
				var at: Vector2i = spot+Vector2i(dx,dz)
				if live.has(at) or seen.has(at) or not ground.is_tile_in_bounds(at): continue
				seen[at] = true
				goals.append(at)
				low = Vector2i(mini(low.x,at.x),mini(low.y,at.y))
				high = Vector2i(maxi(high.x,at.x),maxi(high.y,at.y))
	if goals.is_empty(): return {}
	var box := _box_around(ground,from,low,high-low+Vector2i.ONE,MARGIN+2)
	return _search(ground,from,box,goals,layer,owner)

static func _box_around(ground: Node3D, from: Vector2i, pos: Vector2i, size: Vector2i, pad: int) -> Rect2i:
	var grow := Vector2i.ONE*pad
	var box := Rect2i(pos-grow,size+grow*2)
	if Vector2(from-pos).length() <= 64.0:
		box = box.merge(Rect2i(from-Vector2i(2,2),Vector2i(5,5)))
	return box.intersection(Rect2i(Vector2i.ZERO,ground.grid_size))

static func _search(ground: Node3D, from: Vector2i, box: Rect2i, goals: Array[Vector2i], layer: int, owner: String) -> Dictionary:
	if goals.is_empty() or not box.has_area(): return {}
	var width := box.size.x
	var count := box.size.x*box.size.y
	var kind := PackedByteArray()
	kind.resize(count)
	# dist: what it costs to get from a cell to a goal cell. toward: the next cell on that way.
	var dist := PackedInt32Array()
	dist.resize(count)
	dist.fill(UNSEEN)
	var toward := PackedInt32Array()
	toward.resize(count)
	toward.fill(-1)
	# A binary heap of cost*count+index, smallest first.
	var heap := PackedInt64Array()
	for at in goals:
		if not box.has_point(at): continue
		var i := (at.y-box.position.y)*width+(at.x-box.position.x)
		if dist[i] == 0 or _kind(ground,kind,i,at,layer,owner) == CLOSED: continue
		dist[i] = 0
		heap.append(i)
	if heap.is_empty(): return {}
	# A sorted array is already a heap.
	heap.sort()
	while not heap.is_empty():
		var top: int = heap[0]
		var last: int = heap[heap.size()-1]
		heap.resize(heap.size()-1)
		if not heap.is_empty():
			var hole := 0
			while true:
				var child := hole*2+1
				if child >= heap.size(): break
				if child+1 < heap.size() and heap[child+1] < heap[child]: child += 1
				if heap[child] >= last: break
				heap[hole] = heap[child]
				hole = child
			heap[hole] = last
		var cost := top/count
		var i := top%count
		if cost > dist[i]: continue
		# Stepping onto this cell from a neighbour: a walk, or a tree to fell first.
		var onward := cost+(FELL+1 if kind[i] == FOREST else 1)
		for step in [1,-1,width,-width]:
			var j: int = i+step
			if j < 0 or j >= count or (absi(step) == 1 and j/width != i/width): continue
			if onward >= dist[j] or _kind(ground,kind,j,box.position+Vector2i(j%width,j/width),layer,owner) == CLOSED: continue
			dist[j] = onward
			toward[j] = i
			var key := onward*count+j
			heap.append(key)
			var slot := heap.size()-1
			while slot > 0:
				var parent := (slot-1)/2
				if heap[parent] <= key: break
				heap[slot] = heap[parent]
				slot = parent
			heap[slot] = key
	var start := -1
	if box.has_point(from):
		# Inside the searched ground: of all the cells the unit can walk to as things stand, the one with the
		# least felling beyond it, then the least walking in all.
		var origin := (from.y-box.position.y)*width+(from.x-box.position.x)
		var walked := {origin: 0}
		var queue := PackedInt32Array([origin])
		var head := 0
		var best := -1
		while head < queue.size():
			var i := queue[head]
			head += 1
			var steps: int = walked[i]
			if dist[i] != UNSEEN and (best < 0 or dist[i]+steps < best):
				best = dist[i]+steps
				start = i
			for step in [1,-1,width,-width]:
				var j: int = i+step
				if j < 0 or j >= count or (absi(step) == 1 and j/width != i/width) or walked.has(j): continue
				if _kind(ground,kind,j,box.position+Vector2i(j%width,j/width),layer,owner) != OPEN: continue
				walked[j] = steps+1
				queue.append(j)
	else:
		# Coming from outside: enter by a border cell, least felling first and then the nearest.
		var border: Array[int] = []
		for x in range(box.size.x):
			border.append(x)
			border.append((box.size.y-1)*width+x)
		for z in range(1,box.size.y-1):
			border.append(z*width)
			border.append(z*width+width-1)
		var entries: Array = []
		for i in border:
			if dist[i] == UNSEEN or kind[i] != OPEN: continue
			var at := box.position+Vector2i(i%width,i/width)
			entries.append([dist[i]+int(Vector2(at-from).length()),i,at])
		entries.sort_custom(func(a,b): return a[0] < b[0] if a[0] != b[0] else a[1] < b[1])
		for entry in entries.slice(0,ENTRY_TRIES):
			if not ground.actor_path(from,entry[2],layer,owner).is_empty():
				start = entry[1]
				break
	if start < 0: return {}
	var fell: Array[Vector2i] = []
	var node := start
	if kind[node] == FOREST: fell.append(box.position+Vector2i(node%width,node/width))
	while toward[node] >= 0:
		node = toward[node]
		if kind[node] == FOREST: fell.append(box.position+Vector2i(node%width,node/width))
	var stand := box.position+Vector2i(node%width,node/width)
	return {"stand": stand, "fell": fell}

## Whether a cell is open to this unit, Forest it would have to fell, or closed. Worked out once a cell.
static func _kind(ground: Node3D, kind: PackedByteArray, i: int, at: Vector2i, layer: int, owner: String) -> int:
	if kind[i] == 0:
		kind[i] = OPEN if ground.can_traverse(at,layer,owner) else (FOREST if ground.get_terrain(at) == Grid.Terrain.FOREST else CLOSED)
	return kind[i]
