extends RefCounted
## Rally points (docs/RALLY_POINTS.md): where a building sends the units it makes. A building keeps them in its
## `rally_points`, each {kind = "move", point} or {kind = "gather", target, point}; Shift adds more, in order.

const MOST := 8

## Sets (or with `queued` adds) a rally stop at a ground point, or at a resource to gather from.
static func add(building: Node3D, point: Vector3, target: Node3D, queued: bool) -> void:
	var entry := {kind = "move", point = point}
	if is_instance_valid(target): entry = {kind = "gather", target = target, point = target.global_position}
	if not queued: building.rally_points.clear()
	if building.rally_points.size() >= MOST: building.rally_points.pop_front()
	building.rally_points.append(entry)

## Sends a new unit along its building's rally stops. Gather stops are for units that gather; others walk there.
static func send(building: Node3D, unit: Node3D) -> void:
	if building.rally_points.is_empty() or unit.is_in_group("rail_trains") or not unit.has_method("queue_order"): return
	var first := true
	for stop in building.rally_points:
		var entry: Dictionary = stop
		if entry.kind == "gather" and (not is_instance_valid(entry.target) or not unit.can_gather or unit.is_cargo_vehicle or unit.is_depot_truck):
			entry = {kind = "move", point = entry.point}
		if first: unit.order_queue.clear(); unit.run_order(entry)
		else: unit.queue_order(entry)
		first = false

## The rally path to draw: the building, then each stop.
static func path(building: Node3D) -> Array:
	var points: Array = [building.global_position]
	for stop in building.rally_points:
		points.append(stop.target.global_position if stop.kind == "gather" and is_instance_valid(stop.target) else stop.point)
	return points
