extends SceneTree
# Draws the balanced two-player layout from scratch and saves it as assets/maps/balanced/layout.png
# (docs/BALANCED_MAP.md). The PNG is the map's source: edit it in a paint program, then run build_map_data.gd.
# CAUTION: running this again redraws the first version and overwrites any hand edits to the PNG.
#   godot --headless --path . --script res://scripts/tools/draw_balanced_layout.gd
#
# Only start A's side is described here (A is in the west). Every cell is painted together with its partner
# under a 180 degree turn about the map centre, so start B's side is the same land turned round.
# Coordinates are cells: x runs west to east, z north to south, 0-499.
const MapLayout := preload("res://scripts/tools/map_layout.gd")
const OUTPUT := "res://assets/maps/balanced/layout.png"
const SIZE := 500
enum { GRASS, WATER, DESERT, FOREST, MOUNTAIN, ORE, COAL }
const OPEN := [GRASS, DESERT]
## Depth of forest around a coal field, in cells, measured from the field's centre.
const BELT := 15.0
const CONTESTED_BELT := 18.5
## Rows of a coal field, as cells per row: 20 cells, and 40 for a contested field.
const FIELD_ROWS := [3, 5, 5, 4, 3]
const CONTESTED_ROWS := [4, 6, 7, 7, 6, 6, 4]

var cells := PackedByteArray()
var edge_noise := FastNoiseLite.new()

func _initialize() -> void:
	cells.resize(SIZE*SIZE)
	edge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	edge_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	edge_noise.fractal_octaves = 3
	edge_noise.frequency = 0.06
	edge_noise.seed = 1907
	_mountains()
	_water()
	_desert()
	_forest()
	_iron()
	_coal()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.get_base_dir()))
	if MapLayout.save_indexed_png(cells, ProjectSettings.globalize_path(OUTPUT)) != OK:
		push_error("Could not save "+OUTPUT); quit(1); return
	# Read it back: the file a person edits must give exactly the cells drawn.
	var check: Dictionary = MapLayout.read(OUTPUT)
	if not check.errors.is_empty() or check.cells != cells:
		push_error("Layout PNG does not read back as drawn: "+str(check.errors)); quit(1); return
	var counts := MapLayout.counts(cells)
	var report := PackedStringArray()
	for kind in range(counts.size()): report.append("%s %d (%.1f%%)" % [MapLayout.NAMES[kind], counts[kind], counts[kind]*100.0/(SIZE*SIZE)])
	print("BALANCED_LAYOUT_DRAWN ", ", ".join(report))
	quit()

func _mountains() -> void:
	frame(MOUNTAIN, 9.0, 2.0)
	# High ground behind A's main and in the corner behind the safe expansion.
	ellipse(MOUNTAIN, 6, 250, 32, 70, 3.0)
	ellipse(MOUNTAIN, 12, 28, 30, 40, 3.0)
	# Main plateau, north wall: a gap to the safe expansion's pocket, then the north door.
	capsule(MOUNTAIN, 10, 197, 41, 197, 8, 2.0)
	capsule(MOUNTAIN, 89, 197, 97, 197, 8, 2.0)
	# Ridge between the pocket and the north corridor. Its middle is forest (see _forest).
	capsule(MOUNTAIN, 98, 8, 98, 106, 6, 2.0)
	capsule(MOUNTAIN, 98, 182, 98, 197, 6, 2.0)
	# The massif between the north lane and the centre lane.
	rbox(MOUNTAIN, 136, 106, 230, 220, 16, 5.0)
	# Main plateau, east wall either side of the east door.
	capsule(MOUNTAIN, 139, 202, 139, 221, 7.5, 2.0)
	capsule(MOUNTAIN, 139, 279, 139, 297, 7.5, 2.0)
	# Main plateau, south wall either side of the south door.
	capsule(MOUNTAIN, 10, 303, 49, 303, 8, 2.0)
	capsule(MOUNTAIN, 109, 303, 139, 303, 8, 2.0)
	# East side of the exposed expansion, down to the south lane.
	capsule(MOUNTAIN, 140, 303, 140, 391, 7, 3.0)

