extends SceneTree
# Headless (item 7 of the Round 3 handoff; docs/ROUND3_TROOP_TRAINS.md):
# - Troop cars: a Knights train loads 6 Food crates (150) and takes 6 Round Table Marines aboard (150), its whole
#   300; a seventh is refused, and so is a Tank. Riders still take their housing. They get off at a station, and a
#   derailment throws them out with a quarter of their health gone and slowed.
# - Forward Railhead: 30 iron, 4 x 4, only beside friendly track. A Knights train carries the 6 Food crates and
#   6 Marines out to one beyond the Keep's range, sets the crates down round it and lets the Marines off there.
# - Sky-Pavilion (docs/ROUND3_SKY_PAVILION.md): Found Keep (P) charters one for 50 W / 50 I / 45 F and 1 housing. It
#   flies only to land the side has explored, unfolds there into an empty Keep with a Forester Maiden, and on a site
#   blocked by the time it lands sets down 2 Wood and 2 Iron crates and the Maiden instead.
# - Supply Balloon manifest: Launch balloon opens the Load tiles as a manifest of up to 4 crates from the Keep's
#   stock (Food, Wood, Iron, Coal); the balloon carries them to explored land out of sight. With no manifest set
#   it still takes the crates packed beside the Keep.
var game: Node3D
var network: Node
var rails: Node
## The piece laid from the Keep's loading area for the train.
var track: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func open(path: String, keep_fog := false) -> void:
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
	for fog in get_nodes_in_group("fog_of_war"):
		if keep_fog: fog.set_process(false)
		else: fog.free()
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
	if not await pavilion(): return
	if not await balloon(): return
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
	# The HUD offers it to a train as a Load/Unload stop.
	var hud = game.get_node("Interface")
	game.selected_building = null
	for u in get_nodes_in_group("units"): u.set_selected(u == train)
	game.pending_unit_command = "unload"
	if not check(hud.pick_stops().has(head) and hud.pick_stops().has(keep),"Unload should offer a train the Railhead and the Keep as stops"): return false
	game.cancel_armed()
	train.set_selected(false)
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
func maidens(team: String) -> Array:
	return get_nodes_in_group("units").filter(func(u): return u.team == team and u.get("unit_stats") != null and u.unit_stats.unit_id == &"forester_maiden")
## Flies `pavilion` until it has landed and gone.
func fly(pavilion: Node3D) -> bool:
	var id := pavilion.get_instance_id()
	for i in range(160):
		step([pavilion],0.5)
		await process_frame
		if not is_instance_id_valid(id) or instance_from_id(id).is_queued_for_deletion(): break
	await process_frame
	return not is_instance_id_valid(id) or instance_from_id(id).is_queued_for_deletion()
