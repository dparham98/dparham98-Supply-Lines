extends SceneTree
# Headless (docs/KNIGHTS_TIDY.md): the Chapterhouse has no production-speed setting and a Marine takes its listed
# time; each faction's Build page shows only its own buildings (mines for both); and the Cyborg AI keeps a Drone
# over the centre of the ground units it goes with while they move.
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
	for group in ["units","depots","mines","energy_generators","production_buildings"]:
		for node in get_nodes_in_group(group): node.set_process(false)
func shown_tiles() -> Array[String]:
	var hud = game.get_node("Interface")
	hud.refresh_global_menu()
	var names: Array[String] = []
	for name in ["Depot","Generator","Barracks","TankFactory","Temple","Mine","CoalMine","Rail","Keep","Chapterhouse"]:
		if hud.build_menu.get_node("Actions/"+name).visible: names.append(name)
	return names
func run() -> void:
	var setup = root.get_node("MatchSetup")
	# 1. The Chapterhouse: no speed setting, and a Marine takes its listed time.
	await load_map("res://scenes/maps/arthurian_skirmish.tscn")
	var chapterhouse = game.get_node("Entities/Buildings/Chapterhouse")
	if not check(chapterhouse.stats.max_power == 1.0,"The Chapterhouse should have no speed above 1x: %s" % chapterhouse.stats.max_power): return
	chapterhouse.set_power(4.0)
	if not check(chapterhouse.power == 1.0,"Setting the Chapterhouse to 4x should leave it at 1x: %s" % chapterhouse.power): return
	var marine: PackedScene = load("res://scenes/gameplay/round_table_marine.tscn")
	var listed: float = load("res://assets/units/round_table_marine.tres").build_seconds
	if not check(is_equal_approx(chapterhouse.seconds_at_power(marine),listed),"A Marine should take its listed %s s, not %s" % [listed,chapterhouse.seconds_at_power(marine)]): return
	var hud = game.get_node("Interface")
	hud.shown = chapterhouse
	hud.update_production_panel(null)
	if not check(not hud.production_panel.visible,"The Chapterhouse should show no production-speed panel"): return
	for path in ["res://assets/buildings/barracks.tres","res://assets/buildings/tank_factory.tres"]:
		if not check(load(path).max_power > 1.0,"%s should keep its speed setting" % path): return
	# 2. Build pages: the Knights (a scene run straight, with a Keep and no Depot of the player's).
	var knights := shown_tiles()
	if not check(knights == ["Mine","CoalMine","Keep","Chapterhouse"],"The Knights' Build page should show only their own buildings and mines: %s" % [knights]): return
	# The Cyborgs (a scene run straight, with a Depot).
	await load_map("res://scenes/maps/resource_skirmish.tscn")
	var cyborgs := shown_tiles()
	if not check(cyborgs == ["Depot","Generator","Barracks","TankFactory","Temple","Mine","CoalMine","Rail"],"The Cyborgs' Build page should show only their own buildings and mines: %s" % [cyborgs]): return
	# A configured match goes by its faction setting.
	setup.configured = true
	setup.factions = {"player": &"arthurian_knights", "enemy": &"cyborgs"}
	var configured := shown_tiles()
	setup.configured = false
	setup.factions = {"player": &"cyborgs", "enemy": &"cyborgs"}
	if not check(configured == ["Mine","CoalMine","Keep","Chapterhouse"],"A configured Knights match should show the Knights' page: %s" % [configured]): return
	# 3. The Cyborg AI keeps a Drone behind its wave's front Tank while the wave moves (Round 3,
	# docs/ROUND3_CYBORG_ECONOMY.md): within `drone_behind_front` of it and never ahead of it.
	await load_map("res://scenes/maps/lakes_skirmish.tscn")
	var ai = game.enemy_player()
	ai.set_process(false)
	var depot: Node3D = ai.home()
	var start: Vector3 = depot.global_position+Vector3(-30,0,0)
	var ground: Array[Node3D] = []
	for i in range(4):
		var unit = load("res://scenes/gameplay/tank.tscn" if i < 2 else "res://scenes/gameplay/infantry.tscn").instantiate()
		unit.team = "enemy"
		game.get_node("Entities/Units").add_child(unit)
		unit.set_process(false)
		unit._stop_route()
		for cell in unit._claimed.duplicate(): unit._release(cell)
		unit.grid_position = game.ground.nearest_actor_cell(game.ground.get_tile_at_position(start+Vector3(0,0,i*3)),unit.mobility_layer(),unit._owner_key())
		unit.global_position = game.ground.tile_to_world(unit.grid_position)
		unit._claim(unit.grid_position)
		ground.append(unit)
	var drone = load("res://scenes/gameplay/drone.tscn").instantiate()
	drone.team = "enemy"
	game.get_node("Entities/Units").add_child(drone)
	drone.set_process(false)
	drone.global_position = start
	var everyone: Array[Node3D] = ground.duplicate()
	everyone.append(drone)
	ai.army = everyone.duplicate()
	ai.wave = everyone.duplicate()
	var goal: Vector3 = start+Vector3(-120,0,0)
	# The wave's target, as a sighting would set it: the AI heads its escort the way the wave is sent.
	ai.known = {"test": goal}
	for unit in everyone: unit.command_attack_move(goal)
	var worst := 0.0
	var ahead := 0.0
	var moved := 0.0
	var from: Vector3 = ai._centre(ground)
	for second in range(20):
		for frame in range(60):
			for unit in everyone: unit._process(1.0/60)
		ai._escort_drones()
		var centre: Vector3 = ai._centre(ground)
		var front: Node3D = ai.tank_front(ground,goal)
		if not check(front != null,"The wave should have a front Tank"): return
		if second >= 2:
			worst = maxf(worst,Vector2(drone.global_position.x-front.global_position.x,drone.global_position.z-front.global_position.z).length())
			# Ahead means further west than the front Tank, the way the wave goes.
			ahead = maxf(ahead,front.global_position.x-drone.global_position.x)
		moved = from.distance_to(centre)
	if not check(moved > 20.0,"The wave should have moved: %.1f m" % moved): return
	if not check(worst <= ai.drone_behind_front+1.0,"The Drone should stay within %.0f m of the front Tank: %.1f m" % [ai.drone_behind_front,worst]): return
	if not check(ahead <= 1.0,"The Drone should not fly ahead of the front Tank: %.1f m" % ahead): return
	print("KNIGHTS_TIDY_TEST_PASSED")
	quit(0)
