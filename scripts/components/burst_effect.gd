extends Node3D
## Plays an effect clip authored in Blender: the tank's muzzle fire and its shell impact. Every part
## is keyed down to nothing at the end of the clip, so a finished effect shows nothing. The flash
## mesh's keyed scale also drives the light, which keeps the light on the same beat as the flame.
@export var clip := &"Fire"
@export var player_path := NodePath("Model/AnimationPlayer")
@export var flash_path: NodePath
@export var light_path: NodePath
@export_range(0,40,0.1) var light_energy := 5.0
## Play on spawn and remove the effect when the clip ends; otherwise it waits for play().
@export var one_shot := false
@onready var player: AnimationPlayer = get_node(player_path)
@onready var flash: Node3D = get_node(flash_path)
@onready var light: Light3D = get_node_or_null(light_path)
func _ready() -> void:
	# Effects are not part of a unit's body: no shadows, no picking, no selection outline.
	for node in find_children("*","MeshInstance3D",true,false):
		(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	set_meta(&"not_selectable",true)
	if one_shot:
		player.animation_finished.connect(func(_name: StringName) -> void: queue_free())
		play()
	else:
		player.play(clip)
		player.seek(player.current_animation_length,true)
		player.stop(true)
	_process(0.0)
func play() -> void:
	player.stop(true)
	player.play(clip)
	player.seek(0.0,true)
func _process(_delta: float) -> void:
	if light == null: return
	var strength := flash.scale.x if flash.scale.x > 0.01 else 0.0
	light.visible = strength > 0.0
	light.light_energy = light_energy*strength
