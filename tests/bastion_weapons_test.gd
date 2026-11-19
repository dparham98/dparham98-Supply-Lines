extends SceneTree
# Headless: the Bastion's two weapons (docs/BASTION_TANK.md). The main gun fires from its 10 m minimum range out to
# its 30 m range and never nearer; ordered onto a target that close, the Tank backs off to the minimum range. The roof
# gun fires only at hostile units within 10 m, with its own round, and leaves anything farther to the main gun.
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
func shots(scene: String) -> Array:
	return root.find_children("*","",true,false).filter(func(n): return n is Projectile and n.scene_file_path == scene and not n.is_queued_for_deletion())
func run() -> void:
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	for node in get_nodes_in_group("units"): node.set_process(false)
	var origin := Vector3(180,0,180)
	var tank = actor("tank","player",origin)
	var roof: Node = tank.get_node("CloseDefense")
	roof.set_process(false)
	if not check(tank.min_attack_range == 10.0 and tank.attack_range == 30.0,"Main gun range should be 10-30: %s-%s" % [tank.min_attack_range,tank.attack_range]): return
	if not check(roof.attack_range == 10.0 and roof.damage == 3,"Roof gun should reach 10 m"): return
	if not check(tank.get_node("Visuals/Model").find_child("Aux_Turret",true,false) != null,"The model should carry the roof gun"): return
	# A hostile 6 m away: inside the main gun's minimum range.
	var near = actor("hostile","enemy",origin+Vector3(6,0,0))
	var turret = tank._turret()
	turret.aim_at(near.global_position); turret._yaw = turret.goal_yaw()
	tank._shoot(near)
	if not check(tank._cooldown <= 0.0 and shots("res://scenes/gameplay/tank_shell.tscn").is_empty(),"The main gun must not fire inside its minimum range"): return
	if not check(not tank.in_attack_range(near) and tank._nearest_opponent() == null,"A target inside the minimum range is not the main gun's"): return
	# The roof gun takes it.
	var health: int = near.health
	for frame in range(60):
		roof._process(1.0/60)
		for shot in shots("res://scenes/gameplay/aux_bullet.tscn"): shot._process(1.0/60)
	if not check(near.health < health and (health-near.health) % 3 == 0,"The roof gun should hit the near hostile: %d of %d" % [near.health,health]): return
	near.free()
	for shot in shots("res://scenes/gameplay/aux_bullet.tscn"): shot.free()
	# A hostile 15 m away: the main gun's, not the roof gun's.
	var far = actor("hostile","enemy",origin+Vector3(15,0,0))
	if not check(tank.in_attack_range(far) and tank._nearest_opponent() == far,"15 m is in the main gun's range"): return
	health = far.health
	for frame in range(60): roof._process(1.0/60)
	if not check(shots("res://scenes/gameplay/aux_bullet.tscn").is_empty() and far.health == health,"The roof gun must not fire beyond 10 m"): return
	turret.aim_at(far.global_position); turret._yaw = turret.goal_yaw()
	tank._shoot(far)
	if not check(tank._cooldown > 0.0,"The main gun fires at 15 m"): return
	far.free()
	# Ordered onto a hostile 4 m away, the Tank backs off until it is at the minimum range, then fires.
	var target = actor("hostile","enemy",origin+Vector3(4,0,0))
	tank._cooldown = 0.0
	tank.grid_position = game.ground.get_tile_at_position(origin)
	tank.command_attack(target)
	var seconds := 0.0
	var backed := false
	while seconds < 20.0 and not tank.in_attack_range(target):
		tank._process(1.0/30); seconds += 1.0/30
		if tank.state.begins_with("Backing off"): backed = true
	if not check(backed,"The Tank should back off from a target too close: %s" % tank.state): return
	if not check(tank.in_attack_range(target) and tank.order == "attack","The Tank should reach its minimum range and keep the order: %.1f m, %s" % [tank.global_position.distance_to(target.global_position),tank.state]): return
	var hud = game.get_node("Interface")
	hud.update_unit_sections(tank)
	if not check(hud.context.get_node("Abilities").text.contains("Roof gun"),"The card should list the roof gun"): return
	print("BASTION_WEAPONS_TEST_PASSED")
	quit(0)
