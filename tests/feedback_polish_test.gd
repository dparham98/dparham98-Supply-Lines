extends SceneTree
# UI phase D: order pings and target highlights, plan outlines, alert feed icons.
var game: Node3D
var hud: CanvasLayer
var overlay: Control
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func screen(point: Vector3) -> Vector2:
	return game.get_viewport().get_camera_3d().unproject_position(point)
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game); await process_frame
	game.set_process(false)
	hud = game.get_node("Interface"); hud.set_process(false)
	overlay = hud.get_node("MapOverlay"); overlay.set_process(false)
	for group in ["units","depots"]:
		for node in get_nodes_in_group(group): node.set_process(false)
	var rig = game.get_node("CameraRig"); rig.set_process(false)
	var depot = game.depot
	rig.focus_position(depot.global_position+Vector3(4,0,12),45)
	for frame in range(180): rig.advance_camera(1.0/60)
	var worker = game.get_node("Entities/Units/Infantry")
	var second = load(worker.scene_file_path).instantiate()
	second.position = worker.global_position+Vector3(3,0,0)
	game.get_node("Entities/Units").add_child(second); second.set_process(false)
	for node in get_nodes_in_group("units"): node.set_selected(node == worker or node == second)
	# A group move gives one ping at the clicked spot, not one per unit.
	var point: Vector3 = worker.global_position+Vector3(14,0,-4)
	game.issue_order(screen(point))
	if not check(overlay.pings.size() == 1 and overlay.pings[0].kind == "move" and overlay.pings[0].target == null and not overlay.pings[0].queued,"Group move ping wrong: %s" % [overlay.pings]): return
	# Shift orders ping as queued; attacks highlight their target.
	game.issue_order(screen(point+Vector3(4,0,0)),true)
	if not check(overlay.pings.size() == 2 and overlay.pings[1].queued,"Queued ping missing"): return
	var hostile = game.get_node("Entities/Units/Hostile")
	game.issue_order(screen(hostile.global_position+Vector3.UP*1.5))
	var last: Dictionary = overlay.pings[-1]
	if not check(last.kind == "attack" and last.target == hostile,"Attack ping does not highlight its target"): return
	# Pings expire.
	for ping in overlay.pings: ping.time -= overlay.HIGHLIGHT_SECONDS+0.1
	overlay._process(0)
	if not check(overlay.pings.is_empty(),"Pings did not expire"): return
	# Unpaid plans get a closed footprint outline.
	var plan = game.get_node("DepotNetwork").queue_plan(depot.global_position+Vector3(30,0,-20),&"generator",null,false)
	if not check(plan != null,"Plan could not be queued for the outline check"): return
	var outline: PackedVector2Array = overlay.plan_outline(plan,game.get_viewport().get_camera_3d())
	if not check(outline.size() == 5 and outline[0].is_equal_approx(outline[4]),"Plan outline not a closed footprint"): return
	# Alert feed entries carry an icon for their kind.
	game.alert("Depot under attack",depot.global_position,"","attack")
	game.alert("Tank out of fuel",depot.global_position,"","fuel")
	hud._process(0)
	var attack_icon: Texture2D = load("res://assets/ui/icons/attack.svg")
	var fuel_icon: Texture2D = load("res://assets/ui/icons/refuel.svg")
	if not check(hud.feed.get_node("Entry1").icon == fuel_icon and hud.feed.get_node("Entry2").icon == attack_icon,"Alert feed icons wrong"): return
	if not check(hud.feed.get_node("Entry2").get_theme_color("icon_normal_color").r > 0.8,"Attack alert icon not red"): return
	print("FEEDBACK_POLISH_TEST_PASSED")
	quit(0)
