extends SceneTree
# Headless: Generators cost 0 E / 40 I, coal makes 30 E over 3 s, and a Generator stops at its Depot's
# energy ceiling and never burns the Depot's coal below its reserve, set on the Depot card (docs/GENERATOR_LIMITS.md).
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
	depot.cycle_energy_ceiling()
	if not check(depot.energy_ceiling == 1000,"The ceiling should step from 600 to 1000"): return
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
	depot.cycle_coal_reserve()
	depot.cycle_coal_reserve()
	depot.cycle_coal_reserve()
	if not check(depot.coal_reserve == 30,"The reserve should step 60, 120, 0, 30: %d" % depot.coal_reserve): return
	generator._process(3.0)
	if not check(depot.coal == 59,"A lower reserve should free coal: %d" % depot.coal): return
	# The presets wrap round, and the last ceiling is the Depot's own storage capacity (no ceiling).
	for step in [depot.storage_capacity,300,600]:
		depot.cycle_energy_ceiling()
		if not check(depot.energy_ceiling == step,"The ceiling should step to %d, is %d" % [step,depot.energy_ceiling]): return
	depot.storage_capacity = 600
	depot.energy_ceiling = 300
	depot.cycle_energy_ceiling()
	if not check(depot.energy_ceiling == 600 and depot.energy_ceilings() == [300,600],"A 600-unit Depot's ceilings should be 300 and 600: %s" % [depot.energy_ceilings()]): return
	depot.storage_capacity = 2000
	# The Depot card: the buttons step the settings, with keys H and J; other sides' Depots do not show them.
	var hud: CanvasLayer = game.get_node("Interface")
	hud.set_process(false)
	game.selected_building = depot
	hud._process(0)
	var ceiling_tile: Button = hud.card.get_node("EnergyCeiling")
	var reserve_tile: Button = hud.card.get_node("CoalReserve")
	if not check(ceiling_tile.visible and reserve_tile.visible and hud.hotkey_text(ceiling_tile) == "H" and hud.hotkey_text(reserve_tile) == "J","The Depot card should show both settings with keys H and J"): return
	if not check(hud.context.get_node("Stats/V1").text == "600 E" and hud.context.get_node("Stats/V2").text == "30","The Depot card should show the settings: %s, %s" % [hud.context.get_node("Stats/V1").text,hud.context.get_node("Stats/V2").text]): return
	ceiling_tile.pressed.emit()
	reserve_tile.pressed.emit()
	if not check(depot.energy_ceiling == 1000 and depot.coal_reserve == 60,"The buttons should step the settings: %d E, %d coal" % [depot.energy_ceiling,depot.coal_reserve]): return
	depot.team = "hostile"
	hud._process(0)
	if not check(not ceiling_tile.visible and not reserve_tile.visible and not hud.context.get_node("Stats").visible,"Another side's Depot should not show its settings"): return
	depot.team = "player"
	game.selected_building = null
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
