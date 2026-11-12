class_name OreStateVisuals
extends RefCounted
## Hides the saved ore rock instances standing on cells a mine or mine site covers, and puts them back when it is
## gone (TerrainGrid.cover_ore). Mutates saved batch instances only; no geometry or scenery is rebuilt at runtime.

var batches: Array[MultiMeshInstance3D] = []
## Per batch: every instance's transform as baked.
var originals: Array = []
## Per batch: cell -> indices of the instances standing on it.
var by_cell: Array[Dictionary] = []
var ground_node: Node3D

func bind(ground: Node3D, batch_nodes: Array) -> void:
	for child in batch_nodes:
		if not child is MultiMeshInstance3D or child.multimesh == null: continue
		child.multimesh = child.multimesh.duplicate()
		var saved: Array[Transform3D] = []
		var index: Dictionary = {}
		for i in range(child.multimesh.instance_count):
			# Read from the saved buffer, which is there on every rendering backend.
			var placed := ForestStateVisuals.instance_transform(child.multimesh,i)
			saved.append(placed)
			# Rocks baked with no size (where the landscape stands its own ore) stay as they are.
			if placed.basis.get_scale().y <= 0.0: continue
			var cell = ground.get_tile_at_position(child.to_global(placed.origin))
			if cell == null: continue
			if not index.has(cell): index[cell] = []
			index[cell].append(i)
		batches.append(child); originals.append(saved); by_cell.append(index)
	if ground_node == null and not batches.is_empty():
		ground_node = ground
		ground.ore_cover_changed.connect(cover_changed)
		# Anything covered before the scenery was bound.
		if not ground.ore_covered.is_empty(): cover_changed(ground.ore_covered.keys(),true)

func cover_changed(cells: Array, covered: bool) -> void:
	for part in range(batches.size()):
		var multimesh := batches[part].multimesh
		for cell in cells:
			for index in by_cell[part].get(cell,[]):
				var placed: Transform3D = originals[part][index]
				multimesh.set_instance_transform(index,Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO),placed.origin) if covered else placed)

## How many ore rock instances stand on covered cells, and so are hidden, over every batch.
func hidden_count() -> int:
	var count := 0
	if ground_node == null: return 0
	for part in range(batches.size()):
		for cell in ground_node.ore_covered:
			count += by_cell[part].get(cell,[]).size()
	return count
