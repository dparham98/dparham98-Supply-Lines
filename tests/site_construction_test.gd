extends SceneTree
# Headless: construction from site materials (docs/SITE_CONSTRUCTION.md). A funded Depot no longer
# builds a plan on its own; iron must lie inside the footprint (piles or crates, delivered by a Cargo
# truck or a worker, or already there when the plan is placed) and Infantry build it in at their
# work pace while the covering stockpile pays energy as they go. Rails keep the Depot-paid rule.
var game: Node3D
var network: Node
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> bool:
	if ok: return true
	push_error(message); quit(1); return false
func actor(id: String, team: String, point: Vector3) -> Node3D:
	var unit = load("res://scenes/gameplay/"+id+".tscn").instantiate()
	unit.team = team
	game.get_node("Entities/Units").add_child(unit)
	unit.set_process(false)
	for cell in unit._claimed.duplicate(): unit._release(cell)
	unit.global_position = point
	return unit
func site(kind: StringName, near: Vector3) -> Vector3:
	var spec: Dictionary = network.plan_spec(kind)
	for radius in range(10,100,4):
		for offset in [Vector3(radius,0,0),Vector3(-radius,0,0),Vector3(0,0,radius),Vector3(0,0,-radius)]:
			var point: Vector3 = near+offset
			var start: Vector2i = network.footprint_start(point,spec.size)
			if network.plan_terrain_valid(start,spec.size,kind) and not network.plan_overlaps(start,spec.size) and network.can_place_size(point,game.depot,spec.size): return point
	return Vector3.INF
