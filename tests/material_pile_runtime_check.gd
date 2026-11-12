extends SceneTree
# Rendered: the material pile models (docs/MATERIAL_PILE_MODELS.md). A row of iron, wood and coal piles at 10, 50
# and 100 beside the Depot, close and at play distance, and an iron delivery on a Generator site. Pictures only;
# judge them by eye.
const TestOutput = preload("res://tests/test_output.gd")
const PILE = preload("res://scenes/gameplay/material_pile.tscn")
var game: Node3D
var network: Node
var rig: Node
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func shot(at: Vector3, distance: float, name: String) -> void:
	rig.focus_position(at,distance)
	for frame in range(150): rig.advance_camera(1.0/60)
	for frame in range(8): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(TestOutput.path(name+".png"))
## The first spot near this point with a free 3 x 3 block of open land, so the row of piles stands clear.
func clear_spot(near: Vector3) -> Vector3:
	var spec: Dictionary = network.plan_spec(&"generator")
	for radius in range(8,60,2):
		for offset in [Vector3(radius,0,0),Vector3(-radius,0,0),Vector3(0,0,radius),Vector3(0,0,-radius)]:
			var point: Vector3 = near+offset
			var start: Vector2i = network.footprint_start(point,spec.size)
			if network.plan_terrain_valid(start,spec.size,&"generator") and not network.plan_overlaps(start,spec.size): return game.ground.tile_to_world(start+Vector2i.ONE)
	return Vector3.INF
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	network = game.get_node("DepotNetwork")
	game.set_process(false)
	for unit in get_nodes_in_group("units"): unit.set_process(false)
	for depot in get_nodes_in_group("depots"): depot.set_process(false)
	game.get_node("Interface").visible = false
	rig = game.get_node("CameraRig")
	rig.set_process(false)
	rig.min_zoom = 3.0
	var centre := clear_spot(game.depot.global_position+Vector3(14,0,10))
	if not check(centre != Vector3.INF,"No clear spot for the piles"): return
	# Rows: iron, wood, coal (back to front); columns: 10, 50, 100 (left to right).
	var kinds := ["iron","wood","coal"]
	var amounts := [10,50,100]
	for row in range(3):
		for column in range(3):
			var pile: Node3D = PILE.instantiate()
			pile.material_kind = kinds[row]; pile.amount = amounts[column]
			pile.position = centre+Vector3(column-1,0,row-1)
			game.get_node("Entities/Resources").add_child(pile,true)
			pile.get_node("Label").visible = false
	await shot(centre,6,"piles_close")
	await shot(centre,18,"piles_play")
	var spec: Dictionary = network.plan_spec(&"generator")
	var site := clear_spot(game.depot.global_position+Vector3(-16,0,12))
	var plan = network.queue_plan(site,&"generator")
	if not check(plan != null,"No generator site"): return
	plan.set_process(false)
	plan.receive(&"iron",spec.iron)
	await shot(plan.global_position,10,"piles_on_site")
	print("MATERIAL_PILE_RUNTIME_CHECK_PASSED"); quit(TestOutput.exit_code())
