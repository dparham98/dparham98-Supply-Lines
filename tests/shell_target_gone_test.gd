extends SceneTree
# Headless: a tank shell in flight whose target dies, or whose shooter dies, still lands and goes away; it does not
# hang in the air.
const Projectile = preload("res://scripts/gameplay/projectile.gd")
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
		(foe if gone == "target" else tank).free()
		var steps := fly(shell)
		if not check(steps < 300,"Shell hung in the air after its %s died" % gone): return
		await process_frame
		if not check(not is_instance_valid(shell),"Shell should be gone after its %s died" % gone): return
		for node in [tank,foe]:
			if is_instance_valid(node): node.free()
		await process_frame
	print("SHELL_TARGET_GONE_TEST_PASSED"); quit()
