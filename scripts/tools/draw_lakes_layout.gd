extends SceneTree
# Draws the Two Lakes layout from scratch (docs/TWO_LAKES_MAP.md) and measures it. Saves
# assets/maps/lakes/layout.png and a labelled picture of it, and prints what each start has within reach, how long
# and how wide every route is and what the centre holds.
#   godot --path . --script res://scripts/tools/draw_lakes_layout.gd
# With --headless the picture has markers but no names or figures on it.
# CAUTION: running this again redraws the layout and overwrites any hand edits to the PNG.
#
# The idea of the map. The middle is the Crossing: a neck of forest between two small lakes, on the straight line
# between west and east. It is shut at first (Scouts slip through, Tanks cut a road, Infantry fell their way in)
# and it holds the prizes that matter late: the Iron Crag's twin mines, the mother seam of coal, and five places
# for a dam. Whoever holds it has water on both flanks and two mouths to guard. The ways round the lakes' outer
# shores are open from the first minute and only a little longer, so the early game is fought on the sides, where
# a pair of mines in each field face each other across the centre line.
#
# Only the west half is described. Every cell is painted together with its partner across the north-south centre
# line: the east is the west mirrored. Mirroring, not turning, keeps every mine facing the same way for both
# sides; the game looks north, and a mine that faced north would be hidden behind its mountain.
# Coordinates are cells: x runs west to east, z north to south, 0-499.
const MapLayout := preload("res://scripts/tools/map_layout.gd")
const OUTPUT := "res://assets/maps/lakes/layout.png"
const PICTURE := "res://docs/images/two_lakes_layout.png"
const SIZE := 500
const HALF := 250
enum { GRASS, WATER, DESERT, FOREST, MOUNTAIN, ORE, COAL, MINE_SITE }
const OPEN := [GRASS, DESERT]
const NORTH := Vector2i(0, -1)
const SOUTH := Vector2i(0, 1)
const EAST := Vector2i(1, 0)
## Metres a second (assets/units): a worker on foot, and a Depot truck.
const WALK := 2.0
const DRIVE := 3.0
## Cells a worker reaches across, for counting the trees between it and coal or water.
const REACH := 4.0

## The three starts of the west half and what is drawn round each: the mountain north of it that holds its mine,
## its lake (a few ovals, a bay and the channel between them, which is a place for a dam) and its two coal fields.
## The shapes differ so the starts are not copies; what each has within reach is kept the same.
const KITS := [
	{"name": "North-west", "start": Vector2i(96, 94), "mountain": [64, 42, 138, 69], "lake": [[38, 50, 26, 28], [60, 26, 18, 11]],
		"bay": [38, 98, 9, 8], "channel": [38, 76, 38, 92], "starter": Vector2i(86, 120), "lake_coal": Vector2i(56, 124)},
	{"name": "West", "start": Vector2i(66, 250), "mountain": [30, 198, 104, 225], "lake": [[18, 256, 16, 26], [26, 236, 11, 9]],
		"bay": [22, 298, 9, 8], "channel": [22, 280, 22, 292], "starter": Vector2i(53, 276), "lake_coal": Vector2i(44, 300)},
	{"name": "South-west", "start": Vector2i(100, 412), "mountain": [78, 360, 148, 387], "lake": [[40, 456, 28, 24], [74, 472, 22, 13]],
		"bay": [36, 414, 9, 8], "channel": [36, 422, 36, 434], "starter": Vector2i(87, 438), "lake_coal": Vector2i(58, 426)},
]
## Coal fields as cells per row. Each cell holds 50.
const STARTER_ROWS := [3, 4, 3]
const FIELD_ROWS := [3, 5, 5, 4, 3]
const PASS_ROWS := [4, 6, 7, 7, 6, 6, 4]
const MOTHER_ROWS := [6, 8, 10, 10, 12, 12, 12, 12, 10, 10, 8, 8]
const STARTER_BELT := 8.5
const LAKE_BELT := 15.0

var cells := PackedByteArray()
var edge_noise := FastNoiseLite.new()
var rng := RandomNumberGenerator.new()
## What was placed: {kind: "mine"|"coal"|"dam", tier, at, ...}. West half only; the east is its mirror.
var marks: Array[Dictionary] = []
## Ground the scattered woods and loose rocks leave open: [from, to, metres either side].
var clear: Array = []
var found := {}

func _initialize() -> void: call_deferred("run")

func run() -> void:
	cells.resize(SIZE*SIZE)
	edge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	edge_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	edge_noise.fractal_octaves = 3
	edge_noise.frequency = 0.06
	edge_noise.seed = 2611
	rng.seed = 7741
	_ways()
	_mountains()
	_water()
	_desert()
	_forest()
	_coal()
	_mine_sites()
	var errors := MapLayout.mine_site_errors(cells)
	for line in errors: push_error(line)
	if not errors.is_empty():
		quit(1); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.get_base_dir()))
	if MapLayout.save_indexed_png(cells, ProjectSettings.globalize_path(OUTPUT)) != OK:
		push_error("Could not save "+OUTPUT); quit(1); return
	var check: Dictionary = MapLayout.read(OUTPUT)
	if not check.errors.is_empty() or check.cells != cells:
		push_error("Layout PNG does not read back as drawn: "+str(check.errors)); quit(1); return
	_measure()
	for line in found.lines: print(line)
	await _picture()
	print("TWO_LAKES_LAYOUT_DRAWN")
	quit()

