extends SceneTree
# Headless (docs/WINDOW_CONTROLS.md): the window controls. F11 or Alt+Enter is the fullscreen key, and switches a
# window to fullscreen and either fullscreen back to a window; the controls are an autoload that runs while paused.
# The pause menu frees the cursor the camera keeps inside the window, and gives back the cursor's mode on Resume.
# A headless run has no real window, so the switch itself is checked as the mode it picks, not on screen.
const Controls := preload("res://scripts/ui/window_controls.gd")
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func key(code: Key, alt := false, echo := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.alt_pressed = alt
	event.echo = echo
	event.pressed = true
	return event
func run() -> void:
	var controls := root.get_node_or_null("WindowControls")
	if not check(controls != null and controls.process_mode == Node.PROCESS_MODE_ALWAYS,"WindowControls should be an autoload that runs while paused"): return
	if not check(Controls.is_toggle(key(KEY_F11)) and Controls.is_toggle(key(KEY_ENTER,true)) and Controls.is_toggle(key(KEY_KP_ENTER,true)),"F11 and Alt+Enter should switch fullscreen"): return
	if not check(not Controls.is_toggle(key(KEY_ENTER)) and not Controls.is_toggle(key(KEY_F11,false,true)) and not Controls.is_toggle(key(KEY_F10)),"Enter alone, a held F11 and other keys should not switch fullscreen"): return
	if not check(Controls.next_mode(DisplayServer.WINDOW_MODE_WINDOWED) == DisplayServer.WINDOW_MODE_FULLSCREEN and Controls.next_mode(DisplayServer.WINDOW_MODE_MAXIMIZED) == DisplayServer.WINDOW_MODE_FULLSCREEN,"A window should switch to fullscreen"): return
	if not check(Controls.next_mode(DisplayServer.WINDOW_MODE_FULLSCREEN) == DisplayServer.WINDOW_MODE_WINDOWED and Controls.next_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN) == DisplayServer.WINDOW_MODE_WINDOWED,"Fullscreen should switch back to a window"): return
	# The pause menu frees the cursor and gives its mode back.
	change_scene_to_file("res://scenes/maps/lakes_skirmish.tscn")
	for frame in range(20):
		await process_frame
		if current_scene != null and current_scene.is_in_group("skirmish") and current_scene.is_node_ready(): break
	for frame in range(3): await process_frame
	var menu = current_scene.get_node_or_null("Interface/PauseMenu") if current_scene != null else null
	if not check(menu != null,"The map should have a pause menu"): return
	menu._was_mouse_mode = Input.MOUSE_MODE_VISIBLE
	var before: int = Input.mouse_mode
	menu.open()
	if not check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and menu._was_mouse_mode == before,"Opening the pause menu should free the cursor and remember its mode"): return
	# Pretend the camera had it confined: Resume gives that back.
	menu._was_mouse_mode = Input.MOUSE_MODE_CONFINED
	menu.close()
	var restored: int = Input.mouse_mode
	if not check(restored == Input.MOUSE_MODE_CONFINED or DisplayServer.get_name() == "headless","Resume should confine the cursor again, mode %d" % restored): return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("WINDOW_CONTROLS_TEST_PASSED")
	quit(0)
