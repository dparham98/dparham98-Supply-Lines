extends SceneTree
# The camera treats the HUD's bottom panel as covered: the map's southern edge scrolls up to the
# top of the panel instead of stopping behind it, at any yaw and in the overview.
const INSET := 272.0
const SIZE := Vector2i(1280,900)
var rig: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func settle() -> void:
	for i in range(600): rig.advance_camera(1.0/60)
## The ground under the lowest row of pixels the HUD does not cover, and under the top row.
func panel_top_point() -> Vector3: return rig.ground_point(Vector2(SIZE.x*0.5,SIZE.y-INSET-0.5))
func top_point() -> Vector3: return rig.ground_point(Vector2(SIZE.x*0.5,0.5))
func run() -> void:
	root.size = SIZE
	rig = load("res://scenes/camera/rts_camera.tscn").instantiate()
	root.add_child(rig); await process_frame
	rig.set_process(false); rig.set_process_unhandled_input(false)
	rig.edge_pan_enabled = false
	var bounds: Rect2 = rig.map_bounds
	# Without an inset the old rule holds: the window's bottom row stops at the map's edge.
	rig.screen_bottom_inset = 0
	rig.focus_position(Vector3(0,0,bounds.end.y+500))
	settle()
	if not check(absf(rig.ground_point(Vector2(SIZE.x*0.5,SIZE.y-0.5)).z-bounds.end.y) < 1.0,"No-inset bottom edge moved: %.2f" % rig.ground_point(Vector2(SIZE.x*0.5,SIZE.y-0.5)).z): return
	# With the panel, the map's edge reaches the panel's top, and the window's bottom row lies past it.
	rig.screen_bottom_inset = INSET
	rig.focus_position(Vector3(0,0,bounds.end.y+500))
	settle()
	if not check(absf(panel_top_point().z-bounds.end.y) < 1.0,"South edge stops behind the HUD: %.2f, map edge %.2f" % [panel_top_point().z,bounds.end.y]): return
	# The north edge still stops at the top of the window.
	rig.focus_position(Vector3(0,0,bounds.position.y-500))
	settle()
	if not check(absf(top_point().z-bounds.position.y) < 1.0,"North edge moved: %.2f" % top_point().z): return
	# Turned a quarter, screen-down points along +X, and the east edge reaches the panel's top.
	rig._yaw = deg_to_rad(90); rig._yaw_target = rig._yaw
	rig.focus_position(Vector3(bounds.end.x+500,0,0))
	settle()
	var east := panel_top_point()
	if not check(absf(east.x-bounds.end.x) < 1.0,"Rotated edge stops behind the HUD: %.2f" % east.x): return
	rig._yaw = 0; rig._yaw_target = 0
	# The overview shows the whole map above the panel.
	rig.show_overview()
	settle()
	if not check(top_point().z <= bounds.position.y+0.5 and panel_top_point().z >= bounds.end.y-0.5,"Overview hides part of the map: top %.2f, panel %.2f" % [top_point().z,panel_top_point().z]): return
	print("CAMERA_HUD_INSET_TEST_PASSED")
	quit(0)
