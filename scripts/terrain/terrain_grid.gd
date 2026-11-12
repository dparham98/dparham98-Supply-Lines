extends MeshInstance3D

enum Terrain { GRASS, WATER, DESERT, FOREST, MOUNTAIN, ORE, COAL }
const TERRAIN_NAMES = ["Grass", "Water", "Desert", "Forest", "Mountains", "Ore deposit (unassigned)", "Coal deposit"]
var grid_size := Vector2i(500, 500)
var tile_size := 1.0
## The map this grid plays on: one category byte per cell, row by row. Each map has its own file
## (docs/BALANCED_MAP.md); the terrain scene's material, mountains and scenery must be baked from the same file.
@export_file("*.bin") var cells_path := "res://assets/maps/terrain_cells.bin"
@export var harvesting_rules: HarvestingRules
var forest_reserves: Dictionary = {}
var iron_reserves: Dictionary = {}
var forest_sources: Dictionary = {}
var iron_mines: Dictionary = {}
var coal_reserves: Dictionary = {}
var coal_sources: Dictionary = {}
## Coal cells dug out this match. They are open ground from then on.
var cleared_coal: Dictionary = {}
## Each connected group of Coal cells: {cells: Array[Vector2i], center: Vector3}.
var coal_fields: Array[Dictionary] = []
var _coal_field_of: Dictionary = {}
signal coal_depleted(cell: Vector2i)
var tiles: Array = []
var terrain_cells: PackedByteArray
var navigation_grid := AStarGrid2D.new()
var forest_navigation: AStarGrid2D
var air_navigation: AStarGrid2D
var air_occupancy: Dictionary = {}
var cleared_forest: Dictionary = {}
signal forest_cleared(cell: Vector2i)
## Mines and mine sites hide the ore rocks drawn on and around their footprint (docs/IRON_MINE_MODEL.md).
signal ore_cover_changed(cells: Array, covered: bool)
## Cell -> how many mines or mine sites cover its ore rocks.
var ore_covered: Dictionary = {}
var _ore_covers: Dictionary = {}
var _clearing_mask: Image
var _clearing_texture: ImageTexture
var _mask_dirty := false

func _ready() -> void:
	terrain_cells = FileAccess.get_file_as_bytes(cells_path)
	assert(terrain_cells.size() == grid_size.x * grid_size.y)
	_find_coal_fields()
	navigation_grid.region = Rect2i(Vector2i.ZERO, grid_size)
	navigation_grid.cell_size = Vector2.ONE
	navigation_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	navigation_grid.update()
	tiles.resize(grid_size.x * grid_size.y)
	for z in range(grid_size.y):
		for x in range(grid_size.x):
			var t := int(terrain_cells[z * grid_size.x + x])
			var open := t == Terrain.GRASS or t == Terrain.DESERT
			tiles[z * grid_size.x + x] = {"terrain": t, "terrain_buildable": open, "walkable": open, "buildable": open, "occupied_by": null}
			navigation_grid.set_point_solid(Vector2i(x, z), not open)
	# State texture belongs to this match, never to the shared saved material/map.
	if material_override is ShaderMaterial:
		material_override = material_override.duplicate()
		_clearing_mask = Image.create(grid_size.x,grid_size.y,false,Image.FORMAT_R8)
		_clearing_mask.fill(Color.BLACK)
		_clearing_texture = ImageTexture.create_from_image(_clearing_mask)
		material_override.set_shader_parameter("cleared_cells",_clearing_texture)
	print("Terrain grid ready: ", tiles.size(), " cells")

func is_tile_in_bounds(pos: Vector2i) -> bool:
	return Rect2i(Vector2i.ZERO, grid_size).has_point(pos)

func get_terrain(pos: Vector2i) -> int:
	return int(tiles[pos.y * grid_size.x + pos.x]["terrain"]) if is_tile_in_bounds(pos) else -1

func get_tile_at_position(world_pos: Vector3) -> Variant:
	var local := to_local(world_pos)
	var pos := Vector2i(floori(local.x / tile_size + grid_size.x * 0.5), floori(local.z / tile_size + grid_size.y * 0.5))
	return pos if is_tile_in_bounds(pos) else null

func tile_to_world(pos: Vector2i, height := 0.0) -> Vector3:
	return to_global(Vector3((pos.x + 0.5 - grid_size.x * 0.5) * tile_size, height, (pos.y + 0.5 - grid_size.y * 0.5) * tile_size))