func pavilion() -> bool:
	# Two Lakes with the Knights at home, for its fog of war.
	var setup = root.get_node("MatchSetup")
	setup.configured = true
	setup.mode = "ai"
	setup.map_id = "two_lakes"
	setup.factions = {"player": &"arthurian_knights", "enemy": &"cyborgs"}
	await open(setup.map_path(),true)
	setup.configured = false
	var keep := keep_of("player")
	var fog: Node = game.fog_of_war()
	if not check(keep != null and fog != null,"Two Lakes should give the Knights a Keep and keep its fog"): return false
	var stats: UnitStats = keep.unit_stats_for_kind("sky_pavilion")
	if not check(stats.unit_id == &"sky_pavilion" and stats.wood_cost == 50 and stats.iron_cost == 50 and stats.food_cost == 45 and is_equal_approx(stats.build_seconds,15.0),"A Sky-Pavilion costs 50 W / 50 I / 45 F and takes 15 s"): return false
	if not check(stats.max_health == 80 and KnightHousing.cost(&"sky_pavilion") == 1,"It has 80 health and takes 1 housing"): return false
	# A Keep site well beyond the Keep's range that the side hasn't seen.
	var site = null
	for d in [110.0,130.0,90.0,150.0]:
		for angle in range(0,360,20):
			var point: Vector3 = keep.global_position+Vector3.FORWARD.rotated(Vector3.UP,deg_to_rad(angle))*d
			if network.keep_site_refusal(point,"player").is_empty() and not fog.explored_by("player",point): site = point; break
		if site != null: break
	if not check(site != null,"There should be unexplored open land for a Keep within 150 m"): return false
	for kind in [&"food",&"wood",&"iron"]: keep.stockpile.deposit(kind,200)
	var food: int = keep.stockpile.amount(&"food"); var wood: int = keep.stockpile.amount(&"wood"); var iron: int = keep.stockpile.amount(&"iron")
	if not check(keep.pavilion_refusal(site).contains("explored") and not keep.request_pavilion(site),"Unexplored land should be refused: %s" % keep.pavilion_refusal(site)): return false
	# The HUD's Found Keep tile shows and arms the map click.
	var hud = game.get_node("Interface")
	game.selected_building = keep
	hud._process(0.0)
	var tile: Button = hud.card.get_node("FoundKeep")
	if not check(hud.desired_buttons.has("FoundKeep") and not tile.disabled,"The Keep's card should show an enabled Found Keep tile"): return false
	if not check(str(tile.get_meta("detail","")).contains("Sky-Pavilion"),"The tile should explain the Sky-Pavilion"): return false
	tile.pressed.emit()
	if not check(game.pending_unit_command == "found_keep" and game.armed(),"Found Keep should arm a click on the map"): return false
	game.cancel_armed()
	# A scout looks at the site and leaves: explored, though out of sight now.
	var scout := spawn("res://scenes/gameplay/forester_maiden.tscn","player",site)
	fog.update_now()
	scout.free()
	fog.update_now()
	if not check(fog.explored_by("player",site) and not fog.visible_to("player",site),"The site should be explored and out of sight"): return false
	if not check(keep.pavilion_refusal(site).is_empty(),"Explored open land should take a Sky-Pavilion: %s" % keep.pavilion_refusal(site)): return false
	var housed := KnightHousing.used(self,"player")
	var keeps := get_nodes_in_group("keeps").size()
	var before := maidens("player").size()
	if not check(keep.request_pavilion(site),"The Keep should charter a Sky-Pavilion"): return false
	if not check(keep.stockpile.amount(&"food") == food-45 and keep.stockpile.amount(&"wood") == wood-50 and keep.stockpile.amount(&"iron") == iron-50,"It costs 45 F, 50 W and 50 I from the Keep"): return false
	if not check(KnightHousing.used(self,"player") == housed+1,"It takes 1 housing while queued"): return false
	# Cancelled, it pays back and forgets its site.
	keep._drop_current()
	if not check(keep.stockpile.amount(&"wood") == wood and keep.pavilion_sites.is_empty(),"Cancelled, it pays back and drops its site"): return false
	# Short of Iron: refused, and told.
	var spare: int = keep.stockpile.amount(&"iron")
	keep.stockpile.withdraw(&"iron",spare)
	if not check(not keep.request_pavilion(site) and game.message.contains("price"),"Short of Iron it should be refused and told: '%s'" % game.message): return false
	keep.stockpile.deposit(&"iron",spare)
	keep.request_pavilion(site)
	for i in range(149): keep._process(0.1)
	if not check(get_nodes_in_group("sky_pavilions").is_empty(),"It shouldn't lift off before its 15 s"): return false
	for i in range(3): keep._process(0.1)
	var flying: Array = get_nodes_in_group("sky_pavilions")
	if not check(flying.size() == 1 and keep.pending.is_empty() and keep.pavilion_sites.is_empty(),"After 15 s it lifts off"): return false
	var pavilion: Node3D = flying[0]
	pavilion.set_process(false)
	if not check(KnightHousing.used(self,"player") == housed+1,"Flying, it still takes 1 housing"): return false
	if not check(is_equal_approx(pavilion.height,KnightHousing.rules().balloon_dock_height) and is_equal_approx(pavilion.cruise_height(),KnightHousing.rules().pavilion_cruise_height),"It lifts off the Keep's dock and cruises at its own height"): return false
	pavilion.command_move(keep.global_position)
	if not check(pavilion.move_goal.distance_to(Vector3(site.x,0,site.z)) < 0.01,"It takes no orders"): return false
	if not check(await fly(pavilion),"It should land and be gone"): return false
	var founded: Node3D = null
	for node in get_nodes_in_group("keeps"):
		if node.team == "player" and node != keep and Vector2(node.global_position.x-site.x,node.global_position.z-site.z).length() < 6.0: founded = node
	if not check(founded != null and get_nodes_in_group("keeps").size() == keeps+1,"It unfolds into a Keep at the site"): return false
	if not check(founded.stockpile.amount(&"food") == 0 and founded.stockpile.amount(&"wood") == 0 and founded.stockpile.amount(&"iron") == 0,"The new Keep starts empty"): return false
	var now := maidens("player")
	if not check(now.size() == before+1 and now.any(func(m): return m.global_position.distance_to(founded.global_position) < 14.0),"A Forester Maiden stands at its gate"): return false
	if not check(KnightHousing.used(self,"player") == housed+1,"Its housing passes to the Maiden"): return false
	# The next one finds its site taken by the time it lands: 2 Wood and 2 Iron crates and the Maiden instead.
	var second = null
	for d in [60.0,80.0,100.0,120.0]:
		for angle in range(0,360,20):
			var point: Vector3 = founded.global_position+Vector3.FORWARD.rotated(Vector3.UP,deg_to_rad(angle))*d
			if network.keep_site_refusal(point,"player").is_empty() and point.distance_to(keep.global_position) > 60.0: second = point; break
		if second != null: break
	if not check(second != null,"There should be a second Keep site"): return false
	fog._stamp("player",second,24.0)
	if not check(keep.request_pavilion(second),"A second Sky-Pavilion should be chartered: %s" % keep.pavilion_refusal(second)): return false
	for i in range(152): keep._process(0.1)
	flying = get_nodes_in_group("sky_pavilions")
	if not check(flying.size() == 1,"The second one lifts off"): return false
	pavilion = flying[0]
	pavilion.set_process(false)
	var blocker: Node3D = network.found_keep(second,"player")
	if not check(blocker != null,"A Keep should stand on the second site first"): return false
	await process_frame
	keeps = get_nodes_in_group("keeps").size()
	before = maidens("player").size()
	if not check(await fly(pavilion),"The second one should land and be gone"): return false
	if not check(get_nodes_in_group("keeps").size() == keeps,"A blocked site gets no Keep"): return false
	var dropped := {}
	for crate in get_nodes_in_group("supply_crates"):
		if crate.team == "player" and flat(crate.global_position,second) < 16.0 and crate.amount == 25: dropped[crate.resource_kind] = dropped.get(crate.resource_kind,0)+1
	if not check(dropped.get(&"wood",0) == 2 and dropped.get(&"iron",0) == 2,"A blocked site gets 2 Wood and 2 Iron crates: %s" % dropped): return false
	if not check(maidens("player").size() == before+1,"And a Forester Maiden"): return false
	return true
