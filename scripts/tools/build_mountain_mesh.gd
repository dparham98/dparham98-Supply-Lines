extends SceneTree
# Sculpts the mountains from the Mountain cells of terrain_cells.bin (docs/MOUNTAINS.md) and saves the mesh and its
# rock textures. Run after changing the map or the shape settings, then press Rebuild terrain scenery on terrain.tscn:
#   godot --headless --path . --script res://scripts/tools/build_mountain_mesh.gd
# Another map passes its own files after "--": --cells=<cells .bin> --mesh=<mesh .res> --material=<massif .tres>.
# The shared rock textures are only rewritten for the original map.
const ToolArgs := preload("res://scripts/tools/tool_args.gd")
const WIDTH := 500
const MOUNTAIN := 4
const MESH_PATH := "res://assets/models/terrain/mountains.res"
const MATERIAL_PATH := "res://assets/materials/terrain/mountain_massif.tres"
const DETAIL_PATH := "res://assets/textures/terrain/mountain_rock_detail.png"
const NORMAL_PATH := "res://assets/textures/terrain/mountain_rock_normal.png"
## Vertices per metre.
const DENSITY := 2
## Highest point. Drones fly at 12 m, over the top of every peak.
const PEAK := 11.0
## Metres from the foot at which the slope has risen most of the way.
const RISE := 3.6
## How far the outline wanders from the blocky map cells, in metres.
const WARP := 1.8

var cells: PackedByteArray
var distance: PackedFloat32Array
var ridges := FastNoiseLite.new()
var relief := FastNoiseLite.new()
var spurs := FastNoiseLite.new()
var warp_x := FastNoiseLite.new()
var warp_z := FastNoiseLite.new()

func _initialize() -> void:
	cells = FileAccess.get_file_as_bytes(ToolArgs.value("cells",ToolArgs.DEFAULT_CELLS))
	if cells.size() != WIDTH*WIDTH:
		push_error("Unexpected terrain_cells.bin size"); quit(1); return
	_setup_noise()
	_measure_distance()
	if not ToolArgs.given("mesh"): _save_textures()
	var mesh := _build_mesh()
	mesh.surface_set_material(0,load(ToolArgs.value("material",MATERIAL_PATH)))
	if ResourceSaver.save(mesh,ToolArgs.value("mesh",MESH_PATH),ResourceSaver.FLAG_COMPRESS if ToolArgs.given("mesh") else ResourceSaver.FLAG_NONE) != OK:
		push_error("Could not save the mountain mesh"); quit(1); return
	print("MOUNTAIN_MESH_BUILT ",mesh.get_faces().size()/3," triangles")
	quit()

func _setup_noise() -> void:
	ridges.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridges.fractal_octaves = 5
	ridges.fractal_lacunarity = 2.1
	ridges.fractal_gain = 0.5
	ridges.frequency = 0.03
	ridges.seed = 4127
	relief.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	relief.fractal_type = FastNoiseLite.FRACTAL_FBM
	relief.fractal_octaves = 5
	relief.frequency = 0.2
	relief.seed = 911
	spurs.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	spurs.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	spurs.fractal_octaves = 4
	spurs.frequency = 0.085
	spurs.seed = 3301
	for noise in [warp_x,warp_z]:
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		noise.fractal_octaves = 3
		noise.frequency = 0.09
	warp_x.seed = 21
	warp_z.seed = 87

func is_mountain(x: int, z: int) -> bool:
	return x >= 0 and z >= 0 and x < WIDTH and z < WIDTH and cells[z*WIDTH+x] == MOUNTAIN

# Two-pass chamfer distance from each Mountain cell to the nearest other ground, in metres.
func _measure_distance() -> void:
	distance.resize(WIDTH*WIDTH)
	const DIAGONAL := 1.4142
	for z in range(WIDTH):
		for x in range(WIDTH):
			if not is_mountain(x,z):
				distance[z*WIDTH+x] = 0.0
				continue
			var best := 1.0
			if x > 0 and z > 0 and x < WIDTH-1:
				best = minf(distance[z*WIDTH+x-1]+1.0,minf(distance[(z-1)*WIDTH+x]+1.0,minf(distance[(z-1)*WIDTH+x-1]+DIAGONAL,distance[(z-1)*WIDTH+x+1]+DIAGONAL)))
			distance[z*WIDTH+x] = best
	for z in range(WIDTH-1,-1,-1):
		for x in range(WIDTH-1,-1,-1):
			if not is_mountain(x,z): continue
			var best: float = distance[z*WIDTH+x]
			if x < WIDTH-1 and z < WIDTH-1 and x > 0:
				best = minf(best,minf(distance[z*WIDTH+x+1]+1.0,minf(distance[(z+1)*WIDTH+x]+1.0,minf(distance[(z+1)*WIDTH+x+1]+DIAGONAL,distance[(z+1)*WIDTH+x-1]+DIAGONAL))))
			else:
				best = 1.0
			distance[z*WIDTH+x] = best