func set_tile_feature(pos: Vector2i, feature: String, value) -> void:
	if not is_tile_in_bounds(pos): return
	var tile: Dictionary = tiles[pos.y * grid_size.x + pos.x]
	# Existing unit scripts may release an occupied cell; they must never make water/ore buildable.
	if feature == "buildable": tile[feature] = bool(value) and bool(tile["terrain_buildable"])
	elif feature == "occupied_by": tile[feature] = value
	else: return
	_sync_navigation(pos)

func is_tile_valid(pos: Vector2i) -> bool:
	if not is_tile_in_bounds(pos): return false
	var tile: Dictionary = tiles[pos.y * grid_size.x + pos.x]
	return bool(tile["terrain_buildable"]) and bool(tile["buildable"]) and tile["occupied_by"] == null

func is_footprint_valid(pos: Vector2i, size: Vector2i) -> bool:
	if not is_tile_in_bounds(pos) or not is_tile_in_bounds(pos + size - Vector2i.ONE): return false
	for z in range(pos.y, pos.y + size.y):
		for x in range(pos.x, pos.x + size.x):
			if not is_tile_valid(Vector2i(x, z)) or tiles[z*grid_size.x+x].has("rail"): return false
	return true

func find_buildable_footprint(origin: Vector2i, size: Vector2i) -> Vector2i:
	if is_footprint_valid(origin, size): return origin
	for radius in range(1, maxi(grid_size.x, grid_size.y)):
		for offset in range(-radius, radius + 1):
			for p in [origin + Vector2i(offset, -radius), origin + Vector2i(offset, radius), origin + Vector2i(-radius, offset), origin + Vector2i(radius, offset)]:
				if is_footprint_valid(p, size): return p
	return Vector2i(-1, -1)

func find_nearest_open_tile(origin: Vector2i) -> Vector2i:
	return find_buildable_footprint(origin, Vector2i.ONE)

func get_terrain_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	if not is_tile_in_bounds(start) or not is_tile_valid(goal): return []
	# The starting cell is occupied by this unit. Temporarily permit only that point.
	var was_solid := navigation_grid.is_point_solid(start)
	navigation_grid.set_point_solid(start, false)
	var path: Array[Vector2i] = navigation_grid.get_id_path(start, goal)
	navigation_grid.set_point_solid(start, was_solid)
	return path

func print_tile_state(pos: Vector2i) -> void:
	if is_tile_in_bounds(pos): print("Tile ", pos, ": ", tiles[pos.y * grid_size.x + pos.x])


# Existing ground APIs stay available for legacy actors, construction and logistics.
func can_traverse(pos: Vector2i, layer: int = 0, owner: String = "") -> bool:
	if not is_tile_in_bounds(pos): return false
	if layer == MobilityRules.Layer.AIR:
		return not air_occupancy.has(pos) or (not owner.is_empty() and air_occupancy[pos] == owner)
	var tile: Dictionary = tiles[pos.y*grid_size.x+pos.x]
	if tile.occupied_by != null and (owner.is_empty() or tile.occupied_by != owner): return false
	if layer == MobilityRules.Layer.FOREST and tile.terrain == Terrain.FOREST: return true
	return bool(tile.terrain_buildable) and bool(tile.buildable)
func _sync_navigation(pos: Vector2i) -> void:
	navigation_grid.set_point_solid(pos,not can_traverse(pos))
	if forest_navigation != null: forest_navigation.set_point_solid(pos,not can_traverse(pos,MobilityRules.Layer.FOREST))
func set_air_occupant(pos: Vector2i, owner: String, occupied: bool) -> void:
	if not is_tile_in_bounds(pos): return
	if occupied:
		assert(can_traverse(pos,MobilityRules.Layer.AIR,owner))
		air_occupancy[pos] = owner
	elif air_occupancy.get(pos) == owner: air_occupancy.erase(pos)
	if air_navigation != null: air_navigation.set_point_solid(pos,air_occupancy.has(pos))
func navigation_for(layer: int) -> AStarGrid2D:
	if layer == MobilityRules.Layer.GROUND: return navigation_grid
	var grid := forest_navigation if layer == MobilityRules.Layer.FOREST else air_navigation
	if grid != null: return grid
	grid = AStarGrid2D.new()
	grid.region = Rect2i(Vector2i.ZERO,grid_size)
	grid.cell_size = Vector2.ONE
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	for z in range(grid_size.y):
		for x in range(grid_size.x): grid.set_point_solid(Vector2i(x,z),not can_traverse(Vector2i(x,z),layer))
	if layer == MobilityRules.Layer.FOREST: forest_navigation = grid
	else: air_navigation = grid
	return grid
