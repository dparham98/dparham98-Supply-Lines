extends Control
# Map status overlay (docs/UI_PHASE_C.md): one screen-space pass draws health bars, production
# progress, status icons, capture rings, carried cargo, route lines and delivery pop-ups above
# actors, replacing their always-on text labels at runtime. Hold Alt to show everything.
const Bounds = preload("res://scripts/units/selection_bounds.gd")
const TEAM_COLORS := {"player": Color(0.37,0.82,0.54), "enemy": Color(0.89,0.35,0.31), "neutral": Color(0.6,0.65,0.68)}
const RESOURCE_COLORS := {&"energy": Color(0.498,0.827,0.902), &"iron": Color(0.604,0.655,0.678), &"wood": Color(0.435,0.682,0.353), &"coal": Color(0.788,0.541,0.29)}
const AMBER := Color(0.941,0.698,0.29)
const RED := Color(0.89,0.35,0.31)
const TRACK := Color(0.055,0.09,0.114,0.85)
const STORAGE_WARNING := 0.9
const POPUP_SECONDS := 1.5
const PING_SECONDS := 0.6
const HIGHLIGHT_SECONDS := 0.8
const ORDER_COLORS := {"move": Color(0.498,0.827,0.902), "attack": Color(0.89,0.35,0.31), "attack_move": Color(0.89,0.35,0.31), "gather": Color(0.435,0.682,0.353), "return": Color(0.941,0.698,0.29), "repair": Color(0.941,0.698,0.29), "capture": Color(0.91,0.96,0.98), "load": Color(0.498,0.827,0.902), "unload": Color(0.941,0.698,0.29), "deploy": Color(0.941,0.698,0.29)}
## Icon shown beside the pointer while a command or placement is armed.
const ARMED_ICONS := {"move": "move", "attack": "attack", "gather": "gather", "repair": "repair", "capture": "capture", "load": "load", "unload": "unload", "deploy": "deploy", "build": "build"}
var _armed_icons := {}
## Groups whose authored text labels this overlay replaces. Placement ghosts and waypoints keep theirs.
const LABELLED_GROUPS := ["units","selectable_buildings","resources","material_piles","iron_deposits","construction_plans"]
const LABEL_NAMES := ["Status","Cargo","Label","Progress"]
@export var bar_width := 34.0
@export var icons: Dictionary = {}
@onready var game = get_tree().get_first_node_in_group("skirmish")
@onready var card: PanelContainer = get_parent().get_node("HoverCard")
var hovered: Node3D
var popups: Array[Dictionary] = []
var pings: Array[Dictionary] = []
var _labels_hidden := {}
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if game != null:
		game.resources_delivered.connect(_on_delivered)
		game.order_given.connect(_on_order)
func show_all() -> bool:
	return InputMap.has_action("map_show_all") and Input.is_action_pressed("map_show_all")
func _process(_delta: float) -> void:
	if game == null: return
	hide_actor_labels()
	var mouse := get_viewport().get_mouse_position()
	hovered = null if get_viewport().gui_get_hovered_control() != null else hover_target(mouse)
	update_hover_card(mouse)
	var now := Time.get_ticks_msec()/1000.0
	popups = popups.filter(func(p): return now-p.time < POPUP_SECONDS and is_instance_valid(p.node))
	pings = pings.filter(func(p): return now-p.time < HIGHLIGHT_SECONDS)
	queue_redraw()
# Runtime only: saved scenes keep their labels visible in the editor.
func hide_actor_labels() -> void:
	for group in LABELLED_GROUPS:
		for node in get_tree().get_nodes_in_group(group):
			if _labels_hidden.has(node.get_instance_id()): continue
			for label in LABEL_NAMES:
				if node.has_node(label) and node.get_node(label) is Label3D: node.get_node(label).visible = false
			_labels_hidden[node.get_instance_id()] = true
	if _labels_hidden.size() > 512: _labels_hidden.clear()
func hover_target(screen: Vector2) -> Node3D:
	var camera := get_viewport().get_camera_3d()
	if camera == null: return null
	var best: Node3D
	var distance := INF
	for group in LABELLED_GROUPS:
		for node in get_tree().get_nodes_in_group(group):
			var d: float = Bounds.hit_distance(node,camera,screen)
			if d < distance: distance = d; best = node
	return best
