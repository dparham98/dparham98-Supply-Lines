extends SceneTree
# Headless (item 13 of docs/BALANCE_IMPLEMENTATION_HANDOFF.md, docs/KNIGHTS_RAIL.md): before a Wainwright stands, a
# Keep can't pay for track or build a train. A Wainwright (60 W / 60 I, inside a Keep's range) changes both: the Keep
# lays maglev track at 2 iron a metre, and with track in its loading area builds a train for 60 F / 40 W / 30 I.
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
	# No Wainwright: no track from a Keep and no train.
	if not check(not KnightRail.has_wainwright(keep,"player") and lay_from(rails,keep) == null,"A Keep should not lay track before a Wainwright"): return
	if not check(keep.train_refusal().contains("Wainwright") and not keep.request_train(),"A Keep should refuse a train before a Wainwright"): return
	# The Wainwright.
	var spec: Dictionary = network.plan_spec(&"wainwright")
	if not check(spec.get("title") == "Wainwright" and spec.get("wood") == 60 and spec.get("iron") == 60 and spec.get("size") == Vector2i(4,4) and spec.get("in_keep_range") == true and spec.get("keep_stock") == true,"Wainwright plan spec should be 4 x 4, 60 W / 60 I, in a Keep's range: %s" % spec): return
	var plan = null
	for offset in [Vector3(-14,0,8),Vector3(14,0,-12),Vector3(-12,0,-14),Vector3(10,0,14),Vector3(0,0,-18),Vector3(18,0,0)]:
		plan = network.queue_plan(keep.global_position+offset,&"wainwright",keep,true,false)
		if is_instance_valid(plan): break
	if not check(is_instance_valid(plan),"A Wainwright plan could not be queued: "+game.message): return
	var wainwright = plan.complete_from_stock()
	if not check(is_instance_valid(wainwright) and wainwright.stats.building_id == &"wainwright","The plan should finish as a Wainwright"): return
	await process_frame
	if not check(KnightRail.has_wainwright(keep,"player"),"The side should now have a Wainwright"): return
	# Track from the Keep at 2 iron a metre.
	var iron: int = keep.iron
	var piece := lay_from(rails,keep)
	if not check(piece != null,"With a Wainwright the Keep should lay track: "+game.message): return
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
	if not check(is_equal_approx(train.fuel,5.0),"100 m should burn 5 coal (%.2f left)" % train.fuel): return
	train._pay_for_power(train,200.0)
	if not check(train.fuel <= 0.0 and train.power_source() == null,"An empty train should not move"): return
	var coal: int = keep.stockpile.amount(&"coal")
	for i in range(30): train.fuel_tick(0.1)
	if not check(train.fuel >= 10.0 and keep.stockpile.amount(&"coal") <= coal-10,"A stopped train should refuel from the Keep's coal (fuel %.1f)" % train.fuel): return
	# The HUD: the Keep's train tile and the Build page's Wainwright and Rail tiles.
	var hud = game.get_node("Interface")
	game.selected_building = keep
	hud._process(0)
	if not check(hud.desired_buttons.has("KeepTrain"),"The Keep card should show the train tile: %s" % [hud.desired_buttons]): return
	game.selected_building = null
	hud.refresh_global_menu()
	if not check(hud.build_menu.get_node("Actions/Wainwright").visible and hud.build_menu.get_node("Actions/Rail").visible,"The Knights Build page should show the Wainwright and, with one standing, Rail"): return
	game.queue_free()
	await process_frame
	print("KNIGHTS_RAIL_TEST_PASSED")
	quit(0)
