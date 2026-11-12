extends SceneTree
# Draws a labelled top-down picture of a playable map for review: its terrain cells in the layout palette, the
# markers under the scene's Sites node, and every coal and iron field found in the cells.
# It needs a window, so run it without --headless:
#   godot --path . --script res://scripts/tools/draw_map_preview.gd
# Another map: -- --scene=<skirmish .tscn> --output=<picture .png>
const MapLayout := preload("res://scripts/tools/map_layout.gd")
const ToolArgs := preload("res://scripts/tools/tool_args.gd")
const SIZE := 500
const SCALE := 2
const LEGEND := 64

class Sheet extends Control:
	var map: ImageTexture
	var marks: Array = []
	var legend: Array = []
	func _draw() -> void:
		var font := ThemeDB.fallback_font
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.075, 0.08))
		draw_texture_rect(map, Rect2(0, 0, SIZE*SCALE, SIZE*SCALE), false)
		for mark in marks:
			var at: Vector2 = mark.at
			match mark.kind:
				"start":
					draw_circle(at, 13, Color.BLACK)
					draw_circle(at, 10, mark.colour)
				"site":
					draw_rect(Rect2(at-Vector2(10, 10), Vector2(20, 20)), Color.BLACK)
					draw_rect(Rect2(at-Vector2(7, 7), Vector2(14, 14)), mark.colour)
				"coal":
					draw_colored_polygon(PackedVector2Array([at+Vector2(0, -12), at+Vector2(12, 0), at+Vector2(0, 12), at+Vector2(-12, 0)]), Color.BLACK)
					draw_colored_polygon(PackedVector2Array([at+Vector2(0, -8), at+Vector2(8, 0), at+Vector2(0, 8), at+Vector2(-8, 0)]), mark.colour)
		# Names go on last, so no marker covers one.
		for mark in marks:
			var at: Vector2 = mark.at
			var text_size: int = mark.get("font", 15)
			var width := font.get_string_size(mark.text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x
			var offset: Vector2 = mark.offset
			var origin: Vector2 = (at+offset-Vector2(width*0.5, 0)).clamp(Vector2(4, 16), Vector2(SIZE*SCALE-width-4, SIZE*SCALE-6))
			draw_string_outline(font, origin, mark.text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, 6, Color(0, 0, 0, 0.9))
			draw_string(font, origin, mark.text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, Color.WHITE)
		var x := 16.0
		for entry in legend:
			draw_rect(Rect2(x, SIZE*SCALE+14, 26, 26), Color.WHITE)
			draw_rect(Rect2(x+2, SIZE*SCALE+16, 22, 22), entry.colour)
			draw_string(font, Vector2(x+34, SIZE*SCALE+32), entry.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.9, 0.9, 0.88))
			x += 46+font.get_string_size(entry.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_string(font, Vector2(16, SIZE*SCALE+58), "1 pixel of the layout = 1 m. North is up. Circles: starts. Squares: Depot sites. Diamonds: coal fields.", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.7, 0.68))

func _initialize() -> void: call_deferred("run")

func to_sheet(point: Vector3) -> Vector2:
	return Vector2(point.x+SIZE*0.5, point.z+SIZE*0.5)*SCALE

func run() -> void:
	var game: Node3D = load(ToolArgs.value("scene", "res://scenes/maps/balanced_skirmish.tscn")).instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED
	var ground: Node3D = get_first_node_in_group("terrain_grid")
	var cells: PackedByteArray = FileAccess.get_file_as_bytes(ground.cells_path)
	var pixels := PackedByteArray()
	pixels.resize(SIZE*SIZE*3)
	for i in range(SIZE*SIZE):
		var colour: Color = MapLayout.PALETTE[cells[i]]
		pixels[i*3] = colour.r8; pixels[i*3+1] = colour.g8; pixels[i*3+2] = colour.b8
	var sheet := Sheet.new()
	sheet.map = ImageTexture.create_from_image(Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGB8, pixels))
	sheet.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sheet.size = Vector2(SIZE*SCALE, SIZE*SCALE+LEGEND)
	# Iron fields: each connected group of Ore cells.
	var seen := {}
	for i in range(SIZE*SIZE):
		if cells[i] != 5 or seen.has(i): continue
		var open: Array[int] = [i]
		var sum := Vector2.ZERO
		var count := 0
		seen[i] = true
		while not open.is_empty():
			var at: int = open.pop_back()
			sum += Vector2(at%SIZE+0.5, at/SIZE+0.5); count += 1
			for step in [1, -1, SIZE, -SIZE]:
				var next: int = at+step
				if next >= 0 and next < SIZE*SIZE and cells[next] == 5 and not seen.has(next): seen[next] = true; open.append(next)
		sheet.marks.append({"kind": "label", "at": sum/count*SCALE, "offset": Vector2(0, -12), "text": "Iron %s" % _thousands(count*ground.harvesting_rules.iron_per_tile), "font": 13})
	var richest := 0
	var poorest := 1 << 30
	for field in ground.coal_fields:
		richest = maxi(richest, ground.coal_field_remaining(field))
		poorest = mini(poorest, ground.coal_field_remaining(field))
	for field in ground.coal_fields:
		var amount: int = ground.coal_field_remaining(field)
		var contested: bool = amount == richest and richest > poorest
		sheet.marks.append({"kind": "coal", "at": to_sheet(field.center), "offset": Vector2(0, 30), "colour": Color(1.0, 0.85, 0.3) if contested else Color.WHITE, "text": ("Contested coal %s" if contested else "Coal %s") % _thousands(amount)})
	if game.has_node("Sites"): _markers(game.get_node("Sites"), sheet)
	var counts := MapLayout.counts(cells)
	for kind in range(counts.size()):
		sheet.legend.append({"colour": MapLayout.PALETTE[kind], "text": "%s %.1f%%" % [MapLayout.NAMES[kind].capitalize(), counts[kind]*100.0/(SIZE*SIZE)]})
	var viewport := SubViewport.new()
	viewport.size = Vector2i(sheet.size)
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.add_child(sheet)
	root.add_child(viewport)
	for frame in range(3): await process_frame
	await RenderingServer.frame_post_draw
	var output := ToolArgs.value("output", "res://docs/images/balanced_map_preview.png")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	if viewport.get_texture().get_image().save_png(ProjectSettings.globalize_path(output)) != OK:
		push_error("Could not save "+output); quit(1); return
	print("MAP_PREVIEW_DRAWN ", output)
	quit()

func _markers(node: Node, sheet: Sheet) -> void:
	for child in node.get_children():
		if child is Marker3D:
			var text: String = child.name.capitalize()
			if node.name == "Lanes": sheet.marks.append({"kind": "label", "at": to_sheet(child.position), "offset": Vector2.ZERO, "text": text.to_upper(), "font": 17})
			elif text.contains("Start"): sheet.marks.append({"kind": "start", "at": to_sheet(child.position), "offset": Vector2(0, -24), "colour": Color(0.37, 0.82, 0.54) if text.contains("Player") else Color(0.89, 0.35, 0.31), "text": text.to_upper(), "font": 17})
			else: sheet.marks.append({"kind": "site", "at": to_sheet(child.position), "offset": Vector2(0, 28), "colour": Color(0.37, 0.82, 0.54) if text.ends_with("A") else Color(0.89, 0.35, 0.31), "text": text})
		else: _markers(child, sheet)

func _thousands(value: int) -> String:
	var text := str(value)
	return text if text.length() <= 3 else text.substr(0, text.length()-3)+","+text.substr(text.length()-3)
