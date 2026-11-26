extends "res://scripts/gameplay/unit_agent.gd"

const MuzzleFlash := preload("res://scenes/models/round_table_muzzle_fx.tscn")
const HitBurst := preload("res://scenes/gameplay/round_table_impact.tscn")
const Bounds := preload("res://scripts/units/selection_bounds.gd")

## Show both ends of the burst on discharge. The unit agent resolves its hit in this same tick.
func _show_weapon_shot(model: Node3D, muzzle: Vector3, target: Node3D) -> Node3D:
	if model and model.is_visible_in_tree() and game.in_view(muzzle):
		var socket := model.get_node_or_null("Rig/Marine_Rig/Skeleton3D/MuzzleSocket") as BoneAttachment3D
		if socket:
			# The release pose was just sampled. BoneAttachment normally updates at the end of the frame.
			var skeleton := socket.get_parent() as Skeleton3D
			socket.transform = skeleton.get_bone_global_pose(socket.get_bone_idx())
			var flash: Node3D = MuzzleFlash.instantiate()
			socket.add_child(flash)
			var axis: Vector3 = model.gun_direction()
			_orient(flash, axis)
	if target.is_visible_in_tree() and game.in_view(target.global_position):
		var point := _impact_point(muzzle, target)
		var hit = HitBurst.instantiate()
		game.add_child(hit)
		hit.global_position = point
		_orient(hit, muzzle - point)
		var visuals := target.get_node_or_null("Visuals") as Node3D
		hit.follow_surface(visuals if visuals else target)
	return null

func _orient(effect: Node3D, direction: Vector3) -> void:
	if direction.length_squared() < 0.000001: return
	var forward := direction.normalized()
	effect.look_at(effect.global_position + forward, Vector3.RIGHT if absf(forward.y) > 0.99 else Vector3.UP)

## Aim into the biggest body part, then find the first occupied part on that line.
## A single box around a vehicle also encloses empty space below its barrel.
func _impact_point(origin: Vector3, target: Node3D) -> Vector3:
	var parts := Bounds.meshes(target)
	if parts.is_empty(): return target.global_position + Vector3.UP
	var body := parts[0]
	var largest := -1.0
	for part in parts:
		var volume := part.get_aabb().get_volume() * absf(part.global_basis.determinant())
		if volume > largest:
			largest = volume
			body = part
	var aim := body.to_global(body.get_aabb().get_center())
	var nearest := aim
	var distance := origin.distance_squared_to(aim)
	for part in parts:
		var inverse := part.global_transform.affine_inverse()
		var contact: Variant = part.get_aabb().intersects_segment(inverse * origin, inverse * aim)
		if contact == null: continue
		var world := part.to_global(contact)
		var along := origin.distance_squared_to(world)
		if along < distance:
			nearest = world
			distance = along
	return nearest
