extends SceneTree
# Headless (docs/KNIGHTS_ECONOMY.md): the Knights' economy. A Farm with one Forester yields 80 to 90 Food a minute
# into the Keep, and refuses a second worker; a Farm is a 10 x 10 field any unit walks over and nothing is built on,
# and yields nothing while an enemy ground unit stands on it; its Forester is its Farmer for good, and takes only an
# empty Farm when hers is lost; a House is 4 x 4; a Farm must stand in a Keep's range; a House adds housing only inside
# a Keep's range; training waits when housing is full; a Knights plan in a Keep's range builds from the Keep's
# stock with nothing carried; the Keep trains for the enemy side too; the start and the training times.
var game: Node3D
var network: Node
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func place(node: Node3D, point: Vector3) -> void:
	for cell in node._claimed.duplicate(): node._release(cell)
	node._stop_route()
	node.grid_position = game.ground.nearest_actor_cell(game.ground.get_tile_at_position(point),node.mobility_layer(),node._owner_key())
	node.global_position = game.ground.tile_to_world(node.grid_position)
	node._claim(node.grid_position)
func step(nodes: Array, seconds: float) -> void:
	for i in range(ceili(seconds*30)):
		for node in nodes:
			if is_instance_valid(node): node._process(1.0/30)
## A plan finished at once from its materials, as the playtest tools do, standing on open ground at `point`.
func stand(kind: StringName, point: Vector3, team := "player") -> Node3D:
	var plan = network.queue_plan(point,kind,null,false,false,team)
	if plan == null: return null
	var building = network.finish_plan(plan)
	plan.queue_free()
	return building
