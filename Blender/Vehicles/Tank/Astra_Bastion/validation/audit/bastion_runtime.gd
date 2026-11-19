extends SceneTree
## Supplement the shipping combat and running-gear suites with a real move order and per-instance paint.
const Paint = preload("res://scripts/components/team_paint.gd")
const Bounds = preload("res://scripts/units/selection_bounds.gd")

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> bool:
	if condition: return true
	push_error(message)
	quit(1)
	return false

func overrides(model: Node, painted: bool) -> Dictionary:
	var found := {}
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null: continue
		for i in range(mesh.mesh.get_surface_count()):
			var base: Material = mesh.mesh.surface_get_material(i)
			if base == null or (base.resource_name == "team_color") != painted: continue
			found[str(model.get_path_to(mesh)) + "/" + str(i)] = mesh.get_active_material(i)
	return found

func run() -> void:
	var baseline := OS.get_environment("BASTION_BASELINE") == "1"
	var map = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(map)
	await process_frame
	map.set_process(false)
	for unit in get_nodes_in_group("units"):
		unit.set_process(false)
	var real = load("res://scenes/gameplay/tank.tscn").instantiate()
	real.position = map.depot.global_position + Vector3(-8,0,10)
	map.get_node("Entities/Units").add_child(real)
	real.set_process(false)
	await process_frame
	var model = real.get_node("Visuals/Model")
	var peer = load("res://scenes/models/tank_model.tscn").instantiate()
	root.add_child(peer)
	await process_frame
	var painted_count := 0
	if not baseline:
		real.team = "enemy"
		painted_count = Paint.apply(peer, "player")
		var red := overrides(model,true)
		var stationary := overrides(model,false)
		var player_color := overrides(peer,true)
		if not check(red.size() == painted_count and painted_count > 0, "Team surfaces missing"): return
		if not check(red.values().all(func(m): return m == Paint.paint_for("enemy")), "Actor team hook failed"): return
		if not check(player_color.values().all(func(m): return m == Paint.paint_for("player")), "Peer must use player paint"): return
		Paint.apply(peer,"neutral")
		if not check(red == overrides(model,true) and stationary == overrides(model,false), "Recoloring peer leaked to actor"): return
		real.team = "player"
		if not check(stationary == overrides(model,false) and overrides(peer,true).values().all(func(m): return m == Paint.paint_for("neutral")), "Actor paint changed neutral surfaces or peer"): return
	peer.free()
	real.set_selected(true)
	var marker: MeshInstance3D = real.get_node("Visuals/TeamMarker")
	if not check(marker.visible and not Bounds.meshes(real).has(marker), "Selection marker should be visible and excluded from picking"): return
	var grid = real.ground
	var start: Vector3 = real.global_position
	var destination: Vector3 = start
	for offset in [Vector2i(7,0),Vector2i(0,7),Vector2i(-7,0),Vector2i(0,-7)]:
		var cell: Vector2i = real.grid_position + offset
		var route: Array = grid.actor_path(real.grid_position,cell,real.mobility_layer(),real._owner_key())
		if route.size() >= 4:
			destination = grid.tile_to_world(cell)
			break
	if not check(start.distance_to(destination)>3, "No navigable destination in First Contact fixture"): return
	var start_yaw: float = real.get_node("Visuals").rotation.y
	var max_turn := 0.0
	real.command_move(destination)
	for i in range(900):
		real._process(1.0/60)
		model._process(1.0/60)
		max_turn = maxf(max_turn,absf(angle_difference(real.get_node("Visuals").rotation.y,start_yaw)))
		if real.order=="idle" and real.global_position.distance_to(destination)<1.5: break
	var distance: float = start.distance_to(real.global_position)
	if not check(real.global_position.distance_to(destination)<1.5 and distance>4.0, "Move order did not reach destination"): return
	if not check(max_turn>.2 and model.track_travel_left()>0 and model.track_travel_right()>0, "Agent did not turn and drive both track loops"): return
	if not check(real._claimed.size()==1 and real._is_ours(real.grid_position), "Tank occupancy drifted during move"): return
	var measurements := {"team_painted_surfaces":painted_count,"move_displacement_world_m":snappedf(distance,.001),
		"max_heading_change_degrees":snappedf(rad_to_deg(max_turn),.001),"occupied_cells_at_destination":real._claimed.size(),
		"left_track_travel_authored_m":snappedf(model.track_travel_left(),.001),"right_track_travel_authored_m":snappedf(model.track_travel_right(),.001)}
	print("BASTION_MEASUREMENTS ",JSON.stringify(measurements))
	print("BASTION_RUNTIME_PASSED")
	quit()
