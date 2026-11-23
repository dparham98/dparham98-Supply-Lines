extends SceneTree
## Builds assets/ui/hud_panel.png from Blender/UI/hud_panel_source.webp (docs/HUD_LAYOUT.md).
## The source is cut out with its windows (header band, minimap, middle panel, portrait, button cells) left
## transparent. Those windows, and anything not connected to the outside, are filled with the panel's dark
## interior so the HUD reads as one solid panel; only the outside stays transparent. Then the art is scaled to
## the HUD's 0.55.
## Run from the repository root:
##   godot --headless --script Blender/UI/make_hud_panel.gd
const SOURCE := "res://Blender/UI/hud_panel_source.webp"
const OUT := "res://assets/ui/hud_panel.png"
const SCALE := 0.55
const INTERIOR := Color(0.063,0.071,0.066)
func _initialize() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(SOURCE))
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width(); var h := img.get_height()
	# The outside: clear pixels connected to the image border.
	var outside := PackedByteArray(); outside.resize(w*h)
	var queue: Array[Vector2i] = []
	for x in w: queue.append(Vector2i(x,0)); queue.append(Vector2i(x,h-1))
	for y in h: queue.append(Vector2i(0,y)); queue.append(Vector2i(w-1,y))
	while not queue.is_empty():
		var p: Vector2i = queue.pop_back()
		if p.x < 0 or p.y < 0 or p.x >= w or p.y >= h: continue
		var i := p.y*w+p.x
		if outside[i] == 1 or img.get_pixelv(p).a >= 0.5: continue
		outside[i] = 1
		queue.append(p+Vector2i.RIGHT); queue.append(p+Vector2i.LEFT); queue.append(p+Vector2i.DOWN); queue.append(p+Vector2i.UP)
	# Everything else is panel: put it on the dark interior, so windows and their soft edges are opaque.
	for y in h:
		for x in w:
			if outside[y*w+x] == 1: continue
			var c := img.get_pixel(x,y)
			if c.a >= 1.0: continue
			img.set_pixel(x,y,Color(INTERIOR.lerp(Color(c.r,c.g,c.b),c.a),1.0))
	img.premultiply_alpha()
	img.resize(roundi(w*SCALE),roundi(h*SCALE),Image.INTERPOLATE_LANCZOS)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x,y)
			if c.a > 0.0: img.set_pixel(x,y,Color(c.r/c.a,c.g/c.a,c.b/c.a,c.a))
	img.save_png(ProjectSettings.globalize_path(OUT))
	print("HUD_PANEL ", img.get_size())
	quit()
