extends SceneTree
var rig: Node3D
var elapsed := 0.0
var history: Array = []
const TestOutput = preload("res://tests/test_output.gd")
const OUT = "camera_work/mouse_probe.json"
func _initialize() -> void:
	call_deferred("start")
func start() -> void:
	root.title = "Supply Lines - Mouse edge test"
	root.add_child(load("res://scenes/maps/supply_lines_world.tscn").instantiate())
	rig = root.get_node("SupplyLinesWorld/CameraRig")
func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed < 0.5 or not is_instance_valid(rig): return false
	elapsed = 0
	var mouse := root.get_mouse_position()
	var ui := root.gui_get_hovered_control()
	history.append({"time": Time.get_ticks_msec(), "mouse": [mouse.x,mouse.y], "size": [root.size.x,root.size.y], "focus": root.has_focus(), "ui": str(ui.get_path()) if ui else "", "position": [rig.global_position.x,rig.global_position.z], "pan": str(rig.edge_pan_vector(mouse,root.get_visible_rect().size))})
	TestOutput.write_text(self, OUT, JSON.stringify(history))
	return false