# ---- The land ----
## The ways that must stay open: from each start to its neighbours, to the Crossing's mouth and round each lake.
func _ways() -> void:
	var west: Vector2 = KITS[1].start
	clear.append([west, Vector2(182, 256), 15.0])
	for bend in [[Vector2(172, 182), Vector2(198, 158), Vector2(250, 150)], [Vector2(172, 322), Vector2(198, 346), Vector2(250, 352)]]:
		clear.append([west, bend[0], 11.0])
		clear.append([bend[0], bend[1], 11.0])
		clear.append([bend[1], bend[2], 11.0])
	clear.append([Vector2(KITS[0].start), Vector2(196, 122), 10.0])
	clear.append([Vector2(196, 122), Vector2(250, 122), 10.0])
	clear.append([Vector2(KITS[0].start), Vector2(190, 48), 10.0])
	clear.append([Vector2(190, 48), Vector2(250, 40), 10.0])
	clear.append([Vector2(KITS[2].start), Vector2(196, 452), 10.0])
	clear.append([Vector2(196, 452), Vector2(250, 452), 10.0])
	clear.append([Vector2(KITS[2].start), Vector2(196, 372), 10.0])
	clear.append([Vector2(KITS[0].start), Vector2(104, 180), 10.0])
	clear.append([Vector2(104, 180), west, 10.0])
	clear.append([west, Vector2(104, 330), 10.0])
	clear.append([Vector2(104, 330), Vector2(KITS[2].start), 10.0])
	clear.append([west, Vector2(62, 392), 9.0])
	clear.append([Vector2(62, 392), Vector2(KITS[2].start), 9.0])
	for kit in KITS: clear.append([Vector2(kit.start), Vector2(kit.start), 34.0])

func _mountains() -> void:
	fill(MOUNTAIN, shape(func(p: Vector2) -> float: return minf(minf(p.x, p.y), SIZE-p.y)-5.0, 0, 0, HALF, SIZE), 1.5)
	for kit in KITS:
		var m: Array = kit.mountain
		massif(m[0], m[1], m[2], m[3], NORTH)
	# An expansion for each start, on the way out of it.
	massif(148, 6, 186, 33, NORTH)
	massif(102, 152, 138, 179, NORTH)
	massif(122, 320, 160, 350, NORTH)
	# The gates of the Crossing's west mouth, each grown out of a lake's end. The north one holds a mine in the
	# face that looks into the Crossing.
	fill(MOUNTAIN, box(180, 188, 205, 232, 7), 1.5)
	fill(MOUNTAIN, box(182, 290, 203, 316, 7), 1.5)
	# The Iron Crag, on the north lake's shore at the very middle. It closes the north side of the Crossing and
	# leaves the road through it open to the south.
	fill(MOUNTAIN, box(228, 192, 272, 227, 7), 1.5)
	# In each field, a massif just west of the centre line with a mine in the face that looks east at its
	# partner. Between the pair lies coal. They split each field into an inner and an outer pass.
	massif(200, 72, 233, 102, Vector2i(-1, 0))
	massif(200, 398, 233, 430, Vector2i(-1, 0))
	# Loose rocks, to pinch the open ground here and there.
	var placed := 0
	var tries := 0
	while placed < 8 and tries < 800:
		tries += 1
		var centre := Vector2(rng.randf_range(100, 240), rng.randf_range(14, 486))
		var radii := Vector2(rng.randf_range(4, 8), rng.randf_range(4, 7))
		if not is_free(centre, maxf(radii.x, radii.y)+12.0) or (centre.x > 172 and centre.y > 176 and centre.y < 324): continue
		fill(MOUNTAIN, ell(centre.x, centre.y, radii.x, radii.y), 1.5)
		clear.append([centre, centre, maxf(radii.x, radii.y)+16.0])
		placed += 1
	print("Loose rocks placed: ", placed)

## A mountain with lumps on the side away from its mine, so its outline is not a box.
func massif(x0: float, z0: float, x1: float, z1: float, lumpy: Vector2i) -> void:
	var parts: Array = [box(x0, z0, x1, z1, 8)]
	for i in range(3):
		var along := rng.randf_range(0.15, 0.85)
		var radius := rng.randf_range(5, 9)
		if lumpy.x == 0: parts.append(ell(lerpf(x0, x1, along), z0+rng.randf_range(0, 4), radius*1.3, radius))
		else: parts.append(ell(x0+rng.randf_range(0, 4), lerpf(z0, z1, along), radius, radius*1.3))
	fill(MOUNTAIN, any(parts), 2.0)

func _water() -> void:
	# The two central lakes: small, so the ways round them are short.
	fill(WATER, ell(250, 180, 58, 15), 2.0)
	fill(WATER, ell(250, 322, 58, 15), 2.0)
	# Bays into the Crossing, each joined to its lake by a channel 7 cells wide: a place for a dam. The north
	# lake has one each side of the Crag; the south lake has three, the middle one on the centre line.
	bay(214, 204, 6.5, 214, 191, 199, "inner")
	bay(224, 297, 7, 224, 303, 312, "inner")
	bay(250, 293, 7, 250, 299, 312, "shared")
	for kit in KITS:
		var parts: Array = []
		for oval in kit.lake: parts.append(ell(oval[0], oval[1], oval[2], oval[3]))
		fill(WATER, any(parts), 2.0)
		var b: Array = kit.bay
		var c: Array = kit.channel
		fill(WATER, ell(b[0], b[1], b[2], b[3]), 1.5)
		fill(WATER, cap(c[0], c[1], c[2], c[3], 3.5))
		marks.append({"kind": "dam", "tier": "home", "at": Vector2(c[0]+c[2], c[1]+c[3])*0.5})

func bay(cx: float, cz: float, radius: float, channel_x: float, from_z: float, to_z: float, tier: String) -> void:
	fill(WATER, ell(cx, cz, radius, radius*0.9), 1.0)
	fill(WATER, cap(channel_x, from_z, channel_x, to_z, 3.5))
	marks.append({"kind": "dam", "tier": tier, "at": Vector2(channel_x, (from_z+to_z)*0.5)})

func _desert() -> void:
	# The south is dry, as on the first map; the north is grass.
	fill(DESERT, box(26, 372, 474, 506, 30), 7.0, [GRASS])

