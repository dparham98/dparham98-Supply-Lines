class_name ProductionExit
extends RefCounted
static func find_cell(ground: Node, point: Vector3, footprint: Vector2i, layer: int = 0) -> Vector2i:
	var center = ground.get_tile_at_position(point)
	if center == null: return Vector2i(-1,-1)
	for radius in range(maxi(footprint.x,footprint.y)/2+2,16):
		for offset in [Vector2i(0,radius),Vector2i(radius,0),Vector2i(-radius,0),Vector2i(0,-radius)]:
			if ground.can_traverse(center+offset,layer): return center+offset
	return Vector2i(-1,-1)
