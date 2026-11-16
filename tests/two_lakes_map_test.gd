extends SceneTree
# The Two Lakes map (docs/TWO_LAKES_MAP.md): the playable scene loads, the east mirrors the west, every mine site
# is sound and holds its iron, both starts have their mine built, and the ways are as designed: open round the
# lakes, shut through the Crossing until trees are felled.
const MapLayout := preload("res://scripts/tools/map_layout.gd")
const SIZE := 500
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func run() -> void:
	var game: Node3D = load("res://scenes/maps/lakes_skirmish.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	var ground = game.ground
	var cells: PackedByteArray = ground.terrain_cells
	if not check(ground.cells_path == "res://assets/maps/lakes/terrain_cells.bin","The scene plays on the wrong cells"): return
	# The layout the map was built from gives exactly these cells.
	var layout: Dictionary = MapLayout.read("res://assets/maps/lakes/layout.png")
	if not check(layout.errors.is_empty() and layout.cells == cells,"terrain_cells.bin is not built from layout.png"): return
	# East mirrors west.
	for z in range(SIZE):
		for x in range(SIZE/2):
			if not check(cells[z*SIZE+x] == cells[z*SIZE+SIZE-1-x],"The map is not mirrored at %d,%d" % [x,z]): return
	if not check(cells.count(5) == 0,"This map has no ore fields: iron is in mine sites"): return
	# Mine sites: twenty, sound, none looking north, 7,500 iron each.
	if not check(MapLayout.mine_site_errors(cells).is_empty(),"A mine site breaks the layout rule: %s" % [MapLayout.mine_site_errors(cells)]): return
	var sites: Array[Rect2i] = []
	for i in range(SIZE*SIZE):
		var cell := Vector2i(i%SIZE,i/SIZE)
		if cells[i] != MapLayout.MINE_SITE: continue
		var rect: Rect2i = ground.mine_site_rect(cell)
		if not rect in sites: sites.append(rect)
	if not check(sites.size() == 20,"Expected twenty mine sites: %d" % sites.size()): return
	var built := 0
	for site in sites:
		var facing: Vector2i = ground.mine_site_facing(site.position,site.size)
		if not check(facing != Vector2i.ZERO and facing != Vector2i(0,-1),"Site %s faces north or nowhere" % site): return
		var iron := 0
		for dz in range(site.size.y):
			for dx in range(site.size.x): iron += ground.iron_amount(site.position+Vector2i(dx,dz))
		if not check(iron == 7500,"Site %s holds %d iron" % [site,iron]): return
		if ground.iron_mines.has(site.position): built += 1
	# Each start in play has its mine, the portal mine, in the mountain north of its Depot.
	if not check(built == 2,"Both starts in play should have their home mine built: %d" % built): return
	for name in ["IronMine","IronMineB"]:
		var mine = game.get_node("Entities/Buildings/"+name)
		if not check(is_instance_valid(mine) and mine.cells.size() == 12 and mine.get_node("Visuals/Model").player.has_animation(&"Work"),"%s is not a portal mine on its site" % name): return
	var depot = game.get_node("Entities/Buildings/Depot")
	var home = game.get_node("Entities/Buildings/IronMine")
	if not check(depot.global_position.distance_to(home.global_position) < 32.0,"The home mine is not beside the start"): return
	# Coal: seventeen fields (six starter, six by the home lakes, two in the passes, two inside the mouths and the mother seam); the mother seam in the middle is the largest.
	if not check(ground.coal_fields.size() == 17,"Expected seventeen coal fields: %d" % ground.coal_fields.size()): return
	var largest := {}
	for field in ground.coal_fields:
		if largest.is_empty() or field.cells.size() > largest.cells.size(): largest = field
	if not check(largest.cells.size() >= 110 and largest.center.distance_to(Vector3(0,0,19)) < 12.0,"The mother seam should be the largest field, at the middle: %d cells at %s" % [largest.cells.size(),largest.center]): return
	# Sunk water is in the saved scenery.
	if not check(game.find_child("Bed",true,false) != null and game.find_child("Surface",true,false) != null,"The lakes are not sunk"): return
	# The ways: open ground joins the two starts round a lake; the straight road is shut by forest.
	var west: Vector2i = ground.get_tile_at_position(game.get_node("Sites/PlayerStart").global_position)+Vector2i(8,0)
	var east: Vector2i = ground.get_tile_at_position(game.get_node("Sites/EnemyStart").global_position)-Vector2i(8,0)
	var round_lake: Array[Vector2i] = ground.get_terrain_path(west,east)
	if not check(round_lake.size() > 300,"No open way joins the West and East starts"): return
	var crosses_middle := false
	for cell in round_lake:
		if cell.x > 240 and cell.x < 260 and cell.y > 195 and cell.y < 307: crosses_middle = true
	if not check(not crosses_middle,"The open way runs through the Crossing, which should be shut by forest"): return
	var forest_on_road := 0
	for x in range(180,320):
		if cells[250*SIZE+x] == 3: forest_on_road += 1
	if not check(forest_on_road >= 40,"The straight road should be shut by forest: %d cells" % forest_on_road): return
	# Scouts cross it from the start.
	var scout = game.get_node("Entities/Units/EnemyScout")
	if not check(ground.can_traverse(Vector2i(250,250),scout.mobility_layer(),scout._owner_key()),"A Scout cannot enter the Crossing's forest"): return
	print("Open way West to East: %d cells; forest across the straight road: %d cells" % [round_lake.size(),forest_on_road])
	print("TWO_LAKES_MAP_TEST_PASSED"); quit()