## Distance on the ground, ignoring height.
func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x-b.x,a.z-b.z).length()
## The Supply Balloon's manifest, on the Two Lakes match the Sky-Pavilion section left open.
func balloon() -> bool:
	var keep := keep_of("player")
	var fog: Node = game.fog_of_war()
	var rules := KnightHousing.rules()
	for crate in CrateYard.beside(keep): crate.queue_free()
	await process_frame
	keep.balloon_manifest.clear()
	for kind in [&"food",&"wood",&"iron",&"coal"]: keep.stockpile.deposit(kind,200)
	if not check(keep.balloon_refusal().contains("manifest"),"With no manifest and no crates beside it the Keep should say so: %s" % keep.balloon_refusal()): return false
	# The tile opens the Load tiles as the balloon's manifest.
	var hud = game.get_node("Interface")
	game.selected_building = keep
	hud._process(0.0)
	var tile: Button = hud.card.get_node("LaunchBalloon")
	if not check(hud.desired_buttons.has("LaunchBalloon") and not tile.disabled,"With nothing set the Launch balloon tile should still open"): return false
	tile.pressed.emit()
	hud._process(0.0)
	if not check(game.pending_unit_command == "launch_balloon" and hud.balloon_keep() == keep,"Launch balloon should arm for the Keep"): return false
	if not check(hud.pick_prompt().begins_with("LAUNCH BALLOON") and hud.load_tiles.visible and hud.manifest_panel.visible,"The Load tiles and manifest should show"): return false
	if not check(not hud.load_tiles.get_node("Energy").visible and hud.load_tiles.get_node("Food").visible and hud.load_tiles.get_node("Coal").visible,"Food, Wood, Iron and Coal fly; Energy doesn't"): return false
	hud.edit_manifest(&"food")
	hud.edit_manifest(&"coal")
	hud.edit_manifest(&"iron",true)
	if not check(keep.balloon_manifest_total() == rules.balloon_crates and keep.balloon_manifest.get(&"iron",0) == 2,"Shift fills the free slots: %s" % keep.balloon_manifest): return false
	hud.edit_manifest(&"wood")
	if not check(keep.balloon_manifest_total() == 4 and not keep.balloon_manifest.has(&"wood"),"A fifth crate is refused"): return false
	hud.lower_manifest(&"iron")
	hud.edit_manifest(&"wood")
	if not check(keep.balloon_manifest == {&"food": 1, &"coal": 1, &"iron": 1, &"wood": 1},"Right-click takes one off: %s" % keep.balloon_manifest): return false
	hud._process(0.0)
	if not check(hud.manifest_panel.get_node("Head/Value").text == "4 / 4 crates","The manifest panel counts the balloon's crates"): return false
	# Explored land out of every Keep's range.
	var drop = null
	for d in [80.0,100.0,120.0,140.0]:
		for angle in range(0,360,20):
			var point: Vector3 = keep.global_position+Vector3.FORWARD.rotated(Vector3.UP,deg_to_rad(angle))*d
			if game.ground.get_tile_at_position(point) == null or CrateYard.free_cell(self,point,0,8) == null or fog.explored_by("player",point): continue
			if get_nodes_in_group("keeps").any(func(k): return SupplySource.covers(k,point,"player")): continue
			drop = point; break
		if drop != null: break
	if not check(drop != null,"There should be unexplored open land out of the Keeps' range"): return false
	if not check(keep.balloon_refusal(drop).contains("explored") and not keep.launch_balloon(drop),"Unexplored land is refused"): return false
	fog._stamp("player",drop,12.0)
	var before := {}
	for kind in [&"food",&"wood",&"iron",&"coal"]: before[kind] = keep.stockpile.amount(kind)
	game.cancel_armed()
	if not check(keep.launch_balloon(drop),"Explored land takes the balloon: %s" % keep.balloon_refusal(drop)): return false
	var spent := {}
	for kind in before: spent[kind] = before[kind]-keep.stockpile.amount(kind)
	if not check(spent == {&"food": 25, &"wood": 25+rules.balloon_wood_cost, &"iron": 25, &"coal": 25},"It takes the four crates and its Wood from the stock: %s" % spent): return false
	var flying: Node3D = null
	for node in get_nodes_in_group("air_balloons"):
		if not node.is_in_group("sky_pavilions") and not node.landed: flying = node
	if not check(flying != null and flying.crates.size() == 4,"A balloon carrying four crates should be up"): return false
	flying.set_process(false)
	if not check(await fly(flying),"The balloon should land and be gone"): return false
	var landed := {}
	for crate in get_nodes_in_group("supply_crates"):
		if crate.team == "player" and flat(crate.global_position,drop) < 10.0 and crate.amount == 25: landed[crate.resource_kind] = landed.get(crate.resource_kind,0)+1
	if not check(landed == {&"food": 1, &"wood": 1, &"iron": 1, &"coal": 1},"It sets the four crates down: %s" % landed): return false
	if not check(keep.balloon_manifest_total() == 4,"The manifest stays set for the next balloon"): return false
	# Short of a manifest kind: refused, naming it.
	keep.stockpile.withdraw(&"coal",keep.stockpile.amount(&"coal"))
	if not check(keep.balloon_refusal().contains("Coal"),"Short of Coal the manifest is refused: %s" % keep.balloon_refusal()): return false
	# Cleared, it falls back on the crates packed beside the Keep.
	game.selected_building = keep
	tile.pressed.emit()
	hud.clear_manifest()
	game.cancel_armed()
	if not check(keep.balloon_manifest.is_empty() and keep.balloon_refusal().contains("beside"),"Cleared, it needs crates beside the Keep"): return false
	var cell = CrateYard.free_cell(self,keep.global_position,0,12)
	CrateYard.spawn(self,cell,&"iron",ResourceStockpile.CRATE,"player")
	if not check(keep.balloon_crates().size() == 1 and keep.balloon_refusal().is_empty(),"A crate beside the Keep can go up: %s" % keep.balloon_refusal()): return false
	return true
