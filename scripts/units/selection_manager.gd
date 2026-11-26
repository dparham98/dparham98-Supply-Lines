extends Node
const Bounds = preload("res://scripts/units/selection_bounds.gd")
var selecting := false
const MODIFIER_KEYS := [KEY_SHIFT,KEY_CTRL,KEY_ALT,KEY_META]
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
	# Another button or a key cancels the box, but not Shift, Ctrl or Alt, nor a held key repeating: Shift
	# held through a drag adds the boxed units to the selection (docs/SELECTION_PORTRAITS.md).
	if selecting and ((event is InputEventMouseButton and event.button_index != MOUSE_BUTTON_LEFT and event.pressed) or (event is InputEventKey and event.pressed and not event.echo and not MODIFIER_KEYS.has(event.keycode))):
		selecting = false
	if selecting and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if get_viewport().gui_get_hovered_control() != null: selecting = false
	# Tab and Shift+Tab step the primary through the selection's types (docs/HUD_HOTKEYS.md). Read before the GUI,
	# which would otherwise take Tab to move button focus; with a single type selected Tab is left alone.
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB and not event.ctrl_pressed and not event.alt_pressed:
		if cycle_primary(-1 if event.shift_pressed else 1): get_viewport().set_input_as_handled()
var groups := {}
## The type (scene path) of the primary unit in a group: the one whose card, stats and outlined portrait the HUD
## shows. "" or a type no longer selected means the first selected unit. A new selection resets it.
var primary_type := ""
var _same_type_pending := false
var _last_group := -1
var _last_group_time := -1.0
const GROUP_DOUBLE_TAP_SECONDS := 0.4
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			start_selection(event.position)
			# Ctrl-click does what a double-click does: every unit of the clicked type on screen.
			_same_type_pending = selecting and (event.double_click or event.ctrl_pressed)
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
	# Enemy units can be clicked too, to read their stats (docs/SELECTION_INSPECT.md); they never take orders.
	for group in ["units","selectable_buildings","construction_plans","land_mines"]:
		for actor in get_tree().get_nodes_in_group(group):
			if group in ["units","land_mines"] and actor.team != "player" and not actor.is_visible_in_tree(): continue
			var d: float = Bounds.hit_distance(actor,camera,pos)
			if d < distance: distance = d; closest = actor
	return closest
## The Forest or Coal cell under a screen point, as its harvest handle, or null.
func terrain_source_at(pos: Vector2) -> Node3D:
	var game = get_tree().get_first_node_in_group("skirmish")
	var overlay = game.get_node_or_null("Interface/MapOverlay") if game != null else null
	return overlay.terrain_source_at(pos) if overlay != null else null
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
# Shift adds: a point toggles one unit and a box adds its units. Double-click or Ctrl-click selects every
# visible friendly unit of the same type; with Shift too, they are added to the selection. With buildings (docs/SELECTION_INSPECT.md) double-click selects your
# visible buildings of the type, and Shift-click adds or removes one of the type already selected. A click on an
# enemy unit inspects it.
func end_selection(pos: Vector2, _unit: Node3D = null, additive := false) -> void:
	if not selecting: return
	selecting = false
	end_pos = pos
	var same_type := _same_type_pending
	_same_type_pending = false
	primary_type = ""
	var rect := Rect2(start_pos,end_pos-start_pos).abs()
	var camera := get_viewport().get_camera_3d()
	if camera == null: return
	var point_selection := maxf(drag_distance,start_pos.distance_to(end_pos)) < 6.0
	var closest: Node3D = pick_object(pos) if point_selection else null
	# A click on open Forest or Coal, with nothing else there, selects the tile to inspect (docs/CURSORS.md).
	if closest == null and point_selection and not additive: closest = terrain_source_at(pos)
	var closest_unit: bool = closest != null and closest.is_in_group("units") and closest.team == "player"
	var screen := get_viewport().get_visible_rect()
	var game = get_tree().get_first_node_in_group("skirmish")
	var own_building: bool = closest != null and closest.is_in_group("selectable_buildings") and closest.get("team") == "player"
	if own_building and point_selection and game and (same_type or additive):
		var picked: Array[Node3D] = []
		if same_type:
			for node in get_tree().get_nodes_in_group("selectable_buildings"):
				if node.get("team") == "player" and node.scene_file_path == closest.scene_file_path and not camera.is_position_behind(node.global_position) and screen.intersects(Bounds.screen_rect(node,camera)):
					picked.append(node)
			picked.erase(closest); picked.push_front(closest)
		else:
			picked = game.building_selection()
			var same_kind := not picked.is_empty() and picked[0].scene_file_path == closest.scene_file_path and selected_unit_count() == 0
			if not same_kind: picked = [closest]
			elif picked.has(closest): picked.erase(closest)
			else: picked.append(closest)
		for unit in get_tree().get_nodes_in_group("units"):
			if unit.team == "player": unit.set_selected(false)
		selection_changed(picked[0] if not picked.is_empty() else null,picked)
		return
	if additive and point_selection and not closest_unit:
		if closest == null: return
		additive = false
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.team != "player": continue
		if same_type and point_selection and closest_unit:
			var on_screen_match: bool = unit.scene_file_path == closest.scene_file_path and not camera.is_position_behind(unit.global_position) and screen.intersects(Bounds.screen_rect(unit,camera))
			if on_screen_match or not additive: unit.set_selected(on_screen_match)
		elif additive and point_selection:
			if unit == closest: unit.set_selected(not unit.is_selected)
		elif additive:
			if rect.intersects(Bounds.screen_rect(unit,camera)): unit.set_selected(true)
		else: unit.set_selected(unit == closest if point_selection else rect.intersects(Bounds.screen_rect(unit,camera)))
	# A type added with Ctrl+Shift becomes the primary, as the clicked unit's type.
	if same_type and point_selection and closest_unit: primary_type = closest.scene_file_path
	selection_changed(closest)
