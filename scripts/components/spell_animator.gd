extends "res://scripts/components/character_animator.gd"
## Cast bursts stay on their instrument as the pose changes.
@export var mist_fx: PackedScene
@export var slow_fx: PackedScene
@export var heal_fx: PackedScene
@onready var grail: BoneAttachment3D = $GrailLip
@onready var hourglass: BoneAttachment3D = $ShieldGlass

func _clip_for(kind: StringName) -> StringName:
	if kind == &"heal": return &"Heal"
	return super._clip_for(kind)

func play_cast(kind: StringName) -> void:
	if _dying: return
	if kind == &"mist":
		play_action(&"Mist")
		grail.add_child(mist_fx.instantiate())
	elif kind == &"slow":
		play_action(&"Slow")
		hourglass.add_child(slow_fx.instantiate())

func pulse_heal(patient: Node3D) -> void:
	var pulse: Node3D = heal_fx.instantiate()
	add_child(pulse)
	pulse.top_level = true
	pulse.global_position = grail.global_position
	var tween := pulse.create_tween()
	tween.tween_property(pulse,"global_position",patient.global_position + Vector3.UP,0.32)
	tween.tween_property(pulse,"scale",Vector3.ONE * 0.01,0.12)
	tween.tween_callback(pulse.queue_free)