func is_selected(node: Node) -> bool:
	return node.get("is_selected") == true or node == game.selected_building
func team_color(node: Node) -> Color:
	return TEAM_COLORS.get(str(node.get("team")),TEAM_COLORS["neutral"])
# What to draw for one actor; tests read this instead of pixels.
func status_for(node: Node3D) -> Dictionary:
	var entry := {node = node, health = -1.0, progress = -1.0, icons = [], capture = -1.0, carry = {}, storage = {}}
	var health = node.get("health")
	var max_health = node.get("max_health")
	if health != null and max_health != null and max_health > 0:
		var damaged: bool = health < max_health
		if damaged or is_selected(node) or node == hovered or show_all(): entry.health = float(health)/max_health
	if node.is_in_group("depots"):
		if node.queue > 0: entry.progress = node.progress/node.print_seconds
		if node.capture_progress > 0: entry.capture = node.capture_progress/node.rules.capture_seconds
	elif node.is_in_group("production_buildings"):
		if node.queue > 0: entry.progress = node.progress/node.stats.print_seconds
		if node.exit_blocked: entry.icons.append(["cancel",AMBER])
	if node.is_in_group("energy_generators") and not node.enabled: entry.icons.append(["pause",AMBER])
	if node.is_in_group("mines") and node.remaining <= 0: entry.icons.append(["mine",TEAM_COLORS["neutral"]])
	var stockpile = node.get("stockpile")
	if stockpile is ResourceStockpile and (node.is_in_group("depots") or node.get("deployed") == true) and stockpile.capacity > 0 and stockpile.total() >= stockpile.capacity*STORAGE_WARNING:
		entry.icons.append(["depot",AMBER])
	if game.recently_attacked(node): entry.icons.append(["attack",RED])
	if stockpile is ResourceStockpile and (node.is_in_group("depots") or node.get("is_cargo_vehicle") == true) and (node == hovered or is_selected(node) or show_all()):
		entry.storage = {stockpile = stockpile}
	if node.get("can_gather") == true and node.get("cargo") != null and node.cargo > 0:
		entry.carry = {color = RESOURCE_COLORS.get(node.cargo_kind,Color.WHITE), ratio = float(node.cargo)/maxi(1,node.carry_capacity)}
	if node.get("out_of_fuel") == true: entry.icons.append(["refuel",RED])
	elif node.has_method("fuel_low") and node.fuel_low(): entry.icons.append(["refuel",AMBER])
	return entry
func entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for group in ["units","selectable_buildings"]:
		for node in get_tree().get_nodes_in_group(group):
			var entry := status_for(node)
			if entry.health >= 0 or entry.progress >= 0 or not entry.icons.is_empty() or entry.capture >= 0 or not entry.carry.is_empty() or not entry.storage.is_empty(): out.append(entry)
	return out
# Route lines for selected friendly vehicles on a supply route.
func route_lines() -> Array[Array]:
	var lines: Array[Array] = []
	for unit in get_tree().get_nodes_in_group("units"):
		if not unit.get("is_cargo_vehicle") or not unit.is_selected: continue
		if unit.route_active and is_instance_valid(unit.origin_depot) and is_instance_valid(unit.destination_depot):
			lines.append([unit.origin_depot.global_position,unit.destination_depot.global_position])
		else:
			var pair: Array = unit.shipment_pair()
			if not pair.is_empty(): lines.append([pair[0].global_position,pair[1].global_position])
	return lines
func _on_delivered(target: Node3D, kind: StringName, amount: int) -> void:
	popups.append({node = target, text = "+%d %s" % [amount,str(kind)], color = RESOURCE_COLORS.get(kind,Color.WHITE), time = Time.get_ticks_msec()/1000.0})
# One ping per order: a group order emits once per unit, so repeats at the same spot are merged.
func _on_order(kind: String, point: Vector3, target: Node3D, queued: bool) -> void:
	var msec := Time.get_ticks_msec()
	for ping in pings:
		if ping.msec == msec and ping.kind == kind and ping.queued == queued and ping.point.distance_to(point) < 0.5: return
	pings.append({kind = kind, point = point, target = target, queued = queued, time = msec/1000.0, msec = msec})
