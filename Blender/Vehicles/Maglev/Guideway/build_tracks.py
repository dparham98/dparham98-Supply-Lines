"""Rebuild track geometry on the existing pieces, preserving markers, pivots and preview layouts."""
import argparse
from math import pi
from pathlib import Path
import sys
import bpy
from mathutils import Vector

HERE = Path(__file__).resolve().parent
SOURCE = HERE.parent / 'MaglevTracks.blend'
sys.dont_write_bytecode = True
sys.path.insert(0, str(HERE))
import guideway
from export_tracks import KINDS, export


def build(kinds):
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    bpy.context.preferences.filepaths.save_version = 0
    for kind in kinds:
        root = bpy.data.objects['track_' + kind]
        if kind.startswith('fork_'):
            from forks import build_fork
            build_fork(guideway, 1 if kind == 'fork_left' else -1, root)
        else:
            path = guideway.Path(0, 8) if kind == 'straight' else guideway.Path(1, 10 * pi)
            mesh = guideway.Builder()
            guideway.lane(mesh, path)
            guideway.install(root, mesh)
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type != 'VIEW_3D':
                continue
            viewport = area.spaces.active
            viewport.shading.light = 'STUDIO'
            viewport.shading.color_type = 'MATERIAL'
            viewport.shading.show_cavity = True
            viewport.overlay.show_overlays = False
            viewport.region_3d.view_location = (0, -12, .30)
            viewport.region_3d.view_distance = 64
            viewport.region_3d.view_perspective = 'ORTHO'
            viewport.region_3d.view_rotation = Vector((.58, .88, .90)).to_track_quat('Z', 'Y')
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE), compress=True)
    export(kinds)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pieces', nargs='+', choices=KINDS, default=KINDS)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
    build(args.pieces)
