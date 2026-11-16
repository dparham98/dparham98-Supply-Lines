extends SceneTree
# Mine sites (docs/MINE_SITES.md): a terrain kind, 4 cells across and 3 deep, cut into the side of a mountain.
# Checks the layout rule, that nothing but a mine can stand on a site, that a mine takes the whole site and looks
# out of it, the strip kept clear in front, and that the site holds its own iron. Uses the trial map,
# scenes/maps/mine_site_exercise.tscn.
const MapLayout := preload("res://scripts/tools/map_layout.gd")
const SIZE := 500
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func blank() -> PackedByteArray:
	var cells := PackedByteArray()
	cells.resize(SIZE*SIZE)
	return cells
func stamp(cells: PackedByteArray, at: Vector2i, size: Vector2i, kind: int) -> void:
	for z in range(at.y,at.y+size.y):
		for x in range(at.x,at.x+size.x): cells[z*SIZE+x] = kind
func run() -> void:
	# ---- The layout rule ----
	# A mountain with a recess cut in its southern edge: 4 across, 3 deep.
	var sound := blank()
	stamp(sound,Vector2i(96,94),Vector2i(14,8),4)
	stamp(sound,Vector2i(101,99),Vector2i(4,3),MapLayout.MINE_SITE)
	if not check(MapLayout.mine_site_errors(sound).is_empty(),"A sound mine site was rejected: %s" % [MapLayout.mine_site_errors(sound)]): return
	# The same turned to look east: 3 across the map, 4 down it.
	var east := blank()
	stamp(east,Vector2i(96,94),Vector2i(8,14),4)
	stamp(east,Vector2i(101,99),Vector2i(3,4),MapLayout.MINE_SITE)
	if not check(MapLayout.mine_site_errors(east).is_empty(),"A sound mine site facing east was rejected: %s" % [MapLayout.mine_site_errors(east)]): return
	var loose := blank()
	stamp(loose,Vector2i(101,99),Vector2i(4,3),MapLayout.MINE_SITE)
	if not check(MapLayout.mine_site_errors(loose).size() == 1,"A mine site away from any mountain was accepted"): return
	var pad := blank()
	stamp(pad,Vector2i(96,94),Vector2i(14,5),4)
	stamp(pad,Vector2i(101,99),Vector2i(4,3),MapLayout.MINE_SITE)
	if not check(MapLayout.mine_site_errors(pad).size() == 1,"A mine site standing in front of a mountain, not cut into it, was accepted"): return
	var half := sound.duplicate()
	half[98*SIZE+103] = 0
	if not check(MapLayout.mine_site_errors(half).size() == 1,"A mine site with a gap in the mountain behind it was accepted"): return
	var flank := sound.duplicate()
	flank[100*SIZE+105] = 0
	if not check(MapLayout.mine_site_errors(flank).size() == 1,"A mine site with a gap in one flank was accepted"): return
	var shut := sound.duplicate()
	stamp(shut,Vector2i(101,103),Vector2i(4,1),3)
	if not check(MapLayout.mine_site_errors(shut).size() == 1,"A mine site with forest across the second row of its front was accepted"): return
	var wide := sound.duplicate()
	stamp(wide,Vector2i(101,99),Vector2i(5,3),MapLayout.MINE_SITE)
	if not check(MapLayout.mine_site_errors(wide).size() == 1,"A mine site of the wrong size was accepted"): return
	var turned := sound.duplicate()
	stamp(turned,Vector2i(101,99),Vector2i(4,3),4)
	stamp(turned,Vector2i(102,98),Vector2i(3,4),MapLayout.MINE_SITE)
	if not check(MapLayout.mine_site_errors(turned).size() == 1,"A mine site with its short side to the open ground was accepted"): return

	# ---- The trial map ----
	var game: Node3D = load("res://scenes/maps/mine_site_exercise.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	var ground = game.ground
	var network = game.get_node("DepotNetwork")
	var rules = network.engineering_rules
	if not check(ground.Terrain.MINE_SITE == MapLayout.MINE_SITE and ground.TERRAIN_NAMES[MapLayout.MINE_SITE] == "Mine site","Mine site is not a terrain kind"): return
	if not check(ground.MINE_FRONT_DEPTH == MapLayout.MINE_FRONT_DEPTH,"The layout rule and the game disagree on the strip in front of a site"): return
	if not check(MapLayout.mine_site_errors(ground.terrain_cells).is_empty(),"The trial map's own sites break the rule"): return
	var sites: Array[Rect2i] = []
	for i in range(SIZE*SIZE):
		var cell := Vector2i(i%SIZE,i/SIZE)
		if ground.get_terrain(cell) != MapLayout.MINE_SITE: continue
		var rect: Rect2i = ground.mine_site_rect(cell)
		if not check(rect.has_point(cell),"A site cell is outside its own site"): return
		if not rect in sites: sites.append(rect)
	if not check(sites.size() == 8,"Expected eight mine sites, four a side: %d" % sites.size()): return
	var facings := {}
	for site in sites:
		var facing: Vector2i = ground.mine_site_facing(site.position,site.size)
		if not check(facing != Vector2i.ZERO,"Site %s does not open onto ground" % site): return
		if not check(site.size == (MapLayout.MINE_SITE_SIZE if facing.x == 0 else Vector2i(MapLayout.MINE_SITE_SIZE.y,MapLayout.MINE_SITE_SIZE.x)),"Site %s is not 4 across its face and 3 deep" % site): return
		facings[facing] = true
		# Mirrored: the same site stands on the other side of the map, facing the other way.
		var twin := Rect2i(MapLayout.turned(site.end-Vector2i.ONE),site.size)
		if not check(twin in sites and ground.mine_site_facing(twin.position,twin.size) == -facing,"Site %s has no mirrored twin" % site): return
		# Nothing walks or builds on a site; a mine takes exactly the whole of it.
		for dz in range(site.size.y):
			for dx in range(site.size.x):
				var cell := site.position+Vector2i(dx,dz)
				if not check(not ground.is_tile_valid(cell) and not ground.can_traverse(cell),"Site cell %s can be walked or built on" % cell): return
		if not check(not ground.is_footprint_valid(site.position,site.size),"An ordinary building fits on a mine site"): return
		if not check(ground.ore_footprint_valid(site.position,site.size),"A mine does not fit on site %s" % site): return
		if not check(not ground.ore_footprint_valid(site.position,rules.mine_footprint),"A mine fits on part of site %s" % site): return
		for shift in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)]:
			if not check(not ground.ore_footprint_valid(site.position+shift,site.size),"A mine fits a cell off site %s" % site): return
		# The strip in front: walked across, never built on.
		var across := Vector2i(absi(facing.y),absi(facing.x))
		var mouth: Vector2i = site.position+(Vector2i(0,site.size.y) if facing.y > 0 else Vector2i(site.size.x,0) if facing.x > 0 else facing)
		for depth in range(ground.MINE_FRONT_DEPTH):
			for step in range(4):
				var cell: Vector2i = mouth+across*step+facing*depth
				if not check(ground.is_mine_front(cell) and ground.can_traverse(cell) and not ground.is_footprint_valid(cell,Vector2i.ONE),"Cell %s in front of site %s is not kept clear" % [cell,site]): return
		if not check(not ground.is_mine_front(mouth+facing*ground.MINE_FRONT_DEPTH),"The clear strip runs further than it should in front of %s" % site): return
	if not check(facings.size() == 4,"The trial map should show a mine facing each of the four ways"): return

	# ---- Building on the site in front of SiteDepot ----
	var depot = game.get_node("Entities/Buildings/SiteDepot")
	var site: Rect2i = sites[0]
	for other in sites:
		if ground.tile_to_world(other.position).distance_to(depot.global_position) < ground.tile_to_world(site.position).distance_to(depot.global_position): site = other
	var corner: Vector3 = ground.tile_to_world(site.end-Vector2i.ONE)
	if not check(network.mine_spot(corner) == site and network.mine_spot(ground.tile_to_world(site.position)) == site,"Pointing at any cell of a site should choose the whole site"): return
	if not check(network.range_covers_footprint(depot,site.position,site.size),"SiteDepot does not reach its site"): return
	var facing: Vector2i = ground.mine_site_facing(site.position,site.size)
	var outside: Vector3 = ground.tile_to_world(site.position+(Vector2i(0,site.size.y) if facing.y > 0 else Vector2i(site.size.x,0) if facing.x > 0 else facing))
	if not check(network.can_place_mine(corner,depot) and not network.can_place_mine(outside,depot),"The build rule does not follow the site"): return
	if not check(ground.iron_amount(site.position) == ground.harvesting_rules.iron_per_site_tile,"A site cell holds the wrong iron"): return
	# Set down on a corner cell, the mine still takes the whole site and stands at its middle.
	var mine: Node3D = load("res://scenes/gameplay/iron_mine.tscn").instantiate()
	mine.rules = rules
	mine.position = corner
	game.get_node("Entities/Buildings").add_child(mine)
	await process_frame
	if not check(is_instance_valid(mine) and mine.is_in_group("mines"),"The mine did not stand on its site"): return
	var middle: Vector3 = ground.tile_to_world(site.position)+Vector3(site.size.x*0.5-0.5,0,site.size.y*0.5-0.5)
	if not check(mine.cells.size() == site.size.x*site.size.y and mine.global_position.distance_to(middle) < 0.01,"The mine does not fill its site: %d cells at %s" % [mine.cells.size(),mine.global_position]): return
	var front: Vector3 = mine.get_node("Visuals").global_transform.basis.z
	if not check(Vector2(front.x,front.z).normalized().distance_to(Vector2(facing)) < 0.01,"The mine faces %s, not out of its recess (%s)" % [front,facing]): return
	var whole: int = ground.harvesting_rules.iron_per_site_tile*site.size.x*site.size.y
	if not check(whole == 7500 and mine.reserves() == whole,"A site should hold 7,500 iron: %d" % mine.reserves()): return
	if not check(mine.extract(5,"player") == 5 and mine.extract(5,"enemy") == 5 and mine.reserves() == whole-10,"The mine on a site is not shared or loses iron"): return
	if not check(not ground.ore_footprint_valid(site.position,site.size),"A second mine fits on a site that already has one"): return
	# A planned mine takes the whole site too.
	var other: Rect2i = sites[0] if sites[0] != site else sites[1]
	var plan = network.queue_plan(ground.tile_to_world(other.position),&"iron_mine")
	if not check(plan != null and plan.start == other.position and plan.spec.size == other.size,"A planned mine does not take its whole site"): return
	if not check(network.plan_spec(&"iron_mine").size == rules.mine_footprint,"Planning on a site changed the mine's ordinary footprint"): return
	# The starter mine on the old ore field still works as before.
	var old = game.get_node("Entities/Buildings/IronMine")
	if not check(old.cells.size() == 4 and old.reserves() == ground.harvesting_rules.iron_per_tile*4 and is_zero_approx(old.get_node("Visuals").rotation.y),"The mine on an ore field changed"): return
	print("MINE_SITES_TEST_PASSED"); quit()