# Distance at a point in cell coordinates, smoothly interpolated between cell centres.
func distance_at(x: float, z: float) -> float:
	var fx := x-0.5
	var fz := z-0.5
	var ix := clampi(floori(fx),0,WIDTH-2)
	var iz := clampi(floori(fz),0,WIDTH-2)
	var tx := clampf(fx-ix,0.0,1.0)
	var tz := clampf(fz-iz,0.0,1.0)
	return lerpf(lerpf(distance[iz*WIDTH+ix],distance[iz*WIDTH+ix+1],tx),lerpf(distance[(iz+1)*WIDTH+ix],distance[(iz+1)*WIDTH+ix+1],tx),tz)

func height_at(x: float, z: float) -> float:
	var d := distance_at(x,z)
	if d <= 0.0: return -0.4
	var envelope := 1.0-exp(-d/RISE)
	# Ridged noise is high along crests and low in the valleys between them.
	var crest := clampf(ridges.get_noise_2d(x,z)*0.5+0.5,0.0,1.0)
	var height := PEAK*envelope*lerpf(0.3,1.32,pow(crest,1.7))
	# Smaller ridges run down the flanks; fine relief breaks up the surface.
	var flank := clampf(d/2.5,0.0,1.0)
	height += (spurs.get_noise_2d(x,z)*0.5+0.5)*2.6*flank*envelope-1.0*flank*envelope
	height += relief.get_noise_2d(x,z)*1.5*flank
	# Peaks flatten softly at the ceiling rather than being cut off.
	height = PEAK*tanh(height/PEAK*1.15)
	return lerpf(-0.4,height,smoothstep(0.0,1.2,d))

func _build_mesh() -> ArrayMesh:
	# Vertex grid over every Mountain cell, shared between neighbours.
	var index_of := {}
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var size := WIDTH*DENSITY+1
	var step := 1.0/DENSITY
	for z in range(WIDTH):
		for x in range(WIDTH):
			if not is_mountain(x,z): continue
			for sub_z in range(DENSITY):
				for sub_x in range(DENSITY):
					var gx := x*DENSITY+sub_x
					var gz := z*DENSITY+sub_z
					var a := _vertex(gx,gz,size,step,index_of,vertices,normals,colors)
					var b := _vertex(gx+1,gz,size,step,index_of,vertices,normals,colors)
					var c := _vertex(gx,gz+1,size,step,index_of,vertices,normals,colors)
					var d := _vertex(gx+1,gz+1,size,step,index_of,vertices,normals,colors)
					# Godot front faces wind clockwise seen from outside.
					indices.append_array([a,b,c,b,d,c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

func _vertex(gx: int, gz: int, size: int, step: float, index_of: Dictionary, vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray) -> int:
	var key := gz*size+gx
	if index_of.has(key): return index_of[key]
	var x := gx*step
	var z := gz*step
	var height := height_at(x,z)
	const E := 0.35
	var normal := Vector3(height_at(x-E,z)-height_at(x+E,z),2.0*E,height_at(x,z-E)-height_at(x,z+E)).normalized()
	# Crevices sit below the average of the ground around them.
	var around := 0.0
	for offset in [Vector2(1.5,0),Vector2(-1.5,0),Vector2(0,1.5),Vector2(0,-1.5)]: around += height_at(x+offset.x,z+offset.y)
	var hollow := clampf(0.5+(height-around/4.0)*0.9,0.0,1.0)
	var wander := Vector2(warp_x.get_noise_2d(x,z),warp_z.get_noise_2d(x,z))*WARP*1.6
	var world := Vector3(x-WIDTH*0.5+wander.x,height,z-WIDTH*0.5+wander.y)
	index_of[key] = vertices.size()
	vertices.append(world)
	normals.append(normal)
	colors.append(Color(hollow,clampf(height/PEAK,0.0,1.0),0.0,1.0))
	return vertices.size()-1

# Seamless rock detail: broad fractures with fine grain, and the normal map made from them.
func _save_textures() -> void:
	var broad := FastNoiseLite.new()
	broad.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	broad.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	broad.fractal_octaves = 6
	broad.fractal_gain = 0.55
	broad.frequency = 0.009
	broad.seed = 73
	var grain := FastNoiseLite.new()
	grain.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	grain.fractal_type = FastNoiseLite.FRACTAL_FBM
	grain.fractal_octaves = 6
	grain.frequency = 0.03
	grain.seed = 12
	var broad_image := broad.get_seamless_image(1024,1024)
	var grain_image := grain.get_seamless_image(1024,1024)
	var detail := Image.create(1024,1024,false,Image.FORMAT_RGB8)
	for y in range(1024):
		for x in range(1024):
			var value := clampf(broad_image.get_pixel(x,y).r*0.7+grain_image.get_pixel(x,y).r*0.3,0.0,1.0)
			detail.set_pixel(x,y,Color(value,value,value))
	detail.save_png(ProjectSettings.globalize_path(DETAIL_PATH))
	var normal: Image = detail.duplicate()
	normal.convert(Image.FORMAT_RGBA8)
	normal.bump_map_to_normal_map(7.0)
	normal.convert(Image.FORMAT_RGB8)
	normal.save_png(ProjectSettings.globalize_path(NORMAL_PATH))
