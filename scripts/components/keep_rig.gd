extends "res://scripts/components/production_rig.gd"
## Controls Keep building clips: Idle, Build, Train (unit production), LaunchBalloon, and Die.

@export var launch_clip := &"LaunchBalloon"
var _launching := false

func show_idle() -> void:
	if _dying or _closing or _launching: return
	super.show_idle()

func show_print(fraction: float) -> void:
	if _launching: _launching = false
	super.show_print(fraction)

func play_launch_balloon() -> void:
	if _dying or _closing or player == null or not player.has_animation(launch_clip): return
	_launching = true
	player.play(launch_clip)
	player.seek(0.0, true)

func play_death() -> void:
	_launching = false
	super.play_death()

func _finished(clip: StringName) -> void:
	if clip == launch_clip and _launching:
		_launching = false
		show_idle()
		return
	super._finished(clip)
