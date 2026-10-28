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
static func path(unit: Node3D, target: Node3D, radius: float) -> Array[Vector2i]:
	var current = unit.ground.get_tile_at_position(unit.global_position)
	if current == null: return []
	var goals := candidates(unit.ground,target,radius,unit.mobility_layer(),unit._owner_key())
	# Nearest admissible standing cell first, with a stable grid tie-break.
	goals.sort_custom(func(a,b):
		var da: int = current.distance_squared_to(a)
		var db: int = current.distance_squared_to(b)
		return (a.y < b.y if a.y != b.y else a.x < b.x) if da == db else da < db)
	for goal in goals:
		var route: Array[Vector2i] = unit.ground.actor_path(current,goal,unit.mobility_layer(),unit._owner_key())
		if not route.is_empty(): return route
	return []
