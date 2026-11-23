extends SceneTree
## Writes scenes/maps/temple_exercise.tscn (docs/TEMPLE_OF_SCIENCE.md): Two Lakes with the track the game suggests
## from the player's Depot to the nearest Iron Mine at least 40 m away laid (the starter mine stands almost inside
## the Depot's rail ring, so a train there would never move), a train standing at the Depot and a Temple of Science
## inside the Depot's range. Run it headless from the project folder after the map or the track rules change:
##   Godot --headless --path . --script res://scripts/tools/build_temple_exercise.gd
## The scene inherits lakes_skirmish.tscn, so the map itself stays in one place.
const BASE := "res://scenes/maps/lakes_skirmish.tscn"
const OUTPUT := "res://scenes/maps/temple_exercise.tscn"
const PIECES := {"straight": "res://scenes/gameplay/track_straight.tscn", "curve": "res://scenes/gameplay/track_curve.tscn", "fork_left": "res://scenes/gameplay/track_fork_left.tscn", "fork_right": "res://scenes/gameplay/track_fork_right.tscn"}
const TEMPLE := "res://scenes/gameplay/temple_of_science.tscn"
const TRAIN := "res://scenes/gameplay/train.tscn"
## The exercise Depot holds enough for the research and a second train; Two Lakes itself is unchanged.
const DEPOT_ENERGY := 600
const DEPOT_IRON := 300
func _initialize() -> void: call_deferred("run")
func fail(message: String) -> void:
	push_error(message)
	quit(1)
func run() -> void:
	var game: Node3D = load(BASE).instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	var ai = game.get_node_or_null("EnemyPlayer")
	if ai != null: ai.set_process(false)
	var depot: Node3D = game.get_node("Entities/Buildings/Depot")
	var mine: Node3D = null
	for node in game.get_tree().get_nodes_in_group("mines"):
		var distance: float = node.global_position.distance_to(depot.global_position)
		if node.get("on_coal") != true and distance >= 40.0 and (mine == null or distance < mine.global_position.distance_to(depot.global_position)): mine = node
	if mine == null: fail("No Iron Mine 40 m or more from the Depot"); return
	var rails = game.get_node("RailNetwork")
	var network = game.get_node("DepotNetwork")
	if rails.suggest_route(depot,mine) <= 0: fail("No track path from the Depot to %s" % mine.name); return
	var plan: Array = []
	for entry in rails.pending: plan.append({kind = entry.kind, transform = entry.transform})
	# Lay it live, so the Temple's spot and the train's stop are found with the track in place.
	depot.stockpile.deposit(&"iron",1000)
	var laid: Array = rails.commit_plan(depot)
	if laid.size() != plan.size(): fail("The suggested track could not be laid: %s" % game.message); return
	await process_frame
	if rails.mine_stops(mine,"player").is_empty(): fail("The laid track does not reach the mine's ring"); return
	var stop: Dictionary = rails.spawn_stop(depot)
	if stop.is_empty(): fail("No train stop at the Depot"); return
	var temple_at = temple_spot(game,network,depot,mine)
	if temple_at == null: fail("No free 6 x 6 site in the Depot's range for the Temple"); return
	var text := "[gd_scene format=3]\n"
	text += "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"base\"]\n" % BASE
	var kinds := {}
	for entry in plan: kinds[entry.kind] = true
	for kind in kinds: text += "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"%s\"]\n" % [PIECES[kind],kind]
	text += "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"temple\"]\n" % TEMPLE
	text += "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"train\"]\n\n" % TRAIN
	text += "[node name=\"TempleExercise\" instance=ExtResource(\"base\")]\n"
	text += "editor_description = \"Built by scripts/tools/build_temple_exercise.gd (docs/TEMPLE_OF_SCIENCE.md): Two Lakes with track from the Depot to %s, a train at the Depot and a Temple of Science.\"\n" % mine.name
	text += "[node name=\"Depot\" parent=\"Entities/Buildings\"]\ninitial_energy = %d\ninitial_iron = %d\n" % [DEPOT_ENERGY,DEPOT_IRON]
	text += "[node name=\"TempleOfScience\" parent=\"Entities/Buildings\" instance=ExtResource(\"temple\")]\nposition = %s\nassigned_depot_path = NodePath(\"../Depot\")\n" % var_to_str(temple_at)
	text += "[node name=\"Rails\" type=\"Node3D\" parent=\"Entities\" index=\"2\"]\n"
	for i in range(plan.size()):
		text += "[node name=\"Track%d\" parent=\"Entities/Rails\" instance=ExtResource(\"%s\")]\ntransform = %s\nassigned_depot_path = NodePath(\"../../Buildings/Depot\")\n" % [i,plan[i].kind,var_to_str(plan[i].transform)]
	text += "[node name=\"Train\" parent=\"Entities/Units\" instance=ExtResource(\"train\")]\nposition = %s\n" % var_to_str(stop.position)
	var file := FileAccess.open(OUTPUT,FileAccess.WRITE)
	file.store_string(text)
	file.close()
	print("Temple exercise written: %d track pieces to %s, Temple at %s, train at %s" % [plan.size(),mine.name,temple_at,stop.position])
	print("TEMPLE_EXERCISE_BUILT")
	quit()
## The free 6 x 6 site in the Depot's range nearest the Depot, at least 9 m from it, 14 m from every mine and on the
## side away from the starter mine, so the Deforesters' walk to it stays open.
func temple_spot(game: Node3D, network: Node, depot: Node3D, _mine: Node3D):
	var size := Vector2i(6,6)
	var mines: Array = game.get_tree().get_nodes_in_group("mines")
	var starter: Node3D = null
	for node in mines:
		if starter == null or node.global_position.distance_to(depot.global_position) < starter.global_position.distance_to(depot.global_position): starter = node
	var away: Vector3 = (depot.global_position-starter.global_position).normalized() if starter != null else Vector3.ZERO
	var best = null
	var best_distance := INF
	for dz in range(-30,31):
		for dx in range(-30,31):
			var distance := Vector2(dx,dz).length()
			if distance < 9.0 or distance >= best_distance: continue
			if Vector3(dx,0,dz).normalized().dot(away) < 0.3: continue
			var point: Vector3 = depot.global_position+Vector3(dx,0,dz)
			if not network.can_place_size(point,depot,size): continue
			var start: Vector2i = network.footprint_start(point,size)
			var centre: Vector3 = game.ground.tile_to_world(start)+Vector3(size.x*0.5-0.5,0,size.y*0.5-0.5)
			if mines.any(func(node): return node.global_position.distance_to(centre) < 14.0): continue
			best = centre
			best_distance = distance
	return best
