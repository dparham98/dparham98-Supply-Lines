extends SceneTree
# Headless, on Two Lakes: an armed unit with no opponent unit in range fires at a hostile building in range on its
# own, a unit in range comes first, and a shared mine is left alone (docs/COMBAT_BATCH.md, Buildings as targets).
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func actor(id: String, team: String, point: Vector3) -> Node3D:
	var unit = load("res://scenes/gameplay/"+id+".tscn").instantiate()
	unit.team = team
	game.get_node("Entities/Units").add_child(unit)
	unit.global_position = point
	return unit
func run() -> void:
	game = load("res://scenes/maps/lakes_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	var ai = game.enemy_player()
	ai.set_process(false)
	var depot: Node3D = ai.home()
	for node in get_nodes_in_group("units"): node.free()
	await process_frame
	# Idle beside the enemy's Depot with nobody else near: it opens fire on the Depot.
	var shooter := actor("infantry","player",depot.global_position+Vector3(-8,0,0))
	await process_frame
	shooter.global_position = depot.global_position+Vector3(-shooter.attack_range*0.6,0,0)
	var health: int = depot.health
	for frame in range(30*6): await process_frame
	if not check(depot.health < health,"An idle unit should fire on a hostile building in range (%d -> %d)" % [health,depot.health]): return
	# A unit in range comes first.
	var guard := actor("infantry","enemy",shooter.global_position+Vector3(-shooter.attack_range*0.3,0,3))
	guard.set_process(false)
	var guard_health: int = guard.health
	health = depot.health
	for frame in range(30*6): await process_frame
	if not check(is_instance_valid(guard) == false or guard.health < guard_health,"A hostile unit in range should be shot before a building"): return
	if is_instance_valid(guard): guard.free()
	shooter.free()
	# A shared mine is never picked on its own.
	var mine: Node3D = get_nodes_in_group("mines")[0]
	var miner := actor("infantry","player",mine.global_position+Vector3(4,0,4))
	await process_frame
	miner.global_position = mine.global_position+Vector3(miner.attack_range*0.5,0,0)
	var mine_health = mine.get("health")
	for frame in range(30*4): await process_frame
	if not check(mine.get("health") == mine_health,"A unit should leave a shared mine alone unless ordered to attack it"): return
	print("BUILDING_AGGRO_TEST_PASSED")
	quit()
