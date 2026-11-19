extends RefCounted
## A roughly straight lane through forest (docs/FELL.md). It does no path search: it walks the grid line between
## two cells. That is cheap, so a worker can work it out again each time a tree falls. Nothing here changes
## the terrain.

const Grid := preload("res://scripts/terrain/terrain_grid.gd")

## The cells from `a` to `b`, `a` first. Each step is to a side neighbour, never a corner, so a felled lane can
## be walked.
static func line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [a]
	var n := Vector2i(absi(b.x-a.x),absi(b.y-a.y))
	var s := Vector2i(signi(b.x-a.x),signi(b.y-a.y))
	var at := a
	var i := Vector2i.ZERO
	while i.x < n.x or i.y < n.y:
		# Step along whichever axis keeps nearer the straight line.
		if (1+2*i.x)*n.y < (1+2*i.y)*n.x:
			at.x += s.x; i.x += 1
		else:
			at.y += s.y; i.y += 1
		cells.append(at)
	return cells

## The Forest cells to fell, nearest `from` first, on the line from `from` toward `to`. It is worked out from
## `to` back: past what `to` stands in (open ground, a coal seam, a lake, or `stop` when given), then the
## unbroken trees beyond, up to the first cell that is not Forest. So it is the trees between `to` and the
## open ground on its side toward the worker. Set `whole` to take every Forest cell on the line instead, for a
## worker that cannot reach that open ground.
static func lane(ground: Node3D, from: Vector2i, to: Vector2i, stop := Rect2i(), whole := false) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var path := line(from,to)
	var k := path.size()-1
	while k > 0 and (ground.forest_amount(path[k]) <= 0 or stop.has_point(path[k])): k -= 1
	while k > 0:
		if ground.forest_amount(path[k]) > 0: cells.append(path[k])
		elif not whole: break
		k -= 1
	cells.reverse()
	return cells
