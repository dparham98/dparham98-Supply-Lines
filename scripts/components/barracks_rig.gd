extends Node3D
## Plays the Barracks' authored clips (docs/BARRACKS_MODEL.md): Idle while nothing prints, Build scrubbed
## by construction progress, Print following production, and Die when the Barracks is destroyed. The rest
## pose is the finished hall with its door closed and its cradle empty.
@export var player_path := NodePath("Rig/AnimationPlayer")
@export var idle_clip := &"Idle"
@export var build_clip := &"Build"
@export var print_clip := &"Print"
@export var death_clip := &"Die"
## Seconds into Print when the printed figure reaches the door; the real unit appears outside then.
## Print time is scaled onto 0..this, and the rest of the clip (the door closing) plays at normal speed.
@export_range(0.1,10,0.05) var print_spawn_seconds := 4.0
## Spawned on this model at death (fire, smoke, scrap); built on the same timeline as the clip.
@export var death_fx_scene: PackedScene
@onready var player: AnimationPlayer = get_node(player_path)
var _dying := false
var _closing := false
func _ready() -> void:
	player.animation_finished.connect(_finished)
	show_idle()
func show_idle() -> void:
	if _dying or _closing: return
	if player.is_playing() and player.assigned_animation == idle_clip: return
	player.play(idle_clip)
## Construction progress 0..1: from bare ground to the finished hall.
func show_construction(fraction: float) -> void:
	if _dying: return
	_pose(build_clip,clampf(fraction,0.0,1.0)*player.get_animation(build_clip).length)
## Production progress 0..1 of the unit now printing. At 1 the figure waits at the open door.
func show_print(fraction: float) -> void:
	if _dying or _closing: return
	_pose(print_clip,clampf(fraction,0.0,1.0)*print_spawn_seconds)
## The printed unit has stepped out: the door closes behind it, then the hall idles again.
func unit_left() -> void:
	if _dying: return
	_closing = true
	player.play(print_clip)
	player.seek(print_spawn_seconds,true)
func closing() -> bool:
	return _closing
func has_death_clip() -> bool:
	return player != null and player.has_animation(death_clip)
func dying() -> bool:
	return _dying
## The wreck plays out, sinks out of sight and removes itself.
func play_death() -> void:
	_dying = true
	_closing = false
	player.play(death_clip)
	player.seek(0.0,true)
	if death_fx_scene: add_child(death_fx_scene.instantiate())
func _finished(clip: StringName) -> void:
	if clip == death_clip: queue_free()
	elif clip == print_clip and _closing:
		_closing = false
		show_idle()
func _pose(clip: StringName, seconds: float) -> void:
	if player.is_playing(): player.pause()
	if player.assigned_animation != clip: player.assigned_animation = clip
	player.seek(seconds,true)
