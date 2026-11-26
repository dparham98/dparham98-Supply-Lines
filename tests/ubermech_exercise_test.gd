extends SceneTree
# Headless: scenes/maps/ubermech_exercise.tscn (docs/UBERMECH_EXERCISE.md). The player's Tank Factory stands where it
# was saved, inside the Depot's range; both player Ubermechs stand on open ground with the walker model; the factory
# builds another Ubermech, paid by the Depot, and it walks out.
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func run() -> void:
	game = load("res://scenes/maps/ubermech_exercise.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	var ai = game.get_node_or_null("EnemyPlayer")
	if ai != null: ai.set_process(false)
	var factory = game.get_node_or_null("Entities/Buildings/TankFactory")
	if not check(is_instance_valid(factory) and factory.is_inside_tree(),"The Tank Factory did not stand on its footprint"): return
	if not check(factory.team == "player" and factory.global_position.distance_to(Vector3(-170,0,-18)) < 0.6,"The Tank Factory moved or is not the player's"): return
	if not check(factory.covering_depots().has(game.depot),"The Depot's range should cover the Tank Factory"): return
	var mechs := []
	for id in ["Ubermech","UbermechB"]:
		var mech = game.get_node_or_null("Entities/Units/"+id)
		if not check(is_instance_valid(mech) and mech.team == "player" and mech.unit_stats.unit_id == &"ubermech",id+" missing or not a player Ubermech"): return
		var tile = game.ground.get_tile_at_position(mech.global_position)
		if not check(tile != null and game.ground.can_traverse(tile,mech.mobility_layer(),mech._owner_key()),id+" should stand on an open tile"): return
		if not check(mech.get_node_or_null("Visuals/Model") != null and mech.get_node("Visuals/Model").scene_file_path == "res://scenes/models/ubermech_model.tscn",id+" should carry the walker model"): return
		mechs.append(mech)
	var energy: int = game.depot.energy
	var iron: int = game.depot.iron
	if not check(factory.request_unit(&"ubermech"),"The factory refused an Ubermech: "+game.message): return
	if not check(game.depot.energy == energy-240 and game.depot.iron == iron-100,"The Ubermech was not paid by the Depot"): return
	if not check(factory.request_unit(&"ubermech"),"The Depot should afford a second Ubermech"): return
	var before := get_nodes_in_group("units").size()
	factory._process(40.1)
	for frame in range(2): await process_frame
	if not check(get_nodes_in_group("units").size() == before+1,"The factory did not build an Ubermech"): return
	print("UBERMECH_EXERCISE_TEST_PASSED")
	quit()
