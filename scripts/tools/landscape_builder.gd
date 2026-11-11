extends RefCounted
# Shapes the landscape of LandscapeSettings.region from terrain_cells.bin (docs/LANDSCAPE_LOOKDEV.md): smooth
# distance fields for the shore, the mountain edge, forest and ore, a height for every point, and the ground and
# water meshes. Used by scripts/tools/build_landscape.gd, which saves the meshes, and by terrain_baker.gd, which
# stands the scenery on them. Nothing here runs in a match.
const MAP := 500
## Field pixels per metre.
const DENSITY := 4
## Cells of field kept around the region so its edge has real neighbours.
const MARGIN := 8
## Metres stored either side of a border in the field texture.
const RANGE := 8.0
## Ground vertices per metre.
const MESH_DENSITY := 2
## Metres over which heights return to the flat map at the region edge.
const EDGE_FADE := 4.0
## Thickness of one bed of rock, in metres.
const BED_HEIGHT := 0.85
const WATER := 1
const DESERT := 2
const FOREST := 3
const MOUNTAIN := 4
const ORE := 5

var settings: LandscapeSettings
var cells: PackedByteArray
var origin := Vector2i.ZERO
var cells_size := Vector2i.ZERO
var width := 0
var height := 0
## Metres inside the water (positive) or from it (negative), measured from the drawn shoreline.
var shore: PackedFloat32Array
## Metres inside the rock (positive) or from it (negative).
var mount: PackedFloat32Array
## 0 to 1: how much forest stands around a point.
var forest: PackedFloat32Array
var ore: PackedFloat32Array
var wander := FastNoiseLite.new()
var relief := FastNoiseLite.new()
var crags := FastNoiseLite.new()
var ridges := FastNoiseLite.new()
var tiers := FastNoiseLite.new()
var blocks := FastNoiseLite.new()

func setup(map_cells: PackedByteArray, landscape: LandscapeSettings) -> void:
	cells = map_cells
	settings = landscape
	var grown := settings.region.grow(MARGIN).intersection(Rect2i(0,0,MAP,MAP))
	origin = grown.position
	cells_size = grown.size
	width = cells_size.x*DENSITY
	height = cells_size.y*DENSITY
	_noise(wander,FastNoiseLite.FRACTAL_FBM,3,0.11,311)
	_noise(relief,FastNoiseLite.FRACTAL_FBM,3,0.09,77)
	_noise(crags,FastNoiseLite.FRACTAL_FBM,4,0.33,1907)
	_noise(ridges,FastNoiseLite.FRACTAL_RIDGED,4,0.09,4127)
	_noise(tiers,FastNoiseLite.FRACTAL_FBM,2,0.045,650)
	# One value per irregular patch a few metres across: rock that breaks into blocks instead of flowing.
	blocks.noise_type = FastNoiseLite.TYPE_CELLULAR
	blocks.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	blocks.cellular_jitter = 1.0
	blocks.frequency = 0.24
	blocks.seed = 8141
	shore = _signed_distance(_rounded([WATER]))
	mount = _signed_distance(_rounded([MOUNTAIN]))
	for y in range(height):
		for x in range(width):
			var cx := origin.x+(x+0.5)/DENSITY
			var cz := origin.y+(y+0.5)/DENSITY
			var i := y*width+x
			shore[i] += -settings.shore_inset+wander.get_noise_2d(cx,cz)*0.9
			mount[i] += -0.55+wander.get_noise_2d(cx+91.0,cz-37.0)*0.9
	shore = _box(shore,1)
	mount = _box(mount,1)
	forest = _box(_box(_mask([FOREST]),4),4)
	ore = _box(_box(_mask([ORE]),3),3)

func _noise(noise: FastNoiseLite, fractal: int, octaves: int, frequency: float, seed_: int) -> void:
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = fractal
	noise.fractal_octaves = octaves
	noise.frequency = frequency
	noise.seed = seed_

func _mask(kinds: Array) -> PackedFloat32Array:
	var mask := PackedFloat32Array()
	mask.resize(width*height)
	for y in range(height):
		var cz := origin.y+y/DENSITY
		for x in range(width):
			mask[y*width+x] = 1.0 if kinds.has(int(cells[cz*MAP+origin.x+x/DENSITY])) else 0.0
	return mask

