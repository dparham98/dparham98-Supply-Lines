"""Export the rigged & animated Azure Dragon to glTF Binary (.glb) and optionally verify the export.

Export from open/saved Azure_Dragon.blend:
  "C:/Program Files/Blender Foundation/Blender 4.5/blender.exe" -b --factory-startup "Blender/Characters/AzureDragon/source/Azure_Dragon.blend" --python-exit-code 1 -P "Blender/Characters/AzureDragon/source/export_dragon.py"

Verify exported azure_dragon.glb in a clean scene:
  "C:/Program Files/Blender Foundation/Blender 4.5/blender.exe" -b --factory-startup --python-exit-code 1 -P "Blender/Characters/AzureDragon/source/export_dragon.py" -- --verify
"""

import argparse
from pathlib import Path
import sys

import bpy
from mathutils import Matrix, Vector


HERE = Path(__file__).resolve().parent
PACKAGE = HERE.parent
DEFAULT_EXPORT = PACKAGE / "export" / "azure_dragon.glb"


def export_glb(col, rig, output_path):
    """Export the dragon collection with all NLA tracks unmuted and Armature skinning preserved."""
    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    scene = bpy.context.scene
    anim = rig.animation_data
    if not anim or not any(track.strips for track in anim.nla_tracks):
        raise ValueError("Azure_Dragon_Rig has no NLA tracks to export")

    prior_pose_pos = rig.data.pose_position
    prior_action = anim.action
    prior_use_nla = anim.use_nla
    prior_mutes = {t.name: t.mute for t in anim.nla_tracks}
    prior_frame = scene.frame_current

    light_obj = bpy.data.objects.get("Breath_Light")
    light_anim = light_obj.data.animation_data if (light_obj and light_obj.data) else None
    prior_light_mutes = {t.name: t.mute for t in light_anim.nla_tracks} if light_anim else {}

    # Sample four times per authoring frame. Stance and talon rollover are
    # authored at subframes; scene seconds stay identical in all three clips.
    # Restore the timeline afterwards for normal Blender editing and playback.
    sample_factor = 4
    original_fps = scene.render.fps
    strip_scales = [(strip, strip.scale) for data in (anim, light_anim) if data
                    for track in data.nla_tracks for strip in track.strips]
    try:
        scene.render.fps = original_fps * sample_factor
        for strip, original_scale in strip_scales:
            strip.scale = original_scale * sample_factor
        rig.data.pose_position = "POSE"
        anim.action = None
        anim.use_nla = True
        for track in anim.nla_tracks:
            track.is_solo = False
            track.mute = False
            for strip in track.strips:
                strip.extrapolation = "NOTHING"

        if light_anim:
            light_anim.action = None
            light_anim.use_nla = True
            for track in light_anim.nla_tracks:
                track.is_solo = False
                track.mute = False

        for pb in rig.pose.bones:
            pb.matrix_basis = Matrix.Identity(4)
            pb.scale = Vector((1.0, 1.0, 1.0))

        bpy.ops.object.select_all(action="DESELECT")
        for obj in col.objects:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = rig
        scene.frame_set(0)
        bpy.context.view_layer.update()

        bpy.ops.export_scene.gltf(
            filepath=str(output_path),
            export_format="GLB",
            use_selection=True,
            export_yup=True,
            export_apply=False,
            export_animations=True,
            export_animation_mode="NLA_TRACKS",
            export_frame_range=False,
            export_anim_slide_to_zero=True,
            export_force_sampling=True,
            export_rest_position_armature=True,
            export_skins=True,
            export_def_bones=False,
            export_lights=True,
            export_cameras=False,
            export_normals=True,
            export_vertex_color="MATERIAL",
            export_all_vertex_colors=False,
        )
        print(f"Exported skinned glTF with NLA tracks {[t.name for t in anim.nla_tracks]} -> {output_path}")
    finally:
        for strip, original_scale in strip_scales:
            strip.scale = original_scale
        scene.render.fps = original_fps
        rig.data.pose_position = prior_pose_pos
        anim.action = prior_action
        anim.use_nla = prior_use_nla
        for track in anim.nla_tracks:
            if track.name in prior_mutes:
                track.mute = prior_mutes[track.name]
        if light_anim:
            for track in light_anim.nla_tracks:
                if track.name in prior_light_mutes:
                    track.mute = prior_light_mutes[track.name]
        for pb in rig.pose.bones:
            pb.matrix_basis = Matrix.Identity(4)
            pb.scale = Vector((1.0, 1.0, 1.0))
        scene.frame_set(prior_frame)
        bpy.context.view_layer.update()


def _world_bbox(objs):
    deps = bpy.context.evaluated_depsgraph_get()
    pts = []
    for ob in objs:
        ev = ob.evaluated_get(deps)
        mesh = ev.to_mesh()
        for v in mesh.vertices:
            pts.append(ev.matrix_world @ v.co)
        ev.to_mesh_clear()
    xs = [p.x for p in pts]
    ys = [p.y for p in pts]
    zs = [p.z for p in pts]
    return Vector((min(xs), min(ys), min(zs))), Vector((max(xs), max(ys), max(zs)))


