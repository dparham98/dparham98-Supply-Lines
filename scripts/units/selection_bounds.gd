extends RefCounted
# Visual picking only; collision and navigation remain independent.
static func meshes(actor: Node3D) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	var visuals = actor.get_node_or_null("Visuals")
	if visuals != null:
		for node in visuals.find_children("*", "MeshInstance3D", true, false):
			if node.mesh != null and node.is_visible_in_tree(): result.append(node)
	return result
static func hit_distance(actor: Node3D, camera: Camera3D, screen: Vector2) -> float:
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	var distance := INF
	for mesh in meshes(actor):
		var inverse := mesh.global_transform.affine_inverse()
		var hit = mesh.get_aabb().intersects_ray(inverse * origin,inverse.basis * direction)
		if hit != null:
			var world: Vector3 = mesh.global_transform * hit
			if (world-origin).dot(direction) >= 0: distance = minf(distance,origin.distance_to(world))
	return distance
static func screen_rect(actor: Node3D, camera: Camera3D) -> Rect2:
	var rect := Rect2()
	var initialized := false
	for mesh in meshes(actor):
		for i in range(8):
			var world: Vector3 = mesh.global_transform * mesh.get_aabb().get_endpoint(i)
			if camera.is_position_behind(world): continue
			var point := camera.unproject_position(world)
			if not initialized: rect = Rect2(point,Vector2.ZERO); initialized = true
			else: rect = rect.expand(point)
	return rect
