extends SceneTree
# Balance investigation (not a test): gather rates on Two Lakes for each faction's worker, with the game's own orders.
#   RATES_MODE=cyborg|knights godot --headless --fixed-fps 30 --path . --script res://balance/rates.gd
var game: Node3D
var ground: Node
var depot: Node3D
var log: Array = []       # [time, kind, amount]
var t := 0.0
func _initialize() -> void: call_deferred("run")
func _on_delivered(target: Node3D, kind: StringName, amount: int) -> void:
	log.append([t,str(kind),amount,str(target.name)])
func wait(seconds: float) -> void:
	for frame in range(int(round(seconds*30))):
		await process_frame
		t += 1.0/30.0
func nearest_mine(point: Vector3, kind: StringName) -> Node3D:
	var best: Node3D
	for mine in get_nodes_in_group("mines"):
		if mine.resource_kind != kind: continue
		if best == null or mine.global_position.distance_to(point) < best.global_position.distance_to(point): best = mine
	return best
func forest_near(point: Vector3) -> Node3D:
	var centre = ground.get_tile_at_position(point)
	for r in range(6,90):
		for dx in range(-r,r+1):
			for dz in [-r,r]:
				for cell in [Vector2i(centre.x+dx,centre.y+dz),Vector2i(centre.x+dz,centre.y+dx)]:
					if ground.forest_amount(cell) > 0: return ground.forest_source(cell)
	return null
func rate(kind: String, from: float, to: float) -> String:
	var got := 0
	var times: Array = []
	for entry in log:
		if entry[1] == kind and entry[0] >= from and entry[0] <= to: got += entry[2]; times.append(entry[0])
	if times.size() < 2: return "%s: %d in %.0f s" % [kind,got,to-from]
	# Steady rate: from the first delivery to the last.
	var span: float = times[-1]-times[0]
	var after_first: int = got-log.filter(func(e): return e[1] == kind and e[0] == times[0])[0][2]
	return "%s: %d delivered, first at %.1f s, then %.1f s a load, %.1f a minute" % [kind,got,times[0]-from,span/maxf(1,times.size()-1),after_first/span*60.0]
func run() -> void:
	var mode := OS.get_environment("RATES_MODE")
	var setup: Node = root.get_node("MatchSetup")
	setup.start("sandbox",&"arthurian_knights" if mode.begins_with("knights") else &"cyborgs")
	for frame in range(60):
		await process_frame
		if current_scene != null and current_scene.is_in_group("skirmish") and current_scene.is_node_ready(): break
	game = current_scene
	for frame in range(5): await process_frame
	ground = game.get_node("Terrain/Ground")
	depot = game.depot
	game.resources_delivered.connect(_on_delivered)
	game.get_node("Interface").process_mode = Node.PROCESS_MODE_DISABLED
	var workers: Array = get_nodes_in_group("units").filter(func(u): return u.team == "player" and u.can_gather and not u.is_cargo_vehicle and not u.is_depot_truck)
	print("%s start: %s at %s · stock E %d I %d W %d C %d F %d · workers %d (%s, speed %.1f, carry %d, %d per %.1f s)" % [mode,depot.name,depot.global_position,depot.energy,depot.iron,depot.wood,depot.coal,depot.food,workers.size(),workers[0].unit_stats.display_name,workers[0].move_speed,workers[0].carry_capacity,workers[0].harvest_amount,workers[0].harvest_interval])
	var mine := nearest_mine(depot.global_position,&"iron")
	print("home mine %s, %.1f m from the %s centre" % [mine.name,mine.global_position.distance_to(depot.global_position),depot.name])
	var worker: Node3D = workers[0]
	if OS.has_environment("RATES_SPEED"):
		for unit in workers: unit.move_speed *= float(OS.get_environment("RATES_SPEED"))
		print("worker speed x%s = %.2f" % [OS.get_environment("RATES_SPEED"),worker.move_speed])
	if mode.ends_with("keep"):
		await found_keep(workers)
		quit(); return
	# Iron, one worker, 4 minutes.
	worker.command_gather(mine)
	var from := t
	await wait(240)
	print(rate("iron",from,t))
	# Wood, one worker, 4 minutes.
	var tree := forest_near(depot.global_position)
	print("nearest forest %.1f m from the %s centre" % [tree.global_position.distance_to(depot.global_position),depot.name])
	worker.command_gather(tree)
	from = t
	await wait(8)
	from = t
	await wait(240)
	print(rate("wood",from,t))
	# Two workers on iron at once, to see the queueing at the mine.
	if workers.size() > 1:
		for unit in workers: unit.command_gather(mine)
		await wait(10)
		from = t
		await wait(180)
		print("two workers · "+rate("iron",from,t))
	print("RATES_DONE")
	quit()