# The blocky cell outline with its corners rounded off: blurred, then cut at half.
func _rounded(kinds: Array) -> PackedFloat32Array:
	return _box(_box(_box(_mask(kinds),3),3),3)

func _box(source: PackedFloat32Array, radius: int) -> PackedFloat32Array:
	var across := PackedFloat32Array()
	across.resize(width*height)
	var share := 1.0/(2*radius+1)
	for y in range(height):
		var row := y*width
		var total := 0.0
		for x in range(-radius,radius+1): total += source[row+clampi(x,0,width-1)]
		for x in range(width):
			across[row+x] = total*share
			total += source[row+mini(x+radius+1,width-1)]-source[row+maxi(x-radius,0)]
	var result := PackedFloat32Array()
	result.resize(width*height)
	for x in range(width):
		var total := 0.0
		for y in range(-radius,radius+1): total += across[clampi(y,0,height-1)*width+x]
		for y in range(height):
			result[y*width+x] = total*share
			total += across[mini(y+radius+1,height-1)*width+x]-across[maxi(y-radius,0)*width+x]
	return result

# Metres from the half-way line of a blurred mask: positive inside, negative outside.
func _signed_distance(blurred: PackedFloat32Array) -> PackedFloat32Array:
	var inside := _chamfer(blurred,true)
	var outside := _chamfer(blurred,false)
	var result := PackedFloat32Array()
	result.resize(width*height)
	for i in range(width*height):
		result[i] = (outside[i]-inside[i])/DENSITY
	return result

# Two-pass chamfer distance, in pixels, to the nearest pixel that is (or is not) inside.
func _chamfer(blurred: PackedFloat32Array, to_inside: bool) -> PackedFloat32Array:
	const FAR := 1.0e6
	const DIAGONAL := 1.41421356
	var d := PackedFloat32Array()
	d.resize(width*height)
	for i in range(width*height):
		d[i] = 0.0 if (blurred[i] >= 0.5) == to_inside else FAR
	for y in range(height):
		for x in range(width):
			var i := y*width+x
			var best: float = d[i]
			if best == 0.0: continue
			if x > 0: best = minf(best,d[i-1]+1.0)
			if y > 0:
				best = minf(best,d[i-width]+1.0)
				if x > 0: best = minf(best,d[i-width-1]+DIAGONAL)
				if x < width-1: best = minf(best,d[i-width+1]+DIAGONAL)
			d[i] = best
	for y in range(height-1,-1,-1):
		for x in range(width-1,-1,-1):
			var i := y*width+x
			var best: float = d[i]
			if best == 0.0: continue
			if x < width-1: best = minf(best,d[i+1]+1.0)
			if y < height-1:
				best = minf(best,d[i+width]+1.0)
				if x < width-1: best = minf(best,d[i+width+1]+DIAGONAL)
				if x > 0: best = minf(best,d[i+width-1]+DIAGONAL)
			d[i] = best
	# Half a pixel, so the two distances meet at the line between pixels.
	for i in range(width*height):
		if d[i] > 0.0: d[i] -= 0.5
	return d

