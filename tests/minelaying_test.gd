extends SceneTree
# Headless (item 9 of docs/BALANCE_IMPLEMENTATION_HANDOFF.md, docs/MINES.md): the Derailer costs 60 E / 25 I (Round 3). Before
# Minelaying is researched it cannot buy mines; after, inside a friendly Depot's range, Buy mine (Q) buys one for
# 10 iron a click, up to two, and nothing loads by itself. Lay mine is E and Derail R. It lays one at a point in 2 s; the mine arms after 3 s and is then hidden from the other side,
# shown to it only near one of its detectors (a Drone within 20 m, a Warhound within 10 m, a Depot at its range).
# An enemy ground unit within 2 m sets it off: 60 damage to it, 30 to others within 3 m.
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func spawn(id: String, team: String, point: Vector3) -> Node3D:
	var unit = load("res://scenes/gameplay/%s.tscn" % id).instantiate()
	unit.team = team
	unit.position = point
	game.get_node("Entities/Units").add_child(unit,true)
	unit.set_process(false)
	return unit
func step(unit: Node3D, seconds: float) -> void:
	for i in range(ceili(seconds*30)): unit._process(1.0/30)
func run() -> void:
	var stats: UnitStats = load("res://assets/units/motorcycle.tres")
	if not check(stats.energy_cost == 60 and stats.iron_cost == 25,"The Derailer costs 60 E / 25 I"): return
	var temple = load("res://scenes/gameplay/temple_of_science.tscn").instantiate()
	var temple_research: Array = temple.research
	temple.free()
	if not check(temple_research.any(func(r): return r.research_id == Research.MINELAYING and r.energy_cost == 150 and r.iron_cost == 100 and r.seconds == 60.0),"The Temple researches Minelaying for 150 E / 100 I in 60 s"): return
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	for i in range(3): await process_frame
	game.set_process(false)
	game.vehicle_fuel_required = false
	for group in ["units","depots","mines"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	for node in get_nodes_in_group("enemies"): node.queue_free()
	var depot = game.depot
	depot.stockpile.deposit(&"iron",100)
	var derailer := spawn("motorcycle","player",depot.global_position+Vector3(10,0,12))
	await process_frame
	# The keys: Buy mine Q, Lay mine E, Derail R.
	for pair in [["command_buy_mine",KEY_Q],["command_lay_mine",KEY_E],["command_derail",KEY_R]]:
		var events := InputMap.action_get_events(pair[0])
		if not check(not events.is_empty() and events[0].physical_keycode == pair[1],"%s should be on %s" % [pair[0],OS.get_keycode_string(pair[1])]): return
	# Not researched: it can't buy one.
	var iron: int = depot.stockpile.amount(&"iron")
	if not check(not derailer.command_buy_mine() and derailer.mines == 0 and depot.stockpile.amount(&"iron") == iron and derailer.buy_mine_blocker().contains("Research"),"Without Minelaying a Derailer should not buy mines"): return
	# Researched: nothing loads by itself; each click buys one, up to two, from the covering Depot.
	Research.complete(game,"player",Research.MINELAYING)
	step(derailer,3.0)
	if not check(derailer.mines == 0 and depot.stockpile.amount(&"iron") == iron,"Mines should no longer load by themselves"): return
	if not check(derailer.command_buy_mine() and derailer.mines == 1 and depot.stockpile.amount(&"iron") == iron-10,"Buy mine should buy one for 10 iron"): return
	if not check(derailer.command_buy_mine() and derailer.mines == 2 and depot.stockpile.amount(&"iron") == iron-20,"A second click buys a second"): return
	if not check(not derailer.command_buy_mine() and derailer.buy_mine_blocker().begins_with("Full"),"It carries two at most"): return
	# Lay one well away from the Depot's range.
	var spot: Vector3 = depot.global_position+Vector3(SupplySource.radius(depot)+18.0,0,12)
	derailer.command_lay_mine(spot)
	if not check(derailer.order == "lay_mine","The Derailer should take the Lay mine order: %s" % derailer.state): return
	var mine: Node3D = null
	for i in range(60*30):
		derailer._process(1.0/30)
		if not get_nodes_in_group("land_mines").is_empty(): mine = get_nodes_in_group("land_mines")[0]; break
	if not check(mine != null and derailer.mines == 1 and mine.team == "player","The Derailer should lay a mine and have one left (%s)" % derailer.state): return
	mine.set_process(false)
	if not check(not mine.armed and mine.shown_to("enemy"),"A mine just laid is not armed yet"): return
	step(mine,3.2)
	if not check(mine.armed and not mine.shown_to("enemy") and mine.shown_to("player"),"Armed, it is hidden from the other side and shown to its own"): return
	# Detectors.
	var drone := spawn("drone","enemy",mine.global_position+Vector3(15,0,0))
	drone.global_position = mine.global_position+Vector3(15,0,0)
	if not check(mine.shown_to("enemy") and mine.detected_by("enemy"),"An enemy Drone within 20 m detects it"): return
	drone.global_position = mine.global_position+Vector3(25,0,0)
	if not check(not mine.shown_to("enemy"),"A Drone 25 m off does not"): return
	drone.queue_free()
	var hound := spawn("warhound","enemy",mine.global_position+Vector3(18,0,0))
	hound.global_position = mine.global_position+Vector3(18,0,0)
	if not check(not mine.shown_to("enemy"),"A Warhound 18 m off does not detect it"): return
	hound.global_position = mine.global_position+Vector3(12,0,0)
	if not check(mine.shown_to("enemy"),"A Warhound within 15 m does"): return
	var scout := spawn("scout","enemy",mine.global_position+Vector3(30,0,0))
	hound.global_position = mine.global_position+Vector3(80,0,0)
	if not check(not scout.team_sees(mine),"An undetected mine can't be targeted"): return
	hound.queue_free()
	await process_frame
	# Set off: 60 to the unit on it, 30 to one within 3 m.
	var victim := spawn("infantry","enemy",mine.global_position+Vector3(1.0,0,0))
	var neighbour := spawn("infantry","enemy",mine.global_position+Vector3(0,0,2.7))
	victim.global_position = mine.global_position+Vector3(1.0,0,0)
	neighbour.global_position = mine.global_position+Vector3(0,0,2.7)
	victim.health = 200
	neighbour.health = 200
	step(mine,0.3)
	if not check(victim.health == 140 and neighbour.health == 170,"The mine should do 60 to the unit on it and 30 to one 2.7 m off (%d, %d)" % [victim.health,neighbour.health]): return
	await process_frame
	if not check(get_nodes_in_group("land_mines").is_empty(),"A mine that went off is gone"): return
	# A mine can be selected, and once detected the other side can order an attack on it and shoot it.
	var target: Node3D = load("res://scenes/gameplay/land_mine.tscn").instantiate()
	target.team = "player"
	game.get_node("Entities").add_child(target)
	target.global_position = spot+Vector3(0,0,8)
	target.set_process(false)
	step(target,3.2)
	game.selected_building = target
	if not check(game.hud.selected_object() == target,"A mine of yours can be selected and inspected"): return
	game.hud._process(0)
	if not check(game.hud.name_label.text == "Land mine","The card names the mine"): return
	var head_icon: Texture2D = game.hud.info.get_node("Head/Icon").texture
	var portrait: TextureRect = game.hud.get_node("Bottom/Body/Row/Ornament/Portrait")
	if not check(head_icon != null and head_icon.resource_path.ends_with("renders/land_mine.png") and portrait.visible and portrait.texture.resource_path.ends_with("portraits/land_mine.png"),"The mine's card shows its own icon and portrait"): return
	var camera := game.get_viewport().get_camera_3d()
	camera.global_position = target.global_position+Vector3(0,14,10)
	camera.look_at(target.global_position)
	if not check(get_root().get_node("SelectionManager").pick_object(camera.unproject_position(target.global_position+Vector3(0,0.1,0))) == target,"A click on the mine's model picks it"): return
	game.selected_building = null
	var gunner := spawn("infantry","enemy",target.global_position+Vector3(6,0,0))
	gunner.global_position = target.global_position+Vector3(6,0,0)
	gunner.command_attack(target)
	if not check(gunner.order == "attack" and not gunner.team_sees(target),"An attack can be ordered, but an undetected mine isn't shot"): return
	var spotter := spawn("warhound","enemy",target.global_position+Vector3(-6,0,0))
	spotter.global_position = target.global_position+Vector3(-6,0,0)
	for i in range(20*30):
		gunner._process(1.0/30)
		if not is_instance_valid(target) or target.health <= 0: break
	if not check(not is_instance_valid(target) or target.health <= 0,"Detected, the ordered attack destroys the mine"): return
	print("MINELAYING_TEST_PASSED")
	quit(0)
