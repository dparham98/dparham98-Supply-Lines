extends "res://scripts/gameplay/projectile.gd"
## One straight-flying roof-gun round. The inherited projectile moves its visible mesh.
signal resolved(hit: bool)

@export_range(0.05, 2.0, 0.05) var hit_radius := 0.5
var _shooter: WeakRef
var _target: WeakRef
var _aim_frame: WeakRef
var _local_hit: Vector3
var _launch_team: String
var _damage: int


func arm(shooter: Node3D, target: Node3D, amount: int) -> void:
	_shooter = weakref(shooter)
	_target = weakref(target)
	_launch_team = shooter.team
	_damage = amount
	var frame := target.get_node_or_null("Visuals") as Node3D
	if frame == null:
		frame = target
	_aim_frame = weakref(frame)
	_local_hit = frame.to_local(_end)
	on_impact = _resolve_hit


func _resolve_hit() -> void:
	on_impact = Callable()
	var target := _target.get_ref() as Node3D
	var shooter := _shooter.get_ref() as Node3D
	var frame := _aim_frame.get_ref() as Node3D
	# A fired round survives its shooter. A living shooter's new allegiance,
	# a lost target, or movement clear of the original endpoint cancels the hit.
	var hit: bool = (target != null and frame != null and not target.is_queued_for_deletion()
		and target.is_in_group("units") and target.health > 0
		and target.team != _launch_team and target.team != "neutral"
		and (shooter == null or shooter.team == _launch_team)
		and frame.to_global(_local_hit).distance_squared_to(_end) <= hit_radius * hit_radius)
	if hit:
		if get_parent().has_method("mark_attacked"):
			get_parent().mark_attacked(target)
		target.take_damage(_damage)
	resolved.emit(hit)
