extends Control
## North-up map: world +X right, +Z down. Left-click moves the camera; right-click orders the selected units
## to that point, and a waiting command (Move, Attack, Gather, Deploy, Unload...) takes its point here too
## (docs/MINIMAP_ORDERS.md).
@export var bounds := Rect2(-250,-250,500,500)
@onready var game = get_tree().get_first_node_in_group("skirmish")
const Overlay = preload("res://scripts/ui/map_overlay.gd")
const EDGE := Color(0.05,0.055,0.047,0.9)
const COAL_FILL := Color(0.1,0.09,0.08)
const COAL_RIM := Color(0.95,0.6,0.22)
const IRON_FILL := Color(0.58,0.74,0.92)
const ALERT_PULSE_SECONDS := 6.0
func _process(_delta: float) -> void:
	queue_redraw()
func world_to_map(point: Vector3) -> Vector2:
	return (Vector2(point.x,point.z)-bounds.position)/bounds.size*size
func map_to_world(point: Vector2) -> Vector3:
	var value := bounds.position+(point/size).clamp(Vector2.ZERO,Vector2.ONE)*bounds.size
	return Vector3(value.x,0,value.y)
const PICK_RADIUS := 9.0
## How near a marker an order click must land to target it, in minimap pixels.
const ORDER_PICK_RADIUS := 4.0
## Commands that only take a stop: a click away from every stop pans instead.
const STOP_ONLY := ["pin"]
func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed: return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		# Right-click cancels an armed command, as on the map, else orders the selected units there.
		if game.armed(): game.cancel_armed(); game.notify("Command cancelled.")
		elif not game.hud.selected_units().is_empty(): game.issue_map_order(map_to_world(event.position),order_radius(),false,event.shift_pressed)
		accept_event()
	elif event.button_index == MOUSE_BUTTON_LEFT:
		# While Load, Unload or Pin waits for a stop, clicking a pulsing marker picks it. Another waiting unit
		# command takes the clicked point; with none waiting the click pans.
		var stop := stop_at(event.position)
		if stop != null: game.hud.pick_stop(stop,event.shift_pressed)
		elif not game.pending_unit_command.is_empty() and game.pending_unit_command not in STOP_ONLY:
			game.issue_map_order(map_to_world(event.position),order_radius(),true,event.shift_pressed)
		else: game.get_node("CameraRig").focus_position(map_to_world(event.position))
		accept_event()
## ORDER_PICK_RADIUS in world metres at this minimap's scale, by the coarser axis if they differ.
func order_radius() -> float:
	return ORDER_PICK_RADIUS*maxf(bounds.size.x/maxf(1.0,size.x),bounds.size.y/maxf(1.0,size.y))
func stop_at(point: Vector2) -> Node3D:
	var best: Node3D
	var distance := PICK_RADIUS
	for stop in game.hud.pick_stops():
		var d := world_to_map(stop.global_position).distance_to(point)
		if d <= distance: best = stop; distance = d
	return best
