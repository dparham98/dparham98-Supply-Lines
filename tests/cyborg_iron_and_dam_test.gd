extends SceneTree
# Headless (item 4 of the Round 3 handoff; docs/ROUND3_CYBORG_ECONOMY.md):
# - Cyborg prices: units and buildings shifted toward iron; the Generator is 0 E / 40 I.
# - Production power goes to 3x; 2x prints in half the time for 135% of the base energy.
# - Workers' Iron and Wood wait at a Depot whose Iron, Wood and Coal reach 1,400; Coal still drops off.
# - Two Lakes' mine sites hold their tier's reserve.
# - The Hydro Dam is planned only across a dam channel (snapped onto it), is refused on land, is built by a Deforester
#   from the bank with the iron on its water footprint, and banks 12 E every 3 s into its covering Depot while it has
#   room. The Build page offers it only on a map with channels.
# - The AI plans a dam across a channel one of its Depots covers, and keeps a Drone behind its front Tank.
var game: Node3D
var network: Node
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func open(path: String) -> void:
	if is_instance_valid(game):
		game.queue_free()
		await process_frame
	game = load(path).instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	network = game.get_node("DepotNetwork")
	game.set_process(false)
	game.get_node("Interface").set_process(false)
	var ai = game.get_node_or_null("EnemyPlayer")
	if ai != null: ai.set_process(false)
	for group in ["units","depots","production_buildings","farms","houses","energy_generators","hydro_dams","mines","fog_of_war"]:
		for node in get_nodes_in_group(group): node.set_process(false)
func spawn(id: String, point: Vector3, team := "player") -> Node3D:
	var unit = load("res://scenes/gameplay/"+id+".tscn").instantiate()
	unit.team = team
	game.get_node("Entities/Units").add_child(unit)
	unit.set_process(false)
	unit._stop_route()
	for cell in unit._claimed.duplicate(): unit._release(cell)
	place(unit,game.ground.nearest_actor_cell(game.ground.get_tile_at_position(point),unit.mobility_layer(),unit._owner_key()))
	unit._attack_enabled = false
	return unit
func place(unit: Node3D, cell: Vector2i) -> void:
	for claimed in unit._claimed.duplicate(): unit._release(claimed)
	unit.grid_position = cell
	unit.global_position = game.ground.tile_to_world(cell)
	unit._claim(cell)
func step(nodes: Array, seconds: float, until := Callable()) -> float:
	var frames := ceili(seconds*60)
	for i in range(frames):
		for node in nodes:
			if is_instance_valid(node) and node.is_inside_tree(): node._process(1.0/60)
		if until.is_valid() and until.call(): return (i+1)/60.0
	return seconds
## A plan finished at once from its materials, as the playtest tools do.
func stand(kind: StringName, point: Vector3, team := "player") -> Node3D:
	var plan = network.queue_plan(point,kind,null,false,false,team)
	if plan == null: return null
	var building = network.finish_plan(plan)
	plan.queue_free()
	return building
## A Depot for `team` somewhere within `reach` of `point` on open ground.
func depot_near(point: Vector3, reach: float, team := "player") -> Node3D:
	for r in range(0,int(reach),2):
		for i in range(16):
			var at := point+Vector3(cos(i*TAU/16),0,sin(i*TAU/16))*r
			var depot := stand(&"depot",at,team)
			if depot != null: return depot
	return null
func run() -> void:
	if not await prices(): return
	if not await ceiling(): return
	if not await reserves(): return
	if not await dam(): return
	if not await ai(): return
	print("CYBORG_IRON_AND_DAM_TEST_PASSED")
	quit()