## A field at a point in cell coordinates (map metres from the north-west corner).
func sample(field: PackedFloat32Array, cx: float, cz: float) -> float:
	var fx := clampf((cx-origin.x)*DENSITY-0.5,0.0,width-1.001)
	var fz := clampf((cz-origin.y)*DENSITY-0.5,0.0,height-1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx-ix
	var tz := fz-iz
	var i := iz*width+ix
	return lerpf(lerpf(field[i],field[i+1],tx),lerpf(field[i+width],field[i+width+1],tx),tz)

func cell_kind(cx: float, cz: float) -> int:
	var x := clampi(floori(cx),0,MAP-1)
	var z := clampi(floori(cz),0,MAP-1)
	return int(cells[z*MAP+x])

## 0 at the edge of the region, 1 a few metres inside it.
func edge_fade(cx: float, cz: float) -> float:
	var region := settings.region
	var inside := minf(minf(cx-region.position.x,region.end.x-cx),minf(cz-region.position.y,region.end.y-cz))
	return smoothstep(0.0,EDGE_FADE,inside)

func water_height(cx: float, cz: float) -> float:
	return settings.water_level*edge_fade(cx,cz)

## Outward direction from the rock at a point, on the map plane.
func mountain_outward(cx: float, cz: float) -> Vector2:
	const E := 0.75
	var slope := Vector2(sample(mount,cx+E,cz)-sample(mount,cx-E,cz),sample(mount,cx,cz+E)-sample(mount,cx,cz-E))
	return -slope.normalized() if slope.length() > 0.0001 else Vector2.RIGHT

## Height of the ground at a point in cell coordinates.
func height_at(cx: float, cz: float) -> float:
	var s := sample(shore,cx,cz)
	var m := sample(mount,cx,cz)
	# Walkable ground only dips, so nothing drawn at height 0 ends up under it.
	var h := -settings.walkable_relief*(relief.get_noise_2d(cx,cz)*0.5+0.5)
	if s > 0.0:
		var bed := 1.0-exp(-s/2.4)
		bed += 0.12*crags.get_noise_2d(cx*0.5,cz*0.5)*smoothstep(0.5,3.0,s)
		h = settings.water_level-0.03-settings.bank_depth*bed
	elif s > -0.8:
		h = lerpf(h,settings.water_level-0.03,smoothstep(-0.8,0.0,s))
	if m > 0.0:
		h = maxf(h,0.0)+_rock_height(m,cx,cz)
	elif m > -1.6 and s < -0.8:
		h += 0.05*smoothstep(-1.6,0.0,m)
	return h*edge_fade(cx,cz)

# A first wall, a ledge, a second wall where the rock is wide enough, then a broken top.
func _rock_height(m: float, cx: float, cz: float) -> float:
	var total := rock_first_height(cx,cz)*smoothstep(0.0,0.9,_rock_face(m,cx,cz))
	total += rock_second_height(cx,cz)*smoothstep(0.0,1.0,rock_second_edge(m,cx,cz))
	var crest := clampf(ridges.get_noise_2d(cx,cz)*0.5+0.5,0.0,1.0)
	# Crests: where the rock is wide, ridges stand up out of the top as peaks.
	total += 3.4*pow(crest,2.4)*smoothstep(2.0,6.0,m)
	# Slabs on the top, each a little higher or lower than the next.
	total += 0.7*blocks.get_noise_2d(cx*1.7+300.0,cz*1.7)*smoothstep(0.9,1.8,m)
	# Beds: the rock rises in level steps with short steep risers between them.
	var bed := BED_HEIGHT*(1.0+0.25*tiers.get_noise_2d(cx*3.0,cz*3.0))
	var stepped := (floorf(total/bed)+smoothstep(0.5,0.95,fposmod(total/bed,1.0)))*bed
	total = lerpf(total,stepped,0.75)
	return settings.peak*tanh(total/settings.peak*1.08)

# Metres inside the first wall, which steps in and out block by block.
func _rock_face(m: float, cx: float, cz: float) -> float:
	return m+crags.get_noise_2d(cx,cz)*0.3+blocks.get_noise_2d(cx,cz)*0.4

## Height of the first wall above the ground at a point.
func rock_first_height(cx: float, cz: float) -> float:
	return 3.0+2.0*(tiers.get_noise_2d(cx,cz)*0.5+0.5)+0.5*blocks.get_noise_2d(cx,cz)

## Height of the second wall above the ledge.
func rock_second_height(cx: float, cz: float) -> float:
	return 2.6+2.4*(tiers.get_noise_2d(cx,cz)*0.5+0.5)+0.5*blocks.get_noise_2d(cx+70.0,cz)

## Metres inside the second wall: negative on the ledge in front of it.
func rock_second_edge(m: float, cx: float, cz: float) -> float:
	var ledge := 3.0+1.2*tiers.get_noise_2d(cx+40.0,cz+11.0)
	return _rock_face(m,cx,cz)+0.4*blocks.get_noise_2d(cx*1.3-90.0,cz*1.3)-ledge

func field_uv(cx: float, cz: float) -> Vector2:
	return Vector2((cx-origin.x)/cells_size.x,(cz-origin.y)/cells_size.y)

## Shore, rock, forest and ore in one texture for the ground and water shaders.
func build_fields_image() -> Image:
	var bytes := PackedByteArray()
	bytes.resize(width*height*4)
	for i in range(width*height):
		bytes[i*4] = int(round(clampf(shore[i]/RANGE*0.5+0.5,0.0,1.0)*255.0))
		bytes[i*4+1] = int(round(clampf(mount[i]/RANGE*0.5+0.5,0.0,1.0)*255.0))
		bytes[i*4+2] = int(round(clampf(forest[i],0.0,1.0)*255.0))
		bytes[i*4+3] = int(round(clampf(ore[i],0.0,1.0)*255.0))
	return Image.create_from_data(width,height,false,Image.FORMAT_RGBA8,bytes)

## The ground of the whole region. Vertex colour: R hollows, G height from 0 to 1, B 0 at the region edge.
func build_ground_mesh() -> ArrayMesh:
	var region := settings.region
	var step := 1.0/MESH_DENSITY
	const PAD := 3
	var columns := region.size.x*MESH_DENSITY+1
	var rows := region.size.y*MESH_DENSITY+1
	var wide := columns+PAD*2
	var heights := PackedFloat32Array()
	heights.resize(wide*(rows+PAD*2))
	for gz in range(-PAD,rows+PAD):
		for gx in range(-PAD,columns+PAD):
			heights[(gz+PAD)*wide+gx+PAD] = height_at(region.position.x+gx*step,region.position.y+gz*step)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var indices := PackedInt32Array()
	for gz in range(rows):
		for gx in range(columns):
			var cx := region.position.x+gx*step
			var cz := region.position.y+gz*step
			var i := (gz+PAD)*wide+gx+PAD
			var h: float = heights[i]
			vertices.append(Vector3(cx-MAP*0.5,h,cz-MAP*0.5))
			normals.append(Vector3(heights[i-1]-heights[i+1],2.0*step,heights[i-wide]-heights[i+wide]).normalized())
			var around: float = (heights[i-PAD]+heights[i+PAD]+heights[i-PAD*wide]+heights[i+PAD*wide])*0.25
			colors.append(Color(clampf(0.5+(h-around)*0.9,0.0,1.0),clampf(h/settings.peak,0.0,1.0),edge_fade(cx,cz),1.0))
			uvs.append(Vector2(cx/MAP,cz/MAP))
			uv2s.append(field_uv(cx,cz))
	for gz in range(rows-1):
		for gx in range(columns-1):
			var a := gz*columns+gx
			var b := a+1
			var c := a+columns
			var d := c+1
			# Split each square along its flatter diagonal, which keeps cliff edges clean.
			if absf(vertices[a].y-vertices[d].y) < absf(vertices[b].y-vertices[c].y): indices.append_array([a,b,d,a,d,c])
			else: indices.append_array([a,b,c,b,d,c])
	return _mesh(vertices,normals,colors,uvs,uv2s,indices)

## Flat water over every part of the region within reach of the shore.
func build_water_mesh() -> ArrayMesh:
	var region := settings.region
	var index_of := {}
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var indices := PackedInt32Array()
	for z in range(region.position.y,region.end.y):
		for x in range(region.position.x,region.end.x):
			var wet := false
			for corner in [Vector2(0,0),Vector2(1,0),Vector2(0,1),Vector2(1,1)]:
				if sample(shore,x+corner.x,z+corner.y) > -1.0: wet = true
			if not wet: continue
			var corners: Array[int] = []
			for corner in [Vector2i(0,0),Vector2i(1,0),Vector2i(0,1),Vector2i(1,1)]:
				var key: Vector2i = Vector2i(x,z)+corner
				if not index_of.has(key):
					index_of[key] = vertices.size()
					vertices.append(Vector3(key.x-MAP*0.5,water_height(key.x,key.y),key.y-MAP*0.5))
					normals.append(Vector3.UP)
					colors.append(Color(edge_fade(key.x,key.y),0.0,0.0,1.0))
					uvs.append(Vector2(key.x,key.y)/MAP)
					uv2s.append(field_uv(key.x,key.y))
				corners.append(index_of[key])
			indices.append_array([corners[0],corners[1],corners[2],corners[1],corners[3],corners[2]])
	# The water shader uses a normal map, which needs tangents: +X everywhere on a flat sheet.
	var tangents := PackedFloat32Array()
	tangents.resize(vertices.size()*4)
	for i in range(vertices.size()):
		tangents[i*4] = 1.0
		tangents[i*4+3] = 1.0
	return _mesh(vertices,normals,colors,uvs,uv2s,indices,tangents)

func _mesh(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, uvs: PackedVector2Array, uv2s: PackedVector2Array, indices: PackedInt32Array, tangents := PackedFloat32Array()) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = indices
	if not tangents.is_empty(): arrays[Mesh.ARRAY_TANGENT] = tangents
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh
