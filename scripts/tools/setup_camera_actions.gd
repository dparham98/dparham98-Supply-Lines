extends SceneTree
func _initialize() -> void:
	var keys := {"camera_pan_left": KEY_LEFT, "camera_pan_right": KEY_RIGHT, "camera_pan_forward": KEY_UP, "camera_pan_back": KEY_DOWN, "camera_rotate_left": KEY_Q, "camera_rotate_right": KEY_E, "camera_fast_pan": KEY_SHIFT, "camera_overview": KEY_O, "camera_focus_hq": KEY_BACKSPACE, "camera_focus_selection": KEY_HOME}
	for action in keys:
		var event := InputEventKey.new()
		event.physical_keycode = keys[action]
		ProjectSettings.set_setting("input/" + action, {"deadzone": 0.2, "events": [event]})
	for action in ["camera_zoom_in", "camera_zoom_out"]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_WHEEL_UP if action == "camera_zoom_in" else MOUSE_BUTTON_WHEEL_DOWN
		ProjectSettings.set_setting("input/" + action, {"deadzone": 0.2, "events": [event]})
	assert(ProjectSettings.save() == OK)
	print("Camera Input Map saved")
	quit(0)