func prices() -> bool:
	var units := {"infantry":[90,25],"scout":[35,10],"grenadier":[75,20],"motorcycle":[60,25],"drone":[50,15],"tank":[140,55],"ubermech":[240,100]}
	for id in units:
		var stats: UnitStats = load("res://assets/units/%s.tres" % id)
		if not check(stats.energy_cost == units[id][0] and stats.iron_cost == units[id][1],"%s costs %d E / %d I, not %d / %d" % [id,stats.energy_cost,stats.iron_cost,units[id][0],units[id][1]]): return false
	var buildings := {"barracks":[80,60],"tank_factory":[150,100],"foundry":[120,100]}
	for id in buildings:
		var stats = load("res://assets/buildings/%s.tres" % id)
		if not check(stats.energy_cost == buildings[id][0] and stats.iron_cost == buildings[id][1],"%s costs %d E / %d I" % [id,stats.energy_cost,stats.iron_cost]): return false
	var supply: SupplyRules = load("res://assets/economy/supply_rules.tres")
	if not check(supply.generator_energy_cost == 0 and supply.generator_iron_cost == 40,"The Generator should cost 0 E / 40 I"): return false
	for id in ["barracks","tank_factory"]:
		var stats: ProductionBuildingStats = load("res://assets/buildings/%s.tres" % id)
		if not check(stats.max_power == 3.0 and is_equal_approx(stats.extra_power_energy_scale,0.35),"%s: power to 3x, +35%% energy a step" % id): return false
	await open("res://scenes/maps/resource_skirmish.tscn")
	var barracks := stand(&"barracks",game.depot.global_position+Vector3(-30,0,-50))
	if not check(barracks != null,"No Barracks"): return false
	var infantry: PackedScene = load("res://scenes/gameplay/infantry.tscn")
	barracks.set_power(2.0)
	if not check(is_equal_approx(barracks.seconds_at_power(infantry),5.0) and barracks.energy_at_power(infantry) == 122,"At 2x Infantry should take 5 s (half) for 122 E (135%% of 90): %.2f s, %d E" % [barracks.seconds_at_power(infantry),barracks.energy_at_power(infantry)]): return false
	barracks.set_power(3.0)
	if not check(barracks.power == 3.0 and barracks.energy_at_power(infantry) == 153,"At 3x Infantry should cost 153 E (170%%)"): return false
	return true
func ceiling() -> bool:
	await open("res://scenes/maps/resource_skirmish.tscn")
	var depot = game.depot
	if not check(depot.rules.raw_material_ceiling == 1400,"The raw-material ceiling should be 1,400"): return false
	depot.energy = 0; depot.iron = 1000; depot.wood = 300; depot.coal = 100
	if not check(depot.raw_material_total() == 1400 and depot.raw_ceiling_reached(),"Iron, Wood and Coal at 1,400 reach the ceiling"): return false
	var worker := spawn("infantry",depot.global_position+Vector3(0,0,10))
	worker.cargo = 10; worker.cargo_kind = &"iron"
	worker.command_return(depot)
	step([worker],20.0,func(): return worker.state.contains("raw-material ceiling"))
	if not check(worker.state.contains("raw-material ceiling") and worker.cargo == 10 and depot.iron == 1000,"Iron should wait at the ceiling: %s, %d carried, %d iron" % [worker.state,worker.cargo,depot.iron]): return false
	worker.cargo_kind = &"wood"
	step([worker],1.0)
	if not check(worker.cargo == 10 and depot.wood == 300,"Wood should wait at the ceiling too"): return false
	worker.cargo_kind = &"coal"
	step([worker],2.0,func(): return worker.cargo == 0)
	if not check(worker.cargo == 0 and depot.coal == 110,"Coal should still drop off at the ceiling (%d coal)" % depot.coal): return false
	depot.iron = 900
	worker.cargo = 10; worker.cargo_kind = &"iron"
	worker.command_return(depot)
	step([worker],2.0,func(): return worker.cargo == 0)
	if not check(worker.cargo == 0 and depot.iron == 910,"Below the ceiling Iron drops off again (%d iron)" % depot.iron): return false
	return true
func reserves() -> bool:
	await open("res://scenes/maps/lakes_skirmish.tscn")
	var ground = game.ground
	for case in [["IronMine",2250],["Mine01",3500],["Mine05",5000],["Mine09",5000],["Mine11",8000]]:
		var mine = game.get_node("Entities/Buildings/"+case[0])
		var iron := 0
		for cell in mine.cells: iron += ground.iron_amount(cell)
		if not check(mine.site_reserve == case[1] and iron == case[1],"%s should hold %d iron: %d" % [case[0],case[1],iron]): return false
	return true
