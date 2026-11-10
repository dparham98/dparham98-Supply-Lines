extends SceneTree
# Writes assets/textures/terrain/ground_blend.png from the map's cells: how far each cell is from the border
# between desert and grass ground (forest floor counts as grass). The terrain shader reads it to draw that border
# as a soft, irregular line instead of 1 m steps. It is art only; gameplay keeps reading terrain_cells.bin.
# Run after the map cells change: godot --headless --path . --script res://scripts/tools/build_ground_blend_map.gd
const CELLS := "res://assets/maps/terrain_cells.bin"
const OUTPUT := "res://assets/textures/terrain/ground_blend.png"
const SIZE := 500
const GRASS := 0
const DESERT := 2
const FOREST := 3
# Stored range in metres: 0.5 in the image is the border, 1.0 is this far into desert, 0.0 this far into grass.
const RANGE := 8.0
const DIAGONAL := 1.41421356
const SMOOTHING_PASSES := 3
const FAR := 100000.0

func _initialize() -> void:
	var cells := FileAccess.get_file_as_bytes(CELLS)
	if cells.size() != SIZE*SIZE:
		push_error("Unexpected size for "+CELLS); quit(1); return
	var to_desert := distance_to(cells,[DESERT])
	var to_grass := distance_to(cells,[GRASS,FOREST])
	var signed := PackedFloat32Array()
	signed.resize(SIZE*SIZE)
	for i in range(SIZE*SIZE):
		signed[i] = clampf(to_grass[i]-to_desert[i],-RANGE,RANGE)
	# The raw field still holds the staircase; a small blur rounds it off without moving the border far.
	for pass_index in range(SMOOTHING_PASSES): signed = smoothed(signed)
	var bytes := PackedByteArray()
	bytes.resize(SIZE*SIZE)
	for i in range(SIZE*SIZE):
		bytes[i] = int(round((signed[i]/RANGE*0.5+0.5)*255.0))
	Image.create_from_data(SIZE,SIZE,false,Image.FORMAT_L8,bytes).save_png(ProjectSettings.globalize_path(OUTPUT))
	print("GROUND_BLEND_MAP_BUILT"); quit()

# Two-pass chamfer distance to the nearest cell of the given kinds.
func distance_to(cells: PackedByteArray, kinds: Array) -> PackedFloat32Array:
	var d := PackedFloat32Array()
	d.resize(SIZE*SIZE)
	for i in range(SIZE*SIZE): d[i] = 0.0 if int(cells[i]) in kinds else FAR
	for z in range(SIZE):
		for x in range(SIZE):
			var i := z*SIZE+x
			if x > 0: d[i] = minf(d[i],d[i-1]+1.0)
			if z > 0:
				d[i] = minf(d[i],d[i-SIZE]+1.0)
				if x > 0: d[i] = minf(d[i],d[i-SIZE-1]+DIAGONAL)
				if x < SIZE-1: d[i] = minf(d[i],d[i-SIZE+1]+DIAGONAL)
	for z in range(SIZE-1,-1,-1):
		for x in range(SIZE-1,-1,-1):
			var i := z*SIZE+x
			if x < SIZE-1: d[i] = minf(d[i],d[i+1]+1.0)
			if z < SIZE-1:
				d[i] = minf(d[i],d[i+SIZE]+1.0)
				if x < SIZE-1: d[i] = minf(d[i],d[i+SIZE+1]+DIAGONAL)
				if x > 0: d[i] = minf(d[i],d[i+SIZE-1]+DIAGONAL)
	return d

func smoothed(field: PackedFloat32Array) -> PackedFloat32Array:
	var out := field.duplicate()
	for z in range(1,SIZE-1):
		for x in range(1,SIZE-1):
			var i := z*SIZE+x
			out[i] = (field[i]*4.0+(field[i-1]+field[i+1]+field[i-SIZE]+field[i+SIZE])*2.0+field[i-SIZE-1]+field[i-SIZE+1]+field[i+SIZE-1]+field[i+SIZE+1])/16.0
	return out
