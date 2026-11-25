extends SceneTree
# Headless (docs/AIR_BALLOON.md): the Keep's Launch balloon. With no crates beside it, or short of Wood, the Keep
# refuses. It takes at most four full crates and 20 Wood; the balloon lifts off the Keep's dock, takes no orders, flies
# to the point and lands, sets four crates down there and is gone. Landing inside a friendly Keep's range, it unloads
# into that Keep. Shot down, it drops nothing. The HUD shows the Keep's Launch balloon tile and arms the map click.
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func step(nodes: Array, seconds: float) -> void:
	for i in range(ceili(seconds*30)):
		for node in nodes:
			if is_instance_valid(node) and node.is_inside_tree(): node._process(1.0/30)
func crates_near(point: Vector3, radius: float) -> Array[Node3D]:
	return CrateYard.crates_near(self,point,radius,"player")
func pack(keep: Node3D, kinds: Array) -> void:
	for kind in kinds:
		keep.stockpile.deposit(kind,ResourceStockpile.CRATE)
		if CrateYard.pack(keep,kind) == null: push_error("Could not pack a %s crate" % kind)
func newest_balloon() -> Node3D:
	var balloons := get_nodes_in_group("air_balloons")
	return balloons[-1] if not balloons.is_empty() else null
func run() -> void:
	var rules: KnightsRules = load("res://assets/economy/knights_rules.tres")
	var stats: UnitStats = load("res://assets/units/air_balloon.tres")
	if not check(stats.validation_errors().is_empty() and stats.max_health == 40 and stats.movement_speed == 5.0,"The balloon has 40 health and flies at 5 m/s"): return
	if not check(rules.balloon_wood_cost == 20 and rules.balloon_crates == 4,"A launch costs 20 Wood and carries 4 crates"): return
	game = load("res://scenes/maps/arthurian_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	game.set_process(false)
	game.get_node("Interface").set_process(false)
	for group in ["units","depots","production_buildings","farms","houses"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	var keep = game.get_node("Entities/Buildings/Keep")
	var radius: float = SupplySource.radius(keep)
	var far: Vector3 = keep.global_position+Vector3(radius+12.0,0,0)
	# No crates beside it: refused.
	for crate in CrateYard.beside(keep): crate.queue_free()
	await process_frame
	if not check(not keep.balloon_refusal().is_empty() and not keep.launch_balloon(far),"With no crates beside it the Keep should refuse"): return
	# Five crates beside it, but no Wood: refused.
	pack(keep,[&"wood",&"wood",&"iron",&"iron",&"food"])
	if not check(CrateYard.beside(keep).size() == 5,"Five crates should stand beside the Keep, found %d" % CrateYard.beside(keep).size()): return
	keep.stockpile.withdraw(&"wood",keep.stockpile.amount(&"wood"))
	if not check(keep.launch_balloon(far) == false and keep.balloon_refusal().contains("Wood"),"Short of Wood the Keep should refuse"): return
	keep.stockpile.deposit(&"wood",50)
	# The HUD's tile shows and arms the map click.
	var hud = game.get_node("Interface")
	game.selected_building = keep
	hud._process(0.0)
	var tile: Button = hud.card.get_node("LaunchBalloon")
	if not check(hud.desired_buttons.has("LaunchBalloon") and not tile.disabled,"The Keep's card should show an enabled Launch balloon tile"): return
	tile.pressed.emit()
	if not check(game.pending_unit_command == "launch_balloon" and game.armed(),"Launch balloon should arm a click on the map"): return
	game.cancel_armed()
	# Launched: 20 Wood, four crates aboard, the fifth left beside the Keep.
	if not check(keep.launch_balloon(far),"With crates and Wood the Keep should launch"): return
	var balloon := newest_balloon()
	if balloon != null: balloon.set_process(false)
	await process_frame
	if not check(balloon != null and balloon.team == "player" and balloon.crates.size() == 4,"A balloon carrying four crates should be up"): return
	if not check(keep.stockpile.amount(&"wood") == 30,"A launch costs 20 Wood, Keep has %d" % keep.stockpile.amount(&"wood")): return
	if not check(CrateYard.beside(keep).size() == 1,"One crate should be left beside the Keep"): return
	if not check(is_equal_approx(balloon.height,rules.balloon_dock_height),"It lifts off the Keep's dock"): return
	# It takes no orders.
	balloon.run_order({kind = "move", point = keep.global_position})
	balloon.command_move(keep.global_position)
	if not check(balloon.move_goal.distance_to(Vector3(far.x,0,far.z)) < 0.01,"The balloon should refuse other orders"): return
	# It flies there, lands and sets the four crates down.
	var balloon_id := balloon.get_instance_id()
	for i in range(80):
		step([balloon],0.5)
		await process_frame
		if not is_instance_valid(balloon) or balloon.is_queued_for_deletion(): break
	if not check(not is_instance_id_valid(balloon_id) or instance_from_id(balloon_id).is_queued_for_deletion(),"The balloon should land and be gone within 40 s"): return
	await process_frame
	var landed := crates_near(far,8.0)
	var total := {}
	for crate in landed: total[crate.resource_kind] = total.get(crate.resource_kind,0)+crate.amount
	# The crate left behind and the four set down are the five packed.
	for crate in CrateYard.beside(keep): total[crate.resource_kind] = total.get(crate.resource_kind,0)+crate.amount
	if not check(landed.size() == 4 and landed.all(func(c): return c.amount == 25) and total == {&"wood": 50, &"iron": 50, &"food": 25},"Four full crates should be set down at the point: %s" % total): return
	for crate in CrateYard.beside(keep): crate.queue_free()
	for crate in landed: crate.queue_free()
	# Inside a friendly Keep's range it unloads into that Keep.
	pack(keep,[&"food",&"iron",&"iron"])
	var near: Vector3 = keep.global_position+Vector3(radius-8.0,0,0)
	var iron_before: int = keep.stockpile.amount(&"iron")
	var food_before: int = keep.stockpile.amount(&"food")
	if not check(keep.launch_balloon(near),"A balloon can be sent inside the Keep's own range"): return
	balloon = newest_balloon()
	balloon.set_process(false)
	await process_frame
	for i in range(80):
		step([balloon],0.5)
		await process_frame
		if not is_instance_valid(balloon) or balloon.is_queued_for_deletion(): break
	await process_frame
	if not check(keep.stockpile.amount(&"iron") == iron_before+50 and keep.stockpile.amount(&"food") == food_before+25,"Landing in a Keep's range unloads into it"): return
	if not check(crates_near(near,8.0).is_empty(),"Nothing is set down when the Keep takes it all"): return
	# Shot down, it drops nothing.
	keep.stockpile.deposit(&"wood",20)
	pack(keep,[&"iron",&"iron"])
	if not check(keep.launch_balloon(far),"A third balloon goes up"): return
	balloon = newest_balloon()
	balloon.set_process(false)
	await process_frame
	step([balloon],3.0)
	var at: Vector3 = balloon.global_position
	balloon.take_damage(40)
	await process_frame
	await process_frame
	if not check(crates_near(at,12.0).is_empty() and crates_near(far,8.0).is_empty(),"A balloon shot down drops nothing"): return
	print("AIR_BALLOON_TEST_PASSED")
	quit(0)