func _forest() -> void:
	# The Crossing: forest from lake to lake, and out past the gates.
	fill(FOREST, box(184, 184, 316, 318, 6), 2.0, OPEN)
	for kit in KITS:
		# A wood right round each start's lake: timber to hand, and the screen in front of safe water.
		var parts: Array = []
		for oval in kit.lake: parts.append(ell(oval[0], oval[1], oval[2], oval[3]))
		var b: Array = kit.bay
		parts.append(ell(b[0], b[1], b[2], b[3]))
		fill(FOREST, grown(any(parts), 12.0), 2.5, OPEN)
	# The pocket between each pair of facing massifs.
	fill(FOREST, box(233, 56, 267, 80, 5), 1.5, OPEN)
	fill(FOREST, box(233, 386, 267, 408, 5), 1.5, OPEN)
	# Belts along the west edge between the starts' woods: cover a Scout can run under from one to the next.
	fill(FOREST, box(4, 126, 24, 204, 6), 3.0, OPEN)
	fill(FOREST, box(4, 326, 22, 404, 6), 3.0, OPEN)
	# Woods scattered over the rest, clear of the starts, the mines' yards and the ways between.
	var placed := 0
	const SQUARE := 34.0
	for row in range(ceili(SIZE/SQUARE)):
		for column in range(ceili(HALF/SQUARE)):
			for attempt in range(8):
				var centre := Vector2((column+rng.randf())*SQUARE, (row+rng.randf())*SQUARE)
				var size := rng.randf_range(4, 11)
				if centre.x < 6 or centre.x >= HALF or centre.y < 6 or centre.y >= SIZE-6: continue
				if not int(cells[int(centre.y)*SIZE+int(centre.x)]) in OPEN or not is_free(centre, size+2.0): continue
				var parts: Array = [ell(centre.x, centre.y, size, size*rng.randf_range(0.6, 1.0))]
				for lump in range(rng.randi_range(0, 2)):
					parts.append(ell(centre.x+rng.randf_range(-size, size), centre.y+rng.randf_range(-size, size)*0.7, size*rng.randf_range(0.4, 0.8), size*rng.randf_range(0.4, 0.7)))
				fill(FOREST, any(parts), 2.5, OPEN)
				placed += 1
				break
	var copses := 0
	const PLOT := 23.0
	for row in range(ceili(SIZE/PLOT)):
		for column in range(ceili(HALF/PLOT)):
			for attempt in range(5):
				var centre := Vector2((column+rng.randf())*PLOT, (row+rng.randf())*PLOT)
				var size := rng.randf_range(2.5, 5.5)
				if centre.x < 8 or centre.x >= HALF or centre.y < 8 or centre.y >= SIZE-8: continue
				if not int(cells[int(centre.y)*SIZE+int(centre.x)]) in OPEN or not is_free(centre, size+1.0): continue
				fill(FOREST, any([ell(centre.x, centre.y, size, size*rng.randf_range(0.6, 1.0)), ell(centre.x+rng.randf_range(-size, size), centre.y+rng.randf_range(-size, size), size*0.6, size*0.5)]), 1.5, OPEN)
				copses += 1
				break
	print("Woods placed: ", placed, ", copses: ", copses)

func _coal() -> void:
	for kit in KITS:
		coal_field(kit.starter.x, kit.starter.y, STARTER_ROWS, STARTER_BELT, "starter")
		coal_field(kit.lake_coal.x, kit.lake_coal.y, FIELD_ROWS, LAKE_BELT, "lake")
	# Between each pair of facing massifs, walled by rock west and east.
	coal_field(250, 68, PASS_ROWS, 0.0, "pass")
	coal_field(250, 397, PASS_ROWS, 0.0, "pass")
	# In the Crossing: a field inside each mouth and the mother seam at the middle.
	coal_field(212, 263, PASS_ROWS, 0.0, "forward")
	coal_field(250, 269, MOTHER_ROWS, 0.0, "mother")

func _mine_sites() -> void:
	for kit in KITS:
		mine_site(Vector2i(kit.start.x+2, kit.start.y-28), SOUTH, "home")
	mine_site(Vector2i(165, 31), SOUTH, "expansion")
	mine_site(Vector2i(118, 177), SOUTH, "expansion")
	mine_site(Vector2i(139, 348), SOUTH, "expansion")
	# In each field, looking across the centre line.
	mine_site(Vector2i(230, 94), EAST, "pass")
	mine_site(Vector2i(230, 422), EAST, "pass")
	# The gate mine, inside the mouth and looking into the Crossing; and the Crag's twin mines.
	mine_site(Vector2i(202, 224), EAST, "gate")
	mine_site(Vector2i(238, 225), SOUTH, "crag")

## A mine site (docs/MINE_SITES.md) with its north-west cell at `low`, looking out one way. The rock behind it and
## on its flanks is squared off so the site is sound whatever the mountain's edge did. The ground in front is a
## yard of desert, with room for the Depot that works the mine: iron is found on the dry side of a mountain.
func mine_site(low: Vector2i, facing: Vector2i, tier: String) -> void:
	var size := MapLayout.MINE_SITE_SIZE if facing.x == 0 else Vector2i(MapLayout.MINE_SITE_SIZE.y, MapLayout.MINE_SITE_SIZE.x)
	var across := Vector2i(absi(facing.y), absi(facing.x))
	var width := size.x if facing.x == 0 else size.y
	var depth := size.y if facing.x == 0 else size.x
	var middle := Vector2(low)+Vector2(size)*0.5
	var yard := middle+Vector2(facing)*(depth*0.5+9.0)
	fill(DESERT, ell(yard.x, yard.y, 14.0 if facing.x == 0 else 10.0, 10.0 if facing.x == 0 else 14.0), 1.5, [GRASS, FOREST])
	for row in range(-3, depth+MapLayout.MINE_FRONT_DEPTH+2):
		for step in range(-3, width+3):
			var cell := low+across*step+facing*row
			var inside := step >= 0 and step < width
			if row < depth: put(cell.x, cell.y, MINE_SITE if inside and row >= 0 else MOUNTAIN)
			elif step >= -1 and step <= width: put(cell.x, cell.y, DESERT)
	marks.append({"kind": "mine", "tier": tier, "at": middle, "facing": facing, "yard": yard})

