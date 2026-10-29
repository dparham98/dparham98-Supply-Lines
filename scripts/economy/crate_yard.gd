class_name CrateYard
extends RefCounted
## Crates as map objects (docs/CRATE_CONTAINERS.md): finding, packing beside a stockpile, unpacking.
const SCENE := preload("res://scenes/gameplay/supply_crate.tscn")
## Crates within this distance of a Depot (or deployed Cargo vehicle) count as "beside" it.
const BESIDE_RADIUS := 10.0
const VEHICLE_BESIDE_RADIUS := 4.0
## Load on one crate also takes other crates within this distance of it.
const CLUSTER_RADIUS := 4.0
static func crates_near(tree: SceneTree, point: Vector3, radius: float, team := "") -> Array[Node3D]:
	var result: Array[Node3D] = []
	for crate in tree.get_nodes_in_group("supply_crates"):
		if crate.is_queued_for_deletion() or (not team.is_empty() and crate.team != team): continue
		if crate.global_position.distance_to(point) <= radius: result.append(crate)
	result.sort_custom(func(a,b): return a.global_position.distance_squared_to(point) < b.global_position.distance_squared_to(point))
	return result
static func beside_radius(node: Node3D) -> float:
	return BESIDE_RADIUS if node.is_in_group("depots") else VEHICLE_BESIDE_RADIUS
static func beside(node: Node3D) -> Array[Node3D]:
	return crates_near(node.get_tree(),node.global_position,beside_radius(node),node.team)
static func count_beside(node: Node3D, kind: StringName) -> int:
	var count := 0
	for crate in beside(node):
		if crate.resource_kind == kind: count += 1
	return count
static func crate_at(tree: SceneTree, cell: Vector2i) -> bool:
	var ground = tree.get_first_node_in_group("terrain_grid")
	for crate in tree.get_nodes_in_group("supply_crates"):
		if not crate.is_queued_for_deletion() and ground.get_tile_at_position(crate.global_position) == cell: return true
	return false
## The nearest open land tile at least `min_ring` (and under min_ring+rings) tiles from `center` with
## no crate on it, or null. Each ring tries the camera-facing (south) side first.
static func free_cell(tree: SceneTree, center: Vector3, min_ring := 0, rings := 8) -> Variant:
	var ground = tree.get_first_node_in_group("terrain_grid")
	var origin = ground.get_tile_at_position(center)
	if origin == null: return null
	for ring in range(min_ring,min_ring+rings):
		for dz in range(ring,-ring-1,-1):
			for dx in range(-ring,ring+1):
				if maxi(absi(dx),absi(dz)) != ring: continue
				var cell: Vector2i = origin+Vector2i(dx,dz)
				if ground.can_traverse(cell) and not crate_at(tree,cell): return cell
	return null
static func spawn(tree: SceneTree, cell: Vector2i, kind: StringName, amount: int, team: String) -> Node3D:
	var crate = SCENE.instantiate()
	crate.material_kind = str(kind) if amount > 0 else ""
	crate.amount = amount
	crate.team = team
	var game = tree.get_first_node_in_group("skirmish")
	var parent: Node = game.get_node("Entities/Resources") if game.has_node("Entities/Resources") else game
	crate.position = tree.get_first_node_in_group("terrain_grid").tile_to_world(cell)
	parent.add_child(crate,true)
	return crate
## Packs one full crate of `kind` from the node's loose stock onto a free tile beside it.
static func pack(node: Node3D, kind: StringName) -> Node3D:
	if node.stockpile.amount(kind) < ResourceStockpile.CRATE: return null
	return _place(node,kind,ResourceStockpile.CRATE)
## An empty crate beside the node, for workers to fill.
static func pack_empty(node: Node3D) -> Node3D:
	return _place(node,&"",0)
static func _place(node: Node3D, kind: StringName, amount: int) -> Node3D:
	var cell = free_cell(node.get_tree(),node.global_position,node.footprint.x/2+2 if node.is_in_group("depots") else 2)
	if cell == null: return null
	if amount > 0: node.stockpile.withdraw(kind,amount)
	return spawn(node.get_tree(),cell,kind,amount,node.team)
## Packs until `target` crates of `kind` are beside the node; returns how many it packed.
static func pack_to(node: Node3D, kind: StringName, target: int) -> int:
	var packed := 0
	var count := count_beside(node,kind)
	while count < target and pack(node,kind) != null:
		count += 1; packed += 1
	return packed
## Empties the nearest crate of `kind` beside the node into its storage; returns the units moved.
static func unpack(node: Node3D, kind: StringName) -> int:
	for crate in beside(node):
		if crate.resource_kind == kind and crate.amount > 0: return unpack_crate(node,crate)
	return 0
## Empties one crate into the node's storage as far as space allows; an emptied crate is removed.
static func unpack_crate(node: Node3D, crate: Node3D) -> int:
	if crate.amount == 0: return 0
	var moved: int = node.stockpile.deposit(crate.resource_kind,crate.amount)
	crate.extract(moved)
	if crate.amount == 0: crate.queue_free()
	return moved
## Crate contents as {kind, amount}, grouped by resource for pip rows.
static func contents(crates: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for crate in crates: result.append({kind = crate.resource_kind, amount = crate.amount, node = crate})
	result.sort_custom(func(a,b):
		var ka := ResourceStockpile.KINDS.find(a.kind)
		var kb := ResourceStockpile.KINDS.find(b.kind)
		return a.amount > b.amount if ka == kb else (ka >= 0 and (kb < 0 or ka < kb)))
	return result
## Refill after pickup: repack crates beside the node up to its targets while loose stock allows.
static func restock(node: Node3D) -> void:
	var stockpile: ResourceStockpile = node.stockpile
	if not stockpile.refill: return
	for kind in stockpile.refill_targets: pack_to(node,kind,stockpile.refill_targets[kind])