func run() -> void:
	var rules: KnightsRules = load("res://assets/economy/knights_rules.tres")
	# The start and training times.
	var start = load("res://scenes/maps/starts/knights_start.tscn").instantiate()
	var keep_probe = start.get_node("Keep")
	if not check(keep_probe.initial_food == 150 and keep_probe.initial_wood == 100 and keep_probe.initial_iron == 50 and keep_probe.initial_energy == 0,"A Knights start Keep holds 150 F, 100 W, 50 I and no energy"): return
	if not check(start.get_children().filter(func(n): return n.name.begins_with("ForesterMaiden")).size() == 2 and start.get_children().filter(func(n): return n.is_in_group("supply_crates") or n.name.contains("Crate")).is_empty(),"A Knights start has two Foresters and no Food crate"): return
	start.free()
	for pair in [["forester_maiden",12.0],["warhound",7.0],["round_table_marine",15.0],["grail_sentinel",15.0],["questing_marine",17.0],["azure_dragon",40.0]]:
		if not check(load("res://assets/units/%s.tres" % pair[0]).build_seconds == pair[1],"%s should train in %s s" % pair): return
	game = load("res://scenes/maps/arthurian_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	network = game.get_node("DepotNetwork")
	game.set_process(false)
	game.get_node("Interface").set_process(false)
	for group in ["units","depots","production_buildings","farms","houses"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	var keep = game.get_node("Entities/Buildings/Keep")
	if not check(keep.energy == 0,"The Knights hold no energy"): return
	# A Farm outside every Keep's range is refused.
	if not check(network.queue_plan(keep.global_position+Vector3(80,0,0),&"farm",null,false,false) == null,"A Farm outside every Keep's range should be refused"): return
	# Inside the range, a Farm plan builds from the Keep's wood, with nothing carried.
	keep.stockpile.deposit(&"wood",200)
	var wood_before: int = keep.stockpile.amount(&"wood")
	# Near the Keep: its centre 14 m from the Keep's, its near edge 9 m. The Farmer tills from the near edge, so the walk is
	# the near edge's. Yield falls with the walk (docs/KNIGHTS_ECONOMY.md).
	var plan: Node3D = null
	var spot: Vector3
	for offset in [Vector3(0,0,10),Vector3(0,0,-10),Vector3(10,0,0),Vector3(-10,0,0)]:
		spot = keep.global_position+offset*1.4
		plan = network.queue_plan(spot,&"farm",null,false,false)
		if plan != null: break
	if not check(plan != null,"A Farm inside the Keep's range should be placed"): return
	if not check(plan.materials_covered(),"The Keep's stock should cover a Farm plan in its range"): return
	var builder = game.get_node("Entities/Units/ForesterMaiden1")
	place(builder,spot+Vector3(0,0,4))
	builder.command_construct(plan)
	step([builder,plan],40.0)
	var farms := get_nodes_in_group("farms")
	if not check(farms.size() == 1,"The Farm should be built from the Keep's stock: '%s', state '%s'" % [builder.state,plan.state if is_instance_valid(plan) else "done"]): return
	if not check(wood_before-keep.stockpile.amount(&"wood") == rules.farm_wood_cost,"The Farm should take %d wood from the Keep, took %d" % [rules.farm_wood_cost,wood_before-keep.stockpile.amount(&"wood")]): return
	var farm = farms[0]
	# One Forester tills it and carries the Food home: 80 to 90 a minute.
	var farmer = builder
	place(farmer,farm.global_position+Vector3(0,0,4))
	farmer.command_gather(farm)
	if not check(farmer.order == "gather","The Forester should take the Farm"): return
	step([farmer],10.0)
	var food_before: int = keep.stockpile.amount(&"food")
	step([farmer],120.0)
	var per_minute: int = roundi((keep.stockpile.amount(&"food")-food_before)/2.0)
	print("Farm %.1f m from the Keep's centre: %d Food a minute" % [farm.global_position.distance_to(keep.global_position),per_minute])
	if not check(per_minute >= 80 and per_minute <= 90,"A Farm with one Forester should yield 80 to 90 Food a minute, gave %d" % per_minute): return
	if not check(farmer.state in ["Farming","Returning","Returning cargo"] or farmer.order == "gather","The Forester should be farming: '%s'" % farmer.state): return
	# A second worker is refused.
	var second = game.get_node("Entities/Units/ForesterMaiden2")
	place(second,farm.global_position+Vector3(3,0,4))
	second.command_gather(farm)
	if not check(second.order != "gather" and second.state == "Farm already has a worker","A second Forester should be refused: %s '%s'" % [second.order,second.state]): return
	# The field: 10 x 10, walkable, nothing built on it, no track across it.
	var ground = game.ground
	if not check(farm.cells.size() == rules.farm_footprint.x*rules.farm_footprint.y and rules.farm_footprint == Vector2i(10,10),"A Farm should cover 10 x 10 cells, covers %d" % farm.cells.size()): return
	var mid: Vector2i = farm.field_rect().position+farm.field_rect().size/2
	if not check(ground.is_field(mid) and ground.can_traverse(mid) and not ground.is_footprint_valid(mid,Vector2i.ONE),"A Farm's field should be walkable and unbuildable"): return
	var mid_cells: Array[Vector2i] = [mid]
	if not check(not game.get_node("RailNetwork").ground_clear(mid_cells),"Track should not be laid across a Farm"): return
	if not check(network.queue_plan(farm.global_position,&"house",null,false,false) == null,"A House should not be planned on a Farm"): return
	# An enemy ground unit standing on the field stops its Food; the Farmer waits and does not leave.
	var raider = load("res://scenes/gameplay/scout.tscn").instantiate()
	raider.team = "enemy"
	game.get_node("Entities/Units").add_child(raider)
	await process_frame
	raider.set_process(false)
	place(raider,ground.tile_to_world(mid))
	if not check(farm.on_field(raider.global_position),"The raider should stand on the field"): return
	step([farmer,farm],8.0)
	var raid_before: int = keep.stockpile.amount(&"food")
	step([farmer,farm],30.0)
	if not check(farm.raided and keep.stockpile.amount(&"food")-raid_before <= farmer.carry_capacity,"A raided Farm should yield nothing: raided %s, +%d Food" % [farm.raided,keep.stockpile.amount(&"food")-raid_before]): return
	if not check(farmer.order in ["gather","return"] and farmer.source == farm,"A Farmer should wait out a raid: %s '%s'" % [farmer.order,farmer.state]): return
	raider.queue_free()
	await process_frame
	var after_raid: int = keep.stockpile.amount(&"food")
	step([farmer,farm],30.0)
	if not check(not farm.raided and keep.stockpile.amount(&"food") > after_raid+20,"A Farm should yield again once the raider leaves: +%d" % (keep.stockpile.amount(&"food")-after_raid)): return
	# The Farmer stays a Farmer: no moving, felling or building.
	if not check(farmer.farmer and farmer.farm == farm and game.get_node("Interface").object_name(farmer) == "Farmer","A Forester sent to a Farm should become its Farmer"): return
	farmer.command_move(keep.global_position+Vector3(-6,0,-6))
	farmer.command_fell(mid)
	var probe_plan = network.queue_plan(keep.global_position+Vector3(-14,0,12),&"house",null,false,false)
	if probe_plan != null: farmer.command_construct(probe_plan)
	if not check(farmer.order in ["gather","return"] and farmer.source == farm and farmer.state == "A Farmer works only a Farm","A Farmer should refuse other orders: %s '%s'" % [farmer.order,farmer.state]): return
	if probe_plan != null: probe_plan.queue_free()
	farmer.set_fell_autocast(true)
	if not check(not farmer.fell_autocast,"A Farmer should not fell on autocast"): return
	# Its Farm lost, a Farmer takes an empty Farm and not one that has a Farmer.
	var empty_farm: Node3D = null
	var busy_farm: Node3D = null
	for offset in [Vector3(-13,0,0),Vector3(13,0,0),Vector3(0,0,-13),Vector3(0,0,13),Vector3(-13,0,-13),Vector3(13,0,13)]:
		var made = stand(&"farm",keep.global_position+offset)
		if made == null: continue
		made.set_process(false)
		if empty_farm == null: empty_farm = made
		elif busy_farm == null: busy_farm = made; break
	if not check(empty_farm != null and busy_farm != null,"Two more Farms should fit in the Keep's range"): return
	place(second,busy_farm.global_position)
	second.command_gather(busy_farm)
	if not check(second.farmer and busy_farm.worker_busy(),"The second Forester should become the other Farm's Farmer"): return
	farm.take_damage(100000)
	await process_frame
	farmer.command_gather(busy_farm)
	if not check(farmer.farm != busy_farm and farmer.state == "Farm already has a worker","A Farmer should not take a Farm that has a Farmer: '%s'" % farmer.state): return
	farmer.command_gather(empty_farm)
	if not check(farmer.farm == empty_farm and farmer.order == "gather","A Farmer whose Farm was lost should take an empty Farm: '%s'" % farmer.state): return
	farm = empty_farm
	# Housing: 10 from the Keep; a House inside the range adds 8, one outside adds nothing.
	var cap: int = KnightHousing.cap(self,"player")
	if not check(cap == rules.keep_room,"One Keep should give %d housing, gave %d" % [rules.keep_room,cap]): return
	var house: Node3D = null
	for offset in [Vector3(14,0,-12),Vector3(-14,0,12),Vector3(-12,0,-14),Vector3(12,0,14),Vector3(18,0,0),Vector3(-18,0,0)]:
		house = stand(&"house",keep.global_position+offset)
		if house != null: break
	if not check(house != null and KnightHousing.cap(self,"player") == cap+rules.house_room,"A House in the Keep's range should add %d housing" % rules.house_room): return
	if not check(house.cells.size() == 16,"A House should cover 4 x 4 cells, covers %d" % house.cells.size()): return
	var outside = load("res://scenes/gameplay/house.tscn").instantiate()
	outside.position = keep.global_position+Vector3(90,0,0)
	game.get_node("Entities/Buildings").add_child(outside)
	if not check(KnightHousing.cap(self,"player") == cap+rules.house_room and not outside.housed(),"A House outside every Keep's range should add nothing"): return
	# Training waits when housing is full.
	var room: int = KnightHousing.cap(self,"player")-KnightHousing.used(self,"player")
	keep.stockpile.deposit(&"food",2000)
	for i in range(room): keep.pending.append("forester_maiden")
	keep.queue += room
	if not check(not KnightHousing.room(self,"player",&"forester_maiden"),"Housing should be full"): return
	keep.queue_limit = 999
	if not check(not keep.request_forester() and game.message.contains("No housing"),"A full side should not train, saying why: '%s'" % game.message): return
	var chapterhouse = game.get_node("Entities/Buildings/Chapterhouse")
	if not check(not chapterhouse.request_unit(&"round_table_marine") and game.message.contains("No housing"),"A Chapterhouse should not train without housing: '%s'" % game.message): return
	keep.pending.clear(); keep.queue = 0
	# The HUD: Farm and House on the Knights' Build page; a Farm, a House and the Keep show their panels.
	var hud = game.get_node("Interface")
	hud.refresh_global_menu()
	if not check(hud.build_menu.get_node("Actions/Farm").visible and hud.build_menu.get_node("Actions/House").visible,"The Knights' Build page should show Farm and House"): return
	for unit in get_nodes_in_group("units"): unit.is_selected = false
	for node in [farm,house,keep]:
		game.selected_building = node
		hud.update_contents()
		if not check(not hud.state_label.text.is_empty(),"%s should show a panel" % node.name): return
	if not check(hud.state_label.text.contains("housing"),"The Keep panel should show housing: '%s'" % hud.state_label.text): return
	# A Keep trains for the enemy side too (away from the player's units, which would capture it).
	var enemy_keep = load("res://scenes/gameplay/keep.tscn").instantiate()
	enemy_keep.team = "enemy"
	enemy_keep.position = keep.global_position+Vector3(-120,0,0)
	game.get_node("Entities/Buildings").add_child(enemy_keep)
	enemy_keep.set_process(false)
	var enemy_units := func(): return get_nodes_in_group("units").filter(func(u): return u.team == "enemy" and u.unit_stats != null and u.unit_stats.unit_id == &"forester_maiden").size()
	var before: int = enemy_units.call()
	if not check(enemy_keep.request_forester(),"An enemy Keep should accept training: '%s'" % game.message): return
	for i in range(30): enemy_keep._process(1.0)
	if not check(enemy_units.call() == before+1,"An enemy Keep should train its Forester: '%s', queue %d" % [enemy_keep.get_node("Progress").text,enemy_keep.queue]): return
	print("KNIGHTS_ECONOMY_TEST_PASSED")
	quit(0)