# ---- Measuring ----
func _measure() -> void:
	var lines: Array[String] = []
	var counts := MapLayout.counts(cells)
	var ground := PackedStringArray()
	for kind in range(counts.size()):
		if counts[kind] > 0: ground.append("%s %.1f%%" % [MapLayout.NAMES[kind], counts[kind]*100.0/(SIZE*SIZE)])
	lines.append("Ground: "+", ".join(ground))
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(0, 0, SIZE, SIZE)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	for i in range(SIZE*SIZE): grid.set_point_solid(Vector2i(i%SIZE, i/SIZE), not int(cells[i]) in OPEN)
	var room := clearance()
	# What each start has within reach.
	lines.append("")
	lines.append("Each start: walk to its mine; then distance and trees to fell for starter coal, lake coal and water")
	var reach: Array = []
	for kit in KITS:
		var start: Vector2i = kit.start
		var felled := trees_from(start)
		var home := nearest(start, "mine", "home")
		var starter := nearest(start, "coal", "starter")
		var lake := nearest(start, "coal", "lake")
		var water: Array = []
		for oval in kit.lake:
			for z in range(int(oval[1]-oval[3]), int(oval[1]+oval[3])+1):
				for x in range(maxi(0, int(oval[0]-oval[2])), int(oval[0]+oval[2])+1):
					if z >= 0 and z < SIZE and cells[z*SIZE+x] == WATER: water.append(Vector2i(x, z))
		var entry := {"name": kit.name, "mine": length(way(grid, start, Vector2i(home.yard))),
			"starter": Vector2(start).distance_to(starter.at), "starter_trees": trees_to(felled, starter.cells),
			"lake": Vector2(start).distance_to(lake.at), "lake_trees": trees_to(felled, lake.cells), "water_trees": trees_to(felled, water)}
		reach.append(entry)
		lines.append("  %-11s mine %3.0f m | starter coal %2.0f m, %d trees | lake coal %2.0f m, %d trees | water %d trees" % [entry.name, entry.mine, entry.starter, entry.starter_trees, entry.lake, entry.lake_trees, entry.water_trees])
	found["reach"] = reach
	# The ways between starts, on open ground with no tree felled.
	lines.append("")
	lines.append("Ways on open ground, nothing felled: length, time on foot, and the width of the tightest place")
	var routes: Array = []
	var pairs := [["West to East", KITS[1].start, mirror(KITS[1].start)], ["North-west to North-east", KITS[0].start, mirror(KITS[0].start)],
		["South-west to South-east", KITS[2].start, mirror(KITS[2].start)], ["North-west to West", KITS[0].start, KITS[1].start],
		["West to South-west", KITS[1].start, KITS[2].start], ["North-west to East", KITS[0].start, mirror(KITS[1].start)],
		["South-west to East", KITS[2].start, mirror(KITS[1].start)]]
	for pair in pairs:
		var path := way(grid, pair[1], pair[2])
		var width := widest(room, pair[1], pair[2])
		var route := {"name": pair[0], "path": path, "length": length(path), "straight": Vector2(pair[1]).distance_to(Vector2(pair[2])), "width": width, "pinch": pinch(room, pair[1], pair[2], width*0.5)}
		routes.append(route)
		lines.append("  %-26s %3.0f m (straight %3.0f m, +%d%%), %s on foot, tightest %d m at %s" % [route.name, route.length, route.straight, roundi((route.length/route.straight-1.0)*100.0), clock(route.length/WALK), route.width, route.pinch])
	found["routes"] = routes
	# The Crossing.
	lines.append("")
	lines.append("The Crossing, from the West start")
	var west: Vector2i = KITS[1].start
	var felled := trees_from(west, 186, 316)
	var gate := nearest(west, "mine", "gate")
	var crag := nearest(west, "mine", "crag")
	var mother := nearest(west, "coal", "mother")
	var forward := nearest(west, "coal", "forward")
	var mouth := Vector2i(180, 256)
	lines.append("  Mouth: %.0f m, %s on foot, %s by truck" % [length(way(grid, west, mouth)), clock(length(way(grid, west, mouth))/WALK), clock(length(way(grid, west, mouth))/DRIVE)])
	lines.append("  Trees to fell before reaching: gate mine %d, forward coal %d, Crag mines %d, mother seam %d, the far side's start %d" % [
		int(felled[int(gate.yard.y)*SIZE+int(gate.yard.x)]), trees_to(felled, forward.cells), int(felled[int(crag.yard.y)*SIZE+int(crag.yard.x)]), trees_to(felled, mother.cells), int(felled[west.y*SIZE+SIZE-1-west.x])])
	found["through"] = int(felled[west.y*SIZE+SIZE-1-west.x])
	for kit in KITS:
		lines.append("  From %s to the mouth: %.0f m, %s on foot" % [kit.name, length(way(grid, kit.start, mouth)), clock(length(way(grid, kit.start, mouth))/WALK)])
	lines.append("")
	lines.append("Each start's expansion mine, to the yard in front")
	for kit in KITS:
		var best := INF
		for mark in marks:
			if mark.kind == "mine" and mark.tier == "expansion": best = minf(best, length(way(grid, kit.start, Vector2i(mark.yard))))
		lines.append("  %-11s %3.0f m, %s on foot" % [kit.name, best, clock(best/WALK)])
	# The pass mines: how far from each side.
	lines.append("")
	lines.append("The mines that face each other across the centre line, to the yard in front")
	for mark in marks:
		if mark.kind != "mine" or mark.tier != "pass": continue
		var own := INF
		var other := INF
		for kit in KITS:
			own = minf(own, length(way(grid, kit.start, Vector2i(mark.yard))))
			other = minf(other, length(way(grid, mirror(kit.start), Vector2i(mark.yard))))
		var seam := nearest(Vector2i(mark.at), "coal", "pass")
		lines.append("  At %s: %.0f m from its own side's nearest start, %.0f m from the other side's; %d trees between its yard and the coal beside it" % [Vector2i(mark.at), own, other, trees_to(trees_from(Vector2i(mark.yard)), seam.cells)])
	# Totals.
	lines.append("")
	var mines := {}
	var coal := {}
	var dams := {}
	for mark in marks:
		var twice := 1 if absf(mark.at.x-HALF) < 3.0 else 2
		if mark.kind == "mine": mines[mark.tier] = int(mines.get(mark.tier, 0))+twice
		elif mark.kind == "dam": dams[mark.tier] = int(dams.get(mark.tier, 0))+twice
		else: coal[mark.tier] = int(coal.get(mark.tier, 0))+field_size(mark)*50*twice
	lines.append("Mine sites: %s" % str(mines))
	lines.append("Coal: %s" % str(coal))
	lines.append("Dam places: %s" % str(dams))
	found["mines"] = mines
	found["coal"] = coal
	found["dams"] = dams
	found["lines"] = lines

