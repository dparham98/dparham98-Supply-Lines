extends RefCounted
# Visual picking only; collision and navigation remain independent.
static func meshes(actor: Node3D) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	var visuals = actor.get_node_or_null("Visuals")
	if visuals != null:
		for node in _candidates(actor,visuals):
			if node.mesh != null and node.is_visible_in_tree() and absf(node.global_basis.determinant()) > 0.000001: result.append(node)
	return result
## How long an actor's list of pickable mesh nodes is kept, in milliseconds. Finding it searches the actor's whole
## model, and the map overlay asks for every actor on screen every frame; with a few hundred units that search
## alone took a large part of each frame. Which of them are shown, and where they are, is still checked each call.
const MESH_CACHE_MS := 1000
## The mesh nodes under `visuals` that may be picked, kept on the actor for a while. Looked for again sooner when
## Visuals gains or loses a child or one of the kept nodes has left the tree.
static func _candidates(actor: Node3D, visuals: Node) -> Array:
	var now := Time.get_ticks_msec()
	var kept = actor.get_meta(&"_pick_meshes") if actor.has_meta(&"_pick_meshes") else null
	if kept != null and now < kept[0] and kept[1] == visuals and kept[2] == visuals.get_child_count():
		var fresh := true
		for node in kept[3]:
			if not is_instance_valid(node) or not node.is_inside_tree(): fresh = false; break
		if fresh: return kept[3]
	var found := []
	for node in visuals.find_children("*", "MeshInstance3D", true, false):
		if selectable(node,visuals): found.append(node)
	# Spread the next searches over a quarter second, so units made together don't all search in one frame.
	actor.set_meta(&"_pick_meshes",[now+MESH_CACHE_MS+actor.get_instance_id()%250,visuals,visuals.get_child_count(),found])
	return found
## Parts tagged not_selectable, and everything under them, take no part in picking or outlines.
static func selectable(node: Node, visuals: Node) -> bool:
	while node != null and node != visuals:
		if node.has_meta(&"not_selectable"): return false
		node = node.get_parent()
	return true
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