func dam() -> bool:
	await open("res://scenes/maps/lakes_skirmish.tscn")
	var ground = game.ground
	var hud = game.get_node("Interface")
	var channel := Rect2i(210,195,8,4)
	if not check(ground.dam_channels.size() == 11 and channel in ground.dam_channels,"Two Lakes should have its eleven dam channels"): return false
	var spec: Dictionary = network.plan_spec(&"hydro_dam")
	if not check(spec.size == Vector2i(8,3) and spec.energy == 0 and spec.iron == 90,"A Hydro Dam is 8 x 3 for 0 E / 90 I"): return false
	hud.refresh_global_menu()
	if not check(hud.build_menu.get_node("Actions/HydroDam").visible,"The Build page offers the Hydro Dam on Two Lakes"): return false
	# A Depot whose range reaches the inner north-west channel.
	var centre: Vector3 = ground.tile_to_world(Vector2i(214,197))
	var depot := depot_near(ground.tile_to_world(Vector2i(213,216)),12)
	if not check(depot != null and SupplySource.covers(depot,centre,"player"),"No Depot covers the channel"): return false
	# Refused on land.
	if not check(network.queue_plan(depot.global_position+Vector3(0,0,8),&"hydro_dam",null,false,false) == null,"A Hydro Dam should be refused on land"): return false
	# Planned from the bank, it snaps across the channel.
	var plan = network.queue_plan(ground.tile_to_world(Vector2i(207,197)),&"hydro_dam",null,false,false)
	if not check(plan != null and plan.start == Vector2i(210,196) and plan.spec.size == Vector2i(8,3),"A dam planned beside the channel should snap across it: %s" % (plan.start if plan != null else "refused")): return false
	if not check(network.queue_plan(centre,&"hydro_dam",null,false,false) == null,"A second dam cannot overlap the plan"): return false
	# A Deforester builds it from the bank: fell a pocket by the channel, as its axe would, and send it with 40 iron.
	for z in range(195,200):
		for x in range(205,210): ground.clear_forest(Vector2i(x,z))
	var builder := spawn("infantry",ground.tile_to_world(Vector2i(208,197)))
	if not check(builder.grid_position.x < 210,"The builder should stand on the bank"): return false
	plan.receive(&"iron",50)
	builder.cargo = 40; builder.cargo_kind = &"iron"
	builder.command_construct(plan)
	var seconds := step([builder,plan],120.0,func(): return not is_instance_valid(plan) or plan.finished)
	var dams := get_nodes_in_group("hydro_dams")
	if not check(dams.size() == 1,"The Deforester should build the dam (%s after %.0f s)" % [builder.state,seconds]): return false
	var dam = dams[0]
	if not check(dam.team == "player" and dam.cells.size() == 24 and ground.tiles[196*500+210].occupied_by == dam._key() and builder.cargo == 0,"The dam stands on its 24 water cells"): return false
	if not check(dam.assigned_depot == depot and dam.source_valid(),"The dam banks into the Depot that covers it"): return false
	if not check(not ground.dam_site_valid(Vector2i(210,196),Vector2i(8,3)),"A built dam takes its site"): return false
	# 12 E every 3 s.
	dam.set_process(false)
	depot.energy = 0; depot.iron = 0; depot.wood = 0; depot.coal = 0
	dam.beat_elapsed = 0.0
	step([dam],2.9)
	if not check(depot.energy == 0,"Nothing before the beat ends"): return false
	step([dam],0.2)
	if not check(depot.energy == 12 and is_equal_approx(dam.output_rate(),4.0),"12 E at the end of the beat, 4 E/s (%d)" % depot.energy): return false
	step([dam],6.0)
	if not check(depot.energy == 36,"Two beats more: 36 E (%d)" % depot.energy): return false
	# Full storage: it waits.
	depot.iron = depot.stockpile.space()-5
	var before: int = depot.energy
	step([dam],6.0)
	if not check(depot.energy == before and dam.state.contains("no room"),"With no room it banks nothing: %s" % dam.state): return false
	depot.iron = 0
	# No friendly Depot covering it: it pauses.
	depot.team = "enemy"
	before = depot.energy
	step([dam],4.0)
	if not check(depot.energy == before and dam.state.begins_with("Paused · no friendly Depot"),"Without a friendly Depot it pauses: %s" % dam.state): return false
	depot.team = "player"
	step([dam],3.5)
	if not check(depot.energy > before,"It banks again once the Depot is friendly"): return false
	# The HUD shows it as a dam.
	game.selected_building = dam
	hud.update_contents()
	if not check(hud.commands.get_node("Title").text == "HYDRO DAM · LOCAL POWER" and hud.name_label.text.contains("Hydro Dam"),"The HUD should show the dam: %s" % hud.commands.get_node("Title").text): return false
	game.selected_building = null
	# A map without channels offers no dam.
	await open("res://scenes/maps/resource_skirmish.tscn")
	game.get_node("Interface").refresh_global_menu()
	if not check(not game.get_node("Interface").build_menu.get_node("Actions/HydroDam").visible,"A map with no dam channels offers no dam"): return false
	if not check(network.queue_plan(game.depot.global_position+Vector3(-30,0,-50),&"hydro_dam",null,false,false) == null,"No dam can be planned without channels"): return false
	return true