func clock(seconds: float) -> String:
	return "%d:%02d" % [int(seconds)/60, int(seconds)%60]

func mirror(cell: Vector2i) -> Vector2i:
	return Vector2i(SIZE-1-cell.x, cell.y)

func nearest(start: Vector2i, kind: String, tier: String) -> Dictionary:
	var best := {}
	for mark in marks:
		if mark.kind != kind or mark.tier != tier: continue
		if best.is_empty() or Vector2(start).distance_to(mark.at) < Vector2(start).distance_to(best.at): best = mark
	return best

## A grid path pulled taut: each corner kept only where the straight line past it is blocked.
func taut(path: PackedVector2Array) -> PackedVector2Array:
	if path.size() < 3: return path
	var out := PackedVector2Array([path[0]])
	var at := 0
	while at < path.size()-1:
		var next := path.size()-1
		while next > at+1 and not sees(path[at], path[next]): next -= 1
		out.append(path[next])
		at = next
	return out

func sees(a: Vector2, b: Vector2) -> bool:
	var steps := ceili(a.distance_to(b)*2.0)
	for i in range(steps+1):
		var p := a.lerp(b, float(i)/maxf(steps, 1))
		for offset in [Vector2(0.45, 0.45), Vector2(-0.45, 0.45), Vector2(0.45, -0.45), Vector2(-0.45, -0.45)]:
			var cell := Vector2i((p+offset+Vector2(0.5, 0.5)).floor())
			if cell.x < 0 or cell.y < 0 or cell.x >= SIZE or cell.y >= SIZE or not int(cells[cell.y*SIZE+cell.x]) in OPEN: return false
	return true

func way(grid: AStarGrid2D, from: Vector2i, to: Vector2i) -> PackedVector2Array:
	return taut(grid.get_point_path(from, to))

func length(path: PackedVector2Array) -> float:
	if path.size() < 2: return INF
	var total := 0.0
	for i in range(1, path.size()): total += path[i-1].distance_to(path[i])
	return total

## Cells in the field a coal mark stands for, counted on the finished map.
func field_size(mark: Dictionary) -> int:
	var seen := {}
	var open: Array[Vector2i] = []
	for cell in mark.cells:
		if not seen.has(cell) and cells[cell.y*SIZE+cell.x] == COAL: seen[cell] = true; open.append(cell)
	while not open.is_empty():
		var at: Vector2i = open.pop_back()
		for next in [at+Vector2i(1, 0), at-Vector2i(1, 0), at+Vector2i(0, 1), at-Vector2i(0, 1)]:
			if next.x >= 0 and next.y >= 0 and next.x < SIZE and next.y < SIZE and not seen.has(next) and cells[next.y*SIZE+next.x] == COAL: seen[next] = true; open.append(next)
	var west := 0
	for cell in seen:
		if cell.x < HALF: west += 1
	return west if absf(mark.at.x-HALF) >= 3.0 else seen.size()

## For every cell, the fewest Forest cells felled to walk there from a start. Water, rock and coal stop the way.
## With rows given, the walk stays between them once it is east of the starts.
func trees_from(start: Vector2i, first_row := 0, last_row := SIZE-1) -> PackedInt32Array:
	var cost := PackedInt32Array()
	cost.resize(SIZE*SIZE)
	cost.fill(1 << 30)
	var near: Array[int] = [start.y*SIZE+start.x]
	var far: Array[int] = []
	cost[near[0]] = 0
	while not near.is_empty() or not far.is_empty():
		if near.is_empty():
			near = far
			far = []
		var at: int = near.pop_back()
		var x := at%SIZE
		for next in [at-1 if x > 0 else -1, at+1 if x < SIZE-1 else -1, at-SIZE, at+SIZE]:
			if next < 0 or next >= SIZE*SIZE: continue
			var column: int = int(next)%SIZE
			if column > 150 and column < 350 and (next/SIZE < first_row or next/SIZE > last_row): continue
			var kind := int(cells[next])
			if kind != FOREST and not kind in OPEN: continue
			var step := 1 if kind == FOREST else 0
			if cost[at]+step >= cost[next]: continue
			cost[next] = cost[at]+step
			if step == 0: near.append(next)
			else: far.append(next)
	return cost

## The fewest trees felled before a worker stands within reach of any of the target cells.
func trees_to(felled: PackedInt32Array, targets: Array) -> int:
	var best := 1 << 30
	var span := ceili(REACH)
	for target in targets:
		for dz in range(-span, span+1):
			for dx in range(-span, span+1):
				var cell: Vector2i = target+Vector2i(dx, dz)
				if cell.x < 0 or cell.y < 0 or cell.x >= SIZE or cell.y >= SIZE or Vector2(dx, dz).length() > REACH: continue
				best = mini(best, felled[cell.y*SIZE+cell.x])
	return best