func actor_path(start: Vector2i, goal: Vector2i, layer: int, owner: String) -> Array[Vector2i]:
	if not is_tile_in_bounds(start) or not can_traverse(start,layer,owner) or not can_traverse(goal,layer,owner): return []
	var grid := navigation_for(layer)
	var start_solid := grid.is_point_solid(start)
	var goal_solid := grid.is_point_solid(goal)
	grid.set_point_solid(start,false)
	grid.set_point_solid(goal,false)
	var path: Array[Vector2i] = grid.get_id_path(start,goal)
	grid.set_point_solid(start,start_solid)
	grid.set_point_solid(goal,goal_solid)
	return path
func nearest_actor_cell(origin: Vector2i, layer: int, owner: String = "") -> Vector2i:
	if can_traverse(origin,layer,owner): return origin
	for radius in range(1,maxi(grid_size.x,grid_size.y)):
		for offset in range(-radius,radius+1):
			for point in [origin+Vector2i(offset,-radius),origin+Vector2i(offset,radius),origin+Vector2i(-radius,offset),origin+Vector2i(radius,offset)]:
				if can_traverse(point,layer,owner): return point
	return Vector2i(-1,-1)
func clear_forest(pos: Vector2i) -> bool:
	if get_terrain(pos) != Terrain.FOREST: return false
	forest_reserves[pos] = 0
	cleared_forest[pos] = true
	_open_cell(pos)
	forest_cleared.emit(pos)
	return true
# Turns a cell into bare open ground for the rest of the match: navigation, building and the drawn surface.
func _open_cell(pos: Vector2i) -> void:
	var tile: Dictionary = tiles[pos.y*grid_size.x+pos.x]
	tile.terrain = Terrain.GRASS
	tile.terrain_buildable = true
	tile.walkable = true
	tile.buildable = true
	_sync_navigation(pos)
	if _clearing_mask != null:
		_clearing_mask.set_pixel(pos.x,pos.y,Color.WHITE)
		_mask_dirty = true
## Hides the ore rocks on `footprint` and `margin` cells around it until uncover_ore(key). Covers may overlap.
func cover_ore(key: String, footprint: Array, margin := 1) -> void:
	uncover_ore(key)
	var cells: Array[Vector2i] = []
	var seen := {}
	for at in footprint:
		for dz in range(-margin,margin+1):
			for dx in range(-margin,margin+1):
				var cell: Vector2i = at+Vector2i(dx,dz)
				if seen.has(cell) or not is_tile_in_bounds(cell): continue
				seen[cell] = true
				cells.append(cell)
	_ore_covers[key] = cells
	var changed: Array[Vector2i] = []
	for cell in cells:
		ore_covered[cell] = int(ore_covered.get(cell,0))+1
		if ore_covered[cell] == 1: changed.append(cell)
	if not changed.is_empty(): ore_cover_changed.emit(changed,true)
func uncover_ore(key: String) -> void:
	if not _ore_covers.has(key): return
	var changed: Array[Vector2i] = []
	for cell in _ore_covers[key]:
		ore_covered[cell] = int(ore_covered.get(cell,1))-1
		if ore_covered[cell] <= 0:
			ore_covered.erase(cell)
			changed.append(cell)
	_ore_covers.erase(key)
	if not changed.is_empty(): ore_cover_changed.emit(changed,false)
func _process(_delta: float) -> void:
	if _mask_dirty:
		_clearing_texture.update(_clearing_mask)
		_mask_dirty = false

func forest_amount(cell: Vector2i) -> int:
	if get_terrain(cell) != Terrain.FOREST: return 0
	return forest_reserves.get(cell,harvesting_rules.forest_wood_per_tile)
func harvest_forest(cell: Vector2i, requested: int) -> int:
	var taken := mini(maxi(0,requested),forest_amount(cell))
	if taken <= 0: return 0
	forest_reserves[cell] = forest_amount(cell)-taken
	if forest_reserves[cell] == 0: clear_forest(cell)
	return taken
func forest_source(cell: Vector2i) -> Node3D:
	if forest_amount(cell) <= 0: return null
	if forest_sources.has(cell): return forest_sources[cell]
	var source = load("res://scripts/economy/forest_harvest_source.gd").new()
	source.ground = self; source.cell = cell
	source.name = "Forest_%d_%d" % [cell.x,cell.y]
	add_child(source)
	source.global_position = tile_to_world(cell)
	forest_sources[cell] = source
	return source
