extends SceneTree
# Headless (docs/KNIGHTS_ECONOMY.md): the Knights' economy. A Farm with one Forester yields 80 to 90 Food a minute
# into the Keep, and refuses a second worker; a Farm must stand in a Keep's range; a House adds housing only inside
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

## Check the visible outfit on this instance; touching the shared imported scene would change both workers.
func wears(model: Node3D, visible_parts: Array) -> bool:
	for part in ["Kerchief", "Sunhat", "WoodcuttingAxe", "FarmingTool", "MaterialLoad", "FoodBasket", "BuildingHammer"]:
		var item := model.find_child(part, true, false) as MeshInstance3D
		if not check(item != null and item.is_visible_in_tree() == visible_parts.has(part),
				"Unexpected %s visibility on %s; expected %s" % [part, model.get_path(), visible_parts]): return false
	return true

func check_first_delivery(farmer: Node3D, second: Node3D, farm: Node3D, keep: Node3D) -> bool:
	var model = farmer.get_node("Visuals/Model")
	var field_player := farm.get_node("Visuals/Model/Rig/AnimationPlayer") as AnimationPlayer
	var worked := false
	var returned_with_food := false
	var before: int = keep.stockpile.amount(&"food")
	for tick in 900:
		farmer._process(1.0 / 30.0)
		farm._process(1.0 / 30.0)
		model._process(1.0 / 30.0)
		if not worked and farmer.state == "Farming" and farmer.order == "gather" and farmer.cargo > 0 and field_player.assigned_animation == &"Work":
			if not check(model.current_clip() == &"Till", "A farming Forester should till while filling a load"): return false
			var centre: Vector3 = game.ground.tile_to_world(farmer.grid_position)
			var offset := (centre - farm.global_position).abs()
			if not check(is_equal_approx(maxf(offset.x, offset.z), 2.5) and minf(offset.x, offset.z) <= 1.501,
					"The Forester should stand alongside a crop bed, got offset %s" % offset): return false
			if not check(game.ground.get_tile_at_position(farmer.global_position) == farmer.grid_position and farmer._is_ours(farmer.grid_position),
					"The tilling pose must keep the worker inside her claimed cell"): return false
			if not check(farm.has_furrow(farmer.grid_position) and farmer.global_position.distance_to(farm.tending_pose(farmer.grid_position).origin) < 0.01,
					"The Forester should finish the final step to her furrow before working"): return false
			if not wears(model, ["Sunhat", "FarmingTool"]): return false
			worked = true
		if not returned_with_food and farmer.cargo_kind == &"food" and farmer.order == "return" and model.motion() == &"run":
			if not check(model.current_clip() == &"CarryFood", "The food carrier should walk with the harvest basket"): return false
			if not wears(model, ["Sunhat", "FoodBasket"]): return false
			second.command_gather(farm)
			if not check(farm.worker == farmer and second.order != "gather", "The Farm must retain its worker on her delivery trip"): return false
			returned_with_food = true
		if keep.stockpile.amount(&"food") > before:
			if not check(farmer.cargo == 0 and keep.stockpile.amount(&"food") - before == farmer.carry_capacity,
					"One farm trip should unload one full basket at the Keep"): return false
			if not wears(model, ["Sunhat", "FarmingTool"]): return false
			return check(worked and returned_with_food, "The worker should cultivate the plot and walk a full food basket to the Keep")
	return check(false, "The assigned Forester never delivered the harvest")

