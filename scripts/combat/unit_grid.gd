extends RefCounted
## Units bucketed by where they stand, for "who is near me" questions (docs/COMBAT_BATCH.md, Targeting in big battles). Every unit
## looks for something to shoot every frame; asking the whole "units" group made that grow with the square of the
## units on the map, and a battle of a few hundred ran at a few frames a second. The buckets are rebuilt once a
## frame, on the first question asked in it, and again when a unit joins or leaves (changed()).
const CELL := 16.0
## Units move less than a metre a frame, so a bucket filled at the start of the frame is a little out of date:
## questions reach this much further, and the caller measures from where each unit stands now.
const SLACK := 2.0
var _buckets := {}
var _frame := -1
func _key(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x/CELL),floori(z/CELL))
func _rebuild(tree: SceneTree) -> void:
	_frame = Engine.get_process_frames()
	_buckets.clear()
	for unit in tree.get_nodes_in_group("units"):
		var at: Vector3 = unit.global_position
		var key := _key(at.x,at.z)
		if not _buckets.has(key): _buckets[key] = []
		_buckets[key].append(unit)
## A unit joined or left the "units" group: fill the buckets again on the next question, even in this frame.
func changed() -> void:
	_frame = -1
## Units standing within about `radius` of `point`: every one that is, and perhaps a few just beyond. Freed units may
## be among them; the caller checks.
func near(tree: SceneTree, point: Vector3, radius: float) -> Array:
	if Engine.get_process_frames() != _frame: _rebuild(tree)
	var reach := radius+SLACK
	var low := _key(point.x-reach,point.z-reach)
	var high := _key(point.x+reach,point.z+reach)
	var result := []
	for z in range(low.y,high.y+1):
		for x in range(low.x,high.x+1):
			var bucket = _buckets.get(Vector2i(x,z))
			if bucket != null: result.append_array(bucket)
	return result
