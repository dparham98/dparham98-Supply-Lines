extends SceneTree
# Headless: the cursor labels keep one screen size at every zoom (docs/CURSOR_LABELS.md). Every map's rail label and
# the placement label have Fixed Size, with the same font and pixel size.
const MAPS := ["res://scenes/maps/lakes_skirmish.tscn","res://scenes/maps/balanced_skirmish.tscn","res://scenes/maps/resource_skirmish.tscn","res://scenes/maps/mine_site_exercise.tscn"]
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func readable(label: Label3D) -> bool:
	return label != null and label.fixed_size and label.font_size == 36 and is_equal_approx(label.pixel_size,0.0014) and label.billboard == BaseMaterial3D.BILLBOARD_ENABLED
func run() -> void:
	for path in MAPS:
		var map: Node = load(path).instantiate()
		if not check(readable(map.get_node_or_null("RailPreview/Status") as Label3D),"%s: the rail cursor label should have Fixed Size" % path): return
		map.free()
	var preview: Node = load("res://scenes/gameplay/construction_preview.tscn").instantiate()
	if not check(readable(preview.get_node_or_null("Status") as Label3D),"The placement label should have Fixed Size"): return
	preview.free()
	print("CURSOR_LABEL_TEST_PASSED")
	quit(0)
