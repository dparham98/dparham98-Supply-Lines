"""Export the two Farm collections and check their bounds, watering rig and clips by clean reimport."""
import argparse
from pathlib import Path
import sys

import bpy
from mathutils import Vector

HERE=Path(__file__).resolve().parent


def export_collection(collection,path):
    bpy.ops.object.select_all(action='DESELECT')
    objects=list(bpy.data.collections[collection].all_objects)
    for obj in objects:
        obj.hide_set(False)
        obj.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
    path.parent.mkdir(parents=True,exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,
        export_yup=True,export_cameras=False,export_lights=False,export_extras=False,
        export_animations=True,export_animation_mode='NLA_TRACKS',export_force_sampling=False,
        export_optimize_animation_size=True,export_optimize_animation_keep_anim_object=True,
        export_vertex_color='ACTIVE',export_all_vertex_colors=False)
    print("EXPORTED",path,len(objects),"objects",path.stat().st_size,"bytes")


def import_and_activate(path,clip):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(path))
    clips=set()
    for obj in bpy.context.scene.objects:
        if not obj.animation_data:continue
        obj.animation_data.action=None
        for track in obj.animation_data.nla_tracks:
            clips.update(strip.name for strip in track.strips)
            track.mute=not any(strip.name==clip for strip in track.strips)
    bpy.context.scene.frame_set(0)
    bpy.context.view_layer.update()
    return clips


def verify(main,fx):
    clips=import_and_activate(main,"Idle")
    assert clips=={"Idle","Work","Depleted","Build","Die"},clips
    vertices=[]
    obj=bpy.data.objects
    for o in bpy.context.scene.objects:
        if o.type=='MESH': vertices.extend(o.matrix_world @ Vector(p) for p in o.bound_box)
    lo,hi = [Vector(tuple(fn(v[i] for v in vertices) for i in range(3))) for fn in (min,max)]
    assert -5.002<=lo.x<-4.8 and -5.002<=lo.y<-4.8 and 4.8<hi.x<=5.002 and 4.8<hi.y<=5.002,(lo,hi)
    assert -.01<=lo.z<=.05 and .90<hi.z<1.90,(lo,hi)
    assert 'team_color' in bpy.data.materials
    assert all(f"Vine_row_{i:02d}" in obj for i in range(1,7))
    assert max(obj['Water_West'].scale)<.002
    assert 'Vineyard_water_mist' in bpy.data.images
    assert bpy.data.images['Vineyard_water_mist'].packed_file
    for o in bpy.context.scene.objects:
        if not o.animation_data:continue
        for track in o.animation_data.nla_tracks:
            track.mute=not any(strip.name=="Work" for strip in track.strips)
    scene=bpy.context.scene
    scene.frame_set(0)
    start=obj['Irrigator_West'].location.copy()
    assert min(obj['Water_West'].scale)>.9
    scene.frame_set(96)
    assert (obj['Irrigator_West'].location-start).length>5
    scene.frame_set(192)
    assert (obj['Irrigator_West'].location-start).length<.01
    meshes=[o for o in scene.objects if o.type=='MESH']
    tris=sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in meshes)
    print("VINEYARD VERIFIED",sorted(clips),"bounds",lo,hi,len(meshes),"mesh nodes,",tris,"triangles, packed mist and both active/inactive states")
    assert import_and_activate(fx,"Death")=={'Death'}
    assert bpy.data.objects.get("Valve_flash")


def main():
    parser=argparse.ArgumentParser()
    dest=parser.add_mutually_exclusive_group()
    dest.add_argument("--out",type=Path,default=HERE.parent/"export")
    dest.add_argument("--to-assets",action="store_true")
    args=parser.parse_args(sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else [])
    assets=HERE.parents[3]/"assets/models"
    main=(assets/'buildings' if args.to_assets else args.out)/"farm.glb"
    fx=(assets/'effects' if args.to_assets else args.out)/"farm_death_fx.glb"
    for layer in bpy.context.view_layer.layer_collection.children: layer.exclude=False
    for obj in bpy.context.scene.objects:
        if obj.animation_data:
            for tr in obj.animation_data.nla_tracks:tr.mute=False
    bpy.context.scene.frame_set(0)
    export_collection("farm",main)
    export_collection("farm_death_fx",fx)
    verify(main,fx)

if __name__=='__main__':main()
