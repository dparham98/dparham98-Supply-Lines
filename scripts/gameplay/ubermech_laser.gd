extends Node3D
## A short-lived red beam with a flaring lens and an impact glint.

func configure(start: Vector3, end: Vector3, _team: String) -> void:
	global_position = start
	var segment := end - start
	var length := segment.length()
	if length < 0.001:
		queue_free()
		return
	look_at(end, Vector3.FORWARD if absf(segment.y / length) > 0.99 else Vector3.UP)
	$Span.scale.z = length
	$Impact.position.z = -length
	var fade := create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fade.tween_property($Span, "scale:x", 0.02, 0.14)
	fade.tween_property($Span, "scale:y", 0.02, 0.14)
	fade.tween_property($Lens, "scale", Vector3.ONE * 0.02, 0.12)
	fade.tween_property($Impact, "scale", Vector3.ONE * 0.02, 0.14)
	fade.chain().tween_callback(queue_free)
