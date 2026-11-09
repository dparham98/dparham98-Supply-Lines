extends SceneTree
# Rendered check: a queued Generator plan beside the Depot shows its amber grid while it waits for
# iron, then turns green once a Cargo truck has delivered the materials onto its footprint.
# Saves site_waiting and site_ready.
const TestOutput = preload("res://tests/test_output.gd")
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func shot(name: String) -> void:
	for frame in range(4): await process_frame
	root.get_texture().get_image().save_png(TestOutput.path(name+".png"))
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	game.set_process(false)
	for unit in get_nodes_in_group("units"): unit.set_process(false)
	var network = game.get_node("DepotNetwork")
	var depot = game.depot
	var point: Vector3 = depot.global_position+Vector3(14,0,8)
	var spec: Dictionary = network.plan_spec(&"generator")
	var plan = network.queue_plan(point,&"generator")
	if not check(plan != null,"Plan not placed"): return
	var rig = game.get_node("CameraRig")
	rig.set_process(false)
	rig.focus_position(plan.global_position,16)
	for frame in range(180): rig.advance_camera(1.0/60)
	for frame in range(3): await process_frame
	if not check(not plan.materials_covered() and plan.get_node("Visuals/Grid").material_override.get_shader_parameter("tint").r > 0.9,"Plan should wait amber"): return
	await shot("site_waiting")
	var truck = game.get_node("Entities/Units/CargoTruck")
	for crate in [{kind = &"iron", amount = 25},{kind = &"iron", amount = 25}]: truck.crates.append(crate)
	truck._sync_reserved()
	for cell in truck._claimed.duplicate(): truck._release(cell)
	truck.global_position = plan.global_position+Vector3(plan.dropoff_range-0.5,0,0)
	truck.command_unload(plan)
	for i in range(30): truck._process(0.1)
	for frame in range(3): await process_frame
	if not check(plan.on_site(&"iron") == mini(50,spec.iron) and plan.materials_covered() == (spec.iron <= 50),"Delivery did not land on the site: %d" % plan.on_site(&"iron")): return
	plan.refresh_label()
	if plan.materials_covered() and not check(plan.get_node("Visuals/Grid").material_override.get_shader_parameter("tint").g > 0.9,"Covered site should be green"): return
	await shot("site_ready")
	print("SITE_CONSTRUCTION_RUNTIME_CHECK_PASSED"); quit(TestOutput.exit_code())
