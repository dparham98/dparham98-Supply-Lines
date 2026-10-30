extends Control
## North-up map: world +X right, +Z down. Clicking changes camera focus only.
@export var bounds := Rect2(-250,-250,500,500)
@onready var game = get_tree().get_first_node_in_group("skirmish")
const Overlay = preload("res://scripts/ui/map_overlay.gd")
const EDGE := Color(0.04,0.07,0.09,0.9)
const ALERT_PULSE_SECONDS := 6.0
func _process(_delta: float) -> void:
	queue_redraw()
func world_to_map(point: Vector3) -> Vector2:
	return (Vector2(point.x,point.z)-bounds.position)/bounds.size*size
func map_to_world(point: Vector2) -> Vector3:
	var value := bounds.position+(point/size).clamp(Vector2.ZERO,Vector2.ONE)*bounds.size
	return Vector3(value.x,0,value.y)
const PICK_RADIUS := 9.0
func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed: return
	if event.button_index == MOUSE_BUTTON_RIGHT and game.armed():
		game.cancel_armed(); game.notify("Command cancelled.")
		accept_event()
	elif event.button_index == MOUSE_BUTTON_LEFT:
		# While Load, Unload or Pin waits for a stop, clicking a pulsing marker picks it; elsewhere pans.
		var stop := stop_at(event.position)
		if stop != null: game.hud.pick_stop(stop,event.shift_pressed)
		else: game.get_node("CameraRig").focus_position(map_to_world(event.position))
		accept_event()
func stop_at(point: Vector2) -> Node3D:
	var best: Node3D
	var distance := PICK_RADIUS
	for stop in game.hud.pick_stops():
		var d := world_to_map(stop.global_position).distance_to(point)
		if d <= distance: best = stop; distance = d
	return best
func _draw() -> void:
	if not is_instance_valid(game): return
	for cell in game.ground.cleared_forest:
		var top_left := world_to_map(game.ground.tile_to_world(cell))-size/500.0*0.5
		draw_rect(Rect2(top_left,size/500.0),Color(0.45,0.35,0.18))
	for rail in get_tree().get_nodes_in_group("rails"):
		draw_rect(Rect2(world_to_map(rail.global_position)-Vector2.ONE,Vector2(2,2)),Color(0.4,0.8,0.85) if game.get_node("RailNetwork").friendly(rail.cell,"player") else Color(0.85,0.3,0.25))
	# Markers share the map overlay's team colours, with a dark edge so they read on any terrain.
	for group in ["resources","selectable_buildings","units"]:
		for node in get_tree().get_nodes_in_group(group):
			if group == "resources" and node.is_in_group("mines"): continue
			var point := world_to_map(node.global_position)
			var color: Color = Overlay.RESOURCE_COLORS[&"coal"] if group == "resources" else Overlay.TEAM_COLORS.get(str(node.team),Overlay.TEAM_COLORS["neutral"])
			if group == "selectable_buildings":
				draw_rect(Rect2(point-Vector2(4,4),Vector2(8,8)),EDGE)
				draw_rect(Rect2(point-Vector2(3,3),Vector2(6,6)),color)
			elif group == "resources":
				draw_colored_polygon(PackedVector2Array([point+Vector2(0,-3),point+Vector2(3,0),point+Vector2(0,3),point+Vector2(-3,0)]),color)
			else:
				draw_circle(point,3.2,EDGE)
				draw_circle(point,2.3,color)
			if (group == "units" and node.is_selected) or node == game.selected_building: draw_arc(point,6,0,TAU,16,Color.WHITE,1.5)
	# Recent alerts pulse where they happened.
	var now := Time.get_ticks_msec()/1000.0
	# Stops a waiting Load, Unload or Pin can pick: a steady ring with a pulse.
	for stop in game.hud.pick_stops():
		var at := world_to_map(stop.global_position)
		draw_arc(at,7,0,TAU,20,Overlay.TEAM_COLORS["player"],2)
		draw_arc(at,7+5*fmod(now*1.5,1.0),0,TAU,20,Color(Overlay.TEAM_COLORS["player"],1.0-fmod(now*1.5,1.0)),1.5)
	for alert in game.alerts:
		var age: float = now-alert.time
		if age > ALERT_PULSE_SECONDS: continue
		var pulse := fmod(age,1.0)
		draw_arc(world_to_map(alert.point),4+8*pulse,0,TAU,20,Color(Overlay.RED,1.0-pulse),2)
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
	draw_rect(Rect2(Vector2.ZERO,size),Color(0.165,0.239,0.282),false,2)