func _draw() -> void:
	if not is_instance_valid(game): return
	for cleared in [game.ground.cleared_forest,game.ground.cleared_coal]:
		for cell in cleared:
			var top_left := world_to_map(game.ground.tile_to_world(cell))-size/500.0*0.5
			draw_rect(Rect2(top_left,size/500.0),Color(0.45,0.35,0.18))
	# Deposits (docs/MINIMAP_ORDERS.md, Deposits): coal is a black lump in an amber rim, iron a steel-blue peak.
	# Coal fields are a few pixels across at this scale, so each one that still holds coal gets a marker; a mine
	# shows the deposit it works, ringed when it is selected.
	var mined := {}
	for mine in get_tree().get_nodes_in_group("mines"):
		if mine.get("on_coal") == true and not mine.cells.is_empty(): mined[game.ground.coal_field_at(mine.cells[0]).get("center")] = true
	for field in game.ground.coal_fields:
		if game.ground.coal_field_remaining(field) <= 0 or mined.has(field.center): continue
		draw_coal(world_to_map(field.center))
	for group in ["mines","iron_deposits"]:
		for node in get_tree().get_nodes_in_group(group):
			var at := world_to_map(node.global_position)
			if node.get("on_coal") == true: draw_coal(at)
			else: draw_iron(at)
			if node == game.selected_building: draw_arc(at,8,0,TAU,16,Color.WHITE,1.5)
	# Fog of war (docs/FOG_OF_WAR.md): the map is dimmed outside the player's sight, and the other side's
	# markers show only inside it.
	var fog = game.fog_of_war()
	if fog != null: draw_texture_rect(fog.shade_texture(),Rect2(world_to_map(fog.map_corner()),world_to_map(fog.map_corner()+fog.map_size())-world_to_map(fog.map_corner())),false,Color(1,1,1,0.55))
	for rail in get_tree().get_nodes_in_group("rails"):
		if fog != null and not fog.shows(rail): continue
		var colour := Color(0.4,0.8,0.85) if game.get_node("RailNetwork").friendly_piece(rail,"player") else Color(0.85,0.3,0.25)
		var total: float = rail.length()
		var steps := maxi(2,int(total/2.0))
		var line := PackedVector2Array()
		for i in range(steps+1): line.append(world_to_map(rail.point_at(total*i/steps)))
		draw_polyline(line,colour,1.5)
	# Markers share the map overlay's team colours, with a dark edge so they read on any terrain.
	for group in ["resources","selectable_buildings","units"]:
		for node in get_tree().get_nodes_in_group(group):
			if node.is_in_group("mines"): continue
			if fog != null and not fog.shows(node): continue
			var point := world_to_map(node.global_position)
			var color: Color = Overlay.RESOURCE_COLORS.get(node.get("resource_kind"),Overlay.RESOURCE_COLORS[&"wood"]) if group == "resources" else Overlay.TEAM_COLORS.get(str(node.team),Overlay.TEAM_COLORS["neutral"])
			if group == "selectable_buildings":
				draw_rect(Rect2(point-Vector2(4,4),Vector2(8,8)),EDGE)
				draw_rect(Rect2(point-Vector2(3,3),Vector2(6,6)),color)
			elif group == "resources":
				draw_colored_polygon(PackedVector2Array([point+Vector2(0,-3),point+Vector2(3,0),point+Vector2(0,3),point+Vector2(-3,0)]),color)
			else:
				draw_circle(point,3.2,EDGE)
				draw_circle(point,2.3,color)
			if (group == "units" and node.is_selected) or node == game.selected_building or game.selected_buildings.has(node): draw_arc(point,6,0,TAU,16,Color.WHITE,1.5)
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
	draw_rect(Rect2(Vector2.ZERO,size),Color(0.451,0.42,0.349),false,2)
## A coal deposit: a black diamond in an amber rim.
func draw_coal(at: Vector2) -> void:
	draw_colored_polygon(PackedVector2Array([at+Vector2(0,-6.5),at+Vector2(6.5,0),at+Vector2(0,6.5),at+Vector2(-6.5,0)]),EDGE)
	draw_colored_polygon(PackedVector2Array([at+Vector2(0,-5.5),at+Vector2(5.5,0),at+Vector2(0,5.5),at+Vector2(-5.5,0)]),COAL_RIM)
	draw_colored_polygon(PackedVector2Array([at+Vector2(0,-3.5),at+Vector2(3.5,0),at+Vector2(0,3.5),at+Vector2(-3.5,0)]),COAL_FILL)
## An iron deposit: a steel-blue peak with a dark edge.
func draw_iron(at: Vector2) -> void:
	draw_colored_polygon(PackedVector2Array([at+Vector2(0,-7.5),at+Vector2(7,5),at+Vector2(-7,5)]),EDGE)
	draw_colored_polygon(PackedVector2Array([at+Vector2(0,-5),at+Vector2(5,3.6),at+Vector2(-5,3.6)]),IRON_FILL)
	draw_line(at+Vector2(-2,1),at+Vector2(0,-2),Color(1,1,1,0.75),1.0)
