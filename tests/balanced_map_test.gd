extends SceneTree
# Headless: the balanced two-player map (docs/BALANCED_MAP.md). Checks the map data against its layout PNG, that
# the two sides are the same land turned half a circle, that both starts measure the same to iron, expansions and
# coal, that every coal field is shut inside forest, that the bases are joined by separate routes, and that the
# starts and expansion sites can be built on. Prints the metrics for both sides and an estimate of the opening
# worked out from unit speeds and costs. It cannot judge how the map plays.
const MapLayout := preload("res://scripts/tools/map_layout.gd")
const MAP := "res://assets/maps/balanced"
const SCENE := "res://scenes/maps/balanced_skirmish.tscn"
const SIZE := 500
const DEPOT_SIZE := Vector2i(10, 10)
## Fewest forest cells a worker must clear before any coal of a field is in reach.
const MIN_CLEAR := 8
const MIN_CLEAR_CONTESTED := 10
## Routes between the bases count as separate when they stay this many cells apart outside the two mains.
## That is wider than any lane, so two routes can never be two sides of the same lane.
const ROUTE_GAP := 24
const MAIN_RADIUS := 50.0

var game: Node3D
var ground: Node3D
var cells: PackedByteArray
var nav := AStarGrid2D.new()
var reach: float

func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false