func _water() -> void:
	# Sea along the north lane; its partner lies along the south lane.
	rbox(WATER, 104, -12, 366, 46, 10, 4.0)
	# Lake south of the forward coal, and its partner north of the enemy's.
	ellipse(WATER, 182, 350, 30, 25, 3.0)
	# Lake closing the north end of the pocket, and the shore west of the exposed expansion.
	ellipse(WATER, 64, 34, 27, 19, 3.0)
	ellipse(WATER, 14, 402, 24, 52, 3.0)

func _desert() -> void:
	ellipse(DESERT, 88, 392, 52, 70, 6.0, [GRASS])
	rbox(DESERT, 133, 400, 300, 449, 12, 5.0, [GRASS])
	ellipse(DESERT, 250, 250, 34, 20, 4.0, [GRASS])

func _forest() -> void:
	# The pass between the lanes at midfield: forest from the massif to the open passage. A contested coal field
	# sits inside it. Scouts cross it, Tanks cut it, nothing else gets through.
	rbox(FOREST, 232, 100, 268, 227, 5, 1.5)
	# Forest stretch of the pocket's ridge: the safe expansion's one soft flank.
	capsule(FOREST, 98, 104, 98, 184, 7, 1.5, OPEN)
	# Woods north of the safe coal.
	rbox(FOREST, 10, 58, 93, 110, 6, 3.0, OPEN)
	# Fringes of the massif along the centre lane and the north lane.
	rbox(FOREST, 148, 219, 233, 229, 4, 2.0, OPEN)
	rbox(FOREST, 208, 97, 233, 112, 4, 2.0, OPEN)
	# A curtain across most of the north lane, and a stand narrowing the north corridor.
	rbox(FOREST, 213, 48, 245, 80, 6, 2.5, OPEN)
	rbox(FOREST, 126, 118, 138, 176, 5, 2.0, OPEN)
	# Shore woods along the sea.
	rbox(FOREST, 104, 44, 366, 56, 4, 2.5, OPEN)
	# Wood beside the main.
	ellipse(FOREST, 51, 221, 9, 7, 1.5, OPEN)
	ellipse(FOREST, 120, 286, 8, 6, 1.5, OPEN)
	# Around the exposed expansion: a stand at the mouth of the south lane and woods in the corner.
	rbox(FOREST, 116, 398, 134, 426, 5, 2.0, OPEN)
	ellipse(FOREST, 44, 448, 18, 12, 2.0, OPEN)
	# Around the forward coal: woods against the ridge, and a stand that shapes the passage to the south lane.
	rbox(FOREST, 147, 272, 160, 322, 4, 2.0, OPEN)
	ellipse(FOREST, 205, 300, 8, 14, 2.0, OPEN)

func _iron() -> void:
	block(ORE, 107, 262, 112, 268) # main, inside the starting Depot's 35 m
	block(ORE, 42, 150, 46, 155) # safe expansion
	block(ORE, 102, 366, 106, 371) # exposed expansion

func _coal() -> void:
	coal_field(62, 113, FIELD_ROWS, BELT) # safe: in the pocket beside the safe expansion
	coal_field(58, 414, FIELD_ROWS, BELT) # exposed: beyond the exposed expansion
	coal_field(186, 113, FIELD_ROWS, BELT) # north lane, set into the massif
	coal_field(178, 296, FIELD_ROWS, BELT) # forward: beside the centre lane
	coal_field(250, 208, CONTESTED_ROWS, CONTESTED_BELT) # contested, in the pass; its partner is south of the lane