## Coal (docs/BALANCED_MAP.md): every Coal cell holds harvesting_rules.coal_per_tile. Workers take it straight from
## the cell, as they take wood from a Forest cell, and a cell that runs out is dug out to open ground.
func _find_coal_fields() -> void:
	var at := terrain_cells.find(Terrain.COAL)
	while at >= 0:
		var first := Vector2i(at%grid_size.x,at/grid_size.x)
		if not _coal_field_of.has(first):
			var field := {"cells": [] as Array[Vector2i], "center": Vector3.ZERO}
			var open: Array[Vector2i] = [first]
			_coal_field_of[first] = coal_fields.size()
			while not open.is_empty():
				var cell: Vector2i = open.pop_back()
				field.cells.append(cell)
				field.center += tile_to_world(cell)
				for dz in range(-1,2):
					for dx in range(-1,2):
						var next := cell+Vector2i(dx,dz)
						if is_tile_in_bounds(next) and not _coal_field_of.has(next) and terrain_cells[next.y*grid_size.x+next.x] == Terrain.COAL:
							_coal_field_of[next] = coal_fields.size()
							open.append(next)
			field.center /= field.cells.size()
			coal_fields.append(field)
		at = terrain_cells.find(Terrain.COAL,at+1)
func coal_amount(cell: Vector2i) -> int:
	if get_terrain(cell) != Terrain.COAL: return 0
	return coal_reserves.get(cell,harvesting_rules.coal_per_tile)
func harvest_coal(cell: Vector2i, requested: int) -> int:
	var taken := mini(maxi(0,requested),coal_amount(cell))
	if taken <= 0: return 0
	coal_reserves[cell] = coal_amount(cell)-taken
	if coal_reserves[cell] == 0:
		cleared_coal[cell] = true
		_open_cell(cell)
		coal_depleted.emit(cell)
	return taken
## The field a Coal cell belongs to, also after it has been dug out. Empty for any other cell.
func coal_field_at(cell: Vector2i) -> Dictionary:
	return coal_fields[_coal_field_of[cell]] if _coal_field_of.has(cell) else {}
func coal_field_remaining(field: Dictionary) -> int:
	var total := 0
	for cell in field.get("cells",[]): total += coal_amount(cell)
	return total
## The cell of the same field to work after `cell` runs out: the nearest one that still holds coal.
func next_coal_cell(cell: Vector2i, near: Vector3) -> Vector2i:
	var best := Vector2i(-1,-1)
	var best_distance := INF
	for other in coal_field_at(cell).get("cells",[]):
		if coal_amount(other) <= 0: continue
		# Nearest to the dug-out cell, which is open ground a worker can stand on; ties go to the worker's side.
		var d: float = cell.distance_squared_to(other)+tile_to_world(other).distance_to(near)*0.001
		if d < best_distance: best = other; best_distance = d
	return best
func coal_source(cell: Vector2i) -> Node3D:
	if coal_amount(cell) <= 0: return null
	if coal_sources.has(cell): return coal_sources[cell]
	var source = load("res://scripts/economy/coal_harvest_source.gd").new()
	source.ground = self; source.cell = cell
	source.name = "Coal_%d_%d" % [cell.x,cell.y]
	add_child(source)
	source.global_position = tile_to_world(cell)
	coal_sources[cell] = source
	return source
func iron_amount(cell: Vector2i) -> int:
	return iron_reserves.get(cell,harvesting_rules.iron_per_tile) if get_terrain(cell) == Terrain.ORE else 0
func extract_iron(cell: Vector2i, requested: int) -> int:
	var taken := mini(maxi(0,requested),iron_amount(cell))
	iron_reserves[cell] = iron_amount(cell)-taken
	return taken
func ore_footprint_valid(start: Vector2i, size: Vector2i) -> bool:
	if not is_tile_in_bounds(start) or not is_tile_in_bounds(start+size-Vector2i.ONE): return false
	var reserves := 0
	for z in range(start.y,start.y+size.y):
		for x in range(start.x,start.x+size.x):
			var cell := Vector2i(x,z)
			if get_terrain(cell) != Terrain.ORE or tiles[z*500+x].occupied_by != null or tiles[z*500+x].has("rail"): return false
			reserves += iron_amount(cell)
	return reserves > 0