## For every cell, how many cells of open ground lie between it and the nearest thing in the way.
func clearance() -> PackedFloat32Array:
	var d := PackedFloat32Array()
	d.resize(SIZE*SIZE)
	for i in range(SIZE*SIZE): d[i] = 1000.0 if int(cells[i]) in OPEN else 0.0
	for z in range(SIZE):
		for x in range(SIZE):
			var i := z*SIZE+x
			if x > 0: d[i] = minf(d[i], d[i-1]+1.0)
			if z > 0:
				d[i] = minf(d[i], d[i-SIZE]+1.0)
				if x > 0: d[i] = minf(d[i], d[i-SIZE-1]+1.414)
				if x < SIZE-1: d[i] = minf(d[i], d[i-SIZE+1]+1.414)
	for z in range(SIZE-1, -1, -1):
		for x in range(SIZE-1, -1, -1):
			var i := z*SIZE+x
			if x < SIZE-1: d[i] = minf(d[i], d[i+1]+1.0)
			if z < SIZE-1:
				d[i] = minf(d[i], d[i+SIZE]+1.0)
				if x < SIZE-1: d[i] = minf(d[i], d[i+SIZE+1]+1.414)
				if x > 0: d[i] = minf(d[i], d[i+SIZE-1]+1.414)
	return d

## The width in metres of the tightest place on the widest way between two cells: how broad a front can pass.
func widest(room: PackedFloat32Array, from: Vector2i, to: Vector2i) -> int:
	var low := 1
	var high := 60
	while low < high:
		var middle := (low+high+1)/2
		if joined(room, from, to, float(middle)): low = middle
		else: high = middle-1
	return low*2

func joined(room: PackedFloat32Array, from: Vector2i, to: Vector2i, least: float) -> bool:
	return not trail(room, from, to, least).is_empty()

## The tightest place on the widest way between two cells: where that way first leaves the ground that can be
## reached with a metre more room.
func pinch(room: PackedFloat32Array, from: Vector2i, to: Vector2i, least: float) -> Vector2i:
	var back := trail(room, from, to, least)
	if back.is_empty(): return Vector2i(-1, -1)
	var roomy := PackedByteArray()
	roomy.resize(SIZE*SIZE)
	var open := PackedInt32Array([from.y*SIZE+from.x])
	roomy[open[0]] = 1
	var head := 0
	while head < open.size():
		var at := open[head]; head += 1
		var x := at%SIZE
		for next in [at-1 if x > 0 else -1, at+1 if x < SIZE-1 else -1, at-SIZE, at+SIZE]:
			if next < 0 or next >= SIZE*SIZE or roomy[next] == 1 or room[next] <= 0.0: continue
			var cell := Vector2(next%SIZE, next/SIZE)
			if room[next] < least+1.0 and cell.distance_to(Vector2(from)) > 16.0 and cell.distance_to(Vector2(to)) > 16.0: continue
			roomy[next] = 1
			open.append(next)
	for i in range(back.size()-1, -1, -1):
		if roomy[back[i]] == 0: return Vector2i(back[i]%SIZE, back[i]/SIZE)
	return Vector2i(-1, -1)

## A way between two cells over ground with at least this much room, as cells from the far end back; empty when
## there is none.
func trail(room: PackedFloat32Array, from: Vector2i, to: Vector2i, least: float) -> PackedInt32Array:
	var came := PackedInt32Array()
	came.resize(SIZE*SIZE)
	came.fill(-1)
	var seen := PackedByteArray()
	seen.resize(SIZE*SIZE)
	var open := PackedInt32Array([from.y*SIZE+from.x])
	seen[open[0]] = 1
	var goal := to.y*SIZE+to.x
	var head := 0
	while head < open.size():
		var at := open[head]; head += 1
		if at == goal:
			var back := PackedInt32Array()
			while at >= 0:
				back.append(at)
				at = came[at]
			return back
		var x := at%SIZE
		for next in [at-1 if x > 0 else -1, at+1 if x < SIZE-1 else -1, at-SIZE, at+SIZE]:
			if next < 0 or next >= SIZE*SIZE or seen[next] == 1 or room[next] <= 0.0: continue
			# The ground right beside either end counts whatever its width: a start stands near its own buildings.
			var cell := Vector2(next%SIZE, next/SIZE)
			if room[next] < least and cell.distance_to(Vector2(from)) > 16.0 and cell.distance_to(Vector2(to)) > 16.0: continue
			seen[next] = 1
			came[next] = at
			open.append(next)
	return PackedInt32Array()

