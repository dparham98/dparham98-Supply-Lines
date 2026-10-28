extends Node
const Bounds = preload("res://scripts/units/selection_bounds.gd")
var selecting := false
var start_pos := Vector2.ZERO
var end_pos := Vector2.ZERO
var drag_distance := 0.0
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
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed: start_selection(event.position)
		else: end_selection(event.position)
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
	if game and (not game.global_plan_kind.is_empty() or game.placing_rail or game.placing_depot or game.placing_generator or not game.placing_structure.is_empty() or not game.pending_unit_command.is_empty()):
		selecting = false
		return
	selecting = true
	drag_distance = 0
	start_pos = pos
	end_pos = pos
func end_selection(pos: Vector2, _unit: Node3D = null) -> void:
	if not selecting: return
	selecting = false
	end_pos = pos
	var rect := Rect2(start_pos,end_pos-start_pos).abs()
	var camera := get_viewport().get_camera_3d()
	if camera == null: return
	var point_selection := maxf(drag_distance,start_pos.distance_to(end_pos)) < 6.0
	var closest: Node3D = pick_object(pos) if point_selection else null
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.team != "player": continue
		unit.set_selected(unit == closest if point_selection else rect.intersects(Bounds.screen_rect(unit,camera)))
	var game = get_tree().get_first_node_in_group("skirmish")
	if game and game.has_node("DepotNetwork"):
		game.hud.close_build()
		game.pending_unit_command = ""
		game.get_node("DepotNetwork").clear_builder()
		var building = closest if closest != null and (closest.is_in_group("selectable_buildings") or closest.is_in_group("construction_plans")) else null
		game.get_node("DepotNetwork").select_depot(building if building != null and building.is_in_group("depots") else null)
		game.selected_building = building
