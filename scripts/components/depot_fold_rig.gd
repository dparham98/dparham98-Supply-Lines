extends Node3D
## Plays the authored truck-to-warehouse fold-out on a newly deployed Depot. The scene's rest pose is
## the finished warehouse, so authored Depots show it with nothing running.
@export var player_path := NodePath("Warehouse/AnimationPlayer")
@export var fold_animation := &"deploy"
## Time for the truck to swing onto the Depot's heading and pull up to the site before unfolding.
@export_range(0.1,5,0.05) var line_up_seconds := 1.2
@onready var player: AnimationPlayer = get_node(player_path)
var _line_up: Tween
## Start from the closed truck: `from_world` is where the trailer stands now, `from_yaw` how far the
## truck is turned off the Depot's heading. Lines up with the Depot, then folds out.
func play_deploy(from_world: Vector3, from_yaw: float) -> void:
	player.play(fold_animation)
	player.seek(0.0,true)
	player.pause()
	global_position = from_world
	rotation.y = from_yaw
	_line_up = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT).set_parallel()
	_line_up.tween_property(self,"position",Vector3.ZERO,line_up_seconds)
	_line_up.tween_property(self,"rotation:y",0.0,line_up_seconds)
	_line_up.chain().tween_callback(player.play.bind(fold_animation))
func deploying() -> bool:
	return is_instance_valid(_line_up) and _line_up.is_running() or player.is_playing()
