extends SceneTree
# Rendered: the Depot Truck's and the Depot's deaths (docs/DEPOT_MODEL.md) at the game's camera and closer,
# each held at a few moments: the blast, the collapse and the burning wreck. Saves depot_death_*.png and
# depot_truck_death_*.png. Pictures only; judge them by eye.
const TestOutput = preload("res://tests/test_output.gd")
const Driven = preload("res://scripts/components/driven_death.gd")
var game: Node3D
var rig: Node
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func shot(at: Vector3, distance: float, name: String) -> void:
	rig.focus_position(at,distance)
	for frame in range(150): rig.advance_camera(1.0/60)
	for frame in range(6): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(TestOutput.path(name+".png"))
func effect_of(model: Node3D) -> Node:
	for child in model.get_children():
		if child.get_script() == Driven: return child
	return null
## Holds the death at this moment while the pictures are taken.
func hold(effect: Node, seconds: float) -> void:
	effect.player.seek(seconds,true)
	effect.player.pause()
	effect._process(0.0)
func spawn_truck(near: Vector2i) -> Node3D:
	var truck: Node3D = game.get_node("DepotNetwork").truck_scene.instantiate()
	var start: Vector2i = game.ground.find_buildable_footprint(near,Vector2i(10,10))
	truck.position = game.ground.tile_to_world(start+Vector2i(5,5))
	game.get_node("Entities/Units").add_child(truck)
	truck.set_process(false)
	return truck
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	game.set_process(false)
	game.get_node("Interface").visible = false
	rig = game.get_node("CameraRig")
	rig.set_process(false)
	rig.min_zoom = 4.0
	var network = game.get_node("DepotNetwork")
	# The truck.
	var truck := spawn_truck(Vector2i(220,170))
	var truck_model: Node3D = truck.get_node("Visuals/Model")
	var at: Vector3 = truck.global_position
	await shot(at,30,"depot_truck_alive")
	truck.take_damage(truck.health)
	var effect := effect_of(truck_model)
	if not check(effect != null,"The truck left no death"): return
	for moment in [[0.5,"blast"],[1.4,"rolling"],[2.6,"burning"],[4.1,"sinking"]]:
		hold(effect,moment[0])
		await shot(at,30,"depot_truck_death_%s" % moment[1])
	hold(effect,1.4)
	await shot(at+Vector3(0,1,0),16,"depot_truck_death_close")
	truck_model.queue_free()
	# The Depot, unfolded.
	var builder := spawn_truck(Vector2i(160,230))
	builder.set_selected(true)
	if not check(network.deploy_selected_truck(),"Deploy failed"): return
	var depot: Node3D = network.selected
	depot.set_process(false)
	var model: Node3D = depot.get_node("Visuals/Model")
	await create_timer(model.line_up_seconds+0.2).timeout
	model.player.advance(model.player.current_animation_length)
	at = depot.global_position
	await shot(at,36,"depot_death_alive")
	depot.take_damage(depot.max_health)
	effect = effect_of(model)
	if not check(effect != null,"The Depot left no death"): return
	for moment in [[0.55,"blast"],[1.0,"falling"],[2.2,"burning"],[3.6,"burnt"],[5.0,"sinking"]]:
		hold(effect,moment[0])
		await shot(at,36,"depot_death_%s" % moment[1])
	hold(effect,2.2)
	await shot(at+Vector3(0,1,0),20,"depot_death_close")
	print("DEPOT_DEATH_RUNTIME_CHECK_PASSED"); quit(TestOutput.exit_code())
