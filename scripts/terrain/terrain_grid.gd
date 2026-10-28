extends MeshInstance3D

enum Terrain { GRASS, WATER, DESERT, FOREST, MOUNTAIN, ORE }
const TERRAIN_NAMES = ["Grass", "Water", "Desert", "Forest", "Mountains", "Ore deposit (unassigned)"]
var grid_size := Vector2i(500, 500)
var tile_size := 1.0
@export var harvesting_rules: HarvestingRules
var forest_reserves: Dictionary = {}
var iron_reserves: Dictionary = {}
var forest_sources: Dictionary = {}
var iron_mines: Dictionary = {}
var tiles: Array = []
var terrain_cells: PackedByteArray
var navigation_grid := AStarGrid2D.new()
var forest_navigation: AStarGrid2D
var air_navigation: AStarGrid2D
var air_occupancy: Dictionary = {}
var cleared_forest: Dictionary = {}
signal forest_cleared(cell: Vector2i)
var _clearing_mask: Image
var _clearing_texture: ImageTexture
var _mask_dirty := false

func _ready() -> void:
	terrain_cells = FileAccess.get_file_as_bytes("res://assets/maps/terrain_cells.bin")
	assert(terrain_cells.size() == grid_size.x * grid_size.y)
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
	var tile: Dictionary = tiles[pos.y*grid_size.x+pos.x]
	tile.terrain = Terrain.GRASS
	tile.terrain_buildable = true
	tile.walkable = true
	tile.buildable = true
	forest_reserves[pos] = 0
	cleared_forest[pos] = true
	_sync_navigation(pos)
	if _clearing_mask != null:
		_clearing_mask.set_pixel(pos.x,pos.y,Color.WHITE)
		_mask_dirty = true
	forest_cleared.emit(pos)
	return true
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
