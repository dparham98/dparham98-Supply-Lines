extends SceneTree
# Headless: the material pile models (docs/MATERIAL_PILE_MODELS.md). Each material gets its own model, which stays
# on its cell; the pile shows as many ingots, logs or coal layers as its amount warrants, following extraction and
# top-ups, with its base always shown so it can still be picked. A build site's delivered pile gets the model too.
# How it looks is for tests/material_pile_runtime_check.gd.
const Bounds = preload("res://scripts/units/selection_bounds.gd")
const PILE = preload("res://scenes/gameplay/material_pile.tscn")
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> bool:
	if ok: return true
	push_error(message); quit(1); return false
func pile(kind: String, amount: int) -> Node3D:
	var node: Node3D = PILE.instantiate()
	node.material_kind = kind
	node.amount = amount
	root.add_child(node)
	return node
## Every visible mesh's box in the pile's own space.
func bounds(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mesh in node.find_children("*","MeshInstance3D",true,false):
		if not mesh.is_visible_in_tree(): continue
		var part: AABB = (node.global_transform.affine_inverse()*mesh.global_transform)*mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box
func visible_pieces(node: Node3D) -> int:
	return node.get_node("Visuals/Model").pieces.filter(func(p): return p.visible).size()
func run() -> void:
	for kind in ["iron","wood","coal"]:
		var full := pile(kind,100)
		var model: Node3D = full.get_node_or_null("Visuals/Model")
		if not check(model != null and model.scene_file_path.ends_with("material_pile_%s_model.tscn" % kind),"A %s pile should wear the %s model" % [kind,kind]): return
		var count: int = model.pieces.size()
		if not check(count >= 5,"The %s model should have a stack of pieces: %d" % [kind,count]): return
		if not check(visible_pieces(full) == count,"A full %s pile should show its whole stack" % kind): return
		var box := bounds(full)
		if not check(box.position.x >= -0.5 and box.end.x <= 0.5 and box.position.z >= -0.5 and box.end.z <= 0.5,"The %s pile should stay on its cell: %s" % [kind,box]): return
		if not check(box.position.y >= -0.01 and box.end.y <= 0.6,"The %s pile should stand about knee high: %s" % [kind,box]): return
		# Pieces are laid down in order: the first shown is the lowest.
		if not check(model.pieces[0].get_aabb().position.y <= model.pieces[count-1].get_aabb().position.y,"The %s stack should build up from the bottom" % kind): return
		full.free()
		# The amount sets how much of the stack shows; extraction and top-ups follow it.
		var small := pile(kind,1)
		if not check(visible_pieces(small) == 1,"A %s pile of 1 should show one piece" % kind): return
		var base: Array = small.get_node("Visuals/Model").find_children("*_base","MeshInstance3D",true,false)
		if not check(base.size() == 1 and base[0].is_visible_in_tree(),"The %s base should always show" % kind): return
		if not check(not Bounds.meshes(small).is_empty(),"A small %s pile should still be pickable" % kind): return
		small.add(49)
		if not check(visible_pieces(small) == ceili(count*0.5),"A %s pile of 50 should show half its stack: %d" % [kind,visible_pieces(small)]): return
		small.add(400)
		if not check(visible_pieces(small) == count,"Above full a %s pile shows its whole stack" % kind): return
		small.extract(440)
		if not check(small.remaining == 10 and visible_pieces(small) == ceili(count*0.1),"Taking from a %s pile should shrink it: %d" % [kind,visible_pieces(small)]): return
		small.free()
	# A build site's delivery forms a pile with the model.
	var game: Node3D = load("res://scenes/maps/resource_skirmish.tscn").instantiate()
	root.add_child(game)
	for i in range(3): await process_frame
	var network: Node = game.get_node("DepotNetwork")
	game.set_process(false)
	for unit in get_nodes_in_group("units"): unit.set_process(false)
	for depot in get_nodes_in_group("depots"): depot.set_process(false)
	var spec: Dictionary = network.plan_spec(&"generator")
	var point := Vector3.INF
	for radius in range(10,100,4):
		for offset in [Vector3(radius,0,0),Vector3(-radius,0,0),Vector3(0,0,radius),Vector3(0,0,-radius)]:
			var p: Vector3 = game.depot.global_position+offset
			var start: Vector2i = network.footprint_start(p,spec.size)
			if point == Vector3.INF and network.plan_terrain_valid(start,spec.size,&"generator") and not network.plan_overlaps(start,spec.size) and network.can_place_size(p,game.depot,spec.size): point = p
	if not check(point != Vector3.INF,"No generator site"): return
	var plan = network.queue_plan(point,&"generator")
	plan.set_process(false)
	plan.receive(&"iron",spec.iron)
	var piles: Array = plan.site_stores()
	if not check(piles.size() == 1 and piles[0].get_node("Visuals/Model").scene_file_path.ends_with("material_pile_iron_model.tscn"),"A site delivery should form an iron pile with its model"): return
	if not check(visible_pieces(piles[0]) == piles[0].get_node("Visuals/Model").pieces_for(spec.iron),"The delivered pile should show its amount"): return
	print("MATERIAL_PILE_MODEL_TEST_PASSED")
	quit(0)
