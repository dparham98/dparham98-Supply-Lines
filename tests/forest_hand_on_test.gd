extends SceneTree
# Headless: a worker cutting wood moves on by itself to the nearest Forest cell when its cell runs out
# (docs/FOREST_HAND_ON.md), keeps filling its load, and carries on after each trip home. With
# HarvestingRules.forest_search_cells at 0 it stops when the cell runs out, as before.
var game: Node3D
var ground: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func step(nodes: Array, seconds: float, done: Callable) -> bool:
	for i in range(ceili(seconds*60)):
		for node in nodes:
			if is_instance_valid(node): node._process(1.0/60)
		if done.call(): return true
	return false
func run() -> void:
	game = load("res://scenes/maps/balanced_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	game.set_process(false)
	ground = game.ground
	var depot: Node3D = game.depot
	depot.set_process(false)
	var rules = ground.harvesting_rules
	if not check(rules.forest_search_cells == 10,"Workers should look 10 cells for the next tree"): return
	# The nearest Forest cell to the Depot with at least three Forest neighbours.
	var home: Vector2i = ground.get_tile_at_position(depot.global_position)
	var first := Vector2i(-1,-1)
	for r in range(1,60):
		for z in range(home.y-r,home.y+r+1):
			for x in range(home.x-r,home.x+r+1):
				var cell := Vector2i(x,z)
				if maxi(absi(x-home.x),absi(z-home.y)) != r or ground.forest_amount(cell) <= 0: continue
				var around := 0
				for offset in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)]:
					if ground.forest_amount(cell+offset) > 0: around += 1
				if around >= 1 and around <= 3 and first.x < 0: first = cell
		if first.x >= 0: break
	if not check(first.x >= 0,"No forest edge near the Depot"): return
	# The search: nearest to the cut cell, inside the reach; none beyond it.
	var next: Vector2i = ground.next_forest_cell(first,depot.global_position)
	if not check(next.x >= 0 and next != first and ground.forest_amount(next) > 0 and first.distance_to(next) <= 1.5,"The next cell should be a neighbour of the cut one: %s from %s" % [next,first]): return
	var worker: Node3D = load("res://scenes/gameplay/infantry.tscn").instantiate()
	worker.team = "player"
	game.get_node("Entities/Units").add_child(worker)
	worker.global_position = ground.tile_to_world(first)+(depot.global_position-ground.tile_to_world(first)).normalized()*2.0
	worker.set_process(false)
	await process_frame
	worker.command_gather(ground.forest_source(first))
	# Cut the cell down to its last bit, so the worker finishes it after one stroke and must move on part-loaded.
	ground.harvest_forest(first,ground.forest_amount(first)-1)
	if not check(step([worker],30.0,func(): return ground.forest_amount(first) <= 0),"The worker never finished its first cell: state '%s'" % worker.state): return
	if not check(worker.order == "gather" and is_instance_valid(worker.source) and worker.source.cell != first and worker.source.resource_kind == &"wood","The worker should move on to another Forest cell, order '%s', state '%s'" % [worker.order,worker.state]): return
	if not check(worker.cargo > 0 and worker.cargo < worker.carry_capacity,"It should keep its part load while it moves on: %d" % worker.cargo): return
	# It fills up, delivers and comes back to the forest by itself, cutting more cells than the first.
	var wood_before: int = depot.wood
	var cut_before: int = ground.cleared_forest.size()
	if not check(step([worker],600.0,func(): return depot.wood >= wood_before+worker.carry_capacity*2 and ground.cleared_forest.size() >= cut_before+2),"The worker should keep cutting and delivering: %d wood, %d cells cut, state '%s'" % [depot.wood-wood_before,ground.cleared_forest.size()-cut_before,worker.state]): return
	if not check(worker.order in ["gather","return"],"The worker should still be working the forest: '%s'" % worker.order): return
	# Off: the worker stops when its cell runs out.
	rules.forest_search_cells = 0
	var cell: Vector2i = worker.source.cell
	if not check(ground.next_forest_cell(cell,worker.global_position).x < 0,"A reach of 0 should find nothing"): return
	ground.harvest_forest(cell,ground.forest_amount(cell))
	if not check(not worker._source_left(),"With no reach the cut-out cell should end the order"): return
	rules.forest_search_cells = 10
	print("FOREST_HAND_ON_TEST_PASSED")
	quit(0)
