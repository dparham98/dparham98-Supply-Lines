extends Control
## North-up map: world +X right, +Z down. Clicking changes camera focus only.
@export var bounds := Rect2(-250,-250,500,500)
@onready var game = get_tree().get_first_node_in_group("skirmish")
func _process(_delta: float) -> void:
	queue_redraw()
func world_to_map(point: Vector3) -> Vector2:
	return (Vector2(point.x,point.z)-bounds.position)/bounds.size*size
func map_to_world(point: Vector2) -> Vector3:
	var value := bounds.position+(point/size).clamp(Vector2.ZERO,Vector2.ONE)*bounds.size
	return Vector3(value.x,0,value.y)
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		game.get_node("CameraRig").focus_position(map_to_world(event.position))
		accept_event()
func _draw() -> void:
	if not is_instance_valid(game): return
	for cell in game.ground.cleared_forest:
		var top_left := world_to_map(game.ground.tile_to_world(cell))-size/500.0*0.5
		draw_rect(Rect2(top_left,size/500.0),Color(0.45,0.35,0.18))
	for rail in get_tree().get_nodes_in_group("rails"):
		draw_rect(Rect2(world_to_map(rail.global_position)-Vector2.ONE,Vector2(2,2)),Color(0.4,0.8,0.85) if game.get_node("RailNetwork").friendly(rail.cell,"player") else Color(0.85,0.3,0.25))
	for group in ["resources","selectable_buildings","units"]:
		for node in get_tree().get_nodes_in_group(group):
			if group == "resources" and node.is_in_group("mines"): continue
			var point := world_to_map(node.global_position)
			var color := Color(1,0.65,0.15)
			if group != "resources":
				color = Color(0.2,0.9,1) if node.team == "player" else (Color(1,0.3,0.25) if node.team == "enemy" else Color(0.75,0.75,0.75))
			if group == "selectable_buildings": draw_rect(Rect2(point-Vector2(3,3),Vector2(6,6)),color)
			else: draw_circle(point,2.5,color)
			if (group == "units" and node.is_selected) or node == game.selected_building: draw_arc(point,5,0,TAU,16,Color.WHITE,1.5)
	var camera := game.get_viewport().get_camera_3d()
	var viewport_size := game.get_viewport().get_visible_rect().size
	var hud_top: float = game.get_node("Interface/Bottom").global_position.y
	var outline := PackedVector2Array()
	for screen in [Vector2.ZERO,Vector2(viewport_size.x,0),Vector2(viewport_size.x,hud_top),Vector2(0,hud_top)]:
		var point = Plane(Vector3.UP,0).intersects_ray(camera.project_ray_origin(screen),camera.project_ray_normal(screen))
		if point != null: outline.append(world_to_map(point))
	if outline.size() == 4:
		outline.append(outline[0])
		draw_polyline(outline,Color(1,1,1,0.85),1.0,true)
