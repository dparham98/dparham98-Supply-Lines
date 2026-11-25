extends Node
## Window controls (docs/WINDOW_CONTROLS.md), an autoload so they work on every screen: F11 or Alt+Enter switches
## between fullscreen and a window. The camera keeps the cursor inside the window for edge panning
## (docs/CAMERA_RIG.md); the pause menu lets it go so the window can be moved, resized or closed.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
## Whether `event` is the fullscreen key: F11, or Enter with Alt held.
static func is_toggle(event: InputEvent) -> bool:
	if not event is InputEventKey or not event.pressed or event.echo: return false
	return event.keycode == KEY_F11 or (event.alt_pressed and event.keycode in [KEY_ENTER,KEY_KP_ENTER])
## The mode the window switches to from `mode`: a window from either fullscreen mode, else fullscreen.
static func next_mode(mode: int) -> int:
	if mode in [DisplayServer.WINDOW_MODE_FULLSCREEN,DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]: return DisplayServer.WINDOW_MODE_WINDOWED
	return DisplayServer.WINDOW_MODE_FULLSCREEN
func toggle_fullscreen() -> void:
	var window := get_window()
	window.mode = next_mode(window.mode) as Window.Mode
func _input(event: InputEvent) -> void:
	if not is_toggle(event): return
	toggle_fullscreen()
	get_viewport().set_input_as_handled()
