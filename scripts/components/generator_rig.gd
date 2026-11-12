extends Node3D
## Plays the Generator's authored clips (docs/GENERATOR_MODEL.md): Idle while it stands cold, Run while it
## burns fuel, Build scrubbed by construction progress, and Die when it is destroyed. The rest pose is the
## finished generator standing still.
@export var player_path := NodePath("Rig/AnimationPlayer")
@export var idle_clip := &"Idle"
@export var run_clip := &"Run"
@export var build_clip := &"Build"
@export var death_clip := &"Die"
## Seconds to blend between Idle and Run.
@export_range(0,2,0.05) var switch_blend := 0.3
## Spawned on this model at death (steam, sparks, scrap); built on the same timeline as the clip.
@export var death_fx_scene: PackedScene
@onready var player: AnimationPlayer = get_node(player_path)
var _dying := false
var _running := false
func _ready() -> void:
	player.animation_finished.connect(_finished)
	_play(idle_clip,0.0)
func show_idle() -> void:
	show_running(false)
## Fuel burning or not: Run or Idle, both looping.
func show_running(on: bool) -> void:
	if _dying: return
	_running = on
	_play(run_clip if on else idle_clip,switch_blend)
func running() -> bool:
	return _running and not _dying
## Construction progress 0..1: from bare ground to the finished generator.
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
	_running = false
	player.play(death_clip)
	player.seek(0.0,true)
	if death_fx_scene: add_child(death_fx_scene.instantiate())
func _play(clip: StringName, blend: float) -> void:
	if player.is_playing() and player.assigned_animation == clip: return
	player.play(clip,blend if player.is_playing() else 0.0)
func _finished(clip: StringName) -> void:
	if clip == death_clip: queue_free()
