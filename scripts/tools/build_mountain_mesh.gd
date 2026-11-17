extends SceneTree
# Sculpts the mountains from the Mountain cells of terrain_cells.bin (docs/MOUNTAINS.md) and saves the mesh and its
# rock textures. Run after changing the map or the shape settings, then press Rebuild terrain scenery on terrain.tscn:
#   godot --headless --path . --script res://scripts/tools/build_mountain_mesh.gd
# Another map passes its own files after "--": --cells=<cells .bin> --mesh=<mesh .res> --material=<massif .tres>.
# The shared rock textures are only rewritten for the original map.
const ToolArgs := preload("res://scripts/tools/tool_args.gd")
const WIDTH := 500
const MOUNTAIN := 4
## A mine site (docs/MINE_SITES.md) is a recess cut into the rock: the mountain keeps its height around it, the
## mesh is left open over it, and sheer walls close the cut.
const MINE_SITE := 7
const MESH_PATH := "res://assets/models/terrain/mountains.res"
const MATERIAL_PATH := "res://assets/materials/terrain/mountain_massif.tres"
const DETAIL_PATH := "res://assets/textures/terrain/mountain_rock_detail.png"
const NORMAL_PATH := "res://assets/textures/terrain/mountain_rock_normal.png"
## Vertices per metre.
const DENSITY := 2
## Highest point. Drones fly at 12 m, over the top of every peak.
const PEAK := 11.0
## Metres from the foot at which the slope has risen most of the way.
const RISE := 2.9
## Height of one ledge. The slope is broken into ledges with steep faces between, so the rock reads as blocks
## and shelves, not as one smooth swell.
const LEDGE := 2.2
const LEDGE_STRENGTH := 0.8
## Round a mine site the rock comes down to meet the mine that stands in the cut: this high at the cut's back and
## at its mouth, rising by SITE_SLOPE for each metre away from the cut.
const SITE_BACK := 4.7
const SITE_MOUTH := 1.7
const SITE_SLOPE := 1.15
## How far the outline wanders from the blocky map cells, in metres.
const WARP := 1.8

var cells: PackedByteArray
var distance: PackedFloat32Array
var sites: Array[Vector2] = []
## Each whole mine site: {rect: Rect2, out: Vector2}, `out` pointing from its back to its mouth.
var cuts: Array[Dictionary] = []
var ridges := FastNoiseLite.new()
var relief := FastNoiseLite.new()
var spurs := FastNoiseLite.new()
var warp_x := FastNoiseLite.new()
var warp_z := FastNoiseLite.new()

func _initialize() -> void:
	cells = FileAccess.get_file_as_bytes(ToolArgs.value("cells",ToolArgs.DEFAULT_CELLS))
	if cells.size() != WIDTH*WIDTH:
		push_error("Unexpected terrain_cells.bin size"); quit(1); return
	for i in range(WIDTH*WIDTH):
		if cells[i] == MINE_SITE: sites.append(Vector2(i%WIDTH,i/WIDTH))
	_find_cuts()
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

func is_site(x: int, z: int) -> bool:
	return x >= 0 and z >= 0 and x < WIDTH and z < WIDTH and cells[z*WIDTH+x] == MINE_SITE

# Groups the site cells into whole sites and finds which way each opens: the side with no rock along it.
func _find_cuts() -> void:
	var seen := {}
	for cell in sites:
		if seen.has(cell): continue
		var low := cell
		var high := cell
		var open: Array[Vector2] = [cell]
		seen[cell] = true
		while not open.is_empty():
			var at: Vector2 = open.pop_back()
			low = Vector2(minf(low.x,at.x),minf(low.y,at.y))
			high = Vector2(maxf(high.x,at.x),maxf(high.y,at.y))
			for step in [Vector2(1,0),Vector2(-1,0),Vector2(0,1),Vector2(0,-1)]:
				var next: Vector2 = at+step
				if is_site(int(next.x),int(next.y)) and not seen.has(next):
					seen[next] = true
					open.append(next)
		var rect := Rect2(low,high-low+Vector2.ONE)
		var out := Vector2.ZERO
		for way in [Vector2(0,1),Vector2(0,-1),Vector2(1,0),Vector2(-1,0)]:
			var beyond: Vector2 = rect.get_center()+way*((rect.size.y if way.x == 0.0 else rect.size.x)*0.5+0.5)
			if not is_rock(floori(beyond.x),floori(beyond.y)): out = way
		cuts.append({"rect": rect, "out": out})

# The most the rock may stand at a point because of the mine sites near it.
func site_ceiling(x: float, z: float) -> float:
	var ceiling := INF
	for cut in cuts:
		var rect: Rect2 = cut.rect
		var away := Vector2(maxf(maxf(rect.position.x-x,x-rect.end.x),0.0),maxf(maxf(rect.position.y-z,z-rect.end.y),0.0)).length()
		if away > 14.0: continue
		var out: Vector2 = cut.out
		var depth: float = rect.size.y if out.x == 0.0 else rect.size.x
		# 0 at the cut's back, 1 at its mouth.
		var along := clampf(((Vector2(x,z)-rect.get_center()).dot(out)+depth*0.5)/depth,0.0,1.0)
		ceiling = minf(ceiling,lerpf(SITE_BACK,SITE_MOUTH,along)+away*SITE_SLOPE)
	return ceiling