func open(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < SIZE and cell.y < SIZE and (cells[cell.y*SIZE+cell.x] == 0 or cells[cell.y*SIZE+cell.x] == 2)
func to_cell(point: Vector3) -> Vector2i:
	return Vector2i(floori(point.x+SIZE*0.5), floori(point.z+SIZE*0.5))
func centre(cell: Vector2i) -> Vector2:
	return Vector2(cell.x+0.5, cell.y+0.5)
## A marker's place in cell coordinates, where cell x,z covers x to x+1 and z to z+1.
func site_point(marker: Node3D) -> Vector2:
	return Vector2(marker.position.x+SIZE*0.5, marker.position.z+SIZE*0.5)
func turned(cell: Vector2i) -> Vector2i:
	return MapLayout.turned(cell)

## Length in metres of the shortest ground path over terrain alone (no units or buildings), or -1.
func path_length(from: Vector2i, to: Vector2i) -> float:
	if not open(from) or not open(to): return -1.0
	var path := nav.get_id_path(from, to)
	if path.is_empty(): return -1.0
	var total := 0.0
	for i in range(1, path.size()): total += Vector2(path[i]-path[i-1]).length()
	return total
## Shortest path from a cell to any open cell within `radius` metres of a point (in cell coordinates).
func path_within(from: Vector2i, target: Vector2, radius: float) -> float:
	var best := -1.0
	var span := ceili(radius)+1
	for z in range(floori(target.y)-span, floori(target.y)+span+1):
		for x in range(floori(target.x)-span, floori(target.x)+span+1):
			var cell := Vector2i(x, z)
			if not open(cell) or centre(cell).distance_to(target) > radius+0.0001: continue
			var length := path_length(from, cell)
			if length >= 0.0 and (best < 0.0 or length < best): best = length
	return best

func run() -> void:
	# ---- Map data ----
	cells = FileAccess.get_file_as_bytes(MAP+"/terrain_cells.bin")
	if not check(cells.size() == SIZE*SIZE, "terrain_cells.bin is not 500 x 500"): return
	var layout: Dictionary = MapLayout.read(MAP+"/layout.png")
	if not check(layout.errors.is_empty(), "Layout PNG has pixels outside the palette: "+str(layout.errors)): return
	if not check(layout.cells == cells, "terrain_cells.bin does not match layout.png; run build_map_data.gd"): return
	var data := Image.load_from_file(ProjectSettings.globalize_path(MAP+"/terrain_data.png"))
	if not check(data != null and data.get_size() == Vector2i(SIZE, SIZE), "terrain_data.png missing or the wrong size"): return
	data.convert(Image.FORMAT_RGB8)
	var bytes := data.get_data()
	for i in range(SIZE*SIZE):
		if bytes[i*3] != cells[i]:
			check(false, "terrain_data.png disagrees with the cells at %d,%d" % [i%SIZE, i/SIZE]); return
	for i in range(SIZE*SIZE/2):
		if cells[i] != cells[SIZE*SIZE-1-i]:
			check(false, "Layout is not symmetric at %d,%d" % [i%SIZE, i/SIZE]); return
	var counts := MapLayout.counts(cells)
	print("Category counts:")
	for kind in range(counts.size()): print("  %-9s %6d  %5.1f%%" % [MapLayout.NAMES[kind], counts[kind], counts[kind]*100.0/(SIZE*SIZE)])
	if not check(counts[3] >= SIZE*SIZE/10, "Forest should cover at least a tenth of the map"): return
	if not check(counts[5] > 0 and counts[6] > 0, "Map needs iron and coal"): return
	for i in range(SIZE*SIZE):
		if cells[i] >= 5:
			var edge := mini(mini(i%SIZE, i/SIZE), mini(SIZE-1-i%SIZE, SIZE-1-i/SIZE))
			if not check(edge >= 30, "A resource cell sits %d cells from the map edge" % edge): return

	# ---- The playable scene ----
	game = load(SCENE).instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	for unit in get_nodes_in_group("units"): unit.set_process(false)
	ground = game.ground
	if not check(ground.cells_path == MAP+"/terrain_cells.bin" and ground.terrain_cells == cells, "Scene does not play on the balanced cells"): return
	if not check(game.testing_coal_amount == 0 and not game.has_node("Entities/Resources/TestingCoalPile"), "Balanced map should have no testing coal pile"): return
	if not check(not game.testing_iron_grant and game.depot.iron == 0 and game.depot.energy == game.depot.rules.initial_energy, "Start should be %d energy and no iron" % game.depot.rules.initial_energy): return
	var minimap: TextureRect = game.get_node("Interface/Bottom/Body/Row/MapColumn/Map/Terrain")
	if not check(minimap.texture != null and minimap.texture.resource_path == MAP+"/layout.png", "Minimap does not show the balanced layout"): return
	var players := 0
	var hostiles := 0
	for unit in get_nodes_in_group("units"):
		if unit.team == "player": players += 1
		else: hostiles += 1
	if not check(players == 2 and game.has_node("Entities/Units/Infantry") and game.get_node("Entities/Units/StarterTruck").fuel == game.get_node("Entities/Units/StarterTruck").fuel_rules.reserve_capacity, "Start A should be one Infantry and one fuelled Cargo truck"): return
	if not check(hostiles >= 6, "Start B and the contested coal should be guarded"): return
	reach = game.get_node("Entities/Units/Infantry").interaction_range

	nav.region = Rect2i(0, 0, SIZE, SIZE)
	nav.cell_size = Vector2.ONE
	nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	nav.update()
	for i in range(SIZE*SIZE):
		if cells[i] != 0 and cells[i] != 2: nav.set_point_solid(Vector2i(i%SIZE, i/SIZE), true)

	# ---- Starts and sites mirror each other ----
	var sites := game.get_node("Sites")
	var start_a := to_cell(sites.get_node("PlayerStart").position)
	var start_b := to_cell(sites.get_node("EnemyStart").position)
	var point_a := site_point(sites.get_node("PlayerStart"))
	var point_b := site_point(sites.get_node("EnemyStart"))
	if not check(to_cell(game.depot.global_position) == start_a and game.depot.global_position.distance_to(sites.get_node("PlayerStart").position) < 0.01, "The player's Depot was moved off start A"): return
	for pair in [["PlayerStart", "EnemyStart"], ["SafeExpansionA", "SafeExpansionB"], ["ExposedExpansionA", "ExposedExpansionB"]]:
		if not check(sites.get_node(pair[0]).position.is_equal_approx(-sites.get_node(pair[1]).position), "%s and %s are not opposite each other" % pair): return
	var mine_a: Node3D = game.get_node("Entities/Buildings/IronMine")
	var mine_b: Node3D = game.get_node("Entities/Buildings/IronMineB")
	if not check(mine_a.global_position.is_equal_approx(-mine_b.global_position) and mine_a.remaining == mine_b.remaining and mine_a.remaining > 0, "Starter mines are not mirrored"): return
	# Footprints: each Depot site, and room around each start to build a base.
	for marker in sites.get_children():
		if not marker is Marker3D: continue
		var corner: Vector2i = to_cell(marker.position)-DEPOT_SIZE/2
		for z in range(corner.y, corner.y+DEPOT_SIZE.y):
			for x in range(corner.x, corner.x+DEPOT_SIZE.x):
				if not check(open(Vector2i(x, z)), "%s footprint is not buildable at %d,%d" % [marker.name, x, z]): return
	if not check(ground.is_footprint_valid(start_b-DEPOT_SIZE/2, DEPOT_SIZE), "Start B's Depot footprint is not free in the scene"): return
	for start in [start_a, start_b]:
		var buildable := 0
		for z in range(start.y-20, start.y+20):
			for x in range(start.x-20, start.x+20):
				if open(Vector2i(x, z)): buildable += 1
		if not check(buildable >= 1500, "Start at %s has only %d of 1600 cells to build on" % [start, buildable]): return

	# ---- Ground reachable from start A, and how much forest stands between it and anything else ----
	var from_a := start_a+Vector2i(DEPOT_SIZE.x/2+1, 0)
	var from_b := turned(from_a)
	if not check(open(from_a) and open(from_b), "Cells beside the starts are blocked"): return
	var cost := PackedInt32Array()
	var parent := PackedInt32Array()
	cost.resize(SIZE*SIZE); cost.fill(-1)
	parent.resize(SIZE*SIZE); parent.fill(-1)
	var frontier: Array[int] = [from_a.y*SIZE+from_a.x]
	cost[frontier[0]] = 0
	var forest_edge: Array[int] = []
	var head := 0
	while head < frontier.size():
		var i := frontier[head]; head += 1
		for step in [1, -1, SIZE, -SIZE]:
			var j: int = i+step
			if j < 0 or j >= SIZE*SIZE or (absi(step) == 1 and j/SIZE != i/SIZE) or cost[j] >= 0: continue
			if cells[j] == 0 or cells[j] == 2: cost[j] = 0; frontier.append(j)
			elif cells[j] == 3: cost[j] = 1; parent[j] = i; forest_edge.append(j)
	if not check(cost[from_b.y*SIZE+from_b.x] == 0, "No ground path between the starts"): return
	# Into the forest: cost is the number of forest cells cleared to stand on a cell.
	head = 0
	while head < forest_edge.size():
		var i := forest_edge[head]; head += 1
		for step in [1, -1, SIZE, -SIZE]:
			var j: int = i+step
			if j < 0 or j >= SIZE*SIZE or (absi(step) == 1 and j/SIZE != i/SIZE) or cost[j] >= 0 or cells[j] != 3: continue
			cost[j] = cost[i]+1; parent[j] = i; forest_edge.append(j)

	# ---- Coal fields ----
	var fields: Array[Dictionary] = []
	for field in ground.coal_fields:
		var entry := {"cells": field.cells, "centre": to_cell(field.center), "coal": ground.coal_field_remaining(field), "clear": -1, "stand": -1}
		var span := ceili(reach)+1
		for coal in field.cells:
			for z in range(coal.y-span, coal.y+span+1):
				for x in range(coal.x-span, coal.x+span+1):
					if x < 0 or z < 0 or x >= SIZE or z >= SIZE or centre(Vector2i(x, z)).distance_to(centre(coal)) > reach+0.0001: continue
					var c: int = cost[z*SIZE+x]
					if c >= 0 and (entry.clear < 0 or c < entry.clear): entry.clear = c; entry.stand = z*SIZE+x
		if not check(entry.clear != 0, "Coal field at %s can be reached without clearing forest" % entry.centre): return
		if not check(entry.clear > 0, "Coal field at %s cannot be reached even by clearing forest" % entry.centre): return
		# Walk back out of the forest: one corridor to clear, and every open cell such a corridor can start from.
		var corridor: Array[Vector2i] = []
		var at: int = entry.stand
		while cells[at] == 3:
			corridor.append(Vector2i(at%SIZE, at/SIZE))
			at = parent[at]
		entry["corridor"] = corridor
		entry["corridor_start"] = Vector2i(at%SIZE, at/SIZE)
		var approaches := {}
		var seen := {}
		var back: Array[int] = []
		for coal in field.cells:
			for z in range(coal.y-span, coal.y+span+1):
				for x in range(coal.x-span, coal.x+span+1):
					if x < 0 or z < 0 or x >= SIZE or z >= SIZE or centre(Vector2i(x, z)).distance_to(centre(coal)) > reach+0.0001: continue
					if cost[z*SIZE+x] == entry.clear and not seen.has(z*SIZE+x): seen[z*SIZE+x] = true; back.append(z*SIZE+x)
		while not back.is_empty():
			var i: int = back.pop_back()
			for step in [1, -1, SIZE, -SIZE]:
				var j: int = i+step
				if j < 0 or j >= SIZE*SIZE or (absi(step) == 1 and j/SIZE != i/SIZE) or cost[j] != cost[i]-1 or seen.has(j): continue
				seen[j] = true
				if cost[j] == 0: approaches[Vector2i(j%SIZE, j/SIZE)] = true
				else: back.append(j)
		entry["approaches"] = approaches.keys()
		fields.append(entry)
	if not check(fields.size() >= 8 and fields.size() <= 12, "Expected 3-5 coal fields a side plus 1-2 contested, found %d" % fields.size()): return
	var richest := 0
	for entry in fields: richest = maxi(richest, entry.coal)
	var per_side := {"A": [], "B": []}
	var contested: Array = []
	for entry in fields:
		# Distance to a field is to the nearest open cell a shortest clearing can start from.
		entry["to_a"] = INF; entry["to_b"] = INF
		for approach in entry.approaches:
			var a := path_length(from_a, approach)
			var b := path_length(from_b, approach)
			if a >= 0.0 and a < entry.to_a: entry.to_a = a; entry["approach"] = approach
			if b >= 0.0: entry.to_b = minf(entry.to_b, b)
		if not check(entry.to_a < INF and entry.to_b < INF, "No path to the edge of the coal field at %s" % entry.centre): return
		# A contested field is about as far from one start as from the other.
		entry["contested"] = absf(entry.to_a-entry.to_b) <= 0.1*minf(entry.to_a, entry.to_b)
		if entry.contested: contested.append(entry)
		elif entry.to_a < entry.to_b: per_side.A.append(entry)
		else: per_side.B.append(entry)
		var need := MIN_CLEAR_CONTESTED if entry.contested else MIN_CLEAR
		if not check(entry.clear >= need, "Forest around the coal at %s is only %d cells to clear; expected %d" % [entry.centre, entry.clear, need]): return
	if not check(per_side.A.size() == per_side.B.size() and per_side.A.size() >= 3 and per_side.A.size() <= 5, "Each side should have 3-5 coal fields: A %d, B %d" % [per_side.A.size(), per_side.B.size()]): return
	if not check(contested.size() >= 1 and contested.size() <= 2, "Expected 1-2 contested coal fields, found %d" % contested.size()): return
	for entry in contested:
		if not check(entry.coal == richest and entry.coal > per_side.A[0].coal, "Contested coal should be worth more than a side field"): return
	for side in ["A", "B"]:
		per_side[side].sort_custom(func(a, b): return (a.to_a if side == "A" else a.to_b) < (b.to_a if side == "A" else b.to_b))
		var start: Vector2 = point_a if side == "A" else point_b
		for entry in per_side[side]:
			if not check(centre(entry.centre).distance_to(start) > game.depot.rules.construction_radius+10.0, "Coal at %s is too close to start %s" % [entry.centre, side]): return
			if not check(absi(entry.coal-1000) <= 100, "A side field should hold about 1,000 coal, not %d" % entry.coal): return
	# Clearing the measured corridor is what opens a field: check it on the live terrain for the nearest field.
	var first: Dictionary = per_side.A[0]
	var source: Node3D = ground.coal_source(first.cells[0])
	var Approach = load("res://scripts/units/interaction_approach.gd")
	var before := 0
	for coal in first.cells: before += Approach.candidates(ground, ground.coal_source(coal), reach, MobilityRules.Layer.GROUND, "").size()
	if not check(source != null and before == 0, "Live terrain lets a worker stand within reach of enclosed coal"): return
	for cell in first.corridor:
		if not check(ground.clear_forest(cell), "Corridor cell %s is not forest on the live terrain" % cell): return
	var after := 0
	for coal in first.cells:
		for cell in Approach.candidates(ground, ground.coal_source(coal), reach, MobilityRules.Layer.GROUND, ""):
			if not ground.actor_path(first.corridor_start, cell, MobilityRules.Layer.GROUND, "").is_empty(): after += 1
	if not check(after > 0, "Clearing %d forest cells did not open the coal at %s" % [first.clear, first.centre]): return

	# ---- Distances from each start ----
	var rows: Array = []
	var mine_cell := Vector2(mine_a.global_position.x+SIZE*0.5, mine_a.global_position.z+SIZE*0.5)
	var mine_cell_b := Vector2(SIZE, SIZE)-mine_cell
	rows.append(["Start to starter mine (stand in reach)", path_within(from_a, mine_cell, reach), path_within(from_b, mine_cell_b, reach)])
	var safe_a := to_cell(sites.get_node("SafeExpansionA").position)
	# A Depot site is the corner where four cells meet, so its partner's centre cell is found by turning the cell.
	var safe_b := turned(safe_a)
	var exposed_a := to_cell(sites.get_node("ExposedExpansionA").position)
	var exposed_b := turned(exposed_a)
	rows.append(["Start to safe expansion site", path_length(from_a, safe_a), path_length(from_b, safe_b)])
	rows.append(["Start to exposed expansion site", path_length(from_a, exposed_a), path_length(from_b, exposed_b)])
	rows.append(["Safe expansion to enemy start", path_length(safe_a, from_b), path_length(safe_b, from_a)])
	rows.append(["Exposed expansion to enemy start", path_length(exposed_a, from_b), path_length(exposed_b, from_a)])
	for n in range(per_side.A.size()):
		rows.append(["Start to coal field %d (forest edge)" % (n+1), per_side.A[n].to_a, per_side.B[n].to_b])
		rows.append(["  forest cells to clear, field %d" % (n+1), float(per_side.A[n].clear), float(per_side.B[n].clear)])
		rows.append(["  coal in field %d" % (n+1), float(per_side.A[n].coal), float(per_side.B[n].coal)])
	var contested_b := contested.duplicate()
	contested.sort_custom(func(a, b): return a.to_a < b.to_a)
	contested_b.sort_custom(func(a, b): return a.to_b < b.to_b)
	for n in range(contested.size()):
		rows.append(["Start to contested coal %d (forest edge)" % (n+1), contested[n].to_a, contested_b[n].to_b])
		rows.append(["  forest cells to clear, contested %d" % (n+1), float(contested[n].clear), float(contested_b[n].clear)])
		rows.append(["  coal in contested %d" % (n+1), float(contested[n].coal), float(contested_b[n].coal)])
	# The coal each safe expansion works: the field nearest to it by ground.
	var safe_coal: Array[float] = [INF, INF]
	var safe_field := {}
	for entry in per_side.A:
		for approach in entry.approaches:
			var length := path_length(safe_a, approach)
			if length >= 0.0 and length < safe_coal[0]: safe_coal[0] = length; safe_field = entry
	for entry in per_side.B:
		for approach in entry.approaches:
			var length := path_length(safe_b, approach)
			if length >= 0.0: safe_coal[1] = minf(safe_coal[1], length)
	rows.append(["Safe expansion to its coal (forest edge)", safe_coal[0], safe_coal[1]])
	rows.append(["  forest cells to clear there", float(safe_field.clear), float(safe_field.clear)])
	# Safe and exposed: with the owner's main closed off, the enemy can still walk to the exposed expansion but
	# has no ground route to the safe one.
	var closed: Array[Vector2i] = []
	for z in range(SIZE):
		for x in range(SIZE):
			var cell := Vector2i(x, z)
			if open(cell) and (centre(cell).distance_to(point_a) <= MAIN_RADIUS or centre(cell).distance_to(point_b) <= MAIN_RADIUS): closed.append(cell)
	for cell in closed: nav.set_point_solid(cell, true)
	var around := [path_length(exposed_a, exposed_b), path_length(safe_a, exposed_b), path_length(safe_b, exposed_a)]
	for cell in closed: nav.set_point_solid(cell, false)
	if not check(around[0] > 0.0, "The exposed expansions should be joined by a route that passes neither main"): return
	if not check(around[1] < 0.0 and around[2] < 0.0, "A safe expansion can be reached without passing its owner's main"): return
	rows.append(["Exposed expansion to exposed expansion, no mains", around[0], around[0]])
	# Iron: every start and expansion has a field inside a Depot's construction radius.
	var radius: float = game.depot.rules.construction_radius
	for pair in [["Start", point_a, point_b], ["Safe expansion", site_point(sites.get_node("SafeExpansionA")), site_point(sites.get_node("SafeExpansionB"))], ["Exposed expansion", site_point(sites.get_node("ExposedExpansionA")), site_point(sites.get_node("ExposedExpansionB"))]]:
		var found: Array = []
		for site in [pair[1], pair[2]]:
			var ore := 0
			for z in range(floori(site.y-radius)-1, ceili(site.y+radius)+1):
				for x in range(floori(site.x-radius)-1, ceili(site.x+radius)+1):
					if x >= 0 and z >= 0 and x < SIZE and z < SIZE and cells[z*SIZE+x] == 5 and centre(Vector2i(x, z)).distance_to(site) <= radius: ore += 1
			found.append(float(ore))
		if not check(found[0] >= 16, "%s has no iron field inside %d m" % [pair[0], roundi(radius)]): return
		rows.append(["%s: iron cells within %d m" % [pair[0], roundi(radius)], found[0], found[1]])
	for start in [point_a, point_b]:
		for i in range(SIZE*SIZE):
			if cells[i] == 6 and centre(Vector2i(i%SIZE, i/SIZE)).distance_to(start) <= radius:
				check(false, "Coal inside a start's construction radius"); return
	var wood := []
	for start in [start_a, start_b]:
		var trees := 0
		for z in range(start.y-45, start.y+45):
			for x in range(start.x-45, start.x+45):
				if cells[z*SIZE+x] == 3: trees += 1
		wood.append(float(trees))
	if not check(wood[0] >= 40, "Start has no forest nearby for wood"): return
	rows.append(["Start: forest cells within 45 m", wood[0], wood[1]])

	# ---- Separate routes between the bases ----
	var routes: Array[float] = []
	var blocked: Array[Vector2i] = []
	while routes.size() < 4:
		var path := nav.get_id_path(from_a, from_b)
		if path.is_empty(): break
		var length := 0.0
		for i in range(1, path.size()): length += Vector2(path[i]-path[i-1]).length()
		routes.append(length)
		# Close this route, and a margin either side of it, everywhere outside the two mains.
		for cell in path:
			if centre(cell).distance_to(point_a) <= MAIN_RADIUS or centre(cell).distance_to(point_b) <= MAIN_RADIUS: continue
			for dz in range(-ROUTE_GAP, ROUTE_GAP+1):
				for dx in range(-ROUTE_GAP, ROUTE_GAP+1):
					var near := cell+Vector2i(dx, dz)
					if open(near) and not nav.is_point_solid(near): nav.set_point_solid(near, true); blocked.append(near)
	for cell in blocked: nav.set_point_solid(cell, false)
	if not check(routes.size() >= 2, "Only %d separate ground route between the bases" % routes.size()): return

	print("\nMetrics, in metres of ground path unless the row says otherwise:")
	print("  %-44s %10s %10s" % ["", "Start A", "Start B"])
	for row in rows:
		print("  %-44s %10.1f %10.1f" % row)
		if not check(row[1] >= 0.0 and absf(row[1]-row[2]) <= 0.05, "The two sides differ on '%s': %.2f against %.2f" % row): return
	print("  Separate routes between the starts: %d, of %s m" % [routes.size(), ", ".join(routes.map(func(l): return "%.0f" % l))])

	_opening_estimate(from_a, mine_cell, safe_a, safe_field, safe_coal[0])
	print("BALANCED_MAP_TEST_PASSED")
	quit()

# The opening, worked out from speeds and costs with nothing played: when each step could happen at the earliest
# if the player makes no mistakes. Printed for the PR; nothing here is asserted.
func _opening_estimate(from_a: Vector2i, mine_cell: Vector2, safe_a: Vector2i, coal: Dictionary, to_belt: float) -> void:
	var worker: Node3D = game.get_node("Entities/Units/Infantry")
	var depot: Node3D = game.depot
	var walk: float = worker.move_speed
	var load_seconds: float = ceilf(float(worker.carry_capacity)/worker.harvest_amount)*worker.harvest_interval
	var truck: Node3D = load("res://scenes/gameplay/depot_truck.tscn").instantiate()
	var drive: float = truck.move_speed
	truck.free()
	var depot_point := Vector2(depot.global_position.x+SIZE*0.5, depot.global_position.z+SIZE*0.5)
	var to_mine := path_within(to_cell(worker.global_position), mine_cell, reach)
	# One leg of the mining trip: from in reach of the mine to in reach of the Depot.
	var leg := INF
	var span := ceili(reach)+1
	for z in range(floori(mine_cell.y)-span, floori(mine_cell.y)+span+1):
		for x in range(floori(mine_cell.x)-span, floori(mine_cell.x)+span+1):
			if open(Vector2i(x, z)) and centre(Vector2i(x, z)).distance_to(mine_cell) <= reach:
				var d := path_within(Vector2i(x, z), depot_point, depot.dropoff_range)
				if d >= 0.0: leg = minf(leg, d)
	var mining_starts := to_mine/walk
	var loads_for_truck: int = ceili(float(depot.rules.truck_iron_cost)/worker.carry_capacity)
	var truck_started := mining_starts+loads_for_truck*load_seconds+(loads_for_truck*2-1)*leg/walk
	depot.pending.append("truck")
	var truck_built: float = depot.current_seconds()
	depot.pending.clear()
	var to_safe := path_length(from_a, safe_a)
	var second_depot := truck_started+truck_built+to_safe/drive
	# The new Depot's Infantry cuts into the nearest coal, carrying each load of wood back to that Depot.
	var wood: int = ground.harvesting_rules.forest_wood_per_tile
	var saw: float = ceilf(float(wood)/worker.harvest_amount)*worker.harvest_interval
	var carry_leg := maxf(0.0, to_belt-depot.dropoff_range)
	var per_cell: float = saw+ceilf(float(wood)/worker.carry_capacity)*2.0*carry_leg/walk
	var coal_reached: float = second_depot+to_belt/walk+coal.clear*per_cell
	print("\nOpening estimate for start A (arithmetic from speeds and costs, not played):")
	print("  Infantry %.1f m/s, %d per %.1f s blow, carries %d. Depot truck %.1f m/s, built in %.1f s, costs %d iron." % [walk, worker.harvest_amount, worker.harvest_interval, worker.carry_capacity, drive, truck_built, depot.rules.truck_iron_cost])
	print("  Mining starts          %s   (walk %.1f m to the starter mine; target about 0:10)" % [_clock(mining_starts), to_mine])
	print("  Depot truck started    %s   (%d loads over a %.1f m leg; target about 1:00)" % [_clock(truck_started), loads_for_truck, leg])
	print("  Second Depot down      %s   (truck build, then %.1f m to the safe expansion; deploy animation not counted; target about 2:00)" % [_clock(second_depot), to_safe])
	print("  First coal in reach    %s   (walk %.1f m, clear %d forest cells at %.1f s each, wood carried %.1f m to the new Depot; target about 4:00)" % [_clock(coal_reached), to_belt, coal.clear, per_cell, carry_leg])
	var factory_building: Node3D = load("res://scenes/gameplay/tank_factory.tscn").instantiate()
	var factory: ProductionBuildingStats = factory_building.stats
	factory_building.free()
	var tank: UnitStats = load("res://assets/units/tank.tres")
	var iron_needed: int = depot.rules.truck_iron_cost+factory.iron_cost+tank.iron_cost
	var energy_needed: int = depot.rules.truck_energy_cost+factory.energy_cost+tank.energy_cost
	var loads := ceili(float(iron_needed)/worker.carry_capacity)
	var iron_ready := mining_starts+loads*load_seconds+(loads*2-1)*leg/walk
	# First Tank, built at the main. With new vehicles starting full it only waits for iron. With new vehicles
	# starting empty (FuelRules.testing_full_tanks off) it also waits for a tank of coal dug at the safe expansion
	# and brought home by the starter Cargo truck, which is already waiting there.
	var built_in: float = ceilf(float(factory.iron_cost)/worker.harvest_amount)*worker.harvest_interval
	var tank_fuelled := iron_ready+built_in+factory.print_seconds
	var fuel: FuelRules = load("res://assets/economy/fuel_tank.tres")
	var supply: SupplyRules = load("res://assets/economy/supply_rules.tres")
	var coal_loads := ceili(fuel.reserve_capacity/worker.carry_capacity)
	var coal_dug: float = coal_reached+coal_loads*(load_seconds+2.0*(carry_leg+reach)/walk)
	var coal_home: float = coal_dug+supply.transfer_seconds*2.0+to_safe/supply.cargo_speed
	var tank_empty := maxf(tank_fuelled, coal_home)+fuel.reserve_capacity/fuel.refuel_coal_per_second
	print("  Iron for truck, factory and Tank  %s   (%d iron = %d loads by the first Infantry alone; the three cost %d of the starting %d energy)" % [_clock(iron_ready), iron_needed, loads, energy_needed, depot.rules.initial_energy])
	print("  First Tank, vehicles start full   %s   (as shipped: factory built in over %.0f s, printed in %.0f s; target about 6:00)" % [_clock(tank_fuelled), built_in, factory.print_seconds])
	print("  First Tank, vehicles start empty  %s   (%d coal dug by %s, trucked %.1f m home at %.1f m/s, then fuelled; target about 6:00)" % [_clock(tank_empty), int(fuel.reserve_capacity), _clock(coal_dug), to_safe, supply.cargo_speed])

func _clock(seconds: float) -> String:
	return "%d:%02d" % [int(seconds)/60, int(seconds)%60]