func check_material_jobs(worker: Node3D) -> bool:
	var model = worker.get_node("Visuals/Model")
	var tree: Node3D = game.ground.forest_source(Vector2i(345,275))
	if not check(tree != null, "The test needs a standing forest cell"): return false
	var resources := game.get_node("Entities/Resources")
	for source: Node3D in [tree, resources.get_node("WoodStand"), resources.get_node("StarterWoodPile"), resources.get_node("StarterIronPile")]:
		place(worker, source.global_position + Vector3(1, 0, 0))
		worker.command_gather(source)
		step([worker, model], worker.harvest_interval + 0.2)
		var partial_load: int = worker.cargo
		if not check(partial_load > 0 and partial_load < worker.carry_capacity and worker.order == "gather",
				"The Forester should be partway through gathering from %s" % source.name): return false
		var loose := source.is_in_group("material_piles")
		if not check(model.current_clip() == (&"Gather" if loose else &"Chop"),
				"The work clip should match %s, got %s" % [source.name, model.current_clip()]): return false
		if not wears(model, ["Kerchief"] if loose else ["Kerchief", "WoodcuttingAxe"]): return false
		if source == tree:
			var before_felling: int = tree.remaining
			worker.command_fell(tree.cell, Rect2i(tree.cell, Vector2i.ONE))
			step([worker, model], worker.harvest_interval + 0.2)
			if not check(model.current_clip() == &"Chop" and tree.remaining < before_felling and worker.cargo == partial_load,
					"Felling with a retained load should cut the tree and leave the carried wood alone"): return false
			if not wears(model, ["Kerchief", "WoodcuttingAxe"]): return false
		worker.command_move(worker.global_position)
		step([worker, model], 0.1)
		if not check(worker.cargo == partial_load and model.current_clip() == &"Carry",
				"Interrupting %s should put the retained load in her hands" % source.name): return false
		if source.resource_kind == &"wood" and not wears(model, ["Kerchief", "MaterialLoad"]): return false
		var dropped = game.drop_material(worker)
		if not check(dropped != null and dropped.remaining == partial_load and dropped.resource_kind == source.resource_kind,
				"Dropping the interrupted load should preserve its kind and amount"): return false
		step([worker, model], 0.1)
		if not wears(model, ["Kerchief", "WoodcuttingAxe"]): return false
	return true

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
	# Near the Keep: its centre 12 m from the Keep's. Yield falls with the walk: about 100 a minute touching the Keep,
	# 80 at 13 m and 70 at 18 m (docs/KNIGHTS_ECONOMY.md).
	var plan: Node3D = null
	var spot: Vector3
	for offset in [Vector3(0,0,10),Vector3(0,0,-10),Vector3(10,0,0),Vector3(-10,0,0)]:
		spot = keep.global_position+offset*1.2
		plan = network.queue_plan(spot,&"farm",null,false,false)
		if plan != null: break
	if not check(plan != null,"A Farm inside the Keep's range should be placed"): return
	if not check(plan.materials_covered(),"The Keep's stock should cover a Farm plan in its range"): return
	var site_player := plan.get_node_or_null("Visuals/Model/Rig/AnimationPlayer") as AnimationPlayer
	if not check(site_player != null and site_player.assigned_animation == &"Build", "A Farm plan must show the construction clip"): return
	var builder = game.get_node("Entities/Units/ForesterMaiden1")
	place(builder,spot+Vector3(0,0,4))
	builder.command_construct(plan)
	var builder_model = builder.get_node("Visuals/Model")
	step([builder,plan,builder_model],1.0)
	if not check(builder_model.current_clip() == &"Build", "The Forester should use her building stroke at the Farm plan"): return
	if not wears(builder_model, ["Kerchief", "BuildingHammer"]): return
	step([builder,plan],40.0)
	var farms := get_nodes_in_group("farms")
	if not check(farms.size() == 1,"The Farm should be built from the Keep's stock: '%s', state '%s'" % [builder.state,plan.state if is_instance_valid(plan) else "done"]): return
	if not check(wood_before-keep.stockpile.amount(&"wood") == rules.farm_wood_cost,"The Farm should take %d wood from the Keep, took %d" % [rules.farm_wood_cost,wood_before-keep.stockpile.amount(&"wood")]): return
	var farm = farms[0]
	var field_model = farm.get_node("Visuals/Model")
	if not check(field_model.scene_file_path == "res://scenes/models/farm_model.tscn" and
			field_model.player.assigned_animation == &"Idle", "An unworked Farm must show the finished field at rest"): return
	var cyborg = load("res://scenes/gameplay/infantry.tscn").instantiate()
	cyborg.position = farm.global_position + Vector3(4,0,2)
	game.get_node("Entities/Units").add_child(cyborg)
	cyborg.command_gather(farm)
	if not check(cyborg.can_gather and cyborg.team == farm.team and cyborg.order != "gather" and farm.worker == null and cyborg.state == "A Farm requires a Forester Maiden",
			"A friendly Cyborg gatherer must leave the Farm open for a Forester Maiden"): return
	cyborg.free()
	# One Forester tills it and carries the Food home: 80 to 90 a minute.
	var farmer = builder
	place(farmer,farm.global_position+Vector3(0,0,4))
	farmer.command_gather(farm)
	if not check(farmer.order == "gather","The Forester should take the Farm"): return
	var second = game.get_node("Entities/Units/ForesterMaiden2")
	var farmer_model = farmer.get_node("Visuals/Model")
	farmer_model._process(0)
	second.get_node("Visuals/Model")._process(0)
	if not wears(farmer_model, ["Sunhat", "FarmingTool"]) or not wears(second.get_node("Visuals/Model"), ["Kerchief", "WoodcuttingAxe"]): return
	if not check_first_delivery(farmer,second,farm,keep): return
	step([farmer],10.0)
	var food_before: int = keep.stockpile.amount(&"food")
	step([farmer],120.0)
	var per_minute: int = roundi((keep.stockpile.amount(&"food")-food_before)/2.0)
	print("Farm %.1f m from the Keep's centre: %d Food a minute" % [farm.global_position.distance_to(keep.global_position),per_minute])
	if not check(per_minute >= 80 and per_minute <= 90,"A Farm with one Forester should yield 80 to 90 Food a minute, gave %d" % per_minute): return
	if not check(farmer.state in ["Farming","Returning","Returning cargo"] or farmer.order == "gather","The Forester should be farming: '%s'" % farmer.state): return
	# A second worker is refused.
	place(second,farm.global_position+Vector3(3,0,4))
	second.command_gather(farm)
	if not check(second.order != "gather" and second.state == "Farm already has a worker","A second Forester should be refused: %s '%s'" % [second.order,second.state]): return
	# Housing: 10 from the Keep; a House inside the range adds 8, one outside adds nothing.
	var cap: int = KnightHousing.cap(self,"player")
	if not check(cap == rules.keep_room,"One Keep should give %d housing, gave %d" % [rules.keep_room,cap]): return
	var house = stand(&"house",keep.global_position+Vector3(14,0,-12))
	if not check(house != null and KnightHousing.cap(self,"player") == cap+rules.house_room,"A House in the Keep's range should add %d housing" % rules.house_room): return
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
	# Reassign the plot. The old worker should release it on her next order,
	# and the field should settle back to idle after the last work cycle.
	farmer.command_move(farmer.global_position)
	second.command_gather(farm)
	if not check(farm.worker == second and second.order == "gather", "An unassigned plot should accept a replacement farmer"): return
	var second_model = second.get_node("Visuals/Model")
	second_model._process(0)
	if not wears(second_model, ["Sunhat", "FarmingTool"]): return
	second.command_move(second.global_position)
	second_model._process(0)
	if not wears(second_model, ["Kerchief", "WoodcuttingAxe"]): return
	for tick in 180:
		farm._process(1.0 / 30.0)
		field_model.player.advance(1.0 / 30.0)
		field_model._process(1.0 / 30.0)
	if not check(field_model.player.assigned_animation == &"Idle", "An untended Farm must return to its idle animation"): return
	second.command_gather(farm)
	farm.take_damage(farm.health)
	if not check(not farm.is_in_group("farms") and is_instance_valid(field_model) and field_model.player.assigned_animation == &"Die",
			"A destroyed Farm should stop accepting orders and play its collapse"): return
	var effects_player := field_model.get_node_or_null("FarmDeathFx/Model/AnimationPlayer") as AnimationPlayer
	if not check(effects_player != null and effects_player.current_animation == &"Death", "A collapsing Farm should play its destruction effects"): return
	second_model._process(0)
	if not wears(second_model, ["Kerchief", "WoodcuttingAxe"]): return
	if not check_material_jobs(second): return
	print("KNIGHTS_ECONOMY_TEST_PASSED")
	quit(0)
