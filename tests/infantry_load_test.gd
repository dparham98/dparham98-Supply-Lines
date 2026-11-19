extends SceneTree
# Headless (docs/INFANTRY_LOAD.md): a worker carrying cargo shows a load of that kind on its back and cannot fire;
# once it drops the load it fights again.
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
func shown(worker: Node3D) -> Array:
	var load_node: Node3D = worker.get_node("Visuals").find_child("BackLoad",true,false)
	return load_node.get_children().filter(func(child): return child.visible).map(func(child): return str(child.name))
func run() -> void:
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	game.set_process(false)
	for group in ["units","depots","mines","energy_generators","production_buildings"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	var spot: Vector3 = game.depot.global_position+Vector3(12,0,12)
	var worker = spawn("infantry",spot)
	if not check(worker.get_node("Visuals").find_child("BackLoad",true,false) != null,"The Infantry model has no BackLoad"): return
	worker._update_display()
	if not check(shown(worker).is_empty(),"Nothing on an empty worker's back: %s" % [shown(worker)]): return
	# One load per kind, shown while it carries that kind.
	for kind in [&"iron",&"wood",&"coal"]:
		worker.cargo = 5
		worker.cargo_kind = kind
		worker._update_display()
		if not check(shown(worker) == [str(kind).capitalize()],"Carrying %s should show that load: %s" % [kind,shown(worker)]): return
	worker.cargo = 0
	worker._update_display()
	if not check(shown(worker).is_empty(),"The load should go when the cargo does"): return
	# Carrying, it cannot fire: not on an order, not in self-defence.
	var foe = spawn("infantry",spot+Vector3(6,0,0),"hostile")
	worker.cargo = 5
	worker.cargo_kind = &"iron"
	if not check(worker.carrying(),"A worker with cargo is carrying"): return
	var health: int = foe.health
	worker.command_attack(foe)
	step([worker],4.0)
	if not check(foe.health == health and "drop" in worker.state.to_lower(),"A carrying worker should not fire: foe %d / %d, '%s'" % [foe.health,health,worker.state]): return
	if not check("drop it" in game.message,"Ordering a carrying worker to attack should say why: '%s'" % game.message): return
	worker.order = "idle"
	step([worker],3.0)
	if not check(foe.health == health,"A carrying worker should not fire in self-defence either"): return
	# Attack-move: it keeps walking rather than stopping to engage.
	worker.command_attack_move(spot+Vector3(0,0,20))
	step([worker],1.0)
	if not check(worker.order == "attack_move" and not "engaging" in worker.state,"A carrying worker should walk on, not engage: '%s'" % worker.state): return
	# With the load dropped it fights.
	worker._stop_route()
	game.drop_material(worker)
	if not check(worker.cargo == 0 and not worker.carrying(),"Drop should empty its hands: %d" % worker.cargo): return
	worker.command_attack(foe)
	step([worker],4.0)
	if not check(foe.health < health,"With empty hands it should fire: foe %d / %d, '%s'" % [foe.health,health,worker.state]): return
	print("INFANTRY_LOAD_TEST_PASSED")
	quit(0)
