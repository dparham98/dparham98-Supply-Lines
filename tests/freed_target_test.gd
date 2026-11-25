extends SceneTree
# Headless (docs/FREED_TARGETS.md): a worker whose repair target is destroyed, and a Grail Sentinel whose patient
# is destroyed, drop the order and go idle instead of passing the freed target to a typed check every frame.
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func spawn(id: String, point: Vector3, team := "player") -> Node3D:
	var unit = load("res://scenes/gameplay/"+id+".tscn").instantiate()
	unit.team = team
	game.get_node("Entities/Units").add_child(unit)
	unit.set_process(false)
	unit._stop_route()
	for cell in unit._claimed.duplicate(): unit._release(cell)
	unit.grid_position = game.ground.nearest_actor_cell(game.ground.get_tile_at_position(point),unit.mobility_layer(),unit._owner_key())
	unit.global_position = game.ground.tile_to_world(unit.grid_position)
	unit._claim(unit.grid_position)
	return unit
func step(units: Array, seconds: float) -> void:
	for i in range(ceili(seconds*60)):
		for unit in units: unit._process(1.0/60)
func destroy(unit: Node3D) -> void:
	for cell in unit._claimed.duplicate(): unit._release(cell)
	unit.free()
func run() -> void:
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	game.set_process(false)
	for group in ["units","depots","mines","energy_generators","production_buildings"]:
		for node in get_nodes_in_group(group): node.set_process(false); node.set("is_selected",false)
	var depot = game.depot
	depot.energy = 500
	depot.iron = 500
	var near: Vector3 = depot.global_position+Vector3(10,0,10)
	# Repair: the Tank is destroyed while the worker is on its way.
	var worker = spawn("infantry",near)
	var tank = spawn("tank",near+Vector3(12,0,0))
	tank.health = tank.max_health-60
	worker.command_repair(tank)
	if not check(worker.order == "repair","The worker should take the repair order: %s" % worker.order): return
	step([worker],0.5)
	destroy(tank)
	step([worker],1.0)
	if not check(worker.order == "idle" and worker.order_target == null,"A worker whose repair target is destroyed should go idle: %s, '%s'" % [worker.order,worker.state]): return
	# Heal: the patient is destroyed while the Sentinel is on its way.
	var sentinel = spawn("grail_sentinel",near+Vector3(0,0,6))
	var patient = spawn("infantry",near+Vector3(0,0,16))
	patient.health = patient.max_health-30
	sentinel.command_heal(patient)
	if not check(sentinel.order == "heal","The Sentinel should take the heal order: %s" % sentinel.order): return
	step([sentinel],0.5)
	destroy(patient)
	step([sentinel],1.0)
	if not check(sentinel.order == "idle" and sentinel.order_target == null,"A Sentinel whose patient is destroyed should go idle: %s, '%s'" % [sentinel.order,sentinel.state]): return
	print("FREED_TARGET_TEST_PASSED")
	quit(0)
