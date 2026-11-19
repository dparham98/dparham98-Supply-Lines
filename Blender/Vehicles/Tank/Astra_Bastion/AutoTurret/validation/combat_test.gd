extends SceneTree
## Run the real Bastion actor, cupola and primary shells together on First Contact.
## The runner selects a fixed 60 Hz clock. Targets stand still to isolate the two fire controls.

const TANK = preload("res://bastion/bastion_tank.tscn")
const HOSTILE = preload("res://scenes/gameplay/hostile.tscn")
const TRACER = preload("res://scripts/gameplay/tracer.gd")
const AUX_BULLET = "res://bastion/aux_bullet.tscn"
const ORIGIN = Vector3(180, 0, 180)

var game: Node3D
var tank: Node3D
var head: Node3D
var muzzle: Node3D
var shots: Array[Dictionary] = []
var main_shells := 0
var tracer_count := 0
var bullet_count := 0
var latest_bullet: Node3D
var resolutions := {}
var max_aim_error := 0.0
var max_origin_error := 0.0
var max_bullet_origin_error := 0.0
var results := {}


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> bool:
	if not ok:
		push_error(message)
		quit(1)
	return ok


func advance(frames: int) -> void:
	for i in range(frames):
		await process_frame


func spawn(scene: PackedScene, faction: String, offset: Vector3, run_agent: bool) -> Node3D:
	var actor = scene.instantiate()
	actor.team = faction
	actor.position = ORIGIN + offset
	game.get_node("Entities/Units").add_child(actor)
	for cell in actor._claimed.duplicate():
		actor._release(cell)
	actor.global_position = ORIGIN + offset
	actor.set_process(run_agent)
	return actor


func observe_shot(target: Node3D, origin: Vector3, endpoint: Vector3) -> void:
	var muzzle_error := origin.distance_to(muzzle.global_position)
	var forward := head.global_basis.z
	var bearing := target.global_position - head.global_position
	var planar_heading := Vector2(forward.x, forward.z)
	var planar_bearing := Vector2(bearing.x, bearing.z)
	var error_degrees := absf(rad_to_deg(planar_heading.angle_to(planar_bearing)))
	max_origin_error = maxf(max_origin_error, muzzle_error)
	max_aim_error = maxf(max_aim_error, error_degrees)
	if is_instance_valid(latest_bullet):
		var offset: float = latest_bullet.get("half_length")
		var tail := latest_bullet.global_position + latest_bullet.global_basis.z.normalized()*offset
		max_bullet_origin_error = maxf(max_bullet_origin_error, tail.distance_to(muzzle.global_position))
	shots.append({"frame": Engine.get_process_frames(), "id": target.get_instance_id(),
		"origin": origin, "endpoint": endpoint,
		"bullet_id": latest_bullet.get_instance_id() if is_instance_valid(latest_bullet) else -1})


func count_shots(at: Node3D) -> int:
	var id := at.get_instance_id()
	return shots.filter(func(s): return s.id == id).size()


func observe_child(node: Node) -> void:
	if node.scene_file_path == "res://scenes/gameplay/tank_shell.tscn":
		main_shells += 1
	elif node.scene_file_path == AUX_BULLET:
		latest_bullet = node
		bullet_count += 1
		node.resolved.connect(observe_resolution.bind(node.get_instance_id()))
	elif node.get_script() == TRACER:
		tracer_count += 1


func observe_resolution(hit: bool, id: int) -> void:
	if resolutions.has(id):
		check(false, "A single bullet resolved twice")
	resolutions[id] = {"hit":hit,"frame":Engine.get_process_frames()}


func next_shot() -> Dictionary:
	var before := shots.size()
	for i in range(100):
		await process_frame
		if shots.size() > before:
			return shots.back()
	check(false, "No secondary round launched within the observation window")
	return {}


func wait_for_resolution(shot: Dictionary) -> Dictionary:
	for i in range(65):
		if resolutions.has(shot.bullet_id):
			return resolutions[shot.bullet_id]
		await process_frame
	check(false, "Secondary round failed to reach its snapshotted endpoint")
	return {}