# Unfilled ellipse outline (CanvasItem.draw_ellipse with filled off).
func draw_ring(center: Vector2, radius: Vector2, color: Color, width: float) -> void:
	draw_ellipse(center,radius.x,radius.y,color,false,width,true)
# Dashed footprint for unpaid construction plans.
func plan_outline(plan: Node3D, camera: Camera3D) -> PackedVector2Array:
	var size: Vector2i = plan.spec.size
	var a: Vector3 = game.ground.tile_to_world(plan.start)-Vector3(0.5,0,0.5)
	var b: Vector3 = game.ground.tile_to_world(plan.start+size-Vector2i.ONE)+Vector3(0.5,0,0.5)
	var corners := PackedVector2Array()
	for corner in [Vector3(a.x,0,a.z),Vector3(b.x,0,a.z),Vector3(b.x,0,b.z),Vector3(a.x,0,b.z),Vector3(a.x,0,a.z)]:
		if camera.is_position_behind(corner): return PackedVector2Array()
		corners.append(camera.unproject_position(corner))
	return corners
func top_of(node: Node3D, camera: Camera3D) -> Vector2:
	var rect: Rect2 = Bounds.screen_rect(node,camera)
	if rect.size == Vector2.ZERO: return camera.unproject_position(node.global_position+Vector3.UP*2)
	return Vector2(rect.get_center().x,rect.position.y)
func _draw() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or game == null: return
	var font := get_theme_default_font()
	for plan in get_tree().get_nodes_in_group("construction_plans"):
		var corners := plan_outline(plan,camera)
		for i in range(corners.size()-1): draw_dashed_line(corners[i],corners[i+1],Color(0.91,0.96,0.98,0.8),1.5,6)
	if is_instance_valid(hovered) and hovered.is_in_group("units") and not camera.is_position_behind(hovered.global_position):
		var rect: Rect2 = Bounds.screen_rect(hovered,camera)
		var color := Color(1,1,1,0.75) if hovered.team == "player" else Color(RED,0.85)
		draw_ring(Vector2(rect.get_center().x,rect.end.y),Vector2(maxf(12,rect.size.x*0.6),maxf(5,rect.size.x*0.22)),color,1.5)
	var now_pings := Time.get_ticks_msec()/1000.0
	for ping in pings:
		var age: float = now_pings-ping.time
		var color: Color = ORDER_COLORS.get(ping.kind,Color.WHITE)
		if is_instance_valid(ping.target) and not camera.is_position_behind(ping.target.global_position):
			var rect: Rect2 = Bounds.screen_rect(ping.target,camera).grow(4)
			color.a = 1.0-age/HIGHLIGHT_SECONDS
			var k := minf(10,rect.size.x/3)
			for c in [[rect.position,Vector2(1,1)],[Vector2(rect.end.x,rect.position.y),Vector2(-1,1)],[rect.end,Vector2(-1,-1)],[Vector2(rect.position.x,rect.end.y),Vector2(1,-1)]]:
				draw_line(c[0],c[0]+Vector2(k*c[1].x,0),color,2)
				draw_line(c[0],c[0]+Vector2(0,k*c[1].y),color,2)
		elif age < PING_SECONDS and not camera.is_position_behind(ping.point):
			var center := camera.unproject_position(ping.point)
			var t := age/PING_SECONDS
			color.a = 1.0-t
			draw_ring(center,Vector2(6+16*t,3+8*t),color,2)
			if not ping.queued: draw_ring(center,Vector2(3,1.5),color,2)
	for line in route_lines():
		if camera.is_position_behind(line[0]) or camera.is_position_behind(line[1]): continue
		var a := camera.unproject_position(line[0])
		var b := camera.unproject_position(line[1])
		draw_dashed_line(a,b,Color(0.91,0.96,0.98,0.85),2,10)
		var mid := (a+b)/2
		var dir := (b-a).normalized()
		var side := Vector2(-dir.y,dir.x)
		draw_polyline(PackedVector2Array([mid-dir*7+side*6,mid+dir*3,mid-dir*7-side*6]),Color(0.91,0.96,0.98),2)
	for entry in entries():
		var node: Node3D = entry.node
		if camera.is_position_behind(node.global_position): continue
		var top := top_of(node,camera)
		var y := top.y-8
		var x := top.x-bar_width/2
		if entry.health >= 0:
			draw_rect(Rect2(x,y,bar_width,4),TRACK)
			draw_rect(Rect2(x,y,bar_width*clampf(entry.health,0,1),4),team_color(node))
			if show_all(): draw_string(font,Vector2(x,y-4),hud_name(node),HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color(0.9,0.93,0.94))
		if not entry.storage.is_empty():
			draw_storage(entry.storage.stockpile,Rect2(x,y+(10 if entry.progress >= 0 else 6),bar_width,4))
		if entry.progress >= 0:
			draw_rect(Rect2(x,y+6,bar_width,3),TRACK)
			draw_rect(Rect2(x,y+6,bar_width*clampf(entry.progress,0,1),3),Color(0.498,0.827,0.902))
		if not entry.carry.is_empty():
			draw_rect(Rect2(x,y-6,bar_width*0.5,3),TRACK)
			draw_rect(Rect2(x,y-6,bar_width*0.5*clampf(entry.carry.ratio,0,1),3),entry.carry.color)
		var ix := x+bar_width+3
		for icon in entry.icons:
			var texture: Texture2D = icons.get(icon[0])
			if texture != null:
				draw_circle(Vector2(ix+8,y+1),10,TRACK)
				draw_texture_rect(texture,Rect2(ix+1,y-6,14,14),false,icon[1])
			ix += 21
		if entry.capture >= 0:
			var center := camera.unproject_position(node.global_position)
			draw_arc(center,18,-PI/2,-PI/2+TAU*clampf(entry.capture,0,1),32,TEAM_COLORS.get(str(node.capture_team),AMBER),3)
	draw_armed(camera,font)
	var now := Time.get_ticks_msec()/1000.0
	for popup in popups:
		var age: float = (now-popup.time)/POPUP_SECONDS
		var at := top_of(popup.node,camera)-Vector2(0,14+24*age)
		var color: Color = popup.color
		color.a = 1.0-age
		draw_string(font,at-Vector2(20,0),popup.text,HORIZONTAL_ALIGNMENT_LEFT,-1,13,color)
