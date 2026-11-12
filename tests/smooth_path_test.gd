extends SceneTree
# Headless: units cross open ground in straight runs rather than cell to cell, turn at their turn rate
# instead of snapping, hold exactly the cell they stand in, finish on the goal cell's centre, and
# steer around a unit standing in the way (docs/PATHING.md).
const DT := 1.0/60
var game: Node3D
var ground: Node
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func spawn(id: String, cell: Vector2i) -> Node3D:
	var unit: Node3D = load("res://scenes/gameplay/"+id+".tscn").instantiate()
	unit.team = "player"
	unit.position = ground.tile_to_world(cell)
	game.get_node("Entities/Units").add_child(unit)
	unit.set_process(false)
	return unit
func flat(v: Vector3) -> Vector2: return Vector2(v.x,v.z)
## Walk the unit to the goal cell, checking every frame that it holds only the cell it stands in.
## Returns the positions it passed through, or an empty array when a check failed.
func walk(unit: Node3D, goal: Vector2i, seconds: float) -> Array[Vector3]:
	var trail: Array[Vector3] = []
	unit.command_move(ground.tile_to_world(goal))
	for frame in range(int(seconds/DT)):
		unit._process(DT)
		trail.append(unit.global_position)
		var cell = ground.get_tile_at_position(unit.global_position)
		if not check(unit._claimed.size() == 1 and unit._claimed[0] == cell and ground.tiles[cell.y*500+cell.x].occupied_by == unit._owner_key(),"%s should hold just its own cell %s, holds %s" % [unit.name,cell,unit._claimed]): return []
		if unit.order == "idle": return trail
	check(false,"%s did not arrive in %.0f s (%s)" % [unit.name,seconds,unit.state])
	return []
func run() -> void:
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	for node in get_nodes_in_group("units"): node.set_process(false)
	ground = game.ground
	var corner: Vector2i = ground.find_buildable_footprint(Vector2i(200,200),Vector2i(30,30))
	if not check(corner.x >= 0,"No open ground for the test"): return
	# A straight run: 20 cells east and 7 south is a line, not a staircase of cell steps.
	var start := corner+Vector2i(3,3)
	var goal := start+Vector2i(20,7)
	var soldier := spawn("infantry",start)
	var trail := walk(soldier,goal,40.0)
	if trail.is_empty(): return
	var a := flat(ground.tile_to_world(start))
	var b := flat(ground.tile_to_world(goal))
	var line := (b-a).normalized()
	var worst := 0.0
	for p in trail: worst = maxf(worst,absf(line.cross(flat(p)-a)))
	if not check(worst < 0.05,"An open run should be straight; strayed %.2f m off the line" % worst): return
	if not check(soldier.global_position == ground.tile_to_world(goal) and soldier.grid_position == goal,"It should stop on the goal cell's centre"): return
	var heading: float = soldier.get_node("Visuals").rotation.y
	if not check(absf(angle_difference(heading,atan2(-(b-a).x,-(b-a).y))) < 0.01,"It should face along the run"): return
	# Turning: a Tank facing away pivots at its turn rate before it drives off.
	var tank := spawn("tank",corner+Vector2i(5,20))
	var hull: Node3D = tank.get_node("Visuals")
	hull.rotation.y = 0.0  # facing north (-z)
	tank.command_move(ground.tile_to_world(corner+Vector2i(5,28)))  # due south
	var from: Vector3 = tank.global_position
	var yaw := hull.rotation.y
	var limit := deg_to_rad(tank.turn_rate)*DT+0.0001
	var pivoting := 0
	for frame in range(60):
		tank._process(DT)
		if not check(absf(angle_difference(yaw,hull.rotation.y)) <= limit,"The Tank turned faster than its turn rate"): return
		yaw = hull.rotation.y
		if absf(angle_difference(yaw,PI)) > PI*0.5:
			pivoting += 1
			if not check(tank.global_position == from,"The Tank should not drive off while facing more than 90 degrees away"): return
	if not check(tank.turn_rate == 90.0 and pivoting >= 55,"A Tank turns 90 degrees a second, so it pivots for about a second: %d frames" % pivoting): return
	if not check(walk(tank,corner+Vector2i(5,28),20.0).size() > 0,"The Tank should then drive on"): return
	# A unit standing on the line is gone around, never through.
	var runner := spawn("infantry",corner+Vector2i(3,12))
	var blocker := spawn("infantry",corner+Vector2i(10,12))
	var blocked: Vector2i = blocker.grid_position
	trail = walk(runner,corner+Vector2i(17,12),30.0)
	if trail.is_empty(): return
	if not check(trail.all(func(p): return ground.get_tile_at_position(p) != blocked),"The runner walked through the unit in its way"): return
	if not check(runner.grid_position == corner+Vector2i(17,12),"The runner should still arrive"): return
	print("SMOOTH_PATH_CHECKS_PASSED")
	quit()