func run() -> void:
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	for unit in get_nodes_in_group("units"):
		unit.set_process(false)
	tank = spawn(TANK, "player", Vector3.ZERO, true)
	var far = spawn(HOSTILE, "enemy", Vector3(24,0,0), false)
	var friendly = spawn(HOSTILE, "player", Vector3(2.4,0,0), false)
	var neutral = spawn(HOSTILE, "neutral", Vector3(-3.4,0,0), false)
	var nearby = spawn(HOSTILE, "enemy", Vector3(0,0,10.2), false)
	var alternate = spawn(HOSTILE, "enemy", Vector3(0,0,12), false)
	var defense = tank.get_node("CloseDefense")
	var rig = tank.get_node("Visuals/Model")
	head = rig.find_child("Aux_Turret", true, false)
	muzzle = rig.find_child("Aux_Muzzle", true, false)
	if not check(head != null and muzzle != null and head.is_ancestor_of(muzzle),
			"The real cupola pivot and muzzle are required"): return
	defense.fired.connect(observe_shot)
	game.child_entered_tree.connect(observe_child)
	var friendly_health: int = friendly.health
	var neutral_health: int = neutral.health
	var close_health: int = nearby.health
	var alternate_health: int = alternate.health
	var far_health: int = far.health
	tank.command_attack(far)
	tank._cooldown = 99.0
	await advance(65)
	if not check(shots.is_empty() and main_shells == 0,
			"A friendly, neutral, or hostile beyond 10 m drew fire"): return

	nearby.global_position = ORIGIN + Vector3(0,0,8)
	alternate.global_position = ORIGIN + Vector3(1.8,0,8.8)
	await advance(3)
	if not check(shots.is_empty(), "Cupola fired before turning from its initial bearing"): return
	var first := await next_shot()
	if first.is_empty(): return
	var round_one := instance_from_id(first.bullet_id) as Node3D
	if not check(is_instance_valid(round_one) and round_one.scene_file_path == AUX_BULLET,
			"Expected a discrete round from the specified secondary bullet scene"): return
	if not check(nearby.health == close_health, "Secondary damage landed at launch"): return
	var start: Vector3 = first.origin
	var first_position := round_one.global_position
	var path_length: float = start.distance_to(first.endpoint)
	var shape_bounds := AABB()
	var meshes := round_one.find_children("*", "MeshInstance3D", true, false)
	for part in meshes:
		var bounds: AABB = part.global_transform * part.get_aabb()
		shape_bounds = bounds if part == meshes.front() else shape_bounds.merge(bounds)
	var visual_diameter := shape_bounds.size.length()
	if not check(not meshes.is_empty() and visual_diameter > 0.0 and visual_diameter < path_length*.2,
			"Round geometry should occupy a small fraction of the muzzle-to-target span"): return
	await advance(3)
	if not check(is_instance_valid(round_one) and nearby.health == close_health and
			round_one.global_position.distance_to(first_position) > .2,
			"Expected a moving bullet and undamaged target on later pre-impact frames"): return
	var first_result := await wait_for_resolution(first)
	if not check(first_result.get("hit") == true and nearby.health == close_health - defense.damage,
			"Exactly one secondary hit should land when the first bullet arrives"): return
	results["first_impact_frames_after_launch"] = first_result.frame-first.frame
	results["first_flight_world_m"] = snappedf(path_length,.001)
	results["first_projectile_visual_diagonal_world_m"] = snappedf(visual_diameter,.001)
	results["damage_at_launch"] = 0
	while shots.size() < 4:
		if (await next_shot()).is_empty(): return
	defense.set_process(false)
	await advance(45)
	var initial_hits := count_shots(nearby)
	if not check(initial_hits >= 2 and initial_hits == shots.size() and main_shells == 0,
			"Cupola did not independently acquire the closest eligible enemy"): return
	if not check(nearby.health == close_health - initial_hits * defense.damage and
			alternate.health == alternate_health and far.health == far_health,
			"Expected per-shot damage to precisely one target during the main reload"): return
	var shortest_interval := 10000
	for i in range(1, shots.size()):
		shortest_interval = mini(shortest_interval, int(shots[i].frame - shots[i-1].frame))
	if not check(shortest_interval >= floori(defense.shot_interval * 60),
			"Secondary gun fired more quickly than its configured cadence"): return
	results["secondary_hits_during_main_reload"] = initial_hits
	results["minimum_interval_frames_at_60_hz"] = shortest_interval

	defense.set_process(true)
	tank._cooldown = 0.0
	await advance(130)
	if not check(main_shells >= 2 and far.health < far_health and count_shots(nearby) > initial_hits,
			"The main gun and cupola must each hit their own target"): return
	if not check(tank.order_target == far and tank.order == "attack" and
			tank.global_position.distance_to(ORIGIN) < .001, "Cupola changed the tank order or position"): return
	if not check(bullet_count == shots.size() and tracer_count == 0,
			"Each roof shot should spawn a single bullet and no full-span tracer"): return
	var main_forward: Vector3 = rig.muzzle_position() - rig.turret.global_position
	var aux_forward := head.global_basis.z
	var separation := absf(rad_to_deg(Vector2(main_forward.x, main_forward.z).angle_to(Vector2(aux_forward.x, aux_forward.z))))
	if not check(separation > 65, "Main gun and cupola do not point at separate bearings"): return
	results["separate_bearings_degrees"] = snappedf(separation,.01)
	results["main_shells_within_observation"] = main_shells
	results["confirmed_main_target_damage"] = far_health - far.health
	results["simultaneous_secondary_hits"] = int((close_health-nearby.health)/defense.damage) - initial_hits

	# The chassis changes heading under an existing attack order. The independent pivot
	# must reacquire the same world bearing even though its rotating parent has moved.
	tank.get_node("Visuals").rotate_y(deg_to_rad(105.0))
	var before_turn := shots.size()
	await advance(90)
	if not check(shots.size() > before_turn and tank.order_target == far, "Cupola failed to fire after hull yaw"): return
	var pre_pause := shots.size()
	var pre_pause_health: int = nearby.health
	paused = true
	await advance(65)
	if not check(pre_pause == shots.size() and pre_pause_health == nearby.health,
			"Close defense continued firing while the game was paused"): return
	paused = false
	await advance(35)
	if not check(shots.size() > pre_pause, "Close defense did not resume after unpausing"): return

	# Isolate one round at a time for these mid-flight changes to the intended victim.
	defense.set_process(false)
	await advance(45)
	var before_dodge: int = nearby.health
	defense.set_process(true)
	var moving_target_shot := await next_shot()
	if moving_target_shot.is_empty(): return
	defense.set_process(false)
	var dodge_round := instance_from_id(moving_target_shot.bullet_id) as Node3D
	var frozen_end: Vector3 = moving_target_shot.endpoint
	var flight_direction: Vector3 = (frozen_end - moving_target_shot.origin).normalized()
	nearby.global_position += Vector3(4,0,0)
	await advance(5)
	if not check(is_instance_valid(dodge_round) and
			(dodge_round.global_position-moving_target_shot.origin).cross(flight_direction).length() < .01 and
			(-dodge_round.global_basis.z).normalized().dot(flight_direction) > .999,
			"Bullet changed path toward a dodging unit"): return
	var dodge_result := await wait_for_resolution(moving_target_shot)
	if not check(dodge_result.get("hit") == false and nearby.health == before_dodge,
			"The dodged round must miss and cause no damage"): return
	results["dodged_projectile_missed"] = true

	nearby.global_position = ORIGIN + Vector3(0,0,8)
	defense.set_process(true)
	var changed_side := await next_shot()
	if changed_side.is_empty(): return
	defense.set_process(false)
	nearby.team = "player"
	var side_result := await wait_for_resolution(changed_side)
	if not check(side_result.get("hit") == false and nearby.health == before_dodge,
			"An in-flight round hurt a target that became friendly"): return
	results["in_flight_friendly_spared"] = true
	nearby.team = "enemy"
	defense.set_process(true)
	var freed_target := await next_shot()
	if freed_target.is_empty(): return
	nearby.queue_free()
	var freed_result := await wait_for_resolution(freed_target)
	if not check(freed_result.get("hit") == false, "A round hit a freed target"): return
	results["freed_target_missed"] = true
	await advance(70)
	if not check(count_shots(alternate) > 0 and alternate.health < alternate_health,
			"Cupola failed to reacquire after its previous target was freed"): return
	alternate.global_position = ORIGIN + Vector3(0,0,10.2)
	var exit_count := shots.size()
	await advance(70)
	if not check(shots.size() == exit_count and friendly.health == friendly_health and
			neutral.health == neutral_health, "Cupola fired outside range or hit a non-hostile"): return

	alternate.global_position = ORIGIN + Vector3(0,0,8)
	var last_round := await next_shot()
	if last_round.is_empty(): return
	if not check(shots.size() == exit_count+1, "Cupola did not reacquire when hostiles returned to range"): return
	var death_health: int = alternate.health
	var shot_damage: int = defense.damage
	tank.take_damage(10000)
	var death_count := shots.size()
	var last_result := await wait_for_resolution(last_round)
	if not check(last_result.get("hit") == true and alternate.health == death_health - shot_damage,
			"The already-fired round should finish its flight after launcher death"): return
	results["last_round_landed_after_launcher_died"] = true
	await advance(60)
	if not check(not is_instance_valid(tank) and is_instance_valid(rig) and rig.dying(),
			"Expected the actual tank actor to die and leave its animated model"): return
	if not check(shots.size() == death_count and alternate.health == death_health-shot_damage,
			"Detached wreck launched additional bullets"): return
	if not check(tracer_count == 0 and bullet_count == shots.size() and resolutions.size() == shots.size(),
			"Expected one short-lived round per auxiliary shot, with no leftover bullets or tracers"): return
	if not check(max_bullet_origin_error < .001, "The physical bullet did not start at the roof muzzle"): return
	if not check(max_origin_error < .001 and max_aim_error <= 6.0,
			"Shot origin or aim failed: %.4f world m, %.2f degrees" % [max_origin_error, max_aim_error]): return
	results["max_muzzle_origin_error_world_m"] = snappedf(max_origin_error,.0001)
	results["max_physical_bullet_origin_error_world_m"] = snappedf(max_bullet_origin_error,.0001)
	results["max_planar_aim_error_degrees"] = snappedf(max_aim_error,.01)
	results["total_secondary_shots"] = shots.size()
	results["resolved_bullets"] = resolutions.size()
	results["full_span_tracers"] = tracer_count
	results["allied_and_neutral_damage"] = 0
	results["shots_during_pause_or_after_death"] = 0
	print("CUPOLA_MEASUREMENTS ", JSON.stringify(results))
	print("CUPOLA_COMBAT_PASSED")
	quit(0)
