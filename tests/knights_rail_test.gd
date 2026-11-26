extends SceneTree
# Headless (item 13 of docs/BALANCE_IMPLEMENTATION_HANDOFF.md, docs/KNIGHTS_RAIL.md): before a Dragon Yard stands, a
# Keep can't pay for track or build a train. A Dragon Yard (60 W / 60 I, 6 x 6, inside a Keep's range) changes both:
# the Keep lays maglev track at 2 iron a metre, and the yard's Train tile builds a train for 60 F / 40 W / 30 I at a
# covering Keep with track in its loading area. The yard raises Azure Dragons, which the Chapterhouse no longer does.
# The train runs at 12 m/s and burns coal by the metre from its own tank, refuelling from the Keep's coal.
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
## Lays a straight from the Keep's loading area, trying a ring of spots and headings.
func lay_from(rails: Node, keep: Node3D) -> Node3D:
	var reach: float = rails.depot_reach(keep)
	for angle in range(0,360,15):
		var out := Vector3.FORWARD.rotated(Vector3.UP,deg_to_rad(angle))
		for d in [reach-2.0,reach-4.0,reach-6.0]:
			var piece = rails.place("straight",keep.global_position+out*d,out,0,keep)
			if piece != null: return piece
	return null
func run() -> void:
	game = load("res://scenes/maps/arthurian_skirmish.tscn").instantiate()
	root.add_child(game)
	for i in range(3): await process_frame
	for name in ["EnemyPlayer","KnightsPlayer"]:
		var ai = game.get_node_or_null(name)
		if ai != null: ai.set_process(false)
	var keep: Node3D = null
	for node in get_nodes_in_group("keeps"):
		if node.team == "player": keep = node
	if not check(keep != null,"The Knights map needs a player Keep"): return
	var rails = game.get_node("RailNetwork")
	var network = game.get_node("DepotNetwork")
	keep.stockpile.deposit(&"wood",300)
	keep.stockpile.deposit(&"iron",400)
	keep.stockpile.deposit(&"food",300)
	keep.stockpile.deposit(&"coal",50)
	# The Chapterhouse no longer raises Dragons.
	var hall_stats: ProductionBuildingStats = load("res://assets/buildings/chapterhouse.tres")
	if not check(not hall_stats.unit_scenes.any(func(scene): return scene.resource_path.ends_with("azure_dragon.tscn")),"The Chapterhouse should not raise Azure Dragons"): return
	# No Dragon Yard: no track from a Keep and no train.
	if not check(not KnightRail.has_dragon_yard(keep,"player") and lay_from(rails,keep) == null,"A Keep should not lay track before a Dragon Yard"): return
	if not check(keep.train_refusal().contains("Dragon Yard") and not keep.request_train(),"A Keep should refuse a train before a Dragon Yard"): return
	# The Dragon Yard.
	var spec: Dictionary = network.plan_spec(&"dragon_yard")
	if not check(spec.get("title") == "Dragon Yard" and spec.get("wood") == 60 and spec.get("iron") == 60 and spec.get("size") == Vector2i(6,6) and spec.get("in_keep_range") == true and spec.get("keep_stock") == true,"Dragon Yard plan spec should be 6 x 6, 60 W / 60 I, in a Keep's range: %s" % spec): return
	var plan = null
	for offset in [Vector3(-14,0,8),Vector3(14,0,-12),Vector3(-12,0,-14),Vector3(10,0,14),Vector3(0,0,-18),Vector3(18,0,0),Vector3(-16,0,0),Vector3(0,0,16)]:
		plan = network.queue_plan(keep.global_position+offset,&"dragon_yard",keep,true,false)
		if is_instance_valid(plan): break
	if not check(is_instance_valid(plan),"A Dragon Yard plan could not be queued: "+game.message): return
	var yard = plan.complete_from_stock()
	if not check(is_instance_valid(yard) and yard.stats.building_id == &"dragon_yard","The plan should finish as a Dragon Yard"): return
	await process_frame
	if not check(KnightRail.has_dragon_yard(keep,"player"),"The side should now have a Dragon Yard"): return
	if not check(yard.stats.unit_scenes.size() == 1 and yard.unit_stats_for(yard.stats.unit_scenes[0]).unit_id == &"azure_dragon","The Dragon Yard raises Azure Dragons"): return
	# Its art (docs/DRAGON_YARD_MODEL.md): its own model, whose Work clip loops while it raises a dragon, and icon.
	var yard_model = yard.get_node("Visuals/Model")
	if not check(yard_model.scene_file_path.ends_with("dragon_yard_model.tscn") and yard_model.print_loops and yard_model.player.has_animation(&"Work"),"The Dragon Yard should wear its own model, with a looping Work clip"): return
	if not check(game.get_node("Interface").icon_name(yard) == "dragon_yard","The Dragon Yard's selection icon is its own"): return
	if not check(KnightRail.train_keep(yard) == null and not KnightRail.yard_train_refusal(yard).is_empty(),"With no track at a Keep, the yard can't build a train yet"): return
	# Track from the Keep at 2 iron a metre.
	var iron: int = keep.iron
	var piece := lay_from(rails,keep)
	if not check(piece != null,"With a Dragon Yard the Keep should lay track: "+game.message): return
	if not check(KnightRail.train_keep(yard) == keep and KnightRail.yard_train_refusal(yard).is_empty(),"With track at the Keep, the yard builds its train there: %s" % KnightRail.yard_train_refusal(yard)): return
	if not check(keep.iron == iron-rails.cost("straight") and rails.cost("straight") == ceili(rails.piece_length("straight")*2),"Track should cost 2 iron a metre from the Keep (%d -> %d)" % [iron,keep.iron]): return
	if not check(rails.powered(piece,"player"),"A line joined to a Keep should show as live"): return
	# The train.
	var food: int = keep.food
	var wood: int = keep.wood
	iron = keep.iron
	if not check(keep.train_refusal().is_empty() and keep.request_train(),"The Keep should build a train: "+keep.train_refusal()): return
	if not check(keep.food == food-60 and keep.wood == wood-40 and keep.iron == iron-30,"A train costs 60 F / 40 W / 30 I"): return
	if not check(keep.cancel_current() and keep.food == food and keep.wood == wood and keep.iron == iron,"Cancel refunds the train"): return
	keep.request_train()
	for i in range(31*10): keep._process(0.1)
	var train: Node3D = null
	for node in get_nodes_in_group("rail_trains"):
		if node.team == "player" and node.get("coal_fuelled") == true: train = node
	if not check(train != null,"The Keep should have built a coal train: %s" % keep.get_node("Progress").text): return
	if not check(is_equal_approx(train.move_speed,12.0),"The Knights train runs at 12 m/s (%.1f)" % train.move_speed): return
	# Coal by the metre, and refuelling from the Keep.
	game.vehicle_fuel_required = true
	train.set_process(false)
	train.fuel = 10.0
	train._pay_for_power(train,100.0)
	if not check(is_equal_approx(train.fuel,2.0),"100 m should burn 8 coal (Round 3, 0.08 a metre; %.2f left)" % train.fuel): return
	train._pay_for_power(train,200.0)
	if not check(train.fuel <= 0.0 and train.power_source() == null,"An empty train should not move"): return
	var coal: int = keep.stockpile.amount(&"coal")
	for i in range(30): train.fuel_tick(0.1)
	if not check(train.fuel >= 10.0 and keep.stockpile.amount(&"coal") <= coal-10,"A stopped train should refuel from the Keep's coal (fuel %.1f)" % train.fuel): return
	# The HUD: the Dragon Yard's Dragon and Train tiles, none on the Keep, and the Build page's Dragon Yard and Rail.
	var hud = game.get_node("Interface")
	game.selected_building = keep
	hud._process(0)
	if not check(not hud.desired_buttons.has("KeepTrain"),"The Keep card no longer shows a train tile: %s" % [hud.desired_buttons]): return
	game.selected_building = yard
	hud._process(0)
	if not check(hud.desired_buttons.has("KeepTrain") and hud.desired_buttons.has("ProduceAzureDragon"),"The Dragon Yard card should show the Dragon and train tiles: %s" % [hud.desired_buttons]): return
	var queued_before: int = keep.queue
	hud.queue_train()
	if not check(keep.queue == queued_before+1,"The yard's Train tile should queue a train at the Keep"): return
	game.selected_building = null
	hud.refresh_global_menu()
	if not check(hud.build_menu.get_node("Actions/DragonYard").visible and hud.build_menu.get_node("Actions/Rail").visible,"The Knights Build page should show the Dragon Yard and, with one standing, Rail"): return
	if not check(hud.build_menu.get_node("Actions/DragonYard").icon.resource_path.ends_with("sl_build_dragon_yard.png"),"The Dragon Yard tile should show its own card"): return
	game.queue_free()
	await process_frame
	print("KNIGHTS_RAIL_TEST_PASSED")
	quit(0)
