"""Export the four authored roots in the currently open MaglevTracks.blend."""
from pathlib import Path
import bpy

KINDS = ('straight', 'curve', 'fork_left', 'fork_right')
DEST = Path(__file__).resolve().parents[4] / 'assets/models/rails'


def export(kinds=KINDS, destination=DEST):
    layer = bpy.context.view_layer
    source = layer.layer_collection.children['maglev_tracks']
    excluded = source.exclude
    active = layer.objects.active
    selected = list(bpy.context.selected_objects)
    try:
        source.exclude = False
        layer.update()
        for kind in kinds:
            root = bpy.data.objects['track_' + kind]
            bpy.ops.object.select_all(action='DESELECT')
            for ob in [root, *root.children_recursive]:
                ob.select_set(True)
            layer.objects.active = root
            bpy.ops.export_scene.gltf(filepath=str(destination / f'maglev_track_{kind}.glb'),
                export_format='GLB',use_selection=True,export_yup=True,export_apply=True,
                export_animations=False,export_lights=False,export_cameras=False,
                export_texcoords=False,export_tangents=False,export_extras=False)
    finally:
        bpy.ops.object.select_all(action='DESELECT')
        source.exclude = excluded
        layer.update()
        for ob in selected:
            if layer.objects.get(ob.name):
                ob.select_set(True)
        layer.objects.active = active


if __name__ == '__main__':
    export()
