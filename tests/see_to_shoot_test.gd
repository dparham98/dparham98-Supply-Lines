extends SceneTree
# Headless (docs/SEE_TO_SHOOT.md): a unit fires only at what its side sees, by the fog of war; a map without fog sees
# everything; splash weapons do their splash share to units other than the one aimed at; the moving-fire arc is off
# (360) for every unit and limits shots when set; and the Tank's proposed numbers are in its stats.
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func load_map(path: String) -> void:
	if is_instance_valid(game): game.free()
	game = load(path).instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	game.set_process(false)
	game.get_node("Interface").set_process(false)
	for group in ["units","depots","mines","energy_generators","production_buildings","fog_of_war"]:
		for node in get_nodes_in_group(group): node.set_process(false)
func spawn(id: String, point: Vector3, team: String) -> Node3D:
	var unit = load("res://scenes/gameplay/"+id+".tscn").instantiate()
	unit.team = team
	game.get_node("Entities/Units").add_child(unit)
	unit.set_process(false)
	unit._stop_route()
	for cell in unit._claimed.duplicate(): unit._release(cell)
	unit.grid_position = game.ground.nearest_actor_cell(game.ground.get_tile_at_position(point),unit.mobility_layer(),unit._owner_key())
	unit.global_position = game.ground.tile_to_world(unit.grid_position)
	unit._claim(unit.grid_position)
	return unit
func run() -> void:
	# The Tank's numbers (docs/BALANCE_IMPLEMENTATION_HANDOFF.md, item 3).
	var tank_stats: UnitStats = load("res://assets/units/tank.tres")
	if not check(tank_stats.vision == 18.0 and tank_stats.movement_speed == 5.0 and tank_stats.attack_interval == 1.5 and tank_stats.damage == 12,"Tank sight 18 (Round 3), speed 5, 12 every 1.5 s"): return
	if not check(tank_stats.splash_radius == 2.0 and tank_stats.splash_share == 0.5,"Tank splash 2 m at half share"): return
	if not check(tank_stats.attack_range == 30.0 and tank_stats.min_attack_range == 10.0 and tank_stats.heavy_target_damage == 50 and tank_stats.heavy_target_interval == 3.0 and tank_stats.fire_while_moving,"Tank range, heavy attack and moving fire unchanged"): return
	if not check(tank_stats.energy_cost == 140 and tank_stats.iron_cost == 55,"Tank costs 140 E / 55 I (Round 3)"): return
	for id in ["grenadier","azure_dragon"]:
		if not check(load("res://assets/units/%s.tres" % id).splash_share == 0.5,"%s splash share should be half" % id): return
	for path in DirAccess.get_files_at("res://assets/units"):
		if not path.ends_with(".tres"): continue
		var stats = load("res://assets/units/"+path)
		if stats is UnitStats and not check(stats.moving_fire_arc == 360.0,"%s moving-fire arc should be off (360)" % path): return
	# Two Lakes has fog: a Tank does not fire at a Deforester in range it cannot see.
	await load_map("res://scenes/maps/lakes_skirmish.tscn")
	var fog = game.fog_of_war()
	var here: Vector3 = game.depot.global_position+Vector3(0,0,40)
	var tank = spawn("tank",here,"player")
	var foe = spawn("infantry",here+Vector3(25,0,0),"enemy")
	fog.update_now()
	var d: float = tank.global_position.distance_to(foe.global_position)
	if not check(d > tank.vision and d <= tank.attack_range and d >= tank.min_attack_range,"Test setup: the Deforester should be in range but beyond the Tank's sight (%.1f m)" % d): return
	if not check(not tank.team_sees(foe) and tank._nearest_opponent() == null,"A Tank should not pick a Deforester its side cannot see"): return
	tank.command_attack(foe)
	tank._process(1.0/60)
	if not check(tank.state != "Firing" and tank._cooldown == 0.0,"A Tank ordered onto an unseen target should not fire: '%s'" % tank.state): return
	# A spotter that sees it lets the Tank fire.
	var spotter = spawn("scout",foe.global_position+Vector3(-12,0,6),"player")
	fog.update_now()
	if not check(tank.team_sees(foe) and tank._nearest_opponent() == foe,"With a Scout seeing it, the Tank should pick the Deforester"): return
	# Buildings count as sight, as the fog does: a Depot sees round itself.
	spotter.free()
	fog.update_now()
	var depot_foe = spawn("infantry",game.depot.global_position+Vector3(0,0,30),"enemy")
	fog.update_now()
	if not check(tank.team_sees(depot_foe),"A Depot's sight should count for its side"): return
	# A map with no fog sees everything.
	await load_map("res://scenes/maps/resource_skirmish.tscn")
	var open: Vector3 = game.depot.global_position+Vector3(10,0,10)
	var tank2 = spawn("tank",open,"player")
	var far_foe = spawn("infantry",open+Vector3(25,0,0),"hostile")
	if not check(game.fog_of_war() == null and tank2.team_sees(far_foe),"With no fog a unit should see its target"): return
	# Splash: the target takes the full hit, other units the share, buildings the full hit.
	var by = spawn("infantry",far_foe.global_position+Vector3(1,0,0),"hostile")
	if not check(CombatResolver.splash_damage(tank2,far_foe,far_foe) == 12 and CombatResolver.splash_damage(tank2,by,far_foe) == 6,"Tank splash: 12 to the target, 6 to a bystander"): return
	var grenadier = spawn("grenadier",open+Vector3(0,0,6),"player")
	if not check(CombatResolver.splash_damage(grenadier,by,far_foe) == 10,"Grenadier splash: 10 to a bystander"): return
	var health_before: int = by.health
	CombatResolver.strike_at(tank2,far_foe,far_foe.global_position)
	if not check(health_before-by.health == 6,"A shell bursting should take 6 from a bystander, took %d" % (health_before-by.health)): return
	if not check(CombatResolver.splash_damage(tank2,game.depot,far_foe) == CombatResolver.damage_for(tank2,game.depot),"A building caught in the splash takes the full hit"): return
	# The moving-fire arc: off at 360; at 90 it allows a target ahead and refuses one behind.
	var facing: float = tank2.get_node("Visuals").rotation.y
	var ahead: Vector3 = tank2.global_position+Vector3(-sin(facing),0,-cos(facing))*15.0
	var behind: Vector3 = tank2.global_position-Vector3(-sin(facing),0,-cos(facing))*15.0
	var probe_ahead := Node3D.new(); probe_ahead.position = ahead; game.add_child(probe_ahead)
	var probe_behind := Node3D.new(); probe_behind.position = behind; game.add_child(probe_behind)
	if not check(tank2._in_moving_arc(probe_behind,facing),"At 360 the arc should allow any target"): return
	tank2.unit_stats = tank2.unit_stats.duplicate()
	tank2.unit_stats.moving_fire_arc = 90.0
	if not check(tank2._in_moving_arc(probe_ahead,facing) and not tank2._in_moving_arc(probe_behind,facing),"A 90° arc should allow ahead and refuse behind"): return
	print("SEE_TO_SHOOT_TEST_PASSED")
	quit(0)
