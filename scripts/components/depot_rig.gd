extends Node3D
## Plays the Depot's authored clips (docs/DEPOT_MODEL.md). The rest pose is the finished warehouse with
## its tractor at home, so authored Depots show it with nothing running.
@export var player_path := NodePath("Warehouse/AnimationPlayer")
@export var fold_animation := &"deploy"
@export var exit_animation := &"tractor_exit"
@export var assemble_animation := &"assemble"
@export var tractor_path := NodePath("Warehouse/warehouse_root/warehouse_power_unit")
@export var assembly_path := NodePath("TruckAssembly")
## Ground the new truck needs beside the Depot, in this scene's space.
@export var truck_side := AABB(Vector3(5.4,0,-6.7),Vector3(3.2,0,15.4))
## Time for the truck to swing onto the Depot's heading and pull up to the site before unfolding.
@export_range(0.1,5,0.05) var line_up_seconds := 1.2
@onready var player: AnimationPlayer = get_node(player_path)
@onready var tractor: Node3D = get_node(tractor_path)
@onready var assembly: Node3D = get_node(assembly_path)
@onready var assembly_player: AnimationPlayer = assembly.get_node("Rig/AnimationPlayer")
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
func truck_seconds() -> float:
	return _exit_seconds()+assembly_player.get_animation(assemble_animation).length
## Pose the truck production `seconds` in: the tractor pulls out, then the trailer is built behind
## it. Depot progress drives this, so a cancelled truck simply runs it backwards.
func show_truck(seconds: float) -> void:
	var exit_seconds := _exit_seconds()
	var assembling := seconds > exit_seconds
	tractor.visible = not assembling
	assembly.visible = assembling
	_pose(player,exit_animation,minf(seconds,exit_seconds))
	if assembling: _pose(assembly_player,assemble_animation,seconds-exit_seconds)
## The tractor has left as the new truck, so the Depot stands without one until the next is ordered.
func finish_truck() -> void:
	show_truck(0.0)
	tractor.visible = false
func _exit_seconds() -> float:
	return player.get_animation(exit_animation).length
func _pose(clip_player: AnimationPlayer, clip: StringName, seconds: float) -> void:
	if clip_player.assigned_animation != clip: clip_player.assigned_animation = clip
	clip_player.seek(seconds,true)
