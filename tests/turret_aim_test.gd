extends SceneTree
# Headless: the Tank's turret (scripts/components/turret_aim.gd on scenes/models/tank_model.tscn)
# turns toward the aim point at a limited rate, sways gently when nothing is targeted, and the
# unit agent drives it while shooting without turning the hull.
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func step(model: Node3D, frames: int, aim = null) -> void:
	for i in range(frames):
		if aim != null: model.aim_at(aim)
		model._process(1.0/60)
func run() -> void:
	var model = load("res://scenes/models/tank_model.tscn").instantiate()
	root.add_child(model)
	await process_frame
	if not check(model.turret != null and model.muzzle != null,"Tank model has no turret or muzzle node"): return
	var rest: Vector3 = model.muzzle_position()
	if not check(rest.z < -3.0 and absf(rest.x) < 0.05 and rest.y > 1.2,"Muzzle at rest should sit ahead of the hull: %s" % rest): return
	# A target to the right: the turret turns no faster than its rate, then settles on it.
	var right := Vector3(10,0,0)
	step(model,10,right)
	if not check(absf(model.turret_yaw()) < deg_to_rad(50),"Turret turned too fast: %.1f deg in 1/6 s" % rad_to_deg(model.turret_yaw())): return
	step(model,120,right)
	var aimed: Vector3 = model.muzzle_position()
	if not check(aimed.x > 3.0 and absf(aimed.z) < 0.4,"Muzzle should point right (+X): %s" % aimed): return
	var dir: Vector3 = (right-model.turret.global_position); dir.y = 0
	var barrel: Vector3 = aimed-model.turret.global_position; barrel.y = 0
	if not check(barrel.normalized().dot(dir.normalized()) > 0.995,"Barrel not on the target line"): return
	# Behind: the long way round still arrives.
	step(model,180,Vector3(0,0,10))
	if not check(model.muzzle_position().z > 3.0,"Muzzle should point back (+Z): %s" % model.muzzle_position()): return
	# No target for two frames: aiming lapses and the turret eases back at its rate, then sways.
	await process_frame; await process_frame
	if not check(not model.aiming(),"Aiming should lapse without aim_at calls"): return
	var last: float = model.turret_yaw()
	for i in range(240):
		model._process(1.0/60)
		var now: float = model.turret_yaw()
		if not check(absf(angle_difference(last,now)) <= deg_to_rad(model.turn_speed_degrees)/60+0.001,"Turret snapped while returning"): return
		last = now
	var lo := INF; var hi := -INF
	for i in range(600):
		model._process(1.0/60)
		lo = minf(lo,model.turret_yaw()); hi = maxf(hi,model.turret_yaw())
	var limit := deg_to_rad(model.sway_degrees)+0.01
	if not check(hi-lo > deg_to_rad(2) and lo > -limit and hi < limit,"Idle sway out of range: %.1f..%.1f deg" % [rad_to_deg(lo),rad_to_deg(hi)]): return
	model.queue_free()
	# In the skirmish: a tank engaging a hostile beside it aims the turret, not the hull.
	var game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	for node in get_nodes_in_group("units"): node.set_process(false)
	var origin := Vector3(180,0,180)
	var tank = load("res://scenes/gameplay/tank.tscn").instantiate()
	game.get_node("Entities/Units").add_child(tank); tank.set_process(false)
	for cell in tank._claimed.duplicate(): tank._release(cell)
	tank.global_position = origin
	var foe = load("res://scenes/gameplay/hostile.tscn").instantiate()
	game.get_node("Entities/Units").add_child(foe); foe.set_process(false)
	for cell in foe._claimed.duplicate(): foe._release(cell)
	foe.global_position = origin+Vector3(4,0,0)
	await process_frame
	var turret = tank._turret()
	if not check(turret != null,"Tank agent does not see its turret"): return
	var health_before: int = foe.health
	for i in range(90):
		tank._process(1.0/60)
		turret._process(1.0/60)
	if not check(turret.aiming(),"Tank should be aiming at the hostile in range"): return
	if not check(absf(tank.get_node("Visuals").rotation.y) < 0.001,"Hull turned toward the target; the turret should turn instead"): return
	var barrel_dir: Vector3 = turret.muzzle_position()-turret.turret.global_position; barrel_dir.y = 0
	if not check(barrel_dir.normalized().dot(Vector3.RIGHT) > 0.99,"Turret not aimed at the hostile: %s" % barrel_dir): return
	if not check(foe.health < health_before,"Tank did not fire at the hostile"): return
	print("TURRET_AIM_TEST_PASSED"); quit()
