class_name ForestStateVisuals
extends RefCounted
## Mutate saved batch instances only; no geometry or scenery is rebuilt at runtime.
var batches: Array[MultiMeshInstance3D] = []
var indices: Array[Dictionary] = []
func bind(ground: Node3D, forests: Node3D) -> void:
	if forests == null: return
	for child in forests.get_children():
		if not child is MultiMeshInstance3D: continue
		child.multimesh = child.multimesh.duplicate()
		var index: Dictionary = {}
		for i in range(child.multimesh.instance_count):
			var point: Vector3 = child.to_global(child.multimesh.get_instance_transform(i).origin)
			var cell = ground.get_tile_at_position(point)
			if cell != null:
				var patch := Vector2i(cell.x/2,cell.y/2)
				if not index.has(patch): index[patch] = []
				index[patch].append(i)
		batches.append(child); indices.append(index)
	ground.forest_cleared.connect(clear_cell)
func clear_cell(cell: Vector2i) -> void:
	var patch := Vector2i(cell.x/2,cell.y/2)
	for part in range(batches.size()):
		for index in indices[part].get(patch,[]):
			var transform := batches[part].multimesh.get_instance_transform(index)
			transform.basis = Basis.IDENTITY.scaled(Vector3.ZERO)
			batches[part].multimesh.set_instance_transform(index,transform)
