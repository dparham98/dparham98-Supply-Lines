extends SceneTree
# Headless: Fell (docs/FELL.md). Infantry ordered to fell a spot cut a roughly straight lane of trees to it and
# the Forest cells within HarvestingRules.fell_radius_cells of it; ordered to fell a box, every Forest cell in it.
# They keep no wood, never walk home, and stop when done. The card shows Fell with the F key.
const FellLane := preload("res://scripts/terrain/fell_lane.gd")
var game: Node3D
var ground: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func step(nodes: Array, seconds: float, done: Callable) -> bool:
	for i in range(ceili(seconds*60)):
		for node in nodes:
			if is_instance_valid(node): node._process(1.0/60)
		if done.call(): return true
	return false
## Forest cells with wood left within `reach` cells of `origin`.
func patch(origin: Vector2i, reach: int) -> int:
	var count := 0
	for z in range(origin.y-reach,origin.y+reach+1):
		for x in range(origin.x-reach,origin.x+reach+1):
			var cell := Vector2i(x,z)
			if origin.distance_squared_to(cell) <= reach*reach and ground.forest_amount(cell) > 0: count += 1
	return count
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/balanced_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	game.set_process(false)
	ground = game.ground
	var depot: Node3D = game.depot
	depot.set_process(false)
	var rules = ground.harvesting_rules
	if not check(rules.fell_radius_cells == 1,"Fell should clear 1 cell round the clicked one"): return
	# A forest edge cell near the Depot.
	var home: Vector2i = ground.get_tile_at_position(depot.global_position)
	var first := Vector2i(-1,-1)
	for r in range(1,60):
		for z in range(home.y-r,home.y+r+1):
			for x in range(home.x-r,home.x+r+1):
				var cell := Vector2i(x,z)
				if first.x < 0 and maxi(absi(x-home.x),absi(z-home.y)) == r and ground.forest_amount(cell) > 0: first = cell
		if first.x >= 0: break
	if not check(first.x >= 0,"No forest near the Depot"): return
	var worker: Node3D = load("res://scenes/gameplay/infantry.tscn").instantiate()
	worker.team = "player"
	game.get_node("Entities/Units").add_child(worker)
	worker.global_position = ground.tile_to_world(first)+(depot.global_position-ground.tile_to_world(first)).normalized()*2.0
	worker.set_process(false)
	await process_frame
	# The card: Fell beside Gather, on F.
	for node in get_nodes_in_group("units"): node.set_selected(false)
	worker.set_selected(true)
	var hud = game.get_node("Interface")
	game.selected_building = null
	hud._process(0)
	var button: Button = hud.card.get_node("Fell")
	if not check(button.visible and hud.hotkey_text(button) == "F","The Infantry card should show Fell on F: visible %s, key '%s'" % [button.visible,hud.hotkey_text(button)]): return
	# A lane is one cell wide: each step is to a side neighbour.
	var line: Array[Vector2i] = FellLane.line(Vector2i(0,0),Vector2i(7,-3))
	var sides := true
	for k in range(1,line.size()): sides = sides and absi(line[k].x-line[k-1].x)+absi(line[k].y-line[k-1].y) == 1
	if not check(sides and line.back() == Vector2i(7,-3) and line.size() == 11,"The lane line should step side by side: %s" % [line]): return
	# The armed command refuses a spot with no trees on the way to it.
	game.pending_unit_command = "fell"
	game.issue_map_order(depot.global_position+Vector3(0,0,4),1.0,true)
	if not check(worker.order != "fell" and "already open" in game.message,"Fell on open ground should be refused: '%s'" % game.message): return
	game.pending_unit_command = "fell"
	game.issue_map_order(ground.tile_to_world(first),1.0,true)
	if not check(worker.order == "fell" and worker.source.cell == first and game.pending_unit_command.is_empty(),"Fell on a forest should order the worker: %s, %s from %s, %s" % [first,worker.source.cell,ground.get_tile_at_position(worker.global_position),game.message]): return
	# A small patch, so the test is quick; the worker carries a part load it keeps.
	rules.fell_radius_cells = 1
	worker.cargo = 3; worker.cargo_kind = &"iron"
	var wood_before: int = depot.wood
	var standing := patch(first,1)
	var beyond := patch(first,3)-standing
	if not check(standing >= 1,"Nothing to fell"): return
	if not check(step([worker],standing*rules.forest_wood_per_tile/float(worker.harvest_amount)*worker.harvest_interval+60.0,func(): return worker.order != "fell"),"The worker never finished felling: state '%s', %d cells left" % [worker.state,patch(first,1)]): return
	if not check(patch(first,1) == 0 and worker.state == "Felled","The patch should be clear: %d cells left, state '%s'" % [patch(first,1),worker.state]): return
	if not check(worker.cargo == 3 and worker.cargo_kind == &"iron" and depot.wood == wood_before,"Felling keeps no wood and leaves the load alone: cargo %d %s, wood %d" % [worker.cargo,worker.cargo_kind,depot.wood-wood_before]): return
	# Cells beyond the radius still stand.
	if not check(patch(first,3) == beyond,"Felling should stop at its radius: %d of %d cells beyond it left" % [patch(first,3),beyond]): return
	# Deep forest: clicking a tree enclosed behind other trees cuts a lane from the edge in instead of failing.
	var deep := Vector2i(-1,-1)
	for field in ground.coal_fields:
		var candidate: Vector2i = ground.get_tile_at_position(field.center)
		for dz in range(-6,7):
			for dx in range(-6,7):
				var cell := candidate+Vector2i(dx,dz)
				if ground.forest_amount(cell) <= 0: continue
				var surrounded := true
				for oz in range(-2,3):
					for ox in range(-2,3):
						if ground.can_traverse(cell+Vector2i(ox,oz)): surrounded = false
				if surrounded: deep = cell; break
			if deep.x >= 0: break
		if deep.x >= 0: break
	if not check(deep.x >= 0,"No deep forest cell for lane-felling check"): return
	var start_cell: Vector2i = ground.nearest_actor_cell(ground.get_tile_at_position(depot.global_position),MobilityRules.Layer.GROUND)
	for cell in worker._claimed.duplicate(): worker._release(cell)
	worker.global_position = ground.tile_to_world(start_cell)
	worker._stop_route()
	worker._claim(start_cell)
	game.pending_unit_command = "fell"
	game.issue_map_order(ground.tile_to_world(deep),1.0,true)
	if not check(worker.order == "fell" and worker.source.cell != deep,"Felling a deep forest cell should start on the outer lane tree, not '%s'" % worker.state): return
	if not check(step([worker],300.0,func(): return worker.order != "fell"),"Lane-felling never finished: state '%s'" % worker.state): return
	if not check(ground.forest_amount(deep) == 0 and worker.state == "Felled" and depot.wood == wood_before,"Deep cell should be felled without carrying wood home"): return
	# Coal seam: Fell clicked on a seam behind trees cuts the lane up to the seam's edge.
	var seam := {}
	for field in ground.coal_fields:
		var here: Vector2i = ground.get_tile_at_position(worker.global_position)
		if not FellLane.lane(ground,here,ground.get_tile_at_position(field.center)).is_empty():
			seam = field; break
	if not check(not seam.is_empty(),"No coal seam behind trees for the Fell check"): return
	var seam_cell: Vector2i = ground.get_tile_at_position(seam.center)
	game.pending_unit_command = "fell"
	game.issue_map_order(seam.center,1.0,true)
	if not check(worker.order == "fell","Fell on a coal seam behind trees should order the worker: '%s'" % game.message): return
	if not check(step([worker],300.0,func(): return worker.order != "fell"),"Fell to a coal seam never finished: state '%s'" % worker.state): return
	var after_here: Vector2i = ground.get_tile_at_position(worker.global_position)
	if not check(FellLane.lane(ground,after_here,seam_cell).is_empty(),"Fell on a coal seam should leave no tree on the line to it"): return
	# The way to the seam is open now: Fell there again says so instead of asking for a forest.
	game.pending_unit_command = "fell"
	game.issue_map_order(seam.center,1.0,true)
	if not check(worker.order != "fell" and "already open" in game.message,"Fell on an open seam should say the way is open: '%s'" % game.message): return
	# A box: every Forest cell in it is felled.
	var here_cell: Vector2i = ground.get_tile_at_position(worker.global_position)
	var area := Rect2i()
	for r in range(2,40):
		for z in range(here_cell.y-r,here_cell.y+r+1):
			for x in range(here_cell.x-r,here_cell.x+r+1):
				var box := Rect2i(Vector2i(x,z),Vector2i(3,3))
				if area.has_area() or maxi(absi(x-here_cell.x),absi(z-here_cell.y)) != r: continue
				var trees := 0
				for bz in range(box.position.y,box.end.y):
					for bx in range(box.position.x,box.end.x): if ground.forest_amount(Vector2i(bx,bz)) > 0: trees += 1
				if trees >= 4: area = box
		if area.has_area(): break
	if not check(area.has_area(),"No forest box near the worker"): return
	game.order_fell(area.position+Vector2i.ONE,area,ground.tile_to_world(area.position+Vector2i.ONE))
	if not check(worker.order == "fell","A Fell box should order the worker: '%s'" % game.message): return
	if not check(step([worker],400.0,func(): return worker.order != "fell"),"Felling the box never finished: state '%s'" % worker.state): return
	var left := 0
	for z in range(area.position.y,area.end.y):
		for x in range(area.position.x,area.end.x): if ground.forest_amount(Vector2i(x,z)) > 0: left += 1
	if not check(left == 0 and worker.state == "Felled","The box should be clear: %d cells left, state '%s'" % [left,worker.state]): return
	rules.fell_radius_cells = 1
	print("FELL_TEST_PASSED")
	quit(0)
