extends SceneTree
## Writes the Grail Sentinel's Cast clip (docs/MIST_AND_SLOW.md) to assets/models/units/grail_sentinel_cast.tres.
## The rig came without a Blender source, so the clip is keyed here from the bones' rests: the right (staff) arm
## sweeps up overhead, the body rises onto it, holds while the light bursts, then settles back to rest.
## Change the poses below and re-run rather than editing the .tres:
##   godot --headless --path . -s scripts/tools/build_sentinel_cast.gd
const MODEL := "res://assets/models/units/grail_sentinel.glb"
const TARGET := "res://assets/models/units/grail_sentinel_cast.tres"
const SKELETON := "Marine_Rig/Skeleton3D"
## Seconds: rise, burst (the spell lands at once in play, so the light comes as the arm reaches the top), settle.
const RAISED := 0.22
const HOLD := 0.52
const LENGTH := 0.9
## Bone turns away from rest at the top of the gesture, as (axis, degrees) in each bone's own frame.
const POSES := {
	"upper_arm.R": [Vector3(0,0,1),-150.0],
	"forearm.R": [Vector3(0,0,1),-12.0],
	"upper_arm.L": [Vector3(1,0,0),-35.0],
	"forearm.L": [Vector3(1,0,0),-25.0],
	"spine.03": [Vector3(1,0,0),-8.0],
	"neck": [Vector3(1,0,0),-10.0],
	"head": [Vector3(1,0,0),-8.0],
}
func _initialize() -> void:
	var model: Node = load(MODEL).instantiate()
	var run: Animation = (model.find_children("*","AnimationPlayer",true,false)[0] as AnimationPlayer).get_animation(&"Run")
	var skeleton: Skeleton3D = model.get_node(SKELETON)
	var clip := Animation.new()
	clip.length = LENGTH
	# Every bone the Run clip moves is keyed, so a cast started mid-stride settles the legs too.
	for i in range(run.get_track_count()):
		var path := run.track_get_path(i)
		var bone := skeleton.find_bone(path.get_concatenated_subnames())
		if bone < 0: continue
		var rest := skeleton.get_bone_rest(bone)
		var track := clip.add_track(run.track_get_type(i))
		clip.track_set_path(track,path)
		if run.track_get_type(i) == Animation.TYPE_POSITION_3D:
			clip.position_track_insert_key(track,0.0,rest.origin)
			clip.position_track_insert_key(track,LENGTH,rest.origin)
			continue
		var at_rest := rest.basis.get_rotation_quaternion()
		var pose: Array = POSES.get(String(path.get_concatenated_subnames()),[])
		var top := at_rest if pose.is_empty() else at_rest*Quaternion(pose[0],deg_to_rad(pose[1]))
		clip.rotation_track_insert_key(track,0.0,at_rest)
		clip.rotation_track_insert_key(track,RAISED,top)
		clip.rotation_track_insert_key(track,HOLD,top)
		clip.rotation_track_insert_key(track,LENGTH,at_rest)
	var library := AnimationLibrary.new()
	library.add_animation(&"Cast",clip)
	var err := ResourceSaver.save(library,TARGET)
	print("SAVED ",TARGET," tracks ",clip.get_track_count()," err ",err)
	model.free()
	quit()
