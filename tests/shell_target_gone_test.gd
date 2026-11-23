extends SceneTree
# Headless: a tank shell in flight whose target dies flies on to the ground and bursts there, with splash for any
# hostile beside the burst and none for friendlies (docs/TURRET_AIM.md); one whose shooter dies still lands and
# goes. Neither hangs in the air.
const Projectile = preload("res://scripts/gameplay/projectile.gd")
const Burst = preload("res://scripts/components/burst_effect.gd")
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
func shells() -> Array:
	return game.get_children().filter(func(n): return n.get_script() == Projectile)
## Brings the turret round and fires one shell; returns it, held still.
func fire(tank: Node3D) -> Node3D:
	var turret = tank._turret()
	tank._cooldown = 2.0
	for i in range(100):
		tank._process(1.0/60)
		turret._process(1.0/60)
	for i in range(80):
		tank._process(1.0/60)
		if not shells().is_empty(): break
		turret._process(1.0/60)
	if shells().is_empty(): return null
	var shell: Node3D = shells()[0]
	shell.set_process(false)
	return shell
func fly(shell: Node3D) -> int:
	var steps := 0
	while is_instance_valid(shell) and not shell.is_queued_for_deletion() and steps < 300:
		shell._process(1.0/60)
		steps += 1
	return steps
func run() -> void:
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	for node in get_nodes_in_group("units"): node.set_process(false)
	var origin := Vector3(180,0,180)
	for gone in ["target","shooter"]:
		var tank := actor("tank","player",origin)
		var foe := actor("hostile","enemy",origin+Vector3(24,0,0))
		tank.attack_range = 28.0
		await process_frame
		var shell := fire(tank)
		if not check(shell != null,"Tank did not fire (%s case)" % gone): return
		shell._process(1.0/60)
		var aim: Vector3 = shell.impact_point()
		(foe if gone == "target" else tank).free()
		var bystanders: Array = []
		if gone == "target":
			# It flies to where the target was, then sets off for the ground.
			var guard := 0
			while shell.impact_point() == aim and guard < 300:
				shell._process(1.0/60); guard += 1
			var ground: Vector3 = shell.impact_point()
			if not check(absf(ground.y) < 0.05 and ground.x > aim.x+1.0,"The shell should head on to the ground past its target: %s from %s" % [ground,aim]): return
			bystanders = [actor("hostile","enemy",Vector3(ground.x,0,ground.z+1.5)),actor("infantry","player",Vector3(ground.x,0,ground.z-1.5))]
			for b in bystanders: b.set_meta("was",b.health)
		var steps := fly(shell)
		if not check(steps < 300,"Shell hung in the air after its %s died" % gone): return
		var bursts := game.get_children().filter(func(n): return n.get_script() == Burst and not n.is_queued_for_deletion())
		if not check(bursts.size() == 1,"One burst should show, got %d" % bursts.size()): return
		if gone == "target":
			if not check(absf(bursts[0].global_position.y) < 0.05,"The burst should be on the ground: %s" % bursts[0].global_position): return
			if not check(bystanders[0].health < bystanders[0].get_meta("was"),"A hostile beside the burst should take splash"): return
			if not check(bystanders[1].health == bystanders[1].get_meta("was"),"Splash should spare friendlies"): return
		for b in bursts: b.free()
		await process_frame
		if not check(not is_instance_valid(shell),"Shell should be gone after its %s died" % gone): return
		for node in bystanders+[tank,foe]:
			if is_instance_valid(node): node.free()
		await process_frame
	print("SHELL_TARGET_GONE_TEST_PASSED"); quit()
