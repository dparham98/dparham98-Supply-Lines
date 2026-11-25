"""Export the two gameplay GLBs from the editable Grenadier.blend using Blender 4.5."""
import argparse
from pathlib import Path
import sys
import bpy

# Preserve the paired cloth shell and lining. Trim extra detail on the rigid
# parts at export so the full-resolution source stays available for editing.
DETAIL = {
    "face": 8100, "hair": 2400, "cap": 1350, "goggles": 1550,
    "arm_upper": 1550, "hands": 1700, "legs": 1540, "shoulders": 1100,
    "boots": 1460, "belt": 3100, "backpack": 2110, "grenade_launcher": 2210,
    "tabard_plate": 410, "torso": 1140,
}

def export_looks(directory):
    rig = bpy.data.objects["grenadier_rig"]
    scene = bpy.context.scene
    animation = rig.animation_data
    children = list(rig.children)
    goggles = bpy.data.objects["goggles"]
    assert goggles in children
    view = bpy.context.view_layer
    original_frame = scene.frame_current
    selected = list(bpy.context.selected_objects)
    active = view.objects.active
    action = animation.action
    states = [(t, t.mute, t.is_solo) for t in animation.nla_tracks]
    hidden = [(o, o.hide_get(), o.hide_render) for o in [rig, *children]]
    levels = [(m, m.levels) for obj in children for m in obj.modifiers if m.type == "SUBSURF"]
    reduction = []
    try:
        animation.action = None
        for track, _, _ in states:
            track.is_solo = False
            track.mute = False
        for modifier, _ in levels:
            modifier.levels = 0
        for obj in children:
            if obj.name not in DETAIL:
                continue
            obj.data.calc_loop_triangles()
            count = len(obj.data.loop_triangles)
            if count > DETAIL[obj.name]:
                modifier = obj.modifiers.new("RTS export detail", "DECIMATE")
                modifier.ratio = DETAIL[obj.name] / count
                obj.modifiers.move(len(obj.modifiers)-1, 0)
                reduction.append((obj, modifier))
        bpy.ops.object.select_all(action="DESELECT")
        for obj, _, _ in hidden:
            obj.hide_set(False)
            obj.hide_render = False
            obj.select_set(True)
        view.objects.active = rig
        scene.frame_set(1)
        view.update()
        for look in ("Goggles","NoGoggles"):
            target = directory / look / "grenadier.glb"
            target.parent.mkdir(parents=True, exist_ok=True)
            goggles.select_set(look == "Goggles")
            bpy.ops.export_scene.gltf(
                filepath=str(target), export_format="GLB", use_selection=True,
                export_apply=True, export_yup=True, export_materials="EXPORT",
                export_lights=True, export_cameras=False, export_extras=False,
                export_animations=True, export_animation_mode="NLA_TRACKS",
            )
    finally:
        for obj, modifier in reduction:
            obj.modifiers.remove(modifier)
        for modifier, level in levels:
            modifier.levels = level
        for track, mute, solo in states:
            track.mute, track.is_solo = mute, solo
        animation.action = action
        scene.frame_set(original_frame)
        bpy.ops.object.select_all(action="DESELECT")
        for obj in selected:
            obj.select_set(True)
        for obj, viewport_hidden, render_hidden in hidden:
            obj.hide_set(viewport_hidden)
            obj.hide_render = render_hidden
        view.objects.active = active

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path(bpy.data.filepath).parent/"looks")
    args = parser.parse_args(sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else [])
    export_looks(args.output.resolve())
