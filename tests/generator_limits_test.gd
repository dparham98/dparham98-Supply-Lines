extends SceneTree
# Headless: Generators cost 0 E / 40 I, coal makes 30 E over 3 s, and a Generator stops at its Depot's
# energy ceiling and never burns the Depot's coal below its reserve, set on the Depot panel (docs/GENERATOR_LIMITS.md,
# docs/DEPOT_PANELS.md).
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func run() -> void:
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	var supply: SupplyRules = load("res://assets/economy/supply_rules.tres")
	if not check(supply.generator_energy_cost == 0 and supply.generator_iron_cost == 40,"A Generator should cost 0 E / 40 I"): return
	var depot: Node3D = null
	for node in get_nodes_in_group("depots"):
		if node.team == "player": depot = node; break
	if not check(depot != null,"No player Depot"): return
	if not check(depot.energy_ceiling == 600 and depot.coal_reserve == 60,"A Depot should default to a 600 E ceiling and 60 coal kept"): return
	var ground = game.ground
	var corner: Vector2i = ground.find_buildable_footprint(ground.get_tile_at_position(depot.global_position),Vector2i(3,3))
	if not check(corner.x >= 0,"No room for a Generator"): return
	var generator: Node3D = load("res://scenes/gameplay/energy_generator.tscn").instantiate()
	generator.assigned_depot = depot
	generator.position = ground.tile_to_world(corner+Vector2i(1,1))
	game.get_node("Entities/Buildings").add_child(generator)
	await process_frame
	if not check(is_instance_valid(generator) and generator.is_in_group("energy_generators"),"Generator could not be placed"): return
	generator.set_process(false)
	if not check(generator.fuel_rules.coal_output == 30 and is_equal_approx(generator.fuel_rules.coal_seconds,3.0),"Coal should make 30 E over 3 s"): return
	generator.set_fuel_preference("coal")
	depot.wood = 0
	depot.iron = 0
	# One coal makes 30 E in 3 s.
	depot.energy = 100
	depot.coal = 100
	generator._process(3.0)
	if not check(depot.energy == 130 and depot.coal == 99,"One coal should make 30 E in 3 s: %d E, %d coal" % [depot.energy,depot.coal]): return
	# The ceiling: at 600 E no cycle starts and no coal is burnt.
	depot.energy = 600
	generator._process(30.0)
	if not check(depot.energy == 600 and depot.coal == 99,"A Generator should not run at the 600 E ceiling: %d E, %d coal" % [depot.energy,depot.coal]): return
	if not check(not generator.active() and generator.describe_state().contains("600 E ceiling"),"The Generator should say it is at the ceiling: %s" % generator.describe_state()): return
	# Below it, a cycle starts and finishes: the Depot reaches the ceiling, passing it by under one cycle.
	depot.energy = 580
	generator._process(30.0)
	if not check(depot.energy == 610 and depot.coal == 98,"It should fill to the ceiling and stop: %d E, %d coal" % [depot.energy,depot.coal]): return
	if not check(generator.describe_state().contains("600 E ceiling"),"It should then say it is at the ceiling: %s" % generator.describe_state()): return
	# A higher ceiling lets it run on.
	depot.set_energy_ceiling(1000)
	if not check(depot.energy_ceiling == 1000,"The ceiling should be raised to 1000"): return
	generator._process(3.0)
	if not check(depot.energy == 640,"A raised ceiling should let it run on: %d E" % depot.energy): return
	# The reserve: coal is never burnt below 60.
	depot.energy = 0
	depot.coal = 64
	generator._process(60.0)
	if not check(depot.coal == 60 and depot.energy == 120,"A Generator should burn coal down to the 60 kept, no further: %d coal, %d E" % [depot.coal,depot.energy]): return
	if not check(not generator.active() and generator.describe_state().contains("60 coal kept"),"The Generator should say coal is kept for vehicles: %s" % generator.describe_state()): return
	# Either mode burns wood, and coal only above the reserve.
	generator.set_fuel_preference("either")
	depot.wood = 2
	generator._process(60.0)
	if not check(depot.wood == 0 and depot.coal == 60,"Either should burn all the wood and keep the coal: %d wood, %d coal" % [depot.wood,depot.coal]): return
	# A wood cycle in Either mode whose wood is taken waits for wood, not for the coal reserve.
	depot.coal = 100
	depot.wood = 1
	generator._process(1.0)
	depot.wood = 0
	generator._process(1.0)
	if not check(generator.cycle_kind == &"wood" and generator.describe_state() == "Waiting for wood fuel","A latched wood cycle should wait for wood: %s" % generator.describe_state()): return
	generator.reset_cycle()
	depot.coal = 60
	# A lower reserve frees coal at once.
	depot.set_coal_reserve(30)
	if not check(depot.coal_reserve == 30,"The reserve should be lowered to 30: %d" % depot.coal_reserve): return
	generator._process(3.0)
	if not check(depot.coal == 59,"A lower reserve should free coal: %d" % depot.coal): return
	# The sliders' values snap to 50 E and 10 coal and stay in range; the ceiling tops out at the Depot's storage.
	depot.set_energy_ceiling(1234)
	if not check(depot.energy_ceiling == 1250,"The ceiling should snap to 50 E: %d" % depot.energy_ceiling): return
	depot.set_energy_ceiling(99999)
	if not check(depot.energy_ceiling == depot.storage_capacity,"The ceiling should stop at the storage capacity: %d" % depot.energy_ceiling): return
	depot.set_coal_reserve(1000)
	if not check(depot.coal_reserve == depot.COAL_RESERVE_MAX,"The coal kept should stop at %d: %d" % [depot.COAL_RESERVE_MAX,depot.coal_reserve]): return
	depot.set_coal_reserve(-5)
	if not check(depot.coal_reserve == 0,"The coal kept should not go below 0: %d" % depot.coal_reserve): return
	depot.set_energy_ceiling(600)
	depot.set_coal_reserve(30)
	# The Depot panels: your Depot shows its energy panel top left and its storage top right. The sliders set
	# the ceiling and the coal kept. The card has no setting tiles or keys any more.
	var hud: CanvasLayer = game.get_node("Interface")
	hud.set_process(false)
	game.selected_building = depot
	hud._process(0)
	var body: Control = hud.depot_panel.get_node("Body")
	var ceiling_slider: HSlider = body.get_node("CeilingSlider")
	var coal_slider: HSlider = body.get_node("CoalSlider")
	if not check(hud.depot_panel.visible and hud.storage_panel.visible and not hud.info.get_node("Storage").visible,"Your Depot should show both panels, its storage moved out of the bottom panel"): return
	if not check(not hud.card.has_node("EnergyCeiling") and not hud.card.has_node("CoalReserve") and not InputMap.has_action("command_energy_ceiling") and not InputMap.has_action("command_coal_reserve"),"The Depot card's setting tiles and keys should be gone"): return
	if not check(body.get_node("Ceiling/Value").text == "600 E" and body.get_node("Coal/Value").text == "30" and ceiling_slider.value == 600 and coal_slider.value == 30,"The panel should show the settings: %s, %s" % [body.get_node("Ceiling/Value").text,body.get_node("Coal/Value").text]): return
	# The current energy stock against storage (playtest note, docs/DEPOT_PANELS.md).
	depot.energy = 1240
	hud._process(0)
	var stock_text := "%s / %s E" % [hud.grouped(1240),hud.grouped(depot.storage_capacity)]
	if not check(body.get_node("Stock/Value").text == stock_text and body.get_node("Stock/Value").text.begins_with("1"),"The panel should show the energy stock: "+body.get_node("Stock/Value").text): return
	if not check(ceiling_slider.max_value == depot.storage_capacity and ceiling_slider.focus_mode == Control.FOCUS_NONE,"The ceiling slider should run to the storage capacity and take no keyboard focus"): return
	ceiling_slider.value = 1000
	coal_slider.value = 60
	if not check(depot.energy_ceiling == 1000 and depot.coal_reserve == 60,"The sliders should set the settings: %d E, %d coal" % [depot.energy_ceiling,depot.coal_reserve]): return
	ceiling_slider.value = depot.storage_capacity
	hud._process(0)
	if not check(body.get_node("Ceiling/Value").text == "No ceiling","All the way right should read No ceiling: "+body.get_node("Ceiling/Value").text): return
	depot.set_energy_ceiling(1000)
	# Banking: the bar is the live rate against every Generator running on its faster fuel (here coal, 10 E/s).
	depot.energy = 0
	depot.coal = 100
	generator.reset_cycle()
	generator._process(0.5)
	hud._process(0)
	var bar: ProgressBar = body.get_node("Rate")
	if not check(is_equal_approx(bar.value,depot.generation_rate()) and depot.generation_rate() > 0 and is_equal_approx(bar.max_value,10.0),"The banking bar should show the rate: %.1f of %.1f" % [bar.value,bar.max_value]): return
	if not check(body.get_node("Banking/Value").text == "+%.1f E/s" % depot.generation_rate() and not body.get_node("Note").visible,"The banking value is wrong: "+body.get_node("Banking/Value").text): return
	generator.enabled = false
	hud._process(0)
	if not check(body.get_node("Banking/Value").text == "0 E/s" and body.get_node("Note").visible and body.get_node("Note").text == "Paused by player","A stopped Generator should say why: "+body.get_node("Note").text): return
	generator.enabled = true
	# The storage panel's alert feed moves down under it.
	if not check(hud.feed.offset_top > hud.storage_panel.position.y+hud.storage_panel.size.y,"The alert feed should sit under the storage panel"): return
	# A Generator in the Depot's range shows its Depot's panels.
	game.selected_building = generator
	hud._process(0)
	if not check(hud.depot_panel.visible and hud.panel_depot == depot and hud.storage_panel.get_node("Storage/Head/Label").text == "%s storage" % depot.name,"A Generator should show its Depot's panels"): return
	# Another side's Depot shows neither; its storage stays in the bottom panel.
	game.selected_building = depot
	depot.team = "hostile"
	hud._process(0)
	if not check(not hud.depot_panel.visible and not hud.storage_panel.visible and hud.info.get_node("Storage").visible,"Another side's Depot should not show the panels"): return
	depot.team = "player"
	game.selected_building = null
	hud._process(0)
	if not check(not hud.depot_panel.visible and not hud.storage_panel.visible and hud.feed.offset_top == hud.FEED_TOP,"Nothing selected should hide the panels and put the feed back"): return
	# Built at the real price: a Generator plan takes 40 iron and no energy.
	var network = game.get_node("DepotNetwork")
	var spec: Dictionary = network.plan_spec(&"generator")
	var point := Vector3.INF
	for radius in range(10,100,4):
		for offset in [Vector3(radius,0,0),Vector3(-radius,0,0),Vector3(0,0,radius),Vector3(0,0,-radius)]:
			var start: Vector2i = network.footprint_start(depot.global_position+offset,spec.size)
			if point == Vector3.INF and network.plan_terrain_valid(start,spec.size,&"generator") and not network.plan_overlaps(start,spec.size) and network.can_place_size(depot.global_position+offset,depot,spec.size): point = depot.global_position+offset
	if not check(point != Vector3.INF,"No site for a Generator plan"): return
	var plan = network.queue_plan(point,&"generator",depot)
	if not check(plan != null,"The Generator plan was refused"): return
	plan.set_process(false)
	depot.energy = 0
	depot.iron = 40
	var built = plan.complete_from_stock()
	if not check(built != null and depot.energy == 0 and depot.iron == 0,"A Generator should be built for 40 iron and no energy: %d E, %d I" % [depot.energy,depot.iron]): return
	print("GENERATOR_LIMITS_TEST_PASSED")
	quit()