## Knights: two Forester Maidens found a Keep beside the expansion mine by hand: walk out, carry 50 iron from the mine
## and 50 wood from the nearest trees onto the site, and build it.
func found_keep(workers: Array) -> void:
	var network: Node = game.get_node("DepotNetwork")
	var mines: Array = get_nodes_in_group("mines").filter(func(m): return m.resource_kind == &"iron" and m.global_position.distance_to(depot.global_position) > 55.0)
	mines.sort_custom(func(a,b): return a.global_position.distance_to(depot.global_position) < b.global_position.distance_to(depot.global_position))
	var mine: Node3D = mines[0]
	print("expansion mine %s, %.1f m from the Keep" % [mine.name,mine.global_position.distance_to(depot.global_position)])
	var spec: Dictionary = network.plan_spec(&"keep")
	var toward: Vector3 = (depot.global_position-mine.global_position).normalized()
	var plan: Node3D
	for r in range(8,30,2):
		for step in range(16):
			var turn := (step+1)/2*(1 if step%2 == 0 else -1)*TAU/16
			var point: Vector3 = mine.global_position+toward.rotated(Vector3.UP,turn)*r
			var start: Vector2i = network.footprint_start(point,spec.size)
			if network.plan_terrain_valid(start,spec.size,&"keep") and not network.plan_overlaps(start,spec.size) and network.depot_spacing_ok(point):
				plan = network.queue_plan(point,&"keep",null,false,false)
				if plan != null: break
		if plan != null: break
	if plan == null: print("no Keep site found"); return
	print("Keep plan %.1f m from the mine, %.1f m from home" % [plan.global_position.distance_to(mine.global_position),plan.global_position.distance_to(depot.global_position)])
	var tree := forest_near(plan.global_position)
	print("nearest forest to the site %.1f m" % tree.global_position.distance_to(plan.global_position))
	var jobs := [&"iron",&"wood"]
	var done_at := -1.0
	var arrived := -1.0
	while t < 600.0:
		for i in range(workers.size()):
			var unit: Node3D = workers[i]
			if not is_instance_valid(plan) or plan.finished: break
			if arrived < 0 and unit.global_position.distance_to(plan.global_position) < 20.0: arrived = t
			var want: StringName = jobs[i%2]
			if plan.shortfall(want) <= 0: want = jobs[(i+1)%2]
			if plan.shortfall(want) <= 0:
				if unit.order != "construct": unit.command_construct(plan)
				continue
			if unit.cargo >= unit.carry_capacity or (unit.cargo > 0 and unit.cargo_kind != want):
				if unit.order != "construct": unit.command_construct(plan)
			elif unit.order == "idle" or unit.order == "return" or (unit.order == "construct" and unit.cargo == 0) or (unit.order == "gather" and unit.source != null and unit.source.resource_kind != want):
				var source: Node3D = mine if want == &"iron" else forest_near(plan.global_position)
				if unit.order != "gather" or unit.source == null or unit.source.resource_kind != want: unit.command_gather(source)
		await wait(0.5)
		if not is_instance_valid(plan) or plan.finished: done_at = t; break
	print("workers reached the site at %.0f s; Keep standing at %.0f s (%s)" % [arrived,done_at,"built" if done_at > 0 else "not finished: %s" % (plan.state if is_instance_valid(plan) else "?")])
	print("RATES_DONE")
