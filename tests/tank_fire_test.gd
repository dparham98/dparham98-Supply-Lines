extends SceneTree
# Headless: a tank shot kicks the barrel, rocks the hull, lights the muzzle, sends a shell from the
# barrel tip to the surface of the target and leaves a small impact that removes itself.
const Projectile = preload("res://scripts/gameplay/projectile.gd")
const Burst = preload("res://scripts/components/burst_effect.gd")
const Bounds = preload("res://scripts/units/selection_bounds.gd")
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func actor(id: String, team: String, point: Vector3) -> Node3D:
	var unit = load("res://scenes/gameplay/"+id+".tscn").instantiate()
	unit.team = team
	game.get_node("Entities/Units").add_child(unit)
	unit.set_process(false)
	for cell in unit._claimed.duplicate(): unit._release(cell)
	unit.global_position = point
	return unit
func of_script(script: Script) -> Array:
	return game.get_children().filter(func(n): return n.get_script() == script)
func run() -> void:
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	for node in get_nodes_in_group("units"): node.set_process(false)
	var origin := Vector3(180,0,180)
	var tank := actor("tank","player",origin)
	var foe := actor("hostile","enemy",origin+Vector3(12,0,0))
	tank.attack_range = 14.0
	await process_frame
	var model = tank.get_node("Visuals/Model")
	var fx = model.muzzle
	var hull: Node3D = model.get_node("Tank/Tank_Root/Tank_Hull")
	var barrel: Node3D = model.get_node("Tank/Tank_Root/Tank_Hull/Tank_Turret/Barrel_Mount/Tank_Barrel")
	var brake: Node3D = barrel.get_node("Barrel_Muzzle_Brake")
	if not check(fx != null and fx.get_script() == Burst,"The muzzle node should be the fire effect"): return
	# The fire effect sits on the tip of the brake and shows nothing until a shot.
	var tip_offset: Vector3 = model.muzzle_position()-brake.global_position
	if not check(absf(tip_offset.length()-0.27) < 0.03 and tip_offset.z < 0.0,"Muzzle should be the brake's tip: %s" % tip_offset): return
	if not check(fx.player.has_animation("Fire") and fx.player.get_animation("Fire").loop_mode == Animation.LOOP_NONE,"Fire clip should play once"): return
	if not check(fx.flash.scale.x < 0.01 and not fx.light.visible,"Flash should be out before the first shot"): return
	var body := Bounds.meshes(tank)
	if not check(body.all(func(m): return not fx.is_ancestor_of(m)),"Effects should not count as the tank's body"): return
	# Bring the turret onto the target, then fire.
	var turret = tank._turret()
	tank._cooldown = 2.0
	for i in range(100):
		tank._process(1.0/60)
		turret._process(1.0/60)
	if not check(of_script(Projectile).is_empty(),"Fired during the wait"): return
	var barrel_rest := barrel.position
	var hull_rest := hull.transform.basis
	var along: Vector3 = (model.muzzle_position()-turret.turret.global_position).normalized()
	var health_before: int = foe.health
	var rest_world := barrel.global_position
	for i in range(80):
		tank._process(1.0/60)
		if foe.health < health_before: break
		turret._process(1.0/60)
	if not check(foe.health < health_before,"Tank did not fire"): return
	# The shell leaves the tip, pointing at the middle of the target.
	var shells := of_script(Projectile)
	if not check(shells.size() == 1 and shells[0].scene_file_path == "res://scenes/gameplay/tank_shell.tscn","One shell should fire, got %d" % shells.size()): return
	var shell: Node3D = shells[0]
	if not check(shell.global_position.distance_to(model.muzzle_position()) < 0.6,"Shell should leave the tip: %.2f m" % shell.global_position.distance_to(model.muzzle_position())): return
	var parts := Bounds.meshes(foe)
	var box: AABB = parts[0].global_transform*parts[0].get_aabb()
	for part in parts: box = box.merge(part.global_transform*part.get_aabb())
	var fly: Vector3 = -shell.global_transform.basis.z
	if not check(fly.dot((box.get_center()-shell.global_position).normalized()) > 0.995,"Shell should point at the target"): return
	var trail: MeshInstance3D = shell.get_node("Model/tank_shell/tank_shell_trail")
	var casing: MeshInstance3D = shell.get_node("Model/tank_shell")
	if not check(trail.material_override != null and casing.material_override == null,"Trail takes the team colour; the casing stays lit metal"): return
	# Flash and light come on at once.
	fx.player.advance(1.0/60); fx._process(0.0)
	if not check(fx.flash.scale.x > 0.5 and fx.light.visible and fx.light.light_energy > 2.0,"Shot should light the muzzle: scale %.2f" % fx.flash.scale.x): return
	# The barrel kicks straight back and the firing end of the hull lifts.
	var deepest := 0.0
	var highest := 0.0
	var tip_base: float = (hull.global_transform*hull.to_local(model.muzzle_position())).y
	for i in range(14):
		turret._process(1.0/60)
		deepest = maxf(deepest,(rest_world-barrel.global_position).dot(along))
		highest = maxf(highest,model.muzzle_position().y-tip_base)
	if not check(deepest > 0.25 and deepest < 0.45,"Barrel kick should be about a third of a metre: %.2f" % deepest): return
	if not check(highest > 0.01,"Firing end should lift: %.3f m" % highest): return
	# The shell closes on the target and stops on its surface.
	var start := shell.global_position
	shell.set_process(false)
	var steps := 0
	while not shell.is_queued_for_deletion() and steps < 300:
		var was: float = shell.global_position.distance_to(box.get_center())
		shell._process(1.0/60)
		steps += 1
		if not check(shell.global_position.distance_to(box.get_center()) <= was+0.001,"Shell should close on the target"): return
	if not check(steps > 12 and steps < 60,"Shell should be seen flying, took %d frames" % steps): return
	if not check(shell.global_position.distance_to(start) > 5.0,"Shell should travel: %.1f m" % shell.global_position.distance_to(start)): return
	var impacts := of_script(Burst)
	if not check(impacts.size() == 1,"One impact should appear, got %d" % impacts.size()): return
	var impact: Node3D = impacts[0]
	if not check(impact.player.has_animation("Impact") and impact.flash.scale.x > 0.5 and impact.light.visible,"Impact should start with a flash"): return
	await process_frame
	if not check(not is_instance_valid(shell),"Shell should disappear on arrival"): return
	if not check(box.grow(0.05).has_point(impact.global_position) and impact.global_position.x < box.get_center().x,"Impact should be on the near face: %s in %s" % [impact.global_position,box]): return
	# It bursts back toward the shooter, level, with its own flash.
	var back: Vector3 = -impact.global_transform.basis.z
	if not check(back.dot(Vector3.LEFT) > 0.99,"Impact should lean toward the shooter: %s" % back): return
	impact.player.advance(impact.player.current_animation_length+0.1)
	await process_frame
	await process_frame
	if not check(not is_instance_valid(impact),"Impact should remove itself"): return
	# Everything settles back.
	for i in range(150): turret._process(1.0/60)
	if not check(barrel.position.distance_to(barrel_rest) < 0.0001,"Barrel should run out to rest"): return
	if not check(hull.transform.basis.is_equal_approx(hull_rest),"Hull should settle level"): return
	fx.player.advance(2.0); fx._process(0.0)
	if not check(fx.flash.scale.x < 0.01 and not fx.light.visible,"Flash should be out after the shot"): return
	for path in ["Muzzle_Smoke_1","Muzzle_Smoke_5"]:
		if not check(fx.get_node("Model/"+path).scale.x < 0.01,"Smoke should be gone after the shot"): return
	# A target closer than the barrel is long: the round goes off at the muzzle, not backwards.
	foe.global_position = origin+Vector3(2.5,0,0)
	await process_frame
	var near: Vector3 = model.muzzle_position()
	if not check(tank._shot_end(near,foe,foe.global_position).is_equal_approx(near),"Point-blank shot should land at the muzzle"): return
	print("TANK_FIRE_TEST_PASSED"); quit()
