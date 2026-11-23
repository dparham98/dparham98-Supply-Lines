extends SceneTree
## Draws the game's mouse cursors (docs/CURSORS.md) into assets/ui/cursors/*.png. Each is drawn four times larger and
## scaled down, for smooth edges. Run it again after changing a shape:
##   Godot --headless --path . --script res://scripts/tools/make_cursors.gd
const SIZE := 32
const SCALE := 4
const OUT := "res://assets/ui/cursors/"
const EDGE := Color(0.06,0.05,0.04,1)
const GOLD := Color(0.96,0.74,0.32,1)
const GOLD_LIGHT := Color(1.0,0.9,0.62,1)
const FRIEND := Color(0.5,0.85,0.92,1)
const RED := Color(0.93,0.3,0.25,1)
const WOOD := Color(0.47,0.72,0.36,1)
const HANDLE := Color(0.62,0.42,0.22,1)
const STEEL := Color(0.82,0.85,0.88,1)
## The pointer, its tip at (1,1).
const ARROW := [Vector2(1.5,1.5),Vector2(1.5,22),Vector2(6.5,17.5),Vector2(10,25.5),Vector2(13.2,24.2),Vector2(9.8,16.4),Vector2(16.4,16.4)]
var img: Image
func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for id in ["pointer","select","attack","inspect","gather"]:
		img = Image.create(SIZE*SCALE,SIZE*SCALE,false,Image.FORMAT_RGBA8)
		img.fill(Color(0,0,0,0))
		call("draw_"+id)
		img.resize(SIZE,SIZE,Image.INTERPOLATE_LANCZOS)
		img.save_png(OUT+id+".png")
	print("MAKE_CURSORS_DONE")
	quit()
# ---- shapes, in cursor pixels
func _each(rect: Rect2, inside: Callable, colour: Color) -> void:
	var r := Rect2i((rect.position*SCALE).floor(),(rect.size*SCALE).ceil()+Vector2.ONE*2).intersection(Rect2i(0,0,SIZE*SCALE,SIZE*SCALE))
	for y in range(r.position.y,r.end.y):
		for x in range(r.position.x,r.end.x):
			if inside.call(Vector2(x+0.5,y+0.5)/SCALE): img.set_pixel(x,y,colour)
func _seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var t := clampf((p-a).dot(b-a)/maxf((b-a).length_squared(),0.0001),0.0,1.0)
	return p.distance_to(a+(b-a)*t)
func polygon(points: Array, colour: Color, grow := 0.0) -> void:
	var packed := PackedVector2Array(points)
	var box := Rect2(points[0],Vector2.ZERO)
	for p in points: box = box.expand(p)
	_each(box.grow(grow+1),func(p):
		if Geometry2D.is_point_in_polygon(p,packed): return true
		if grow <= 0.0: return false
		for i in points.size():
			if _seg(p,points[i],points[(i+1)%points.size()]) <= grow: return true
		return false,colour)
func line(a: Vector2, b: Vector2, width: float, colour: Color) -> void:
	var box := Rect2(a,Vector2.ZERO).expand(b).grow(width)
	_each(box,func(p): return _seg(p,a,b) <= width*0.5,colour)
func ring(c: Vector2, radius: float, width: float, colour: Color) -> void:
	_each(Rect2(c-Vector2.ONE*(radius+width),Vector2.ONE*(radius+width)*2),func(p): return absf(p.distance_to(c)-radius) <= width*0.5,colour)
func disc(c: Vector2, radius: float, colour: Color) -> void:
	_each(Rect2(c-Vector2.ONE*radius,Vector2.ONE*radius*2),func(p): return p.distance_to(c) <= radius,colour)
func arrow(fill := GOLD) -> void:
	polygon(ARROW,EDGE,1.4)
	polygon(ARROW,fill)
	# A lighter left edge, as the HUD's bronze catches the light.
	line(Vector2(2.6,3.5),Vector2(2.6,18.5),1.3,GOLD_LIGHT)
# ---- the cursors
## Over nothing in particular.
func draw_pointer() -> void: arrow()
## Over something of yours that a click selects.
func draw_select() -> void:
	arrow()
	ring(Vector2(23.5,23.5),5.5,4.2,EDGE)
	ring(Vector2(23.5,23.5),5.5,2.0,FRIEND)
## Over an enemy: the crosshair, its centre the hotspot.
func draw_attack() -> void:
	var c := Vector2(16,16)
	ring(c,9.5,4.4,EDGE)
	for d in [Vector2.UP,Vector2.DOWN,Vector2.LEFT,Vector2.RIGHT]: line(c+d*5.0,c+d*14.5,4.2,EDGE)
	disc(c,2.6,EDGE)
	ring(c,9.5,2.2,RED)
	for d in [Vector2.UP,Vector2.DOWN,Vector2.LEFT,Vector2.RIGHT]: line(c+d*5.5,c+d*14.0,2.0,RED)
	disc(c,1.5,RED)
## Over a resource with nobody selected who can gather it: click to inspect it.
func draw_inspect() -> void:
	arrow()
	line(Vector2(25.5,25.5),Vector2(30,30),4.6,EDGE)
	ring(Vector2(21.5,21.5),5.0,4.2,EDGE)
	disc(Vector2(21.5,21.5),4.0,Color(0.75,0.9,1.0,0.45))
	ring(Vector2(21.5,21.5),5.0,2.0,GOLD_LIGHT)
	line(Vector2(25.5,25.5),Vector2(29.6,29.6),2.4,GOLD)
## Over wood, coal or ore with workers selected: a right-click gathers it.
func draw_gather() -> void:
	arrow()
	line(Vector2(17,30.5),Vector2(28.5,19),4.6,EDGE)
	var blade := [Vector2(23.5,16),Vector2(30.5,14.5),Vector2(31,22),Vector2(27,21.5)]
	polygon(blade,EDGE,1.3)
	line(Vector2(17,30.5),Vector2(28.5,19),2.4,HANDLE)
	polygon(blade,STEEL)
	line(Vector2(30,15.5),Vector2(30.3,21),1.2,WOOD)