func run() -> void:
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	for i in range(3): await process_frame
	network = game.get_node("DepotNetwork")
	game.set_process(false)
	for unit in get_nodes_in_group("units"): unit.set_process(false)
	for depot in get_nodes_in_group("depots"): depot.set_process(false)
	var depot = game.depot
	# The player starts with an Infantry and a fuelled, empty Cargo truck.
	var start_truck = game.get_node_or_null("Entities/Units/CargoTruck")
	if not check(start_truck != null and start_truck.is_cargo_vehicle and start_truck.team == "player","No starting Cargo truck"): return
	if not check(start_truck.fuel_rules != null and is_equal_approx(start_truck.fuel,start_truck.fuel_rules.reserve_capacity),"Starting truck should have a full tank: %.1f" % start_truck.fuel): return
	if not check(start_truck.crates.is_empty() and start_truck.stockpile.total() == 0,"Starting truck should be empty"): return
	# A funded Depot does not complete a building plan by itself any more.
	depot.energy = 1000; depot.iron = 500
	var point := site(&"generator",depot.global_position)
	if not check(point != Vector3.INF,"No generator site"): return
	var spec: Dictionary = network.plan_spec(&"generator")
	var plan = network.queue_plan(point,&"generator")
	if not check(plan != null,"Plan not placed"): return
	plan.set_process(false)
	plan.elapsed = 1.0; plan._process(0.0)
	for i in range(2): plan.refresh_state()
	if not check(get_nodes_in_group("construction_plans").has(plan) and depot.iron == 500 and depot.energy == 1000 and not plan.materials_covered(),"Depot stock built the plan without site materials"): return
	if not check(plan.state == "Waiting for materials on site" and plan.site_text().begins_with("Iron on site 0/%d" % spec.iron),"Plan should wait for materials: %s / %s" % [plan.state,plan.site_text()]): return
	# A truck unloads crates onto the site; the site takes only what the build lacks.
	var truck := actor("cargo_vehicle","player",point+Vector3(plan.dropoff_range-0.5,0,0))
	for crate in [{kind = &"iron", amount = 25},{kind = &"iron", amount = 25},{kind = &"wood", amount = 25}]: truck.crates.append(crate)
	truck._sync_reserved()
	if not check(truck.stop_valid("unload",plan,plan.global_position),"Truck cannot unload at a build site"): return
	truck.command_unload(plan)
	if not check(truck.order == "unload" and truck.job_target == plan,"Unload order not accepted"): return
	for i in range(30): truck._process(0.1)
	var delivered: int = mini(spec.iron,50)
	if not check(plan.on_site(&"iron") == delivered,"Site should hold %d iron, has %d" % [delivered,plan.on_site(&"iron")]): return
	if not check(truck.crate_units(&"wood") == 25 and truck.crate_units(&"iron") == 50-delivered,"Truck should keep wood and surplus iron aboard: %s" % [truck.crates]): return
	var piles: Array = plan.site_stores()
	if not check(piles.size() == 1 and piles[0].is_in_group("material_piles") and plan.inside(piles[0].global_position),"Delivery should form one pile inside the footprint"): return
	# A worker carrying iron tops the pile up by right-click construct, then builds.
	var worker := actor("infantry","player",point+Vector3(0,0,plan.dropoff_range+1.5))
	worker.cargo_kind = &"iron"; worker.cargo = 10
	var before_site: int = plan.on_site(&"iron")
	worker.command_construct(plan)
	if not check(worker.order == "construct","Construct order not accepted"): return
	worker._process(0.1)
	var topped: int = mini(10,spec.iron-before_site)
	if not check(plan.on_site(&"iron") == before_site+topped and worker.cargo == 10-topped,"Worker did not deliver its cargo to the site"): return
	# Shortfall: a plain pile and a crate dropped on the footprint both count.
	var still_short: int = plan.shortfall(&"iron")
	if still_short > 0:
		var crate = CrateYard.spawn(self,network.footprint_start(point,spec.size),&"iron",still_short,"player")
		if not check(plan.on_site(&"iron") == spec.iron and plan.materials_covered(),"Crate inside the footprint should count toward the site"): return
	plan.refresh_state()
	if not check(plan.state.begins_with("Materials on site"),"Covered site should say so: %s" % plan.state): return
	if not check(plan.get_node("Visuals/Grid").material_override.get_shader_parameter("tint").g > 0.9,"Grid should turn green when the site is covered"): return
	# Construction ticks: 5 iron per work cycle, energy charged in step, nothing from Depot iron.
	var iron_before: int = depot.iron
	var energy_before: int = depot.energy
	worker._work_timer = worker.harvest_interval
	worker._process(0.0)
	if not check(plan.added.get(&"iron",0) == 5 and plan.on_site(&"iron") == spec.iron-5,"First tick should build in 5 iron: added %s" % [plan.added]): return
	var expected_energy: int = ceili(spec.energy*5.0/spec.iron)
	if not check(depot.energy == energy_before-expected_energy and depot.iron == iron_before,"Energy should be charged in step (%d) and Depot iron untouched" % expected_energy): return
	if not check(worker.state == "Constructing" and plan.state.begins_with("Constructing"),"States should read Constructing: %s / %s" % [worker.state,plan.state]): return
	# No energy: the tick waits without taking materials.
	depot.energy = 0
	var added_before: int = plan.added[&"iron"]
	worker._work_timer = worker.harvest_interval; worker._process(0.0)
	if not check(plan.added[&"iron"] == added_before and worker.state.begins_with("Waiting for energy"),"Tick without energy should wait: %s" % worker.state): return
	depot.energy = 1000
	var generators_before: int = get_nodes_in_group("energy_generators").size()
	var rect: Rect2i = plan.footprint()
	for i in range(60):
		worker._work_timer = worker.harvest_interval; worker._process(0.0)
		if not get_nodes_in_group("construction_plans").has(plan): break
	if not check(get_nodes_in_group("energy_generators").size() == generators_before+1,"Plan did not finish into a Generator"): return
	if not check(plan.energy_paid == spec.energy and depot.energy == 1000-(spec.energy-expected_energy) and depot.iron == iron_before,"Energy total should equal the cost; iron never from the Depot"): return
	var built = get_nodes_in_group("energy_generators")[generators_before]
	if not check(built.assigned_depot == depot,"Energy payer should operate the building"): return
	if not check(worker.order == "idle" and worker.state == "Construction complete","Worker should stand down: %s" % worker.state): return
	# Nothing is left lying under the finished building.
	if not check(network.stores_inside(rect).is_empty(),"Leftover stores should be moved off the footprint"): return
	# Placing a plan on an existing pile adopts it, and the preview reports it.
	var point2 := site(&"barracks",depot.global_position+Vector3(0,0,40))
	if not check(point2 != Vector3.INF,"No barracks site"): return
	var spec2: Dictionary = network.plan_spec(&"barracks")
	var pile = game.pile_scene.instantiate()
	pile.material_kind = "iron"; pile.amount = spec2.iron
	pile.position = game.ground.tile_to_world(network.footprint_start(point2,spec2.size))
	game.get_node("Entities/Resources").add_child(pile,true)
	if not check(network.materials_inside(Rect2i(network.footprint_start(point2,spec2.size),spec2.size)).get(&"iron",0) == spec2.iron,"Preview should see the pile"): return
	var plan2 = network.queue_plan(point2,&"barracks")
	if not check(plan2 != null and plan2.materials_covered() and plan2.on_site(&"iron") == spec2.iron,"Plan on a pile should start covered"): return
	plan2.set_process(false)
	# Cancelling leaves the pile.
	plan2.cancel()
	if not check(is_instance_valid(pile) and pile.remaining == spec2.iron,"Cancel should leave the pile"): return
	# Rails keep the Depot-paid instant rule.
	var rail_cell: Vector2i = network.footprint_start(depot.global_position+Vector3(0,0,-14),Vector2i.ONE)
	var rails = game.get_node("RailNetwork")
	if rails.can_build(rail_cell,depot):
		var rail_plan = network.queue_plan(game.ground.tile_to_world(rail_cell),&"rail")
		if not check(rail_plan != null,"Rail plan not placed"): return
		rail_plan.set_process(false)
		var rail_iron: int = depot.iron
		rail_plan.elapsed = 1.0; rail_plan._process(0.0)
		if not check(not get_nodes_in_group("construction_plans").has(rail_plan) and depot.iron == rail_iron-network.plan_spec(&"rail").iron,"Rail should still complete from Depot stock"): return
	print("SITE_CONSTRUCTION_TEST_PASSED"); quit()
