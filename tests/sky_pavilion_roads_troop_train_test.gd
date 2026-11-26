extends SceneTree
# Headless (item 7 of the Round 3 handoff; docs/ROUND3_TROOP_TRAINS.md):
# - Troop cars: a Knights train loads 6 Food crates (150) and takes 6 Round Table Marines aboard (150), its whole
#   300; a seventh is refused, and so is a Tank. Riders still take their housing. They get off at a station, and a
#   derailment throws them out with a quarter of their health gone and slowed.
# - Forward Railhead: 30 iron, 4 x 4, only beside friendly track. A Knights train carries the 6 Food crates and
#   6 Marines out to one beyond the Keep's range, sets the crates down round it and lets the Marines off there.
var game: Node3D
var network: Node
var rails: Node
## The piece laid from the Keep's loading area for the train.
var track: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func open(path: String) -> void:
	if is_instance_valid(game): game.free()
	game = load(path).instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	network = game.get_node("DepotNetwork")
	rails = game.get_node("RailNetwork")
	game.set_process(false)
	game.get_node("Interface").set_process(false)
	for name in ["EnemyPlayer","KnightsPlayer"]:
		var ai = game.get_node_or_null(name)
		if ai != null: ai.set_process(false)
	for group in ["units","depots","production_buildings","farms","houses","energy_generators","mines"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	for fog in get_nodes_in_group("fog_of_war"): fog.free()
func place(node: Node3D, point: Vector3) -> void:
	for cell in node._claimed.duplicate(): node._release(cell)
	node._stop_route()
	node.grid_position = game.ground.nearest_actor_cell(game.ground.get_tile_at_position(point),node.mobility_layer(),node._owner_key())
	node.global_position = game.ground.tile_to_world(node.grid_position)
	node._claim(node.grid_position)
func step(nodes: Array, seconds: float, until := Callable()) -> float:
	var t := 0.0
	while t < seconds:
		for node in nodes:
			if is_instance_valid(node) and node.is_inside_tree(): node._process(1.0/30)
		t += 1.0/30
		if until.is_valid() and until.call(): break
	return t
func spawn(scene: String, team: String, point: Vector3) -> Node3D:
	var unit = load(scene).instantiate()
	unit.team = team
	game.get_node("Entities/Units").add_child(unit)
	unit.set_process(false)
	place(unit,point)
	return unit
func keep_of(team: String) -> Node3D:
	for node in get_nodes_in_group("keeps"):
		if node.team == team: return node
	return null
## Lays a straight from the Keep's loading area, trying a ring of spots and headings (as knights_rail_test does).
func lay_from(keep: Node3D) -> Node3D:
	var reach: float = rails.depot_reach(keep)
	for angle in range(0,360,15):
		var out := Vector3.FORWARD.rotated(Vector3.UP,deg_to_rad(angle))
		for d in [reach-2.0,reach-4.0,reach-6.0]:
			var piece = rails.place("straight",keep.global_position+out*d,out,0,keep)
			if piece != null: return piece
	return null
## A Dragon Yard and track at the player's Keep, and a Knights train built there.
func knights_train(keep: Node3D) -> Node3D:
	for kind in [&"food",&"wood",&"iron"]: keep.stockpile.deposit(kind,400)
	keep.stockpile.deposit(&"coal",100)
	var plan = null
	for offset in [Vector3(-14,0,8),Vector3(14,0,-12),Vector3(-12,0,-14),Vector3(10,0,14),Vector3(0,0,-18),Vector3(18,0,0),Vector3(-16,0,0),Vector3(0,0,16)]:
		plan = network.queue_plan(keep.global_position+offset,&"dragon_yard",keep,true,false)
		if is_instance_valid(plan): break
	if not is_instance_valid(plan): return null
	plan.complete_from_stock()
	await process_frame
	track = lay_from(keep)
	if track == null: return null
	if not keep.request_train(): return null
	for i in range(31*10): keep._process(0.1)
	for node in get_nodes_in_group("rail_trains"):
		if node.team == "player" and node.get("coal_fuelled") == true:
			node.set_process(false)
			return node
	return null
## Lays `count` more straights on from the free end of `piece` furthest from `keep`, paid by the Keep.
func extend(piece: Node3D, keep: Node3D, count: int) -> Node3D:
	var last := piece
	for i in range(count):
		var far: Dictionary = {}
		for end in last.ends():
			if far.is_empty() or end.position.distance_to(keep.global_position) > far.position.distance_to(keep.global_position): far = end
		var spot: Dictionary = rails.placement("straight",far.position,far.out)
		if spot.is_empty(): return null
		var next: Node3D = rails.lay("straight",spot.transform,keep)
		if next == null: return null
		last = next
	return last
func run() -> void:
	if not await troop_train(): return
	if not await railhead(): return
	game.free()
	print("SKY_PAVILION_ROADS_TROOP_TRAIN_TEST_PASSED")
	quit(0)
func troop_train() -> bool:
	await open("res://scenes/maps/arthurian_skirmish.tscn")
	var keep := keep_of("player")
	var train: Node3D = await knights_train(keep)
	if not check(train != null,"A Knights train should stand at the Keep"): return false
	if not check(train.station() == keep,"The new train stands at its Keep's stop"): return false
	# Food on the train: six crates, 150.
	train.manifest = {&"food": 6}
	if not check(train.load_crates(keep,keep.global_position) == 6 and train.crate_units(&"food") == 150,"The train should load 6 Food crates: %d" % train.crate_units(&"food")): return false
	if not check(train.free_slots() == 6,"Six slots left for riders: %d" % train.free_slots()): return false
	# Six Marines board; a seventh is refused.
	var marines: Array[Node3D] = []
	for i in range(7):
		marines.append(spawn("res://scenes/gameplay/round_table_marine.tscn","player",train.global_position+Vector3(4+i%3*2,0,4+i/3*2)))
	var housed := KnightHousing.used(self,"player")
	for i in range(6): marines[i].command_board(train)
	step(marines.slice(0,6),20.0,func(): return train.passengers.size() == 6)
	if not check(train.passengers.size() == 6 and train.free_slots() == 0 and train.stockpile.reserved == 300,"Six Marines should ride, filling the train: %d aboard, %d free, %d reserved ('%s')" % [train.passengers.size(),train.free_slots(),train.stockpile.reserved,marines[0].state]): return false
	if not check(marines.slice(0,6).all(func(m): return not m.is_inside_tree()),"Riders leave the field"): return false
	if not check(KnightHousing.used(self,"player") == housed,"Riders still take their housing: %d -> %d" % [housed,KnightHousing.used(self,"player")]): return false
	marines[6].command_board(train)
	if not check(marines[6].order != "board" and marines[6].state.contains("full"),"A seventh rider should be refused: '%s'" % marines[6].state): return false
	# A Tank never boards.
	var tank := spawn("res://scenes/gameplay/tank.tscn","player",train.global_position+Vector3(-6,0,-6))
	tank.command_board(train)
	if not check(tank.order != "board" and TroopCars.refusal(tank,train).begins_with("Only foot soldiers"),"A Tank should be refused: '%s'" % tank.state): return false
	# They get off at the Keep's stop.
	if not check(train.disembark() == 6 and train.passengers.is_empty() and train.free_slots() == 6,"All six should get off"): return false
	if not check(marines.slice(0,6).all(func(m): return m.is_inside_tree() and m.global_position.distance_to(train.global_position) < 12.0 and m.health == m.max_health),"Riders stand by the train, unhurt"): return false
	# A derailment throws riders out hurt and slowed.
	for i in range(3): marines[i].command_board(train)
	step(marines.slice(0,3),20.0,func(): return train.passengers.size() == 3)
	if not check(train.passengers.size() == 3,"Three should board again: %d" % train.passengers.size()): return false
	train.derail()
	await process_frame
	for i in range(3):
		var m: Node3D = marines[i]
		if not check(m.is_inside_tree() and m.health == m.max_health-roundi(m.max_health*0.25),"A thrown rider loses a quarter of its health: %d / %d" % [m.health,m.max_health]): return false
		if not check(m._slow_left > 0.0 and is_equal_approx(m._slow_factor,0.6),"A thrown rider is slowed to 0.6x"): return false
	marines[3].command_board(train)
	if not check(train.passengers.is_empty() and marines[3].order != "board" and marines[3].state.contains("derailed"),"A derailed train takes nobody: '%s'" % marines[3].state): return false
	return true
func railhead() -> bool:
	await open("res://scenes/maps/arthurian_skirmish.tscn")
	var keep := keep_of("player")
	var train: Node3D = await knights_train(keep)
	if not check(train != null,"A Knights train should stand at the Keep"): return false
	var spec: Dictionary = network.plan_spec(&"railhead")
	if not check(spec.iron == 30 and spec.energy == 0 and spec.size == Vector2i(4,4),"A Railhead is 4 x 4 for 30 iron: %s" % spec): return false
	# Track on past the Keep's range, and a Railhead beside its far end.
	var far_piece := extend(track,keep,5)
	if not check(far_piece != null,"Track should run on from the Keep: "+game.message): return false
	var end: Dictionary = {}
	for e in far_piece.ends():
		if end.is_empty() or e.position.distance_to(keep.global_position) > end.position.distance_to(keep.global_position): end = e
	var side: Vector3 = (end.out as Vector3).cross(Vector3.UP).normalized()
	var spot: Vector3 = end.position-end.out*3.0+side*(2.0+far_piece.half_width()+1.0)
	if not check(spot.distance_to(keep.global_position) > SupplySource.radius(keep),"The Railhead stands beyond the Keep's range: %.1f m" % spot.distance_to(keep.global_position)): return false
	# Open ground away from the track: refused.
	var away := Vector3.INF
	for angle in range(0,360,20):
		var probe: Vector3 = keep.global_position+Vector3.FORWARD.rotated(Vector3.UP,deg_to_rad(angle))*24.0
		var start: Vector2i = network.footprint_start(probe,spec.size)
		if away == Vector3.INF and network.plan_terrain_valid(start,spec.size,&"railhead") and not network.plan_overlaps(start,spec.size) and not rails.track_beside(start,spec.size,"player"): away = probe
	if not check(away != Vector3.INF and network.queue_plan(away,&"railhead",null,false,false) == null and game.message == network.RAILHEAD_NOTICE,"A Railhead away from track is refused: '%s'" % game.message): return false
	var plan = network.queue_plan(spot,&"railhead",null,false,false)
	if not check(plan != null,"A Railhead beside the track should be planned: "+game.message): return false
	var head: Node3D = network.finish_plan(plan)
	plan.queue_free()
	if not check(is_instance_valid(head) and head.is_in_group("railheads") and game.get_node("Interface").object_name(head) == "Railhead","It stands as a Railhead"): return false
	head.set_process(false)
	# Food and six Marines aboard at the Keep: the whole 300.
	train.manifest = {&"food": 6}
	train.load_crates(keep,keep.global_position)
	var marines: Array[Node3D] = []
	for i in range(6):
		var m := spawn("res://scenes/gameplay/round_table_marine.tscn","player",train.global_position+Vector3(4+i%3*2,0,4+i/3*2))
		m.command_board(train)
		marines.append(m)
	step(marines,20.0,func(): return train.passengers.size() == 6)
	if not check(train.passengers.size() == 6 and train.crate_units(&"food") == 150 and train.free_slots() == 0,"150 Food and 6 Marines should fill the train"): return false
	# Out to the Railhead: Unload sets the crates down round it.
	train.command_unload(head)
	if not check(train.order == "unload","The train should take Unload to the Railhead: '%s'" % train.state): return false
	var ran := step([train],90.0,func(): return train.crates.is_empty() and train.station() == head)
	if not check(train.crates.is_empty() and train.station() == head,"The train should reach the Railhead and set its crates down: %.0f s, '%s'" % [ran,train.state]): return false
	var crates: Array = CrateYard.beside(head).filter(func(c): return c.resource_kind == &"food")
	if not check(crates.size() == 6,"Six Food crates should lie round the Railhead: %d" % crates.size()): return false
	if not check(train.passengers.size() == 6,"The riders stay aboard through Unload"): return false
	if not check(train.disembark() == 6 and marines.all(func(m): return m.is_inside_tree() and m.global_position.distance_to(head.global_position) < 14.0),"The Marines should get off at the Railhead"): return false
	# Another train run there picks the crates up again.
	train.manifest = {}
	if not check(train.load_crates(head,head.global_position) == 6 and train.crate_units(&"food") == 150,"A train at the Railhead picks its crates up: %d" % train.crate_units(&"food")): return false
	return true
