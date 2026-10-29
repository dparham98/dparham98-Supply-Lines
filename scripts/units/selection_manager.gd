extends Node
const Bounds = preload("res://scripts/units/selection_bounds.gd")
var selecting := false
var start_pos := Vector2.ZERO
var end_pos := Vector2.ZERO
var drag_distance := 0.0
# Selection keeps working while playtest tools pause the game.
func _ready() -> void: process_mode = PROCESS_MODE_ALWAYS
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT: selecting = false
func _input(event: InputEvent) -> void:
	if selecting and event is InputEventMouseMotion:
		end_pos = event.position
		drag_distance = maxf(drag_distance,start_pos.distance_to(end_pos))
	if selecting and ((event is InputEventMouseButton and event.button_index != MOUSE_BUTTON_LEFT and event.pressed) or (event is InputEventKey and event.pressed)):
		selecting = false
	if selecting and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if get_viewport().gui_get_hovered_control() != null: selecting = false
var groups := {}
var _same_type_pending := false
var _last_group := -1
var _last_group_time := -1.0
const GROUP_DOUBLE_TAP_SECONDS := 0.4
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			start_selection(event.position)
			_same_type_pending = selecting and event.double_click
		else: end_selection(event.position,null,event.shift_pressed)
	elif event is InputEventKey and event.pressed and not event.echo:
		var game = get_tree().get_first_node_in_group("skirmish")
		if event.keycode == KEY_ESCAPE and get_tree().paused and game and game.armed():
			game.cancel_armed()
			get_viewport().set_input_as_handled()
			return
		for index in range(1,10):
			if event.is_action_pressed("control_group_%d" % index):
				if event.ctrl_pressed: save_group(index)
				else: recall_group(index)
				get_viewport().set_input_as_handled()
				return
func pick_object(pos: Vector2) -> Node3D:
	var camera := get_viewport().get_camera_3d()
	if camera == null: return null
	var closest: Node3D
	var distance := INF
	for group in ["units","selectable_buildings","construction_plans"]:
		for actor in get_tree().get_nodes_in_group(group):
			if group == "units" and actor.team != "player": continue
			var d: float = Bounds.hit_distance(actor,camera,pos)
			if d < distance: distance = d; closest = actor
	return closest
func switch_at(pos: Vector2) -> bool:
	if pick_object(pos) == null: return false
	selecting = true
	start_pos = pos
	drag_distance = 0
	end_selection(pos)
	return true
func start_selection(pos: Vector2) -> void:
	var game = get_tree().get_first_node_in_group("skirmish")
	# The paused skirmish can't complete an armed command, so a paused click cancels it and selects.
	if game and get_tree().paused and game.armed(): game.cancel_armed()
	if game and game.armed():
		selecting = false
		return
	selecting = true
	drag_distance = 0
	start_pos = pos
	end_pos = pos
# Shift adds: a point toggles one unit and a box adds its units. Double-click selects every
# visible friendly unit of the same type.
func end_selection(pos: Vector2, _unit: Node3D = null, additive := false) -> void:
	if not selecting: return
	selecting = false
	end_pos = pos
	var same_type := _same_type_pending
	_same_type_pending = false
	var rect := Rect2(start_pos,end_pos-start_pos).abs()
	var camera := get_viewport().get_camera_3d()
	if camera == null: return
	var point_selection := maxf(drag_distance,start_pos.distance_to(end_pos)) < 6.0
	var closest: Node3D = pick_object(pos) if point_selection else null
	var closest_unit := closest != null and closest.is_in_group("units")
	if additive and point_selection and not closest_unit:
		if closest == null: return
		additive = false
	var screen := get_viewport().get_visible_rect()
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.team != "player": continue
		if same_type and point_selection and closest_unit:
			unit.set_selected(unit.scene_file_path == closest.scene_file_path and not camera.is_position_behind(unit.global_position) and screen.intersects(Bounds.screen_rect(unit,camera)))
		elif additive and point_selection:
			if unit == closest: unit.set_selected(not unit.is_selected)
		elif additive:
			if rect.intersects(Bounds.screen_rect(unit,camera)): unit.set_selected(true)
		else: unit.set_selected(unit == closest if point_selection else rect.intersects(Bounds.screen_rect(unit,camera)))
	selection_changed(closest)
func save_group(index: int) -> void:
	var members: Array[Node3D] = []
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.team == "player" and unit.is_selected: members.append(unit)
	groups[index] = members
func recall_group(index: int) -> void:
	var members: Array = groups.get(index,[]).filter(func(unit): return is_instance_valid(unit) and unit.team == "player")
	groups[index] = members
	if members.is_empty(): return
	selecting = false
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.team == "player": unit.set_selected(members.has(unit))
	selection_changed(null)
	# Pressing the same group again quickly centres the camera on it.
	var now := Time.get_ticks_msec()/1000.0
	var game = get_tree().get_first_node_in_group("skirmish")
	if index == _last_group and now-_last_group_time <= GROUP_DOUBLE_TAP_SECONDS and game and game.has_node("CameraRig"):
		game.get_node("CameraRig").focus_selection()
	_last_group = index
	_last_group_time = now
func selection_changed(closest: Node3D) -> void:
	var game = get_tree().get_first_node_in_group("skirmish")
	if game and game.has_node("DepotNetwork"):
		game.hud.close_build()
		game.pending_unit_command = ""
		game.get_node("DepotNetwork").clear_builder()
		var building = closest if closest != null and (closest.is_in_group("selectable_buildings") or closest.is_in_group("construction_plans")) else null
		game.get_node("DepotNetwork").select_depot(building if building != null and building.is_in_group("depots") else null)
		game.selected_building = building
