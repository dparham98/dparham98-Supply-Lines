extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	for group in ["units","depots"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	var depot = game.depot
	depot.energy = 1000; depot.iron = 1000
	assert(not depot.request_infantry() and depot.energy == 1000 and depot.iron == 1000 and depot.queue == 0)
	game.get_node("Interface")._process(0)
	assert(not game.get_node("Interface").card.get_node("PrintInfantry").visible)
	# A funded Depot can still recover through new construction's one-time grant.
	for unit in get_nodes_in_group("units"):
		if unit.team == "player": unit.free()
	depot.energy = 20; depot.iron = 20
	game._process(0)
	assert(game.outcome.is_empty())
	depot.energy = 0; depot.iron = 0
	game._process(0)
	assert(game.outcome.begins_with("DEFEAT"))
	game.outcome = ""
	depot.construction_infantry_pending = true
	game._process(0)
	assert(game.outcome.is_empty())
	print("DEPOT_CORRECTION_CHECKS_PASSED")
	quit()
