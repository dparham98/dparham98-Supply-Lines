extends SceneTree
# Headless: the Motorcycle's model (assets/models/units/motorcycle.glb via scenes/models/motorcycle_model.tscn)
# faces -Z at the right size, rolls its wheels, steers and leans into a turn with the rider's hands still on
# the grips, puts its stand down when it stops, fires a rail spike on the move without turning its body, and
# on death stays behind to crash and remove itself after the unit has left the game.
const Bounds = preload("res://scripts/units/selection_bounds.gd")
const Projectile = preload("res://scripts/gameplay/projectile.gd")
const Burst = preload("res://scripts/components/burst_effect.gd")
const BIKE := "Rig/bike_root/"
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func step(unit: Node3D, model: Node3D, frames: int) -> void:
	for i in range(frames):
		unit._process(1.0/60)
		model._process(1.0/60)
func of_script(script: Script) -> Array:
	return game.get_children().filter(func(n): return n.get_script() == script)
func flat(v: Vector3) -> Vector3:
	return Vector3(v.x,0,v.z).normalized()
func run() -> void:
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	for node in get_nodes_in_group("units"): node.set_process(false)
	var origin := Vector3(180,0,180)
	var unit: Node3D = load("res://scenes/gameplay/motorcycle.tscn").instantiate()
	unit.team = "player"
	unit.start_fuelled = true
	game.get_node("Entities/Units").add_child(unit)
	unit.set_process(false)
	for cell in unit._claimed.duplicate(): unit._release(cell)
	unit.global_position = origin
	await process_frame
	var model = unit.get_node("Visuals/Model")
	if not check(model.scene_file_path == "res://scenes/models/motorcycle_model.tscn" and model.has_method("set_drive") and model.has_method("aim_at"),"Motorcycle does not use the rigged model"): return
	if not check(unit.fuel > 0.0,"Motorcycle should start this test fuelled"): return
	if not check(unit.projectile_scene != null and unit.projectile_scene.resource_path == "res://scenes/gameplay/rail_spike.tscn","Motorcycle should fire rail spikes"): return
	if not check(model.has_death_clip() and model.player.get_animation("Die").loop_mode == Animation.LOOP_NONE,"Die clip missing or looping: %s" % model.player.get_animation_list()): return
	var bike: Node3D = model.get_node(BIKE.trim_suffix("/"))
	var fork: Node3D = model.get_node(BIKE+"steer_F/fork_F")
	var bars: Node3D = model.get_node(BIKE+"steer_F/handlebar_F")
	var front: Node3D = model.get_node(BIKE+"steer_F/wheel_F")
	var rear: Node3D = model.get_node(BIKE+"wheel_R")
	var stand: Node3D = model.get_node(BIKE+"stand")
	var swivel: Node3D = model.get_node(BIKE+"gun_swivel")
	var barrel: Node3D = model.get_node(BIKE+"gun_swivel/gun_body/gun_barrel")
	var torso: Node3D = model.get_node(BIKE+"rider_torso")
	var arm: Node3D = model.get_node(BIKE+"rider_torso/rider_arm_L")
	var fx = model.muzzle
	if not check(fx != null and fx.get_script() == Burst and fx.player.has_animation("Fire"),"The muzzle node should be the steam effect"): return
	if not check(fx.flash.scale.x < 0.01,"Steam should be out before the first shot"): return
	# On the ground, the size of the concept, headlight and muzzle to the front; effects are not its body.
	var meshes := Bounds.meshes(unit)
	if not check(meshes.size() == 17 and meshes.all(func(m): return not fx.is_ancestor_of(m)),"Motorcycle meshes wrong: %d" % meshes.size()): return
	var low := INF; var high := -INF; var ahead := INF; var behind := -INF; var left := INF; var right := -INF
	for mesh in meshes:
		for i in range(8):
			var p: Vector3 = unit.global_transform.affine_inverse()*(mesh.global_transform*mesh.get_aabb().get_endpoint(i))
			low = minf(low,p.y); high = maxf(high,p.y); ahead = minf(ahead,p.z); behind = maxf(behind,p.z); left = minf(left,p.x); right = maxf(right,p.x)
	if not check(absf(low) < 0.15 and high > 1.9 and high < 2.2,"Motorcycle not on the ground or the wrong height: y %.2f..%.2f" % [low,high]): return
	if not check(behind-ahead > 2.5 and behind-ahead < 2.9 and right-left > 0.8 and right-left < 1.3,"Motorcycle size wrong: z %.2f..%.2f x %.2f..%.2f" % [ahead,behind,left,right]): return
	if not check(unit.to_local(fork.global_position).z < -0.5 and unit.to_local(model.muzzle_position()).z < unit.to_local(swivel.global_position).z-0.5,"Motorcycle should face -Z"): return
	if not check(unit.get_node("SelectionRing").mesh.outer_radius >= (behind-ahead)*0.5,"The bike sticks out past its selection ring"): return
	# Where the left hand holds the bars, for checking it stays there through a turn.
	var hand_in_arm := Vector3(0.0775,-0.117,0.5)
	var grip_in_bars: Vector3 = bars.global_transform.affine_inverse()*(arm.global_transform*hand_in_arm)
	# Parked: stand down, settled onto it toward the left, wheels still.
	step(unit,model,90)
	var parked_lean: float = model.lean_angle()
	if not check(model.stand_stowed() == 0.0 and parked_lean > deg_to_rad(3.0) and parked_lean < deg_to_rad(8.0),"Parked bike should rest on its stand: stowed %.2f lean %.1f" % [model.stand_stowed(),rad_to_deg(parked_lean)]): return
	if not check((bike.global_basis.y).dot(-unit.global_basis.x) > 0.04,"Parked bike should lean to its left"): return
	if not check(model.wheel_roll() == 0.0,"Wheels turned while parked"): return
	var stand_down := stand.transform.basis
	# Riding: wheels roll with the ground, the stand folds away, the bike stands up.
	unit.command_move(origin+Vector3(0,0,-16))
	var rolled := 0.0
	var from := unit.global_position
	for i in range(50):
		var roll: float = model.wheel_roll()
		step(unit,model,1)
		rolled += wrapf(model.wheel_roll()-roll,-PI,PI)
	var travelled := unit.global_position.distance_to(from)
	if not check(travelled > 3.0,"Motorcycle did not move: %.2f m" % travelled): return
	if not check(absf(rolled*model.rear_wheel_radius-travelled) < 0.25,"Wheels should roll with the ground: %.2f m rolled over %.2f m" % [rolled*model.rear_wheel_radius,travelled]): return
	if not check(absf(rear.rotation.x) > 0.01 and absf(front.rotation.x) > 0.01,"Wheel nodes did not turn"): return
	if not check(model.stand_stowed() == 1.0 and not stand.transform.basis.is_equal_approx(stand_down),"Stand should fold away when moving"): return
	if not check(absf(model.lean_angle()) < deg_to_rad(2.0),"Bike should stand up riding straight: %.1f" % rad_to_deg(model.lean_angle())): return
	# A left turn: the fork steers left, the bike leans left about its tyres, and the hands stay on the grips.
	unit.command_move(unit.global_position+Vector3(-14,0,-1))
	var steer_most := 0.0
	var lean_most := 0.0
	var tilt_most := 0.0
	var hand_off := 0.0
	var lean_steps: Array[float] = []
	for i in range(60):
		var before: float = model.lean_angle()
		step(unit,model,1)
		lean_steps.append(absf(model.lean_angle()-before))
		steer_most = maxf(steer_most,model.steer_angle())
		lean_most = maxf(lean_most,model.lean_angle())
		tilt_most = maxf(tilt_most,bike.global_basis.y.dot(-(unit.get_node("Visuals") as Node3D).global_basis.x))
		hand_off = maxf(hand_off,(bars.global_transform*grip_in_bars).distance_to(arm.global_transform*hand_in_arm))
	if not check(steer_most > deg_to_rad(8.0) and steer_most <= deg_to_rad(15.01),"Fork should steer into a left turn, up to 15 degrees: %.1f" % rad_to_deg(steer_most)): return
	if not check(lean_most > deg_to_rad(8.0) and lean_most <= deg_to_rad(18.01),"Bike should lean into a left turn, up to 18 degrees: %.1f" % rad_to_deg(lean_most)): return
	if not check(tilt_most > 0.13,"The lean should tip the whole bike toward the inside of the turn: %.2f" % tilt_most): return
	if not check(lean_steps.max() < deg_to_rad(1.5),"The lean should build smoothly, jumped %.2f degrees in a frame" % rad_to_deg(lean_steps.max())): return
	if not check(hand_off < 0.05,"The rider's hand left the grip by %.3f m" % hand_off): return
	if not check(bike.global_position.distance_to((unit.get_node("Visuals") as Node3D).global_position) < 0.001,"The lean should pivot at the tyres"): return
	# Stopping puts the stand back down.
	unit._stop_route(); unit.order = "idle"
	step(unit,model,120)
	if not check(model.stand_stowed() == 0.0 and stand.transform.basis.is_equal_approx(stand_down) and model.lean_angle() > deg_to_rad(3.0),"Stand should come down when the bike stops"): return
	# A shot on the move: ride past a target on the right. The bike never turns to it; the gun does.
	unit.global_position = origin
	unit.get_node("Visuals").rotation.y = 0.0
	var foe: Node3D = load("res://scenes/gameplay/hostile.tscn").instantiate()
	foe.team = "enemy"
	game.get_node("Entities/Units").add_child(foe)
	foe.set_process(false)
	for cell in foe._claimed.duplicate(): foe._release(cell)
	foe.global_position = origin+Vector3(2.4,0,-8)
	await process_frame
	await process_frame
	if not check(not model.aiming() and unit.global_position.distance_to(foe.global_position) > unit.attack_range,"The target should start out of range"): return
	unit.command_move(origin+Vector3(0,0,-20))
	var health: int = foe.health
	var barrel_rest := barrel.position
	var fired := false
	for i in range(120):
		step(unit,model,1)
		if foe.health < health: fired = true; break
	if not check(fired,"Motorcycle did not fire on the move"): return
	if not check(unit.order == "move" and unit.global_position.distance_to(origin) > 2.0,"The shot should not stop the ride"): return
	var heading := -(unit.get_node("Visuals") as Node3D).global_basis.z
	var to_foe := flat(foe.global_position-unit.global_position)
	if not check(heading.dot(Vector3.FORWARD) > 0.98 and heading.dot(to_foe) < 0.9,"The bike turned its body to aim: heading %s" % heading): return
	var gun := flat(model.muzzle_position()-swivel.global_position)
	if not check(gun.dot(to_foe) > 0.97,"The gun should be on the target as the spike leaves: %.2f" % gun.dot(to_foe)): return
	var spikes := of_script(Projectile)
	if not check(spikes.size() == 1 and spikes[0].scene_file_path == "res://scenes/gameplay/rail_spike.tscn","One rail spike should fire, got %d" % spikes.size()): return
	var spike: Node3D = spikes[0]
	spike.set_process(false)
	if not check(spike.global_position.distance_to(model.muzzle_position()) < 0.8,"The spike should leave the muzzle: %.2f m away" % spike.global_position.distance_to(model.muzzle_position())): return
	if not check((-spike.global_basis.z).dot((foe.global_position+Vector3.UP-spike.global_position).normalized()) > 0.9,"The spike should point at the target"): return
	if not check(spike.get_node("Model/rail_spike").material_override == null and spike.get_node("Model/rail_spike/rail_spike_trail").material_override != null,"The spike stays iron; its trail takes the team colour"): return
	# Steam, recoil, the rider's look and the ride all carry on together.
	fx.player.advance(1.0/30)
	if not check(fx.player.is_playing() and fx.flash.scale.x > 0.03,"The shot should vent steam: %.3f" % fx.flash.scale.x): return
	var here := unit.global_position
	var roll_then: float = model.wheel_roll()
	var deepest := 0.0
	for i in range(8):
		step(unit,model,1)
		deepest = maxf(deepest,barrel_rest.z-barrel.position.z)
	if not check(deepest > 0.08 and deepest < 0.13,"Barrel should slam back about 12 cm: %.3f" % deepest): return
	if not check(unit.global_position.distance_to(here) > 0.5 and model.wheel_roll() != roll_then,"The bike should keep riding through the shot"): return
	if not check(absf(model.head_yaw()) > 0.3 and signf(model.head_yaw()) == signf(model.turret_yaw()) and absf(model.head_yaw()) <= deg_to_rad(70.01),"The rider should look where the gun points: head %.2f gun %.2f" % [model.head_yaw(),model.turret_yaw()]): return
	if not check((-(unit.get_node("Visuals") as Node3D).global_basis.z).dot(Vector3.FORWARD) > 0.98,"The bike turned after the shot"): return
	# The wisp tapers off over the reload and is gone when the next spike is ready.
	fx.player.seek(1.0,true)
	var wisp := 0.0
	for i in range(1,10): wisp = maxf(wisp,(fx.get_node("Model/Steam_Wisp_%d" % i) as Node3D).scale.x)
	if not check(wisp > 0.01,"A wisp of steam should hang on through the reload"): return
	fx.player.seek(fx.player.current_animation_length,true)
	for node in fx.get_node("Model").get_children():
		if node is Node3D and not check((node as Node3D).scale.x < 0.01,"Steam should be gone by the next shot: %s" % node.name): return
	if not check(is_equal_approx(fx.player.current_animation_length,unit.unit_stats.attack_interval),"Steam should last the reload"): return
	# The spike flies to the target's surface and sticks there for half a second.
	var parts := Bounds.meshes(foe)
	var box: AABB = parts[0].global_transform*parts[0].get_aabb()
	for part in parts: box = box.merge(part.global_transform*part.get_aabb())
	var flight := 0
	while not spike.is_queued_for_deletion() and flight < 120:
		spike._process(1.0/60)
		flight += 1
	if not check(flight >= 1 and flight < 40,"The spike's flight should be seen: %d frames" % flight): return
	var impacts := of_script(Burst)
	if not check(impacts.size() == 1 and impacts[0].scene_file_path == "res://scenes/gameplay/rail_spike_impact.tscn","One impact should appear, got %d" % impacts.size()): return
	var impact = impacts[0]
	if not check(box.grow(0.1).has_point(impact.global_position),"The impact should be on the target: %s in %s" % [impact.global_position,box]): return
	var stuck: Node3D = impact.get_node("Model/Impact_Spike")
	if not check(impact.flash.scale.x > 0.5 and stuck.scale.x > 1.0,"The impact should start with sparks and the spike in place"): return
	var stuck_at := stuck.global_position
	impact.player.seek(0.45,true)
	if not check(stuck.scale.x > 1.0 and stuck.global_position.distance_to(stuck_at) < 0.02,"The spike should stay embedded for half a second"): return
	impact.player.seek(0.8,true)
	if not check(stuck.global_position.y < stuck_at.y-0.2,"The spike should drop away"): return
	impact.player.advance(impact.player.current_animation_length)
	await process_frame
	await process_frame
	if not check(not is_instance_valid(impact) and not is_instance_valid(spike),"Spike and impact should remove themselves"): return
	# Death: the unit is gone at once, the wreck plays out where it was and the rig lets go of it.
	step(unit,model,30)
	var where: Vector3 = model.global_position
	var gun_before := swivel.transform
	unit.take_damage(unit.health)
	if not check(unit.is_queued_for_deletion() and not unit.is_in_group("units"),"The unit should leave the game at once"): return
	if not check(model.get_parent() == game and model.dying() and model.player.current_animation == "Die","The wreck should stay and play Die"): return
	if not check(model.global_position.is_equal_approx(where),"The wreck moved when it was left behind"): return
	await process_frame
	if not check(not is_instance_valid(unit),"The unit should be freed"): return
	var crash := model.get_children().filter(func(n): return n.get_script() == Burst)
	if not check(crash.size() == 1 and crash[0].player.has_animation("Death"),"Crash effect missing"): return
	if not check(is_equal_approx(crash[0].player.get_animation("Death").length,model.player.get_animation("Die").length),"The crash effect should share Die's timeline"): return
	model.player.seek(2.6,true)
	if not check(bike.global_basis.y.y < 0.35,"The bike should be down on its side: up.y %.2f" % bike.global_basis.y.y): return
	var skid: Vector3 = model.to_local(bike.global_position)
	if not check(skid.z < -2.5 and skid.z > -5.0,"The bike should skid a few metres along its travel: %s" % skid): return
	if not check(flat(torso.global_position-bike.global_position).length() > 0.0 and torso.global_position.distance_to(bike.global_position) > 1.5 and model.to_local(torso.global_position).y < 0.5,"The rider should be thrown clear and land: %s" % model.to_local(torso.global_position)): return
	if not check(swivel.transform.is_equal_approx(gun_before),"The gun should stay where it was pointing"): return
	var pose := bike.transform
	model._process(1.0/60)
	if not check(bike.transform.is_equal_approx(pose),"The rig should stop writing to the model while it dies"): return
	crash[0].player.seek(2.6,true)
	if not check((crash[0].get_node("Model/Oil_Pool_Rider") as Node3D).scale.x > 0.3 and (crash[0].get_node("Model/Fire_1") as Node3D).scale.y > 0.05,"Oil and fire should be showing on the wreck"): return
	var length: float = model.player.get_animation("Die").length
	if not check(length >= 4.0 and length <= 5.5,"Die should run 4 to 5 seconds: %.2f" % length): return
	model.player.seek(length-0.02,true)
	if not check(model.to_local(bike.global_position).y < -1.0 and model.to_local(torso.global_position).y < -0.5,"The wreck should sink out of sight"): return
	model.player.advance(0.2)
	await process_frame
	await process_frame
	if not check(not is_instance_valid(model),"The wreck should remove itself"): return
	print("MOTORCYCLE_MODEL_TEST_PASSED"); quit()