func selected_unit_count() -> int:
	return get_tree().get_nodes_in_group("units").filter(func(unit): return unit.team == "player" and unit.is_selected).size()
func save_group(index: int) -> void:
	var members: Array[Node3D] = []
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.team == "player" and unit.is_selected: members.append(unit)
	# With no units selected, a selected friendly building becomes the group. So does a building still being
	# built (a construction plan): the group takes the finished building when it stands (replace_member).
	var game = get_tree().get_first_node_in_group("skirmish")
	if members.is_empty() and game:
		for building in game.building_selection():
			if building.get("team") == "player": members.append(building)
		if members.is_empty() and _in_group_ok(game.selected_building): members.append(game.selected_building)
	groups[index] = members
## Whether a node can stay in a control group: your units and buildings, and construction plans (only yours exist).
static func _in_group_ok(node) -> bool:
	if not is_instance_valid(node) or not node.is_inside_tree(): return false
	if node.is_in_group("construction_plans"): return not node.finished
	return node.get("team") == "player"
## A construction plan became `building`: every control group holding the plan holds the building instead.
func replace_member(old: Node, building: Node) -> void:
	for index in groups:
		var at: int = groups[index].find(old)
		if at < 0: continue
		if is_instance_valid(building) and not groups[index].has(building): groups[index][at] = building
		else: groups[index].remove_at(at)
func recall_group(index: int) -> void:
	var members: Array = groups.get(index,[]).filter(func(unit): return _in_group_ok(unit))
	groups[index] = members
	if members.is_empty(): return
	selecting = false
	primary_type = ""
	var building: Node3D = members[0] if not members[0].is_in_group("units") else null
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.team == "player": unit.set_selected(members.has(unit))
	var buildings: Array[Node3D] = []
	for member in members:
		if not member.is_in_group("units"): buildings.append(member)
	selection_changed(building,buildings)
	# Pressing the same group again quickly centres the camera on it.
	var now := Time.get_ticks_msec()/1000.0
	var game = get_tree().get_first_node_in_group("skirmish")
	if index == _last_group and now-_last_group_time <= GROUP_DOUBLE_TAP_SECONDS and game and game.has_node("CameraRig"):
		if building != null: game.get_node("CameraRig").focus_position(building.global_position)
		else: game.get_node("CameraRig").focus_selection()
	_last_group = index
	_last_group_time = now
func selection_changed(closest: Node3D, buildings: Array[Node3D] = []) -> void:
	var game = get_tree().get_first_node_in_group("skirmish")
	if game and game.has_node("DepotNetwork"):
		game.hud.close_build()
		game.pending_unit_command = ""
		game.get_node("DepotNetwork").clear_builder()
		var enemy_unit: bool = closest != null and closest.is_in_group("units") and closest.team != "player"
		var cell: bool = closest != null and (closest.is_in_group("forest_cells") or closest.is_in_group("coal_cells"))
		var building = closest if closest != null and (closest.is_in_group("selectable_buildings") or closest.is_in_group("construction_plans") or closest.is_in_group("land_mines") or enemy_unit or cell) else null
		game.get_node("DepotNetwork").select_depot(building if building != null and building.is_in_group("depots") else null)
		if buildings.size() > 1: game.select_buildings(buildings)
		else: game.selected_building = building
## Your selected units, in selection order.
func selected_units() -> Array[Node3D]:
	var units: Array[Node3D] = []
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.team == "player" and unit.is_selected: units.append(unit)
	return units
## The selection's unit types, in the order the portraits show them: the order each type was first selected.
static func types_of(units: Array[Node3D]) -> Array[String]:
	var types: Array[String] = []
	for unit in units:
		if not types.has(unit.scene_file_path): types.append(unit.scene_file_path)
	return types
## The primary unit of `units`: the first of `primary_type`, else the first.
func primary_of(units: Array[Node3D]) -> Node3D:
	if units.is_empty(): return null
	for unit in units:
		if unit.scene_file_path == primary_type: return unit
	return units[0]
## Moves the primary to the next (or, with `step` -1, the previous) type in the selection. False when fewer than two
## types are selected.
func cycle_primary(step := 1) -> bool:
	var game = get_tree().get_first_node_in_group("skirmish")
	if game == null or game.armed(): return false
	var units := selected_units()
	var types := types_of(units)
	if types.size() < 2: return false
	var at := types.find(primary_of(units).scene_file_path)
	primary_type = types[posmod(at+step,types.size())]
	return true