# ---- The picture ----
class Sheet extends Control:
	const SCALE := 2
	var map: ImageTexture
	var marks: Array = []
	var starts: Array = []
	var routes: Array = []
	var names: Array = []
	var panel: Array = []
	func mirrored(at: Vector2) -> Vector2:
		return Vector2(500.0-at.x, at.y)
	func _draw() -> void:
		var font := ThemeDB.fallback_font
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.075, 0.08))
		draw_texture_rect(map, Rect2(0, 0, 500*SCALE, 500*SCALE), false)
		for route in routes:
			var points := PackedVector2Array()
			for point in route.path: points.append((point+Vector2(0.5, 0.5))*SCALE)
			if points.size() > 1:
				draw_polyline(points, Color(0, 0, 0, 0.55), 5.0)
				draw_polyline(points, route.colour, 2.5)
		for mark in marks:
			for side in [0, 1]:
				if side == 1 and absf(mark.at.x-250.0) < 3.0: continue
				var at: Vector2 = (mark.at if side == 0 else mirrored(mark.at))*SCALE
				if mark.kind == "mine":
					draw_circle(at, 12, Color.BLACK)
					draw_circle(at, 9.5, mark.colour)
					var facing := Vector2(mark.facing.x if side == 0 else -mark.facing.x, mark.facing.y)
					draw_colored_polygon(PackedVector2Array([at+facing*17.0, at+facing*8.0+facing.orthogonal()*6.0, at+facing*8.0-facing.orthogonal()*6.0]), Color.BLACK)
				elif mark.kind == "dam":
					draw_rect(Rect2(at-Vector2(12, 5), Vector2(24, 10)), Color.BLACK)
					draw_rect(Rect2(at-Vector2(10, 3), Vector2(20, 6)), Color(0.4, 1.0, 1.0))
				else:
					var reach: float = mark.size
					draw_colored_polygon(PackedVector2Array([at+Vector2(0, -reach-3), at+Vector2(reach+3, 0), at+Vector2(0, reach+3), at+Vector2(-reach-3, 0)]), Color.WHITE)
					draw_colored_polygon(PackedVector2Array([at+Vector2(0, -reach), at+Vector2(reach, 0), at+Vector2(0, reach), at+Vector2(-reach, 0)]), Color(0.08, 0.08, 0.1))
		for start in starts:
			var at: Vector2 = Vector2(start.at)*SCALE
			draw_circle(at, 14, Color.BLACK)
			draw_circle(at, 11, Color.WHITE)
			var width := font.get_string_size(start.number, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
			draw_string(font, at+Vector2(-width*0.5, 6), start.number, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.BLACK)
		for label in names:
			var text_size: int = label.get("size", 15)
			var width := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x
			var origin: Vector2 = (label.at*SCALE-Vector2(width*0.5, 0)).clamp(Vector2(4, 16), Vector2(500*SCALE-width-4, 500*SCALE-6))
			draw_string_outline(font, origin, label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, 6, Color(0, 0, 0, 0.9))
			draw_string(font, origin, label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, label.get("colour", Color.WHITE))
		var y := 26.0
		for line in panel:
			var text_size: int = line.get("size", 14)
			if line.has("swatch"):
				draw_rect(Rect2(500*SCALE+18, y-12, 16, 16), Color.WHITE)
				draw_rect(Rect2(500*SCALE+20, y-10, 12, 12), line.swatch)
			draw_string(font, Vector2(500*SCALE+(42 if line.has("swatch") else 18), y), line.text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, line.get("colour", Color(0.9, 0.9, 0.88)))
			y += text_size+5.0 if not line.text.is_empty() else 7.0

func _picture() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PICTURE.get_base_dir()))
	var pixels := PackedByteArray()
	pixels.resize(SIZE*SIZE*3)
	for i in range(SIZE*SIZE):
		var colour: Color = MapLayout.PALETTE[cells[i]]
		pixels[i*3] = colour.r8; pixels[i*3+1] = colour.g8; pixels[i*3+2] = colour.b8
	var flat := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGB8, pixels)
	if DisplayServer.get_name() == "headless":
		flat.resize(SIZE*2, SIZE*2, Image.INTERPOLATE_NEAREST)
		flat.save_png(ProjectSettings.globalize_path(PICTURE))
		print("Picture saved without names (headless) to ", PICTURE)
		return
	var sheet := Sheet.new()
	sheet.map = ImageTexture.create_from_image(flat)
	sheet.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sheet.size = Vector2(SIZE*2+640, SIZE*2+90)
	var tints := {"home": Color(1.0, 0.9, 0.2), "expansion": Color(1.0, 0.6, 0.15), "pass": Color(1.0, 0.25, 0.25), "gate": Color(0.85, 0.45, 1.0), "crag": Color(1.0, 1.0, 1.0)}
	var sizes := {"starter": 6.0, "lake": 8.0, "pass": 10.0, "forward": 10.0, "mother": 14.0}
	for mark in marks:
		var copy := mark.duplicate()
		if mark.kind == "mine": copy["colour"] = tints[mark.tier]
		elif mark.kind == "coal": copy["size"] = sizes[mark.tier]
		sheet.marks.append(copy)
	for index in range(KITS.size()):
		sheet.starts.append({"at": KITS[index].start, "number": str(index*2+1)})
		sheet.starts.append({"at": mirror(KITS[index].start), "number": str(index*2+2)})
	var colours := {"West to East": Color(1.0, 0.95, 0.4), "North-west to North-east": Color(1, 1, 1), "South-west to South-east": Color(1, 1, 1)}
	for route in found.routes:
		if colours.has(route.name): sheet.routes.append({"path": route.path, "colour": colours[route.name]})
	sheet.routes.append({"path": PackedVector2Array([Vector2(KITS[1].start), Vector2(mirror(KITS[1].start))]), "colour": Color(1.0, 0.35, 0.3)})
	sheet.names = [{"at": Vector2(250, 250), "text": "THE CROSSING", "size": 18}, {"at": Vector2(250, 214), "text": "Iron Crag"},
		{"at": Vector2(250, 281), "text": "mother seam", "size": 13}, {"at": Vector2(250, 182), "text": "North Lake"}, {"at": Vector2(250, 325), "text": "South Lake"},
		{"at": Vector2(250, 140), "text": "north inner pass", "size": 13}, {"at": Vector2(250, 30), "text": "north outer pass", "size": 13},
		{"at": Vector2(250, 364), "text": "south inner pass", "size": 13}, {"at": Vector2(250, 466), "text": "south outer pass", "size": 13},
		{"at": Vector2(174, 250), "text": "west mouth", "size": 13}, {"at": Vector2(326, 250), "text": "east mouth", "size": 13}]
	var panel: Array = [{"text": "TWO LAKES", "size": 22, "colour": Color.WHITE}, {"text": "1 cell = 1 m, 500 x 500 m. North is up. East mirrors west.", "size": 12, "colour": Color(0.7, 0.7, 0.68)}, {"text": ""},
		{"text": "Starts 1 to 6", "swatch": Color.WHITE}, {"text": "Home mine", "swatch": tints.home}, {"text": "Expansion mine", "swatch": tints.expansion},
		{"text": "Pass mine: faces its partner across the line", "swatch": tints.pass}, {"text": "Gate mine: inside the mouth, faces in", "swatch": tints.gate},
		{"text": "Crag mines: the middle", "swatch": tints.crag}, {"text": "Coal (larger diamond, more coal)", "swatch": Color(0.08, 0.08, 0.1)},
		{"text": "A place for a dam", "swatch": Color(0.4, 1.0, 1.0)}, {"text": "Way round, open from the start", "swatch": Color(1.0, 0.95, 0.4)},
		{"text": "Straight road, shut by forest", "swatch": Color(1.0, 0.35, 0.3)}, {"text": ""}]
	for line in found.lines:
		var text: String = line
		while text.length() > 92:
			var cut := text.rfind(" ", 92)
			if cut < 20: cut = 92
			panel.append({"text": text.substr(0, cut), "size": 12})
			text = "    "+text.substr(cut+1)
		panel.append({"text": text, "size": 12})
	sheet.panel = panel
	var viewport := SubViewport.new()
	viewport.size = Vector2i(sheet.size)
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.add_child(sheet)
	root.add_child(viewport)
	for frame in range(3): await process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(ProjectSettings.globalize_path(PICTURE))
	print("Picture saved to ", PICTURE)

