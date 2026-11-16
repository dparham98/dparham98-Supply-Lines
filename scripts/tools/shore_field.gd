extends RefCounted
# Where the drawn shoreline runs, worked out from a map's cells. Bake tools use it so the shore map, the sunken
# basin and the plants along the bank all agree with what assets/shaders/terrain_surface.gdshader draws.
# It is art only; gameplay keeps reading terrain_cells.bin.
const SIZE := 500
const WATER := 1
# Stored range of the distance maps, in metres.
const RANGE := 8.0
const DIAGONAL := 1.41421356
const FAR := 100000.0
# The shoreline is rounded off: lakes drawn cell by cell should not keep their corners.
const SMOOTHING_PASSES := 6
# These match the shader's shore_wander and shore_inset. The drawn shore sits this far inside the Water cells and
# wanders either side of that line, so drawn water never reaches ground that units walk on.
const WANDER := 0.35
const INSET := 0.8
# Height of the water surface of a sunken basin, with the ground at 0.
const WATER_LEVEL := -0.32
# What a land cell holds in the map of the Water cells' own edge.
const LAND := -2.0

# Metres from the border between water and everything else, positive into the water, blurred.
var smooth := PackedFloat32Array()
# Metres inside the Water cells, and LAND on every other cell: the true edge, which the drawn shore never crosses.
# Read between cell centres it is below zero all along the edge of a land cell, corners included.
var inside := PackedFloat32Array()

func _init(cells: PackedByteArray) -> void:
	var to_water := distance_to(cells,[WATER])
	# Land is every kind that is not Water, whatever kinds a map has.
	inside = distance_to(cells,[WATER],true)
	smooth.resize(SIZE*SIZE)
	for i in range(SIZE*SIZE):
		smooth[i] = clampf(inside[i]-to_water[i],-RANGE,RANGE)
		inside[i] = minf(inside[i]-0.5,RANGE+LAND) if inside[i] > 0.0 else LAND
	for pass_index in range(SMOOTHING_PASSES): smooth = smoothed(smooth)

# Two-pass chamfer distance to the nearest cell of the given kinds, or with others set, of any other kind.
static func distance_to(cells: PackedByteArray, kinds: Array, others := false) -> PackedFloat32Array:
	var d := PackedFloat32Array()
	d.resize(SIZE*SIZE)
	for i in range(SIZE*SIZE): d[i] = 0.0 if (int(cells[i]) in kinds) != others else FAR
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

static func smoothed(field: PackedFloat32Array) -> PackedFloat32Array:
	var out := field.duplicate()
	for z in range(1,SIZE-1):
		for x in range(1,SIZE-1):
			var i := z*SIZE+x
			out[i] = (field[i]*4.0+(field[i-1]+field[i+1]+field[i-SIZE]+field[i+SIZE])*2.0+field[i-SIZE-1]+field[i-SIZE+1]+field[i+SIZE-1]+field[i+SIZE+1])/16.0
	return out

# A field read between cell centres, as the shader's linear filter reads its image. x and z are metres from the
# map's north-west corner.
static func sample(field: PackedFloat32Array, x: float, z: float) -> float:
	var fx := clampf(x-0.5,0.0,SIZE-1.001)
	var fz := clampf(z-0.5,0.0,SIZE-1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx-ix
	var tz := fz-iz
	var i := iz*SIZE+ix
	return lerpf(lerpf(field[i],field[i+1],tx),lerpf(field[i+SIZE],field[i+SIZE+1],tx),tz)

# The value noise of the terrain shader, so the bake can follow the line that shader draws.
static func _hash(x: int, y: int) -> float:
	var h := (x*1597334677+y*3812015801) & 0xffffffff
	h = ((h ^ (h >> 15))*2246822519) & 0xffffffff
	h = ((h ^ (h >> 13))*3266489917) & 0xffffffff
	h = h ^ (h >> 16)
	return float(h)/4294967295.0

static func noise(p: Vector2, layers: int) -> float:
	var total := 0.0
	var weight := 0.5
	var sum := 0.0
	for i in range(layers):
		var cell := Vector2i(floori(p.x),floori(p.y))
		var f := p-Vector2(cell)
		f = f*f*(Vector2(3.0,3.0)-2.0*f)
		total += lerpf(lerpf(_hash(cell.x,cell.y),_hash(cell.x+1,cell.y),f.x),lerpf(_hash(cell.x,cell.y+1),_hash(cell.x+1,cell.y+1),f.x),f.y)*weight
		sum += weight
		weight *= 0.5
		p = Vector2(1.6*p.x-1.2*p.y,1.2*p.x+1.6*p.y)+Vector2(17.3,9.1)
	return total/sum

# Metres into the drawn water at a point, negative on the drawn land. The same sum as the shader's "shore".
func shore(x: float, z: float) -> float:
	var wander := (noise(Vector2(x,z)*0.19+Vector2(41.0,7.0),3)-0.5)*4.0*WANDER
	return minf(sample(smooth,x,z)+wander-INSET,sample(inside,x,z))

# Height of a sunken basin's bed for a shore distance: level ground up to the shore, a short bank down past the
# water level, then a slow fall to the deep.
static func bed(distance: float) -> float:
	return -(0.52*smoothstep(0.0,0.55,distance)+1.0*smoothstep(0.3,5.0,distance))
