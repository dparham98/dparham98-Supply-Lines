extends "res://scripts/components/burst_effect.gd"

var _surface: Node3D
var _attachment: Transform3D

## Keep the sparks at the contact point on moving units. A lethal hit finishes in world space.
func follow_surface(surface: Node3D) -> void:
	_surface = surface
	_attachment = surface.global_transform.affine_inverse() * global_transform

func _process(delta: float) -> void:
	super._process(delta)
	if is_instance_valid(_surface) and _surface.is_inside_tree() and not _surface.is_queued_for_deletion():
		global_transform = _surface.global_transform * _attachment
		visible = _surface.is_visible_in_tree()