# ---- Drawing ----
# A shape is {d, box}: `d` gives metres from a point to the shape's edge, negative inside, and `box` bounds it.
func shape(d: Callable, x0: float, z0: float, x1: float, z1: float) -> Dictionary:
	return {"d": d, "box": Rect2(x0, z0, x1-x0, z1-z0)}

func ell(cx: float, cz: float, rx: float, rz: float) -> Dictionary:
	return shape(func(p: Vector2) -> float: return (Vector2((p.x-cx)/rx, (p.y-cz)/rz).length()-1.0)*minf(rx, rz), cx-rx, cz-rz, cx+rx, cz+rz)

## A box with rounded corners.
func box(x0: float, z0: float, x1: float, z1: float, radius: float) -> Dictionary:
	var centre := Vector2((x0+x1)*0.5, (z0+z1)*0.5)
	var half := Vector2((x1-x0)*0.5, (z1-z0)*0.5)
	var d := func(p: Vector2) -> float:
		var q := (p-centre).abs()-half+Vector2(radius, radius)
		return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length()+minf(maxf(q.x, q.y), 0.0)-radius
	return shape(d, x0, z0, x1, z1)

## A line with thickness: everything within `radius` of the segment.
func cap(ax: float, az: float, bx: float, bz: float, radius: float) -> Dictionary:
	var a := Vector2(ax, az)
	var b := Vector2(bx, bz)
	var d := func(p: Vector2) -> float:
		var along := clampf((p-a).dot(b-a)/maxf((b-a).length_squared(), 0.0001), 0.0, 1.0)
		return p.distance_to(a+(b-a)*along)-radius
	return shape(d, minf(ax, bx)-radius, minf(az, bz)-radius, maxf(ax, bx)+radius, maxf(az, bz)+radius)

## Several shapes as one.
func any(parts: Array) -> Dictionary:
	var merged: Rect2 = parts[0].box
	for part in parts: merged = merged.merge(part.box)
	var d := func(p: Vector2) -> float:
		var best := INF
		for part in parts: best = minf(best, part.d.call(p))
		return best
	return {"d": d, "box": merged}

## A shape with its edge moved out.
func grown(inner: Dictionary, by: float) -> Dictionary:
	return {"d": func(p: Vector2) -> float: return inner.d.call(p)-by, "box": inner.box.grow(by)}

## Paints the cells inside a shape on the west half, each with its partner in the east. `wobble` moves the edge by
## up to about that many metres. With `only`, just cells of those kinds are painted.
func fill(kind: int, what: Dictionary, wobble := 0.0, only: Array = []) -> void:
	var bounds: Rect2 = what.box.grow(wobble*2.0+1.0)
	for z in range(maxi(0, floori(bounds.position.y)), mini(SIZE, ceili(bounds.end.y)+1)):
		for x in range(maxi(0, floori(bounds.position.x)), mini(HALF, ceili(bounds.end.x)+1)):
			var d: float = what.d.call(Vector2(x+0.5, z+0.5))
			if wobble > 0.0: d += edge_noise.get_noise_2d(x, z)*wobble*2.0
			if d > 0.0: continue
			if not only.is_empty() and not int(cells[z*SIZE+x]) in only: continue
			put(x, z, kind)

func put(x: int, z: int, kind: int) -> void:
	if x < 0 or z < 0 or x >= SIZE or z >= SIZE: return
	var west := mini(x, SIZE-1-x)
	cells[z*SIZE+west] = kind
	cells[z*SIZE+SIZE-1-west] = kind

## Whether a spot is clear of every way that must stay open, with a margin.
func is_free(at: Vector2, margin: float) -> bool:
	for way in clear:
		var a: Vector2 = way[0]
		var b: Vector2 = way[1]
		var along := clampf((at-a).dot(b-a)/maxf((b-a).length_squared(), 0.0001), 0.0, 1.0)
		if at.distance_to(a+(b-a)*along) < way[2]+margin: return false
	for mark in marks:
		if mark.kind == "mine" and at.distance_to(mark.yard) < 20.0+margin: return false
	return true

## A coal field centred on a cell, row by row. With a belt, it stands inside its own round wood of that radius.
func coal_field(cx: int, cz: int, rows: Array, belt: float, tier: String) -> void:
	if belt > 0.0: fill(FOREST, ell(cx+0.5, cz+0.5, belt, belt), 0.4, [GRASS, DESERT, FOREST])
	var field: Array = []
	for row in range(rows.size()):
		for column in range(rows[row]):
			var cell := Vector2i(cx-rows[row]/2+column, cz-rows.size()/2+row)
			put(cell.x, cell.y, COAL)
			field.append(Vector2i(mini(cell.x, SIZE-1-cell.x), cell.y))
	marks.append({"kind": "coal", "tier": tier, "at": Vector2(cx+0.5, cz+0.5), "cells": field})