def _find_imported_action(name):
    if name in bpy.data.actions:
        return bpy.data.actions[name]
    for act in bpy.data.actions:
        if act.name == name or act.name.startswith(name + "."):
            return act
    return None


def verify_glb(glb_path):
    """Import azure_dragon.glb into a clean scene and validate skeleton, clips, ground contact, and AOE cone."""
    glb_path = Path(glb_path)
    if not glb_path.is_file():
        raise FileNotFoundError(f"Missing export file: {glb_path}")

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(glb_path))
    scene = bpy.context.scene

    rigs = [o for o in bpy.data.objects if o.type == "ARMATURE"]
    if len(rigs) != 1:
        raise AssertionError(f"Expected 1 Armature in imported GLB, found {len(rigs)}")
    rig = rigs[0]

    required_bones = [
        "root", "pelvis", "spine.01", "chest", "neck.01", "neck.02", "head", "jaw",
        "Rider_Mount", "breath_muzzle", "breath_origin",
        "breath_seg_0", "breath_seg_1", "breath_seg_2", "breath_seg_3",
        "fore_foot.L", "fore_foot.R", "hind_foot.L", "hind_foot.R",
    ]
    missing_bones = [b for b in required_bones if b not in rig.data.bones]
    if missing_bones:
        raise AssertionError(f"Missing required bones in imported GLB: {missing_bones}")

    # Check vertex colors survived glTF export
    wing_l = bpy.data.objects.get("Dragon_Wing_Membrane_L")
    cone_outer = bpy.data.objects.get("Dragon_Fire_Cone_Outer")
    if not wing_l or not wing_l.data.color_attributes:
        raise AssertionError("Dragon_Wing_Membrane_L lost its vertex colors on GLB export")
    if not cone_outer or not cone_outer.data.color_attributes:
        raise AssertionError("Dragon_Fire_Cone_Outer lost its vertex colors on GLB export")

    # Check actions
    anim = rig.animation_data
    if not anim:
        raise AssertionError("Imported rig has no animation_data")
    anim.use_nla = False
    actions = {}
    for clip in ("Rest", "Walk", "FireBreath"):
        act = _find_imported_action(clip)
        if act is None:
            raise AssertionError(f"Missing imported action '{clip}'. Available: {[a.name for a in bpy.data.actions]}")
        actions[clip] = act

    # Check Walk ground contact across every 2 frames
    paw_objs = [
        ob for ob in bpy.data.objects
        if ob.type == "MESH" and ("_Forefoot_" in ob.name or "_Hindfoot_" in ob.name)
    ]
    if len(paw_objs) < 8:
        raise AssertionError(f"Expected foot meshes, found {len(paw_objs)}")

    anim.action = actions["Walk"]
    walk_start = int(round(actions["Walk"].frame_range[0]))
    walk_end = int(round(actions["Walk"].frame_range[1]))
    min_z_all, max_min_z = 999.0, -999.0
    for f in range(walk_start, walk_end + 1, 2):
        scene.frame_set(f)
        bpy.context.view_layer.update()
        bmin, _ = _world_bbox(paw_objs)
        min_z_all = min(min_z_all, bmin.z)
        max_min_z = max(max_min_z, bmin.z)
    print(f"Walk foot ground Z range across loop: [{min_z_all:.4f}, {max_min_z:.4f}] m")
    if min_z_all < -0.04 or max_min_z > 0.06:
        raise AssertionError(f"Walk foot contact out of [-0.04, 0.06] m tolerance: [{min_z_all:.4f}, {max_min_z:.4f}]")

    # Check FireBreath cone collapse at start & full AOE spread at peak blast
    anim.action = actions["FireBreath"]
    fb_start = int(round(actions["FireBreath"].frame_range[0]))
    scene.frame_set(fb_start)
    bpy.context.view_layer.update()
    cmin0, cmax0 = _world_bbox([cone_outer])
    size0 = cmax0 - cmin0
    max_dim0 = max(size0.x, size0.y, size0.z)
    print(f"FireBreath start frame {fb_start} Dragon_Fire_Cone_Outer bbox size: {tuple(round(v, 4) for v in size0)}")
    if max_dim0 >= 0.08:
        raise AssertionError(f"FireBreath cone failed to collapse at start frame: max_dim={max_dim0:.4f} m")

    peak_frame = fb_start + 29
    scene.frame_set(peak_frame)
    bpy.context.view_layer.update()
    cmin_p, cmax_p = _world_bbox([cone_outer])
    size_p = cmax_p - cmin_p
    print(f"FireBreath peak frame {peak_frame} Dragon_Fire_Cone_Outer bbox size: {tuple(round(v, 3) for v in size_p)}")
    if size_p.y < 7.0 or size_p.x < 2.6:
        raise AssertionError(
            f"FireBreath AOE cone too small at peak frame {peak_frame}: length={size_p.y:.3f} m, width={size_p.x:.3f} m"
        )

    print("ALL GLB VERIFICATION CHECKS PASSED!")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_EXPORT)
    parser.add_argument("--verify", action="store_true")
    opts = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    if opts.verify:
        verify_glb(opts.output)
    else:
        col = bpy.data.collections["azure_dragon"]
        rig = bpy.data.objects["Azure_Dragon_Rig"]
        export_glb(col, rig, opts.output)