# Rock for the purpose of the mountain's shape: a site is cut out of it afterwards.
func is_rock(x: int, z: int) -> bool:
	return is_mountain(x,z) or is_site(x,z)

# Metres from a point to the nearest mine site cell, or a large number when none is near.
func site_distance(x: float, z: float) -> float:
	var best := 1000.0
	for site in sites:
		var dx := maxf(maxf(site.x-x,x-site.x-1.0),0.0)
		var dz := maxf(maxf(site.y-z,z-site.y-1.0),0.0)
		best = minf(best,sqrt(dx*dx+dz*dz))
	return best

# Two-pass chamfer distance from each Mountain cell to the nearest other ground, in metres.
func _measure_distance() -> void:
	distance.resize(WIDTH*WIDTH)
	const DIAGONAL := 1.4142
	for z in range(WIDTH):
		for x in range(WIDTH):
			if not is_rock(x,z):
				distance[z*WIDTH+x] = 0.0
				continue
			var best := 1.0
			if x > 0 and z > 0 and x < WIDTH-1:
				best = minf(distance[z*WIDTH+x-1]+1.0,minf(distance[(z-1)*WIDTH+x]+1.0,minf(distance[(z-1)*WIDTH+x-1]+DIAGONAL,distance[(z-1)*WIDTH+x+1]+DIAGONAL)))
			distance[z*WIDTH+x] = best
	for z in range(WIDTH-1,-1,-1):
		for x in range(WIDTH-1,-1,-1):
			if not is_rock(x,z): continue
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
	# Ledges: the slope climbs in steps whose level wanders, so shelves run round the rock without lining up.
	var level := height/LEDGE+spurs.get_noise_2d(x*0.45+31.0,z*0.45-17.0)*0.55
	var shelf := (floorf(level)+smoothstep(0.42,0.96,level-floorf(level)))*LEDGE
	height = lerpf(height,shelf,LEDGE_STRENGTH*flank)
	# Peaks flatten softly at the ceiling rather than being cut off.
	height = PEAK*tanh(height/PEAK*1.15)
	if not cuts.is_empty(): height = minf(height,site_ceiling(x,z))
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
	_cut_walls(size,step,index_of,vertices,normals,colors,indices)
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
	# The outline stays on the cells around a mine site, so the cut lines up with the mine that stands in it.
	if not sites.is_empty(): wander *= smoothstep(1.0,6.0,site_distance(x,z))
	var world := Vector3(x-WIDTH*0.5+wander.x,height,z-WIDTH*0.5+wander.y)
	index_of[key] = vertices.size()
	vertices.append(world)
	normals.append(normal)
	colors.append(Color(hollow,clampf(height/PEAK,0.0,1.0),0.0,1.0))
	return vertices.size()-1

# Sheer walls down to the ground along every edge between a mine site cell and a Mountain cell.
func _cut_walls(size: int, step: float, index_of: Dictionary, vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array) -> void:
	for site in sites:
		var x := int(site.x)
		var z := int(site.y)
		for side in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)]:
			if not is_mountain(x+side.x,z+side.y): continue
			# The edge shared with that Mountain cell, as grid points along it.
			var inward := Vector3(-side.x,0.0,-side.y)
			for sub in range(DENSITY):
				var tops: Array[int] = []
				for end in [sub,sub+1]:
					var gx: int = (x+(1 if side.x > 0 else 0))*DENSITY+(end if side.x == 0 else 0)
					var gz: int = (z+(1 if side.y > 0 else 0))*DENSITY+(end if side.y == 0 else 0)
					tops.append(_vertex(gx,gz,size,step,index_of,vertices,normals,colors))
				var corners: Array[int] = []
				for top in tops:
					for foot in [false,true]:
						var point: Vector3 = vertices[top]
						if foot: point.y = -0.3
						corners.append(vertices.size())
						vertices.append(point)
						normals.append(inward)
						colors.append(Color(0.32 if foot else 0.45,clampf(point.y/PEAK,0.0,1.0),0.0,1.0))
				# corners: top a, foot a, top b, foot b. Front faces wind clockwise seen from inside the cut.
				var across: Vector3 = (vertices[corners[2]]-vertices[corners[0]]).cross(vertices[corners[1]]-vertices[corners[0]])
				if across.dot(inward) < 0.0: indices.append_array([corners[0],corners[2],corners[1],corners[2],corners[3],corners[1]])
				else: indices.append_array([corners[0],corners[1],corners[2],corners[2],corners[1],corners[3]])

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
