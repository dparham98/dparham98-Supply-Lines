extends SceneTree
# Headless, on Two Lakes: suggesting track stays cheap (docs/RAIL_PLANNING.md). A mine walled in by trees is turned
# down without a search, as is a cursor point with no open ground near it; while the track follows the cursor a
# long search runs a slice a frame, and ends with the same track as running it at once.
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func shape(rails) -> Array:
	return rails.pending.map(func(e): return [e.kind,(e.transform as Transform3D).origin.snapped(Vector3.ONE*0.01)])
func run() -> void:
	game = load("res://scenes/maps/lakes_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	game.set_process(false)
	var rails = game.get_node("RailNetwork")
	rails.set_process(false)
	var depot: Node3D = game.depot
	var mines := get_nodes_in_group("mines")
	mines.sort_custom(func(a,b): return a.global_position.distance_to(depot.global_position) < b.global_position.distance_to(depot.global_position))
	# A mine in a pocket of open ground walled in by trees: no track can reach it, and no search is run to find that.
	var walled: Node3D = null
	for mine in mines:
		if rails.suggest_route(depot,mine) == 0 and rails._router.last_expanded == 0: walled = mine; break
	if not check(walled != null,"A walled-in mine should be turned down without a search"): return
	var pocket = rails._router._pocket(rails._router._disc(walled.global_position,rails.target_reach(walled)),null)
	if not check(pocket != null and pocket.size() < rails._router.pocket_cap,"The walled-in mine should sit in a closed pocket"): return
	# A reachable mine some way off, through open ground.
	var far: Node3D = null
	for mine in mines:
		if mine.global_position.distance_to(depot.global_position) > 100.0 and rails.suggest_route(depot,mine) > 0: far = mine; break
	if not check(far != null,"No mine over 100 m away can be reached"): return
	rails.route_from = depot
	rails.route_to = far
	var shortest: int = rails.suggest_route(depot,far)
	# A cursor point in the lake, with no open ground within a lattice step: no search.
	var wet := Vector3.INF
	var ground = game.ground
	for x in range(0,500,4):
		for z in range(0,500,4):
			var at: Vector3 = ground.tile_to_world(Vector2i(x,z))
			if ground.get_terrain(Vector2i(x,z)) != 1: continue
			var dry := false
			for cell in rails._router._disc(at,rails._router.step+1.0):
				if rails.ground_clear([cell] as Array[Vector2i]): dry = true; break
			if not dry: wet = Vector3(at.x,0,at.z); break
		if wet != Vector3.INF: break
	if not check(wet != Vector3.INF,"No water cell found"): return
	if not check(not rails.drag_route(wet) and rails._router.last_expanded == 0 and rails.pending.size() == shortest,"A point in the lake should be turned down without a search, keeping the track"): return
	# A long drag, at once and then following the cursor.
	var a: Vector3 = depot.global_position
	var b: Vector3 = far.global_position
	var side := (b-a).cross(Vector3.UP).normalized()
	var pull := Vector3.INF
	var at_once := []
	for offset in [20.0,-20.0,14.0,-14.0,28.0,-28.0]:
		var point: Vector3 = a.lerp(b,0.6)+side*offset
		point.y = 0.0
		rails._drag_tried = null
		rails.suggest_route(depot,far)
		if rails.drag_route(point) and rails._router.last_expanded > 2000: pull = point; at_once = shape(rails); break
	if not check(pull != Vector3.INF,"No long drag found to follow"): return
	rails.route_via = null
	rails._drag_tried = null
	rails.suggest_route(depot,far)
	rails._follow_left = 0.0
	var calls := 0
	var longest := 0
	while calls < 2000:
		var started := Time.get_ticks_usec()
		rails.follow_cursor(pull,1.0/60)
		longest = maxi(longest,Time.get_ticks_usec()-started)
		calls += 1
		if rails._follow_search.is_empty(): break
	if not check(calls > 1,"A long search should run over several frames"): return
	if not check(rails._follow_search.is_empty() and rails.route_via != null and not rails.route_blocked,"Following the cursor should end with the track through it"): return
	if not check(shape(rails) == at_once,"Following the cursor should give the same track as searching at once"): return
	if not check(longest < 60000,"No frame should spend long on the search: %d us" % longest): return
	print("RAIL_PLAN_SPEED_TEST_PASSED (%d frames, longest %.1f ms)" % [calls,longest/1000.0])
	quit()
