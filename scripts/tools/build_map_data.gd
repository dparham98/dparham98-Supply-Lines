extends SceneTree
# Turns a map's layout PNG into the files the game reads (docs/BALANCED_MAP.md). Give the map's folder after "--":
#   godot --headless --path . --script res://scripts/tools/build_map_data.gd -- --map=res://assets/maps/balanced
# From <map>/layout.png (scripts/tools/map_layout.gd) it writes, in the same folder:
#   terrain_cells.bin    one category byte per cell, row by row. The only file gameplay reads.
#   terrain_data.png     the same categories in the red channel, for the ground shader. Lossless.
#   terrain_surface.png  soft ground colours: the shader tints its tiles with them and draws ore from them.
# The same layout always gives the same three files. Afterwards rebuild the art that follows the cells: the
# ground blend map, the mountain mesh and the terrain scenery (see the doc).
const MapLayout := preload("res://scripts/tools/map_layout.gd")
const ToolArgs := preload("res://scripts/tools/tool_args.gd")
const SIZE := 500
## Mean ground colours the shader expects (its *_surface_mean settings, as sRGB), then ore and coal as drawn.
const SURFACE: Array[Color] = [
	Color8(88, 112, 57), Color8(28, 91, 110), Color8(200, 168, 103), Color8(60, 93, 45), Color8(84, 86, 77),
	Color8(150, 74, 48), Color8(26, 26, 30),
]
## How far the soft variation moves a colour from its mean. The shader ignores differences over a quarter.
const VARIATION := 0.12
const SURFACE_PIXELS := 1024

func _initialize() -> void:
	var folder := ToolArgs.value("map", "")
	if folder.is_empty():
		push_error("Name the map folder: -- --map=res://assets/maps/balanced"); quit(1); return
	var layout: Dictionary = MapLayout.read(folder+"/layout.png")
	if not layout.errors.is_empty():
		for line in layout.errors: push_error(line)
		quit(1); return
	var cells: PackedByteArray = layout.cells
	var file := FileAccess.open(folder+"/terrain_cells.bin", FileAccess.WRITE)
	if file == null:
		push_error("Could not write terrain_cells.bin"); quit(1); return
	file.store_buffer(cells)
	file.close()
	var data := PackedByteArray()
	data.resize(SIZE*SIZE*3)
	for i in range(SIZE*SIZE): data[i*3] = cells[i]
	if Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGB8, data).save_png(ProjectSettings.globalize_path(folder+"/terrain_data.png")) != OK:
		push_error("Could not write terrain_data.png"); quit(1); return
	if _surface(cells).save_png(ProjectSettings.globalize_path(folder+"/terrain_surface.png")) != OK:
		push_error("Could not write terrain_surface.png"); quit(1); return
	var counts := MapLayout.counts(cells)
	var report := PackedStringArray()
	for kind in range(counts.size()): report.append("%s %d (%.1f%%)" % [MapLayout.NAMES[kind], counts[kind], counts[kind]*100.0/(SIZE*SIZE)])
	print("MAP_DATA_BUILT ", folder, ": ", ", ".join(report))
	quit()

# Each cell's mean colour, drifting a little across the map so large areas are not one flat tint.
func _surface(cells: PackedByteArray) -> Image:
	var drift := FastNoiseLite.new()
	drift.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	drift.fractal_type = FastNoiseLite.FRACTAL_FBM
	drift.fractal_octaves = 3
	drift.frequency = 0.018
	drift.seed = 6431
	var pixels := PackedByteArray()
	pixels.resize(SIZE*SIZE*3)
	for z in range(SIZE):
		for x in range(SIZE):
			var i := z*SIZE+x
			var kind := int(cells[i])
			# Ore and coal keep their colour exactly; the ground kinds drift.
			var shade := 1.0+drift.get_noise_2d(x, z)*VARIATION*2.0 if kind < 5 else 1.0
			var colour: Color = SURFACE[kind]
			pixels[i*3] = clampi(roundi(colour.r8*shade), 0, 255)
			pixels[i*3+1] = clampi(roundi(colour.g8*shade), 0, 255)
			pixels[i*3+2] = clampi(roundi(colour.b8*shade), 0, 255)
	var image := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGB8, pixels)
	# Enlarged smoothly, so borders between kinds of ground are soft rather than stepped.
	image.resize(SURFACE_PIXELS, SURFACE_PIXELS, Image.INTERPOLATE_CUBIC)
	return image
