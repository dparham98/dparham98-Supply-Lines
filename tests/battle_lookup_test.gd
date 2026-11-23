extends SceneTree
# Headless, on Two Lakes: the shortcuts that keep big battles quick (docs/COMBAT_BATCH.md, Targeting in big battles;
# docs/PATHING.md, Lane checks) give the answers the slow ways gave. The unit grid finds every unit the whole
# "units" group would, units pick the same nearest opponent, and the lane walk sees every cell a fine sampling does.
# Units look round for targets on a timer, and actors keep their picking meshes.
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func spawn(id: String, team: String, point: Vector3) -> Node3D:
	var unit = load("res://scenes/gameplay/"+id+".tscn").instantiate()
	unit.team = team
	game.get_node("Entities/Units").add_child(unit)
	unit.set_process(false)
	unit.global_position = point
	return unit
## The nearest opponent the slow way: every unit on the map.
func slow_nearest(unit: Node3D) -> Node3D:
	var closest: Node3D
	var distance: float = unit.attack_range
	for other in get_nodes_in_group("units"):
		if not CombatResolver.can_hit(unit,other): continue
		var d: float = unit.global_position.distance_to(other.global_position)
		if d < distance and d >= unit.min_attack_range: closest = other; distance = d
	return closest
## Whether every cell under a finely sampled segment is open: the lane check as it was.
func sampled_open(ground: Node3D, from: Vector3, to: Vector3, layer: int, owner: String) -> bool:
	var steps := ceili(from.distance_to(to)/0.02)+1
	for i in range(steps+1):
		var cell = ground.get_tile_at_position(from.lerp(to,float(i)/steps))
		if cell == null or not ground.can_traverse(cell,layer,owner): return false
	return true
