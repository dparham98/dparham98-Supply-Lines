extends Node3D
## Plays the Iron Mine's authored clips (docs/IRON_MINE_MODEL.md): Idle while nobody is mining it, Work while
## Infantry take iron from it, Depleted once its reserves are gone, Build scrubbed by construction progress, and
## Die when it is destroyed. The rest pose is the finished pithead with its skip raised.
@export var player_path := NodePath("Rig/AnimationPlayer")
@export var idle_clip := &"Idle"
@export var work_clip := &"Work"
@export var depleted_clip := &"Depleted"
@export var build_clip := &"Build"
@export var death_clip := &"Die"
## Seconds to blend into Depleted, or between clips when Work is not playing.
@export_range(0,2,0.05) var switch_blend := 0.3
## Spawned on this model at death (sparks, dust, spilled ore); built on the same timeline as the clip.
@export var death_fx_scene: PackedScene
@onready var player: AnimationPlayer = get_node(player_path)
var _dying := false
var _wanted := &""
var _last_position := 0.0
func _ready() -> void:
	player.animation_finished.connect(_finished)
	_wanted = idle_clip
	_play(idle_clip,0.0)
func show_idle() -> void:
	show_state(false,false)
## Being mined or not, and worked out or not. Work's loop starts and ends with the skip raised, as in Idle, so
## Work always finishes its winding cycle before the mine settles to Idle or Depleted.
func show_state(working: bool, depleted: bool) -> void:
	if _dying: return
	_wanted = depleted_clip if depleted else (work_clip if working else idle_clip)
	if player.assigned_animation == work_clip and player.is_playing() and _wanted != work_clip: return
	_play(_wanted,0.0 if _wanted == work_clip or player.assigned_animation == work_clip else switch_blend)
func working() -> bool:
	return not _dying and player.assigned_animation == work_clip and player.is_playing()
func depleted() -> bool:
	return not _dying and player.assigned_animation == depleted_clip
## Construction progress 0..1: from bare ground to the finished pithead.
func show_construction(fraction: float) -> void:
	if _dying: return
	if player.is_playing(): player.pause()
	if player.assigned_animation != build_clip: player.assigned_animation = build_clip
	player.seek(clampf(fraction,0.0,1.0)*player.get_animation(build_clip).length,true)
func has_death_clip() -> bool:
	return player != null and player.has_animation(death_clip)
func dying() -> bool:
	return _dying
## The wreck plays out, sinks out of sight and removes itself.
func play_death() -> void:
	_dying = true
	player.play(death_clip)
	player.seek(0.0,true)
	if death_fx_scene: add_child(death_fx_scene.instantiate())
func _process(_delta: float) -> void:
	if _dying or player.assigned_animation != work_clip or not player.is_playing(): return
	var position := player.current_animation_position
	# A finished winding cycle: hand over to whatever the mine is doing now.
	if position < _last_position and _wanted != work_clip: _play(_wanted,0.0)
	_last_position = position
func _play(clip: StringName, blend: float) -> void:
	if player.is_playing() and player.assigned_animation == clip: return
	_last_position = 0.0
	player.play(clip,blend if player.is_playing() else 0.0)
func _finished(clip: StringName) -> void:
	if clip == death_clip: queue_free()
