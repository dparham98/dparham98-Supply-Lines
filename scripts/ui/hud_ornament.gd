extends Control
# Decorative filler for spare HUD width: a framed panel with faint hatching, corner ticks and a
# small emblem. It carries no information, so the fixed-size HUD never stretches content to fill space.
@export var line_color := Color(0.165,0.239,0.282,1)
@export var accent_color := Color(0.122,0.435,0.502,0.55)
@export var hatch_spacing := 14.0
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
func _draw() -> void:
	if size.x < 24 or size.y < 24: return
	var rect := Rect2(Vector2(2,2),size-Vector2(4,4))
	draw_rect(rect,Color(0.039,0.071,0.086,0.6))
	var hatch := Color(line_color,0.35)
	var x := -rect.size.y
	while x < rect.size.x:
		var a := Vector2(rect.position.x+maxf(x,0),rect.position.y+maxf(-x,0))
		var b := Vector2(rect.position.x+minf(x+rect.size.y,rect.size.x),rect.position.y+minf(rect.size.y,rect.size.x-x))
		draw_line(a,b,hatch,1)
		x += hatch_spacing
	draw_rect(rect,line_color,false,1)
	var k := minf(14,rect.size.x/4)
	for corner in [[rect.position,Vector2(1,1)],[Vector2(rect.end.x,rect.position.y),Vector2(-1,1)],[rect.end,Vector2(-1,-1)],[Vector2(rect.position.x,rect.end.y),Vector2(1,-1)]]:
		draw_line(corner[0],corner[0]+Vector2(k*corner[1].x,0),accent_color,2)
		draw_line(corner[0],corner[0]+Vector2(0,k*corner[1].y),accent_color,2)
	var center := rect.get_center()
	var radius := minf(28,minf(rect.size.x,rect.size.y)/3)
	if radius < 10: return
	var hexagon := PackedVector2Array()
	for i in 7: hexagon.append(center+Vector2.from_angle(PI/6+TAU*i/6)*radius)
	draw_colored_polygon(hexagon.slice(0,6),Color(0.039,0.071,0.086,0.9))
	draw_polyline(hexagon,accent_color,2,true)
	draw_line(center+Vector2(-radius*0.45,0),center+Vector2(radius*0.45,0),accent_color,2)
	draw_line(center+Vector2(0,-radius*0.45),center+Vector2(0,radius*0.45),accent_color,2)
