extends Control
## The pause menu (docs/MAIN_MENU.md). Esc, with no command or placement armed, opens it, as does the HUD's Menu
## button. It pauses the game and takes every click and key until it closes: Resume (or Esc again), Restart match,
## Main menu, Quit game. A game already paused from the playtest panel stays paused when it closes. While it is open
## the cursor is free to leave the window (docs/WINDOW_CONTROLS.md), so the window can be moved, resized or closed.
@onready var game = get_tree().get_first_node_in_group("skirmish")
@onready var setup = get_node_or_null("/root/MatchSetup")
## Whether the tree was paused before the menu opened.
var _was_paused := false
## The cursor's mode before the menu opened, given back when it closes.
var _was_mouse_mode := Input.MOUSE_MODE_VISIBLE
func _ready() -> void:
	visible = false
	%Resume.pressed.connect(close)
	%Restart.pressed.connect(restart)
	%MainMenu.pressed.connect(main_menu)
	%Quit.pressed.connect(func(): get_tree().quit())
func is_open() -> bool: return visible
func open() -> void:
	if visible: return
	_was_paused = get_tree().paused
	get_tree().paused = true
	_was_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if game != null: game.cancel_armed()
	%Match.text = setup.summary() if setup != null and setup.configured else "Map started directly · no match set up"
	visible = true
	%Resume.grab_focus()
func close() -> void:
	if not visible: return
	visible = false
	get_tree().paused = _was_paused
	Input.mouse_mode = _was_mouse_mode
func restart() -> void:
	visible = false
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()
func main_menu() -> void:
	visible = false
	if setup != null: setup.to_menu()
	else:
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
## While open, the menu has the keyboard: Esc closes it and nothing else reaches the game.
func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey: return
	if event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
		return
	# The fullscreen key still reaches the window controls.
	if preload("res://scripts/ui/window_controls.gd").is_toggle(event): return
	# Enter and Space still work the focused button.
	if event.keycode in [KEY_ENTER,KEY_KP_ENTER,KEY_SPACE,KEY_UP,KEY_DOWN]: return
	get_viewport().set_input_as_handled()
## Esc opens it when nothing is armed: Esc first cancels an armed command (the skirmish does that), and the
## playtest panel's spawning keeps its own Esc.
func _unhandled_input(event: InputEvent) -> void:
	if visible or not event is InputEventKey or not event.pressed or event.echo or event.keycode != KEY_ESCAPE: return
	if game != null and game.armed(): return
	var playtest = get_parent().get_node_or_null("PlaytestPanel")
	if playtest != null and playtest.spawn_armed: return
	open()
	get_viewport().set_input_as_handled()
