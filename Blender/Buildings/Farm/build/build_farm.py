"""Build the editable 10-metre vineyard. Follow with animate_farm.py and export_farm.py.

blender -b --factory-startup -P build/build_farm.py
Optional trailing argument: -- --blend /path/to/Farm.blend
"""
import argparse
from pathlib import Path
import sys

import bpy

HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
from vineyard_irrigation import build_sprayers, empty
from vineyard_mesh import material
from vineyard_rows import EDGE, create_ground, create_rows
from vineyard_pigments import dirt_paint, leaf_paint


def run():
    parser=argparse.ArgumentParser()
    parser.add_argument("--blend",type=Path,default=HERE.parent/"Farm.blend")
    args=parser.parse_args(sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else [])
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    scene=bpy.context.scene
    scene.render.fps=24
    scene.unit_settings.system="METRIC"
    coll=bpy.data.collections.new("farm")
    scene.collection.children.link(coll)
    root=empty("farm_root",coll,None,(0,0,0))
    mats={
        'ground':material("Vineyard soil and limestone",painted=True,roughness=.97),
        'detritus':material("Gravel and dry herbs",painted=True,roughness=.94),
        'botanic':material("Grapevine bark and leaves",painted=True,roughness=.82),
        'canopy':material("Hand-trained grape leaves",painted=True,roughness=.74),
        'fruit':material("Damson grape bloom",painted=True,roughness=.5),
        'machinery':material("Ceramic and alloy paint",painted=True,roughness=.43,metal=.29),
        'team':material("team_color",(.026,.083,.225),roughness=.33,metal=.28),
        'light':material("Water optics",(.23,.75,.82),roughness=.22,glow=.55),
        'spray':material("Travelling water glints",(.67,.84,.90),roughness=.23,alpha=.47,glow=.40),
    }
    dirt_paint(mats['ground'])
    leaf_paint(mats['canopy'],EDGE)
    create_ground(coll,root,mats['ground'],mats['detritus'])
    create_rows(coll,root,mats)
    build_sprayers(coll,root,mats)
    root['footprint_m']="10 x 10"
    root['fieldwork']="A permanent Farmer tends the near edge. Watering carriages run overhead in Work."
    root['number_of_vines']=42
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action='DESELECT')
    root.select_set(True)
    bpy.context.view_layer.objects.active=root
    from mathutils import Vector
    for area in bpy.context.screen.areas:
        if area.type=='VIEW_3D':
            space=area.spaces.active
            space.region_3d.view_rotation=Vector((8,-11,9)).to_track_quat('Z','Y')
            space.region_3d.view_location=(0,0,.35)
            space.region_3d.view_distance=15.2
            space.region_3d.view_perspective='ORTHO'
            space.shading.color_type='VERTEX'
            space.shading.type='MATERIAL'
            space.overlay.show_overlays=False
    args.blend.parent.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(args.blend),compress=True)
    print("VINEYARD BUILT",args.blend,len(coll.objects))

if __name__=='__main__':
    run()
