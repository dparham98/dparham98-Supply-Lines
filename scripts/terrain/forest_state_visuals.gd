class_name ForestStateVisuals
extends RefCounted
## Mutate saved batch instances only; no geometry or scenery is rebuilt at runtime.
## Old 2 x 2 patches vanish when one of their cells is cleared. Single trees (docs/LANDSCAPE_LOOKDEV.md) are felled:
## they topple about their foot, lie for a moment and sink away, and the low growth under them shrinks.

## Seconds a tree takes to topple, and then to sink out of sight.
const FALL_SECONDS := 1.25
const SINK_SECONDS := 1.1
## Seconds low growth takes to shrink away.
const SHRINK_SECONDS := 0.35
## Anything at least this tall, in metres, topples; smaller pieces shrink.
const TREE_HEIGHT := 2.0

var batches: Array[MultiMeshInstance3D] = []
var indices: Array[Dictionary] = []
## Cells along one side of the area each batch's instances stand for: 2 for the old patches, 1 for single trees.
var patch_cells: Array[int] = []
var ground_node: Node3D
## Pieces on their way down: batch, index, start transform, tree or not, the way it falls, seconds since it began.
var felling: Array[Dictionary] = []

func bind(ground: Node3D, forests: Node3D, cells_per_patch: int = 2) -> void:
	if forests == null: return
	for child in forests.get_children():
		if not child is MultiMeshInstance3D: continue
		child.multimesh = child.multimesh.duplicate()
		var index: Dictionary = {}
		for i in range(child.multimesh.instance_count):
			# Read from the saved buffer, which is there on every rendering backend.
			var point: Vector3 = child.to_global(instance_transform(child.multimesh,i).origin)
			var cell = ground.get_tile_at_position(point)
			if cell != null:
				var patch := Vector2i(cell.x/cells_per_patch,cell.y/cells_per_patch)
				if not index.has(patch): index[patch] = []
				index[patch].append(i)
		batches.append(child); indices.append(index); patch_cells.append(cells_per_patch)
	if ground_node == null:
		ground_node = ground
		ground.forest_cleared.connect(clear_cell)

## An instance's transform as baked, from the batch's saved buffer.
static func instance_transform(multimesh: MultiMesh, index: int) -> Transform3D:
	var b := multimesh.buffer
	var stride := b.size()/maxi(multimesh.instance_count,1)
	if stride < 12: return multimesh.get_instance_transform(index)
	var o := index*stride
	return Transform3D(Vector3(b[o],b[o+4],b[o+8]),Vector3(b[o+1],b[o+5],b[o+9]),Vector3(b[o+2],b[o+6],b[o+10]),Vector3(b[o+3],b[o+7],b[o+11]))

func clear_cell(cell: Vector2i) -> void:
	for part in range(batches.size()):
		var patch := Vector2i(cell.x/patch_cells[part],cell.y/patch_cells[part])
		var multimesh := batches[part].multimesh
		for index in indices[part].get(patch,[]):
			var start := instance_transform(multimesh,index)
			if patch_cells[part] != 1 or start.basis.get_scale().y <= 0.0:
				multimesh.set_instance_transform(index,Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO),start.origin))
				continue
			# A trunk and its leaves are two batches with the same placement, so the way a tree falls comes from
			# its cell alone and both go down together.
			var seed_ := absi(hash(cell))
			var heading := float(seed_ % 628)/100.0
			var tall := multimesh.mesh.get_aabb().size.y*start.basis.get_scale().y >= TREE_HEIGHT
			felling.append({"batch": part,"index": index,"start": start,"tall": tall,"axis": Vector3(cos(heading),0.0,sin(heading)),"time": -float(seed_ % 23)/100.0})
		# A single tree falls once only.
		if patch_cells[part] == 1: indices[part].erase(patch)

func is_felling() -> bool:
	return not felling.is_empty()

## Moves every falling piece on by delta seconds. Called each frame by terrain_assets.gd.
func advance(delta: float) -> void:
	for i in range(felling.size()-1,-1,-1):
		var piece := felling[i]
		piece.time += delta
		var time: float = piece.time
		if time < 0.0: continue
		var multimesh := batches[piece.batch].multimesh
		var start: Transform3D = piece.start
		if time >= (FALL_SECONDS+SINK_SECONDS if piece.tall else SHRINK_SECONDS):
			multimesh.set_instance_transform(piece.index,Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO),start.origin))
			felling.remove_at(i)
		elif not piece.tall:
			multimesh.set_instance_transform(piece.index,Transform3D(start.basis.scaled(Vector3.ONE*(1.0-time/SHRINK_SECONDS)),start.origin))
		else:
			multimesh.set_instance_transform(piece.index,toppled(start,piece.axis,time))

## A tree this many seconds into its fall: slow at first, fast at the end, one small bounce, then sinking.
static func toppled(start: Transform3D, axis: Vector3, time: float) -> Transform3D:
	var fall := clampf(time/FALL_SECONDS,0.0,1.0)
	var angle := PI*0.5*0.96*fall*fall*fall
	var after := maxf(time-FALL_SECONDS,0.0)
	angle -= 0.07*exp(-after*7.0)*absf(sin(after*16.0))
	var sink := smoothstep(0.25,1.0,after/SINK_SECONDS)
	var basis := Basis(axis,angle)*start.basis
	return Transform3D(basis.scaled(Vector3.ONE*(1.0-0.35*sink)),start.origin+Vector3.DOWN*2.6*sink)
