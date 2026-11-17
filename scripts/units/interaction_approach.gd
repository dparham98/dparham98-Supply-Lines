extends RefCounted
# Resource/delivery approach goals only. All paths and claims remain owned by the terrain grid/unit.
static func candidates(ground: Node3D, target: Node3D, radius: float, layer: int, owner: String) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not is_instance_valid(target) or radius < 0: return result
	var center = ground.get_tile_at_position(target.global_position)
	if center == null: return result
	var reach := ceili(radius/ground.tile_size)+1
	for z in range(maxi(0,center.y-reach),mini(ground.grid_size.y,center.y+reach+1)):
		for x in range(maxi(0,center.x-reach),mini(ground.grid_size.x,center.x+reach+1)):
			var cell := Vector2i(x,z)
			if ground.can_traverse(cell,layer,owner) and ground.tile_to_world(cell).distance_squared_to(target.global_position) <= radius*radius+0.00001:
				result.append(cell)
	return result
## How far from a footprint's edge a unit counts as touching it (docs/BUILDER_TOUCH.md): enough for a cell beside
## it, straight or diagonal.
const TOUCH := 1.0
## The distance, on the ground, from `point` to the edge of a footprint of cells; 0 inside it.
static func distance_to_rect(ground: Node3D, point: Vector3, rect: Rect2i) -> float:
	var low: Vector3 = ground.tile_to_world(rect.position)-Vector3(0.5,0,0.5)*ground.tile_size
	var high: Vector3 = ground.tile_to_world(rect.end-Vector2i.ONE)+Vector3(0.5,0,0.5)*ground.tile_size
	return Vector2(maxf(maxf(low.x-point.x,point.x-high.x),0.0),maxf(maxf(low.z-point.z,point.z-high.z),0.0)).length()
## A path to the nearest cell touching the footprint `rect` from outside it, from whichever side the unit is on.
static func touch_path(unit: Node3D, rect: Rect2i) -> Array[Vector2i]:
	var ground: Node3D = unit.ground
	var current = ground.get_tile_at_position(unit.global_position)
	if current == null: return []
	var goals: Array[Vector2i] = []
	for z in range(rect.position.y-1,rect.end.y+1):
		for x in range(rect.position.x-1,rect.end.x+1):
			var cell := Vector2i(x,z)
			if rect.has_point(cell) or not ground.is_tile_in_bounds(cell) or not ground.can_traverse(cell,unit.mobility_layer(),unit._owner_key()): continue
			goals.append(cell)
	goals.sort_custom(func(a,b):
		var da: int = current.distance_squared_to(a)
		var db: int = current.distance_squared_to(b)
		return (a.y < b.y if a.y != b.y else a.x < b.x) if da == db else da < db)
	for goal in goals:
		var route: Array[Vector2i] = ground.actor_path(current,goal,unit.mobility_layer(),unit._owner_key())
		if not route.is_empty(): return route
	return []
## `keep_off`: cells not to stand on, such as the footprint of the building being built.
static func path(unit: Node3D, target: Node3D, radius: float, keep_off := Rect2i()) -> Array[Vector2i]:
	var current = unit.ground.get_tile_at_position(unit.global_position)
	if current == null: return []
	var goals := candidates(unit.ground,target,radius,unit.mobility_layer(),unit._owner_key())
	if keep_off.has_area(): goals = goals.filter(func(cell): return not keep_off.has_point(cell))
	# Nearest admissible standing cell first, with a stable grid tie-break.
	goals.sort_custom(func(a,b):
		var da: int = current.distance_squared_to(a)
		var db: int = current.distance_squared_to(b)
		return (a.y < b.y if a.y != b.y else a.x < b.x) if da == db else da < db)
	for goal in goals:
		var route: Array[Vector2i] = unit.ground.actor_path(current,goal,unit.mobility_layer(),unit._owner_key())
		if not route.is_empty(): return route
	return []