# ---- Drawing ----
# Paints the cells inside a shape. `distance` gives metres from a point to the shape's edge, negative inside;
# `wobble` moves the edge by up to about that many metres so it is not ruler-straight. With `only`, just cells
# of those kinds are painted.
func paint(kind: int, box: Rect2i, distance: Callable, wobble: float, only: Array) -> void:
	for z in range(maxi(0, box.position.y), mini(SIZE, box.end.y)):
		for x in range(maxi(0, box.position.x), mini(SIZE, box.end.x)):
			var d: float = distance.call(Vector2(x+0.5, z+0.5))
			if wobble > 0.0: d += edge_noise.get_noise_2d(x, z)*wobble*2.0
			if d > 0.0: continue
			var i := z*SIZE+x
			if not only.is_empty() and not int(cells[i]) in only: continue
			cells[i] = kind
			cells[SIZE*SIZE-1-i] = kind # the same cell seen from start B

func _bounds(x0: float, z0: float, x1: float, z1: float, margin: float) -> Rect2i:
	return Rect2i(floori(x0-margin), floori(z0-margin), ceili(x1-x0+margin*2.0)+1, ceili(z1-z0+margin*2.0)+1)

func frame(kind: int, width: float, wobble: float) -> void:
	var distance := func(p: Vector2) -> float: return minf(minf(p.x, p.y), minf(SIZE-p.x, SIZE-p.y))-width
	paint(kind, Rect2i(0, 0, SIZE, SIZE), distance, wobble, [])

func disc(kind: int, cx: float, cz: float, radius: float, wobble := 0.0, only: Array = []) -> void:
	var distance := func(p: Vector2) -> float: return p.distance_to(Vector2(cx, cz))-radius
	paint(kind, _bounds(cx-radius, cz-radius, cx+radius, cz+radius, wobble*2.0+1.0), distance, wobble, only)

func ellipse(kind: int, cx: float, cz: float, rx: float, rz: float, wobble := 0.0, only: Array = []) -> void:
	var distance := func(p: Vector2) -> float: return (Vector2((p.x-cx)/rx, (p.y-cz)/rz).length()-1.0)*minf(rx, rz)
	paint(kind, _bounds(cx-rx, cz-rz, cx+rx, cz+rz, wobble*2.0+1.0), distance, wobble, only)

## A box with rounded corners.
func rbox(kind: int, x0: float, z0: float, x1: float, z1: float, radius: float, wobble := 0.0, only: Array = []) -> void:
	var centre := Vector2((x0+x1)*0.5, (z0+z1)*0.5)
	var half := Vector2((x1-x0)*0.5, (z1-z0)*0.5)
	var distance := func(p: Vector2) -> float:
		var q := (p-centre).abs()-half+Vector2(radius, radius)
		return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length()+minf(maxf(q.x, q.y), 0.0)-radius
	paint(kind, _bounds(x0, z0, x1, z1, wobble*2.0+1.0), distance, wobble, only)

## A line with thickness: everything within `radius` of the segment.
func capsule(kind: int, ax: float, az: float, bx: float, bz: float, radius: float, wobble := 0.0, only: Array = []) -> void:
	var a := Vector2(ax, az)
	var b := Vector2(bx, bz)
	var distance := func(p: Vector2) -> float:
		var along := clampf((p-a).dot(b-a)/maxf((b-a).length_squared(), 0.0001), 0.0, 1.0)
		return p.distance_to(a+(b-a)*along)-radius
	paint(kind, _bounds(minf(ax, bx)-radius, minf(az, bz)-radius, maxf(ax, bx)+radius, maxf(az, bz)+radius, wobble*2.0+1.0), distance, wobble, only)

## An exact rectangle of cells, both corners included.
func block(kind: int, x0: int, z0: int, x1: int, z1: int) -> void:
	for z in range(z0, z1+1):
		for x in range(x0, x1+1): put(x, z, kind)

func put(x: int, z: int, kind: int) -> void:
	cells[z*SIZE+x] = kind
	cells[SIZE*SIZE-1-(z*SIZE+x)] = kind

## A coal field centred on a cell, row by row, inside a forest belt that covers whatever was there.
func coal_field(cx: int, cz: int, rows: Array, belt: float) -> void:
	disc(FOREST, cx+0.5, cz+0.5, belt, 0.4)
	for row in range(rows.size()):
		for column in range(rows[row]): put(cx-rows[row]/2+column, cz-rows.size()/2+row, COAL)
