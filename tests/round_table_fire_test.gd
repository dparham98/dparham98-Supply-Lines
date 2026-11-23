extends SceneTree
## Exercise a simultaneous group attack through the playable scene and its real bullets.

const MARKERS := [6, 10, 14, 30, 34, 38, 54, 58, 62]
const STEP := 1.0 / 120.0

var game: Node3D
var last_bullet: Node3D
var bullet_count := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition


func spawn(scene: PackedScene, point: Vector3) -> Node3D:
	var unit := scene.instantiate() as Node3D
	unit.position = point
	game.add_child(unit)
	unit.set_process(false)
	return unit


func bullet_added(node: Node) -> void:
	if node.scene_file_path == "res://scenes/gameplay/infantry_bullet.tscn":
		last_bullet = node as Node3D
		bullet_count += 1


func run() -> void:
	game = preload("res://scripts/gameplay/skirmish.gd").new()
	game.add_to_group("skirmish")
	var terrain: Node3D = load("res://scenes/maps/terrain.tscn").instantiate()
	terrain.name = "Terrain"
	game.add_child(terrain)
	var interface := CanvasLayer.new()
	interface.name = "Interface"
	game.add_child(interface)
	root.add_child(game)
	game.set_process(false)

	var center := Vector3(180,0,180)
	var target := spawn(load("res://scenes/gameplay/hostile.tscn"),center + Vector3(0,0,-8))
	target.health = 1000
	var squad: Array[Node3D] = []
	var positions: Array[Vector3] = []
	var times := [[],[],[]]
	var planted_feet := [{},{},{}]
	for i in times.size():
		var unit := spawn(load("res://scenes/gameplay/round_table_marine.tscn"),center + Vector3((i-1)*2.0,0,0))
		squad.append(unit)
		unit.command_attack(target)
		positions.append(unit.global_position)
		if not check(unit.order == "attack" and unit.in_attack_range(target),"Fixture could not order a shot from this cell"): return
	game.child_entered_tree.connect(bullet_added)

	for tick in range(540):
		for i in squad.size():
			var unit := squad[i]
			var before: int = target.health
			var count_before := bullet_count
			unit._process(STEP)
			if not check(positions[i].distance_to(unit.global_position) < .001,"Knight moved while shooting at an in-range target"): return
			var model := unit.get_node("Visuals/Model")
			if model.player.assigned_animation == &"Shoot" and (bullet_count > count_before or not times[i].is_empty()):
				var skeleton: Skeleton3D = model.skeleton
				for name in [&"foot.L", &"foot.R"]:
					var foot := skeleton.find_bone(name)
					if not check(foot >= 0,"Missing boot joint"): return
					var at := skeleton.to_global(skeleton.get_bone_global_pose(foot).origin)
					if not planted_feet[i].has(name): planted_feet[i][name] = at
					if not check(at.distance_to(planted_feet[i][name]) < .002,"The firing rig moved a planted boot"): return
			if bullet_count == count_before:
				if not check(target.health == before,"Damage occurred without a bullet"): return
				continue
			var expected_damage: int = unit.attack_damage if times[i].size()%3 == 0 else 0
			if not check(bullet_count == count_before + 1 and before-target.health == expected_damage,"Each three-round burst should apply one rifle hit"): return
			var marker: float = (MARKERS[times[i].size() % MARKERS.size()]-1) / 24.0
			var clip_position: float = model.player.current_animation_position
			if not check(model.player.assigned_animation == &"Shoot" and absf(clip_position-marker) <= 2*STEP+.001,
					"Bullet released at %.3fs in its own animation, expected %.3fs" % [clip_position,marker]): return
			var muzzle: Vector3 = last_bullet.global_position + last_bullet.global_basis.z * last_bullet.half_length
			if not check(muzzle.distance_to(model.muzzle_position()) < .03,"Bullet and animated muzzle disagree at release"): return
			var rig: Skeleton3D = model.skeleton
			var bore := (rig.global_transform * rig.get_bone_global_pose(rig.find_bone("muzzle"))).basis.y
			var travel := -last_bullet.global_basis.z
			var yaw_error := absf(Vector2(bore.x,bore.z).angle_to(Vector2(travel.x,travel.z)))
			if not check(rad_to_deg(yaw_error) < 3.0,"Rifle points %.1f degrees away from its bullet" % rad_to_deg(yaw_error)): return
			times[i].append(tick*STEP)

	var first_shots := []
	for actor_times: Array in times:
		if not check(actor_times.size() == 27,"Expected nine complete three-round bursts in 4.5 seconds, got %s" % [actor_times]): return
		first_shots.append(actor_times[0])
		for j in range(1,actor_times.size()):
			var interval := 1./3. if j%3 == 0 else 1./12.
			if not check(absf(actor_times[j]-actor_times[j-1]-interval) < STEP+.001,"Automatic rifle cadence changed"): return
	first_shots.sort()
	for i in range(1,first_shots.size()):
		if not check(first_shots[i]-first_shots[i-1] >= STEP-.00001,"Knights given the same order fired on the same tick"): return
	if not await check_order_changes(squad[0],target): return
	print("ROUND_TABLE_FIRE_TEST_PASSED first_shots_s=",first_shots)
	game.free()
	await process_frame
	quit(0)


func check_order_changes(knight: Node3D, old_target: Node3D) -> bool:
	# Let the unit, child animator, and projectiles use their regular frame callbacks.
	Engine.max_fps = 60
	var model := knight.get_node("Visuals/Model")
	var new_target := spawn(load("res://scenes/gameplay/hostile.tscn"),knight.global_position + Vector3(5,0,-6))
	var previous_hp: int = old_target.health
	var full_hp: int = new_target.health
	knight.command_attack(new_target)
	knight.set_process(true)
	for frame in range(180):
		await process_frame
		if new_target.health < full_hp: break
	if not check(old_target.health == previous_hp and new_target.health == full_hp - knight.attack_damage,
			"Retargeting must fire at the new target only"): return false
	if not check(model.player.assigned_animation == &"Shoot","Child animator lost the new target's firing pose"): return false

	# Cancel immediately after the damaging opening round, with two visual rounds pending.
	var count := bullet_count
	var start := knight.global_position
	knight.command_move(start + Vector3(0,0,6))
	for frame in range(90):
		await process_frame
		if knight.global_position.distance_to(start) > .6: break
	if not check(knight.global_position.distance_to(start) > .6 and model.current_clip() == &"Run",
			"Move order failed to return the knight to his running animation"): return false
	return check(bullet_count == count and new_target.health == full_hp - knight.attack_damage,
			"A cancelled burst fired during a move order")