# One bar split by resource against capacity, matching the HUD storage bar.
func draw_storage(stockpile: ResourceStockpile, rect: Rect2) -> void:
	draw_rect(rect,TRACK)
	var x := rect.position.x
	for kind in RESOURCE_COLORS:
		var width := rect.size.x*stockpile.amount(kind)/maxf(1,stockpile.capacity)
		if width > 0: draw_rect(Rect2(x,rect.position.y,width,rect.size.y),RESOURCE_COLORS[kind])
		x += width
func armed_kind() -> String:
	if not game.pending_unit_command.is_empty(): return game.pending_unit_command
	if game.placing_depot or game.placing_generator or game.placing_rail or not game.placing_structure.is_empty() or not game.global_plan_kind.is_empty(): return "build"
	return ""
func selected_truck() -> Node3D:
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.team == "player" and unit.is_selected and unit.is_depot_truck: return unit
	return null
# Armed commands: an icon beside the pointer; Deploy also previews its footprint.
func draw_armed(camera: Camera3D, font: Font) -> void:
	var kind := armed_kind()
	if kind.is_empty(): return
	var mouse := get_viewport().get_mouse_position()
	if kind == "deploy":
		var point = Plane(Vector3.UP,0).intersects_ray(camera.project_ray_origin(mouse),camera.project_ray_normal(mouse))
		var truck := selected_truck()
		if point != null and truck != null:
			var network = game.get_node("DepotNetwork")
			var size: Vector2i = Vector2i(8,8)
			var start: Vector2i = network.footprint_start(point,size)
			var a: Vector3 = game.ground.tile_to_world(start)-Vector3(0.5,0,0.5)
			var b: Vector3 = game.ground.tile_to_world(start+size-Vector2i.ONE)+Vector3(0.5,0,0.5)
			var corners := PackedVector2Array()
			for c in [Vector3(a.x,0,a.z),Vector3(b.x,0,a.z),Vector3(b.x,0,b.z),Vector3(a.x,0,b.z)]: corners.append(camera.unproject_position(c))
			var ok: bool = network.can_deploy_at(truck,point)
			var fill := Color(0.37,0.82,0.54,0.22) if ok else Color(0.89,0.35,0.31,0.25)
			draw_colored_polygon(corners,fill)
			corners.append(corners[0])
			draw_polyline(corners,Color(fill,0.9),2)
	var icon_name: String = ARMED_ICONS.get(kind,"focus")
	if not _armed_icons.has(icon_name): _armed_icons[icon_name] = load("res://assets/ui/icons/%s.svg" % icon_name)
	var color: Color = ORDER_COLORS.get(kind,AMBER)
	var at := mouse+Vector2(16,14)
	draw_circle(at+Vector2(9,9),12,TRACK)
	draw_texture_rect(_armed_icons[icon_name],Rect2(at,Vector2(18,18)),false,color)
	draw_string(font,at+Vector2(24,14),kind.replace("_","-").capitalize(),HORIZONTAL_ALIGNMENT_LEFT,-1,12,color)