func run() -> void:
	game = load("res://scenes/maps/lakes_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	var ai = game.get_node_or_null("EnemyPlayer")
	if ai != null: ai.set_process(false)
	var ground: Node3D = game.ground
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# Two armies mixed over open ground.
	var centre := Vector3(-90,0,-110)
	var ids := ["infantry","grenadier","tank","motorcycle","drone","scout"]
	var units := []
	for i in range(60):
		var cell: Vector2i = ground.find_nearest_open_tile(ground.get_tile_at_position(centre+Vector3(rng.randf_range(-30,30),0,rng.randf_range(-30,30))))
		var unit := spawn(ids[i%ids.size()],"player" if i%2 == 0 else "enemy",ground.tile_to_world(cell))
		unit._claim(cell)
		units.append(unit)
	await process_frame
	# The grid misses nobody the group would find.
	for trial in range(200):
		var point := centre+Vector3(rng.randf_range(-40,40),0,rng.randf_range(-40,40))
		var radius := rng.randf_range(1,30)
		var near: Array = game.units_near(point,radius)
		for unit in get_nodes_in_group("units"):
			if unit.global_position.distance_to(point) <= radius and not near.has(unit):
				check(false,"units_near(%s, %.1f) missed %s" % [point,radius,unit.name]); return
	# Moved units are found where they are, a frame later.
	var mover: Node3D = units[0]
	mover.global_position = centre+Vector3(70,0,0)
	await process_frame
	if not check(game.units_near(centre+Vector3(70,0,0),1.0).has(mover),"A moved unit should be found where it now stands"): return
	if not check(not game.units_near(centre,40.0).has(mover),"A moved unit should no longer be found where it was"): return
	mover.global_position = centre
	await process_frame
	# Every unit picks the opponent the slow way picks.
	var compared := 0
	for unit in units:
		if not unit.has_method("_nearest_opponent") or unit.attack_range <= 0.0: continue
		var fast = unit._nearest_opponent()
		var slow := slow_nearest(unit)
		if not check(fast == slow,"%s should pick %s, picked %s" % [unit.name,slow,fast]): return
		if slow != null: compared += 1
	if not check(compared >= 20,"Most units should have an opponent in range to compare (%d)" % compared): return
	# Lanes: a blocker on the line closes it, one beside it doesn't, off the map is closed.
	var open_cell: Vector2i = ground.find_nearest_open_tile(ground.get_tile_at_position(Vector3(-150,0,40)))
	var a: Vector3 = ground.tile_to_world(open_cell)
	var b := a+Vector3(6,0,0)
	if sampled_open(ground,a,b,0,"") and sampled_open(ground,a+Vector3(0,0,3),b+Vector3(0,0,3),0,""):
		var blocker := spawn("infantry","player",a+Vector3(3,0,0))
		var blocked: Vector2i = ground.get_tile_at_position(a+Vector3(3,0,0))
		blocker._claim(blocked)
		if not check(not ground.segment_open(a,b,0,""),"A unit on the lane should close it"): return
		if not check(ground.segment_open(a,b,0,blocker._owner_key()),"Its own cell should not close the lane for the blocker"): return
		if not check(ground.segment_open(a+Vector3(0,0,3),b+Vector3(0,0,3),0,""),"A unit beside the lane should not close it"): return
		blocker._release(blocked); blocker.free()
	if not check(not ground.segment_open(Vector3(-249.5,0,0),Vector3(-260,0,0),0,""),"A lane off the map should be closed"): return
	# Over many short segments round the armies, the walk sees every cell the fine sampling sees.
	var mismatches := 0
	for trial in range(600):
		var from := centre+Vector3(rng.randf_range(-35,35),0,rng.randf_range(-35,35))
		var angle := rng.randf_range(0,TAU)
		var to := from+Vector3(cos(angle),0,sin(angle))*rng.randf_range(0.2,8.0)
		var walked: bool = ground.segment_open(from,to,0,"")
		var sampled := sampled_open(ground,from,to,0,"")
		if walked and not sampled:
			check(false,"The lane walk passed a cell the sampling found closed: %s to %s" % [from,to]); return
		if walked != sampled: mismatches += 1
	# The walk may also catch a corner the sampling steps over; that should be rare.
	if not check(mismatches <= 6,"The lane walk and the sampling disagreed on %d of 600 segments" % mismatches): return
	for unit in units:
		if is_instance_valid(unit): unit.free()
	# Target scans (unit_agent _acquire): a unit with nothing in range looks again only every TARGET_SCAN_SECONDS,
	# keeps what it found while that stays in range, and looks again at once when that target dies.
	var spot: Vector3 = ground.tile_to_world(ground.find_nearest_open_tile(ground.get_tile_at_position(Vector3(-150,0,60))))
	var shooter := spawn("infantry","player",spot)
	await process_frame
	if not check(shooter._acquire() == null,"Nothing in range: nothing found"): return
	var near := spawn("hostile","enemy",spot+Vector3(4,0,0))
	await process_frame
	if not check(shooter._acquire() == null,"A new enemy should wait for the next scan"): return
	shooter._scan_wait -= shooter.TARGET_SCAN_SECONDS
	if not check(shooter._acquire() == near,"The next scan should find the enemy in range"): return
	var nearer := spawn("hostile","enemy",spot+Vector3(2,0,0))
	await process_frame
	if not check(shooter._acquire() == near,"It keeps its target while that stays in range"): return
	near.free()
	if not check(shooter._acquire() == nearer,"With its target gone it looks again at once"): return
	nearer.free()
	# Picking meshes (selection_bounds.gd) are kept on the actor, and looked for again when Visuals changes.
	var bounds = preload("res://scripts/units/selection_bounds.gd")
	var before: int = bounds.meshes(shooter).size()
	if not check(before > 0 and shooter.has_meta(&"_pick_meshes"),"The unit's meshes should be found and kept"): return
	var extra := MeshInstance3D.new()
	extra.mesh = BoxMesh.new()
	shooter.get_node("Visuals").add_child(extra)
	if not check(bounds.meshes(shooter).size() == before+1,"A mesh added under Visuals should be picked up at once"): return
	extra.visible = false
	if not check(bounds.meshes(shooter).size() == before,"A hidden mesh should not count"): return
	extra.free()
	if not check(bounds.meshes(shooter).size() == before,"A freed mesh should be dropped at once"): return
	shooter.free()
	# Death clips: at most DEATH_CLIPS_MAX play at once; the rest go at once (headless counts every point as in view).
	var Agent = preload("res://scripts/gameplay/unit_agent.gd")
	var doomed := []
	for i in range(Agent.DEATH_CLIPS_MAX+8): doomed.append(spawn("infantry","enemy",spot+Vector3(-10+(i%6)*2,0,8+(i/6)*2)))
	await process_frame
	for unit in doomed: unit.take_damage(100000)
	await process_frame
	var playing := get_nodes_in_group(Agent.DYING).size()
	if not check(playing == Agent.DEATH_CLIPS_MAX,"Exactly DEATH_CLIPS_MAX death clips should play, not %d" % playing): return
	print("BATTLE_LOOKUP_TEST_PASSED")
	quit()
