extends SceneTree
# Production queues and power (docs/PRODUCTION_POWER.md): five units queue, each takes its build time at 1x and its
# base energy; more power divides the time and draws the extra energy from the assigned Depot while the unit prints;
# a Depot that cannot pay prints at 1x; the HUD's slider under the Depot panel sets the power.
var game: Node3D
var network: Node
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> bool:
	if ok: return true
	push_error(message); quit(1); return false
func site(kind: StringName, near: Vector3) -> Vector3:
	var spec: Dictionary = network.plan_spec(kind)
	for radius in range(10,100,4):
		for offset in [Vector3(radius,0,0),Vector3(-radius,0,0),Vector3(0,0,radius),Vector3(0,0,-radius)]:
			var point: Vector3 = near+offset
			var start: Vector2i = network.footprint_start(point,spec.size)
			if network.plan_terrain_valid(start,spec.size,kind) and not network.plan_overlaps(start,spec.size) and network.can_place_size(point,game.depot,spec.size): return point
	return Vector3.INF
func build(kind: StringName) -> Node3D:
	var point := site(kind,game.depot.global_position)
	if point == Vector3.INF: return null
	var plan = network.queue_plan(point,kind)
	if plan == null: return null
	plan.set_process(false)
	var building: Node3D = plan.complete_from_stock()
	if building != null: building.set_process(false)
	return building
## Runs the building in 1/60 s steps until its queue shrinks; returns the seconds taken.
func run_until_produced(building: Node3D, limit: float) -> float:
	var start: int = building.queue
	var seconds := 0.0
	while building.queue == start and seconds < limit:
		building._process(1.0/60)
		seconds += 1.0/60
	return seconds
func run() -> void:
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	for i in range(3): await process_frame
	network = game.get_node("DepotNetwork")
	game.set_process(false)
	for unit in get_nodes_in_group("units"): unit.set_process(false)
	for depot in get_nodes_in_group("depots"): depot.set_process(false)
	var depot = game.depot
	depot.storage_capacity = 100000
	depot.energy = 20000; depot.iron = 20000
	var barracks := build(&"barracks")
	if not check(barracks != null,"No Barracks"): return
	var factory := build(&"tank_factory")
	if not check(factory != null,"No Tank Factory"): return
	# Base build times: Barracks units take 8-12 s, Tank Factory units 14-40 s.
	var times := {"scout":8.0,"infantry":10.0,"grenadier":12.0,"motorcycle":14.0,"drone":16.0,"tank":28.0,"ubermech":40.0}
	for id in times:
		var stats: UnitStats = load("res://assets/units/%s.tres" % id)
		if not check(is_equal_approx(stats.build_seconds,times[id]),"%s should take %.0f s at 1x, not %.1f" % [id,times[id],stats.build_seconds]): return
	if not check(barracks.stats.queue_limit == 5 and factory.stats.queue_limit == 5,"Production buildings queue five"): return
	if not check(barracks.stats.max_power == 4.0 and barracks.power == 1.0,"Power starts at 1x and goes to 4x"): return
	# Five queue, paying each unit's base cost; a sixth is refused and costs nothing.
	var energy: int = depot.energy
	for i in range(5):
		if not check(barracks.request_unit(&"infantry"),"Infantry %d not queued" % (i+1)): return
	if not check(depot.energy == energy-500 and barracks.queue == 5,"Five Infantry should cost 5 x 100 E at queueing (%d)" % (energy-depot.energy)): return
	if not check(not barracks.request_unit(&"infantry") and depot.energy == energy-500,"A sixth should be refused without payment"): return
	# 1x: ten seconds and no more energy.
	energy = depot.energy
	var seconds := run_until_produced(barracks,30)
	if not check(absf(seconds-10.0) < 0.03 and depot.energy == energy,"Infantry at 1x: 10 s and no extra energy (%.2f s, %d E)" % [seconds,energy-depot.energy]): return
	# Power snaps to its step and stays between 1x and 4x.
	barracks.set_power(9.0)
	if not check(barracks.power == 4.0,"Power is capped at 4x"): return
	barracks.set_power(0.2)
	if not check(barracks.power == 1.0,"Power is at least 1x"): return
	barracks.set_power(2.2)
	if not check(barracks.power == 2.0,"Power snaps to the 0.5 step"): return
	# 2x: five seconds for another 100 E; 4x: 2.5 s for another 300 E, the fastest a Barracks prints.
	for case in [[2.0,5.0,100],[4.0,2.5,300]]:
		barracks.set_power(case[0])
		energy = depot.energy
		seconds = run_until_produced(barracks,30)
		var drawn: int = energy-depot.energy
		if not check(absf(seconds-case[1]) < 0.03 and absi(drawn-case[2]) <= 1,"Infantry at %.0fx: %.1f s and %d E extra (%.2f s, %d E)" % [case[0],case[1],case[2],seconds,drawn]): return
		if not check(is_equal_approx(barracks.seconds_at_power(),case[1]) and barracks.energy_at_power(barracks.pending[0]) == 100+case[2],"The building should report the time and energy at this power"): return
	# A starved Depot prints at 1x: the work goes on, slower, without spending what it does not have.
	depot.energy = 0
	seconds = run_until_produced(barracks,30)
	if not check(absf(seconds-10.0) < 0.03 and depot.energy == 0,"With no energy the Infantry should print at 1x (%.2f s)" % seconds): return
	# It picks up the power again once there is energy.
	depot.energy = 5000
	barracks._process(0.5)
	if not check(not barracks.power_starved and absf(barracks.progress-2.0) < 0.01,"Power should return with energy (%.2f)" % barracks.progress): return
	barracks.pending.clear(); barracks.progress = 0
	# The fastest Tank, at 4x, takes 7 s; slower than the fastest Infantry.
	factory.set_power(factory.stats.max_power)
	if not check(factory.request_unit(&"tank"),"Tank not queued"): return
	energy = depot.energy
	seconds = run_until_produced(factory,60)
	if not check(absf(seconds-7.0) < 0.03 and absi(energy-depot.energy-450) <= 1,"A Tank at 4x: 7 s for 450 E extra (%.2f s, %d E)" % [seconds,energy-depot.energy]): return
	# The HUD: selecting the Barracks shows its power slider under the Depot panel, and the slider sets the power.
	var hud = game.get_node("Interface")
	game.selected_building = barracks
	for frame in range(4): await process_frame
	var panel: Control = hud.get_node("ProductionPanel")
	var slider: HSlider = panel.get_node("Body/PowerSlider")
	if not check(panel.visible and slider.value == 4.0 and slider.max_value == 4.0,"The production panel should show the Barracks at 4x"): return
	if not check(panel.get_node("Body/Power/Value").text == "4.0x energy","Power label: %s" % panel.get_node("Body/Power/Value").text): return
	if not check(panel.get_node("Body/Note").text.begins_with("Deforester: 2.5 s for 400 E (base 10 s, 100 E)"),"Note: %s" % panel.get_node("Body/Note").text): return
	slider.value = 1.5
	if not check(barracks.power == 1.5,"The slider should set the power (%.1f)" % barracks.power): return
	for frame in range(2): await process_frame
	if not check(panel.get_node("Body/Note").text.begins_with("Deforester: 6.7 s for 150 E"),"Note at 1.5x: %s" % panel.get_node("Body/Note").text): return
	game.selected_building = null
	for frame in range(4): await process_frame
	if not check(not panel.visible,"The panel goes with the selection"): return
	print("PRODUCTION_POWER_CHECKS_PASSED")
	quit(0)