func hud_name(node: Node) -> String:
	if node.is_in_group("material_piles"): return "%s pile" % str(node.material_kind).capitalize()
	if node.is_in_group("iron_deposits"): return "Iron deposit · build a mine to gather"
	if node.is_in_group("resources"): return str(node.get("resource_name")) if node.get("resource_name") != null else "Resource"
	if node.is_in_group("construction_plans"): return node.spec.title+" plan"
	return get_parent().object_name(node)
# Name, owner and health, plus remaining amounts or storage, beside the pointer.
func update_hover_card(mouse: Vector2) -> void:
	card.visible = is_instance_valid(hovered)
	if not card.visible: return
	var node := hovered
	card.get_node("Body/Name").text = hud_name(node)
	var line := ""
	var ratio := -1.0
	if node.is_in_group("resources") or node.is_in_group("material_piles") or node.is_in_group("iron_deposits"):
		line = "%d left" % node.remaining
		if node.get("amount") != null and node.amount > 0: ratio = float(node.remaining)/node.amount
	elif node.is_in_group("construction_plans"):
		line = "Unpaid · %d E · %d I · %s" % [node.spec.energy,node.spec.iron,node.state]
	else:
		line = "%s · health %d / %d" % [str(node.get("team")).capitalize(),node.health,node.max_health]
		if node.is_in_group("mines"): line += " · %d iron left" % node.remaining
		var stockpile = node.get("stockpile")
		if stockpile is ResourceStockpile and (node.is_in_group("depots") or node.get("is_cargo_vehicle") == true):
			line += "\nStorage %d / %d" % [stockpile.total(),stockpile.capacity]
			ratio = float(stockpile.total())/maxi(1,stockpile.capacity)
	card.get_node("Body/Line").text = line
	var health = node.get("health")
	var max_health = node.get("max_health")
	card.get_node("Body/Health").visible = health != null and max_health != null and max_health > 0
	if card.get_node("Body/Health").visible: card.get_node("Body/Health").value = float(health)/max_health
	var stockpile = node.get("stockpile")
	var split: bool = stockpile is ResourceStockpile and (node.is_in_group("depots") or node.get("is_cargo_vehicle") == true)
	card.get_node("Body/Storage").visible = split
	if split:
		for kind in RESOURCE_COLORS:
			var segment: Control = card.get_node("Body/Storage/Segments/"+str(kind).capitalize())
			segment.visible = stockpile.amount(kind) > 0
			segment.size_flags_stretch_ratio = maxf(stockpile.amount(kind),0.001)
		card.get_node("Body/Storage/Segments/Free").size_flags_stretch_ratio = maxf(stockpile.space(),0.001)
		ratio = -1.0
	card.get_node("Body/Meter").visible = ratio >= 0
	if ratio >= 0: card.get_node("Body/Meter").value = ratio
	card.reset_size()
	var pos := mouse+Vector2(18,18)
	# Keep the card above the bottom HUD.
	var limit := Vector2(get_viewport_rect().size.x,get_parent().get_node("Bottom").global_position.y)-card.size-Vector2(4,4)
	card.position = pos.clamp(Vector2.ZERO,limit)