func ai() -> bool:
	await open("res://scenes/maps/lakes_skirmish.tscn")
	var ground = game.ground
	var ai = game.get_node("EnemyPlayer")
	ai.build_step = 0
	if not check(ai.dam_site() == null,"The AI's start Depot covers no channel"): return false
	var depot := depot_near(ground.tile_to_world(Vector2i(286,216)),12,"enemy")
	if not check(depot != null and SupplySource.covers(depot,ground.tile_to_world(Vector2i(286,197)),"enemy"),"No enemy Depot covers the inner north-east channel"): return false
	var site = ai.dam_site()
	if not check(site != null and ground.get_tile_at_position(site) == Vector2i(286,196),"The AI should find the channel its Depot covers: %s" % [site]): return false
	if not check(ai.next_building() == ai.build_order[0],"Before dam_after_step the order comes first"): return false
	ai.build_step = ai.dam_after_step
	if not check(ai.next_building() == &"hydro_dam","Then a dam comes next"): return false
	if not check(stand(&"hydro_dam",site,"enemy") != null and ai.dam_site() == null,"With a dam across it the channel is done"): return false
	if not check(ai.next_building() == ai.build_order[ai.dam_after_step],"The order goes on where it was"): return false
	# The Drone escort: behind the front Tank, never ahead of it nor more than 10 m behind.
	var home: Vector3 = game.get_node("Entities/Buildings/EnemyDepot").global_position
	var tank_a := spawn("tank",home+Vector3(-20,0,10),"enemy")
	var tank_b := spawn("tank",home+Vector3(-32,0,10),"enemy")
	var drone := spawn("drone",home+Vector3(0,0,10),"enemy")
	var threat := Node3D.new()
	game.add_child(threat)
	threat.global_position = home+Vector3(-150,0,10)
	ai.army = [tank_a,tank_b,drone] as Array[Node3D]
	ai.wave = [] as Array[Node3D]
	var front: Node3D = ai.tank_front([tank_a,tank_b] as Array[Node3D],threat.global_position)
	var heading: Vector3 = ai.escort_heading([tank_a,tank_b] as Array[Node3D],threat.global_position)
	var further: Node3D = tank_a if tank_a.global_position.dot(heading) > tank_b.global_position.dot(heading) else tank_b
	if not check(front == further,"The front Tank is the one furthest toward the threat"): return false
	ai._escort_drones(null,threat)
	var behind: float = (front.global_position-drone.move_goal).dot(heading)
	if not check(drone.order == "move" and behind >= 0.0 and behind <= ai.drone_behind_front and ai._flat_distance(drone.move_goal,front.global_position) <= ai.drone_behind_front,"A Drone behind the Tanks' rear should come up behind the front Tank (%.1f m behind)" % behind): return false
	# One in place stays put.
	place(drone,ground.get_tile_at_position(drone.move_goal))
	drone.order = "idle"
	ai._escort_drones(null,threat)
	if not check(drone.order == "idle","A Drone already behind the front Tank stays"): return false
	# One ahead of the front drops back.
	place(drone,ground.get_tile_at_position(front.global_position+heading*12.0))
	ai._escort_drones(null,threat)
	behind = (front.global_position-drone.move_goal).dot(heading)
	if not check(drone.order == "move" and behind >= 0.0 and behind <= ai.drone_behind_front,"A Drone ahead of the Tanks should drop back behind the front one"): return false
	threat.queue_free()
	return true
