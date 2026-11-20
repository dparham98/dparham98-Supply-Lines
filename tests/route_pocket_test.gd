extends SceneTree
# Headless, on Two Lakes: route searches that cannot succeed are turned down cheaply (docs/PATHING.md). A free cell
# walled in by units, as round a crowded rally point or target, and a unit walled in itself get no route without
# the search flooding the map; open routes are found as before.
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func wall(ground: Node3D, centre: Vector2i) -> Array:
	var units := []
	for dz in range(-1,2):
		for dx in range(-1,2):
			if dx == 0 and dz == 0: continue
			var unit = load("res://scenes/gameplay/infantry.tscn").instantiate()
			game.get_node("Entities/Units").add_child(unit)
			unit.set_process(false)
			unit.global_position = ground.tile_to_world(centre+Vector2i(dx,dz))
			unit._claim(centre+Vector2i(dx,dz))
			units.append(unit)
	return units
func run() -> void:
	game = load("res://scenes/maps/lakes_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	game.set_process(false)
	var ground: Node3D = game.ground
	var start: Vector2i = ground.get_tile_at_position(Vector3(-170,0,10))
	var far: Vector2i = ground.get_tile_at_position(Vector3(150,0,10))
	if not check(ground.actor_path(start,far,0,"").size() > 100,"A route across the map should be found"): return
	# A free cell walled in by a ring of units: no route, and no flood of the map.
	var goal: Vector2i = ground.get_tile_at_position(Vector3(-120,0,10))
	var ring := wall(ground,goal)
	if not check(ground.can_traverse(goal,0,"") and ground.sealed(ground.navigation_grid,goal,start),"The ring should seal the free cell"): return
	var t := Time.get_ticks_usec()
	var path: Array[Vector2i] = ground.actor_path(start,goal,0,"")
	var ms := (Time.get_ticks_usec()-t)/1000.0
	if not check(path.is_empty() and ms < 4.0,"A walled-in goal should be turned down at once: %d cells, %.1f ms" % [path.size(),ms]): return
	# The start walled in: the same.
	t = Time.get_ticks_usec()
	path = ground.actor_path(goal,far,0,"")
	ms = (Time.get_ticks_usec()-t)/1000.0
	if not check(path.is_empty() and ms < 4.0,"A walled-in start should be turned down at once: %d cells, %.1f ms" % [path.size(),ms]): return
	# A corner gap is no way in (diagonals only pass open corners); a side gap is.
	ring[0]._release(goal+Vector2i(-1,-1)); ring[0].free()
	if not check(ground.actor_path(start,goal,0,"").is_empty(),"A gap at a corner should not let a route in"): return
	ring[1]._release(goal+Vector2i(0,-1)); ring[1].free()
	if not check(not ground.actor_path(start,goal,0,"").is_empty(),"With a gap in the side of the ring the route should be found"): return
	for unit in ring:
		if is_instance_valid(unit): unit.free()
	print("ROUTE_POCKET_TEST_PASSED")
	quit()
