"""Build the editable Bastion source. Run in a fresh Blender background process."""
import argparse
from pathlib import Path
import sys

import bpy
from mathutils import Vector

HERE = Path(__file__).resolve().parent
PACKAGE = HERE.parent
PROJECT = next(path for path in PACKAGE.parents if (path / 'project.godot').is_file())
sys.dont_write_bytecode = True
sys.path.insert(0, str(HERE))
import forms
import hull
import turret


def draft_gear(parent):
    """Use the accepted guide meshes for the initial silhouette render."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(PROJECT / 'assets/models/units/tank.glb'))
    imported = set(bpy.data.objects) - before
    parts = [obj for obj in imported if obj.name.startswith(('Track_Links_', 'Road_Wheels_',
             'Drive_Sprocket_', 'Idler_Wheel_', 'Return_Rollers_'))]
    for obj in parts:
        transform = obj.matrix_world.copy()
        obj.parent = parent
        obj.matrix_world = transform
    for obj in imported - set(parts):
        bpy.data.objects.remove(obj, do_unlink=True)


def build(draft=None):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = 'METRIC'
    groups = {}
    for name in ('Hull', 'Skirts', 'Turret', 'Cannon', 'Optics and service'):
        group = bpy.data.collections.new(name)
        scene.collection.children.link(group)
        groups[name] = group
    root = bpy.data.objects.new('Tank_Root', None)
    groups['Hull'].objects.link(root)
    root.empty_display_type = 'PLAIN_AXES'
    root.empty_display_size = .25
    palette = forms.finish_palette()
    lower = hull.build(root,groups,palette)
    turret.build(lower,groups,palette)
    bpy.context.view_layer.update()
    if draft is not None:
        from render_studio import render
        draft_gear(lower)
        render(draft, draft=True)
        return
    from gear_export import add_running_gear, export_tank
    add_running_gear(lower)
    bpy.ops.object.select_all(action='DESELECT')
    bpy.context.view_layer.objects.active = lower
    for area in bpy.context.screen.areas:
        if area.type == 'VIEW_3D':
            view = area.spaces.active
            view.shading.color_type = 'MATERIAL'
            view.shading.light = 'STUDIO'
            view.shading.show_cavity = True
            view.overlay.show_overlays = False
            view.region_3d.view_rotation = Vector((.69,-.96,.54)).to_track_quat('Z','Y')
            view.region_3d.view_location = (0,-.72,1.67)
            view.region_3d.view_distance = 16
            view.region_3d.view_perspective = 'ORTHO'
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(HERE / 'Bastion.blend'), compress=True)
    (PACKAGE / 'export').mkdir(exist_ok=True)
    export_tank(PACKAGE / 'export/Bastion.glb')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--draft', type=Path, help='Render a shape study without saving the asset')
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    build(args.draft)
