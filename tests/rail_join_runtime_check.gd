extends SceneTree
# Rendered check of joining track (docs/RAIL_PLANNING.md): a branch planned off a laid line, with the fork's ghost in
# place of three hidden straights (rail_join_plan), then laid (rail_join_laid).
const TestOutput = preload("res://tests/test_output.gd")
var game: Node3D
var rails: Node
var network: Node
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func site_near(point: Vector3) -> Node3D:
	for r in range(0,40,3):
		for offset in [Vector3(r,0,0),Vector3(-r,0,0),Vector3(0,0,r),Vector3(0,0,-r)]:
			var plan = network.queue_plan(point+offset,&"generator")
			if plan != null: return plan
	return null
func line_of(piece: Node3D) -> Array:
	return rails.lines()[piece.get_instance_id()].pieces
func shot(rig, at: Vector3, height: float, name: String) -> void:
	rig.focus_position(at,height)
	for frame in range(180): rig.advance_camera(1.0/60)
	for frame in range(12): await process_frame
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	TestOutput.save_png(self,root.get_texture().get_image(),"rail_join_work/"+name+".png")
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/balanced_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	game.set_process(false)
	rails = game.get_node("RailNetwork")
	network = game.get_node("DepotNetwork")
	var depot: Node3D = game.depot
	depot.set_process(false)
	depot.storage_capacity = 100000; depot.iron = 20000; depot.energy = 20000
	for unit in get_nodes_in_group("units"): unit.set_process(false)
	var rig = game.get_node("CameraRig")
	rig.set_process(false)
	var far: Node3D
	var heading := Vector3.ZERO
	for direction in [Vector3(1,0,0),Vector3(-1,0,0),Vector3(0,0,1),Vector3(0,0,-1)]:
		far = site_near(depot.global_position+direction*75.0)
		if far == null: continue
		rails.pick_target(depot)
		rails.pick_target(far)
		if not rails.pending.is_empty() and rails.plan_blocker().is_empty(): heading = direction; break
		rails.drop_route(); far.queue_free(); far = null
	if not check(far != null,"No open line from the Depot"): return
	var line: Array[Node3D] = rails.commit_plan()
	rails.drop_route()
	var middle: Node3D
	for piece in line:
		if piece.kind == "straight" and not rails._straight_run(piece,0,3).is_empty() and piece.global_position.distance_to(depot.global_position) > 30.0: middle = piece; break
	if not check(middle != null,"No straight run"): return
	var side := Vector3(-heading.z,0,heading.x)
	var branch_site := site_near(middle.global_position+side*40.0+heading*10.0)
	if branch_site == null: branch_site = site_near(middle.global_position-side*40.0+heading*10.0)
	if not check(branch_site != null,"No side site"): return
	game.placing_rail = true
	rails.pick_target(rails.pick_at(middle.point_at(1.0)))
	rails.pick_target(branch_site)
	if not check(not rails.pending.is_empty() and rails.pending[0].kind.begins_with("fork"),"No fork planned"): return
	var view: Vector3 = (middle.global_position+branch_site.global_position)*0.5
	await shot(rig,view,55,"rail_join_plan")
	rails.commit_plan()
	rails.drop_route()
	game.placing_rail = false
	await shot(rig,view,55,"rail_join_laid")
	print("RAIL_JOIN_RUNTIME_PASSED")
	quit(0)
