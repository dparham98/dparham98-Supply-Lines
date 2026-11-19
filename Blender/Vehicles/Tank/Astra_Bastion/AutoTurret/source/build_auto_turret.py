"""Build or export the Bastion with its independently traversing roof station.

blender -b --factory-startup --python-exit-code 1 -P build_auto_turret.py
blender -b Bastion_AutoTurret.blend --python-exit-code 1 -P build_auto_turret.py -- --export-only
"""
from math import radians
from pathlib import Path
import sys

import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

HERE = Path(__file__).resolve().parent
BASTION = HERE.parents[1]
DEST = HERE.parent / "export/Bastion_AutoTurret.glb"
EDITABLE = HERE / "Bastion_AutoTurret.blend"
sys.dont_write_bytecode = True
sys.path.insert(0, str(BASTION / "source"))
from forms import Forms, front_section, plan, round_section, xyz
from gear_export import export_tank


# In the hatch's frame, X is across the roof and F points forward.
STATION = (.67, -.16, 2.025)
BARREL_HEIGHT = .265
MUZZLE_FORWARD = 1.52


def materials():
    names = {
        "armor": "Bastion | graphite enamel",
        "edge": "Bastion | iron edge",
        "gun": "Bastion | barrel graphite",
        "steel": "Bastion | service steel",
        "rubber": "Bastion | rubber and gaskets",
        "shade": "Bastion | recessed steel",
        "bore": "Bastion | cavity",
    }
    return {key: bpy.data.materials[name] for key, name in names.items()}


def bearing(hatch, collection, palette):
    x, f, pivot = STATION
    flange = Forms()
    # Seat the stationary casting against the actual slope of the hatch at every corner.
    rim = plan(x-.376, x+.376, f-.373, f+.373, 0, .138, .13)
    foot = []
    for u, v, _ in rim:
        hit, point, _, _ = hatch.ray_cast((u,-v,6), (0,0,-1))
        if not hit:
            raise ValueError("Auxiliary bearing extends past the hatch")
        foot.append((u,v,point.z-.012))
    flange.loft([foot, [(u,v,pivot-.095) for u,v,_ in rim],
                 plan(x-.342,x+.342,f-.334,f+.334,pivot-.049,.112,.117)],
                lambda row,side: ("armor","edge")[row], "armor", "armor")
    flange.loft([round_section("z",pivot+z,(x,f),radius,20)
                 for z,radius in [(-.049,.305),(-.029,.325),(-.006,.325),(.010,.297)]],
                lambda row,side: ("shade","edge","rubber")[row], "shade","rubber")
    flange.finish("Aux_Bearing", hatch, collection, palette)


def receiver(hatch, collection, palette):
    head = Forms()
    # Faceted cast housing with a black travelling race below its skirt.
    head.loft([round_section("z",z,(0,0),r,20)
               for z,r in [(0,.235),(.014,.235),(.038,.313),(.088,.313)]],
              "shade","rubber","shade")
    sections = [(-.341,.370,-.49,.36,.054,.130,.094),
                (-.422,.442,-.537,.431,.115,.165,.119),
                (-.442,.450,-.534,.431,.25,.154,.110),
                (-.345,.365,-.410,.364,.433,.121,.102),
                (-.303,.326,-.369,.324,.46,.110,.084)]
    head.loft([plan(*section) for section in sections],
              lambda row,side: ("shade","armor","armor","edge")[row], "shade","armor")
    # Raised service cover and a dark seal on its outer cheek.
    def cheek(x, rear, front, bottom, top, trim):
        return [(x,rear+trim,bottom),(x,front-trim,bottom),(x,front,bottom+trim),
                (x,front,top-trim),(x,front-trim,top),(x,rear+trim,top),
                (x,rear,top-trim),(x,rear,bottom+trim)]
    cheek_rings = [cheek(x, rear, front, bottom, top, .046) for x,rear,front,bottom,top in
                   [(.356,-.38,.17,.100,.321),(.444,-.374,.160,.100,.304),
                    (.462,-.347,.139,.121,.280)]]
    head.loft(cheek_rings, lambda row,side: ("shade","gun")[row], "shade","gun")
    head.loft([round_section("x",x,(-.16,.20),radius,12)
               for x,radius in [(.46,.082),(.475,.082),(.481,.064)]],
              "shade","shade","edge")
    return head.finish("Aux_Turret",hatch,collection,palette,position=STATION)


def secondary_gun(head, collection, palette):
    gun = Forms()
    h = BARREL_HEIGHT
    # A compact square-jacketed pulse gun with a visibly recessed dark muzzle.
    profile = [(.265,.169,.132,.048),(.405,.184,.147,.050),
               (.551,.166,.133,.047),(.593,.127,.116,.036),
               (.794,.118,.109,.032),(.834,.092,.092,.028),
               (1.236,.092,.091,.026),(1.259,.112,.103,.026),
               (1.46,.112,.103,.026),(MUZZLE_FORWARD,.101,.094,.022),
               (MUZZLE_FORWARD,.062,.051,.013),(1.443,.059,.048,.013)]
    finishes = ("armor","gun","edge","gun","edge","gun","edge","gun","edge","gun","bore")
    gun.loft([front_section(0,f,h,w,height,trim,trim*.82)
              for f,w,height,trim in profile],
             lambda row,side: finishes[row], "shade","bore")
    gun.finish("Aux_Barrel",head,collection,palette)
    marker = bpy.data.objects.new("Aux_Muzzle",None)
    collection.objects.link(marker)
    marker.empty_display_type = 'PLAIN_AXES'
    marker.empty_display_size = .11
    marker.parent = head
    marker.location = xyz((0,MUZZLE_FORWARD,h))


def triangulated(objects):
    vertices, triangles = [], []
    for obj in objects:
        obj.data.calc_loop_triangles()
        start = len(vertices)
        vertices.extend(obj.matrix_world @ vertex.co for vertex in obj.data.vertices)
        triangles.extend(tuple(start + i for i in triangle.vertices)
                         for triangle in obj.data.loop_triangles)
    return vertices, triangles


def verify():
    head = bpy.data.objects["Aux_Turret"]
    marker = bpy.data.objects["Aux_Muzzle"]
    if marker.parent != head or head.parent.name != "Turret_Hatch":
        raise ValueError("Auxiliary turret hierarchy changed")
    bpy.context.view_layer.update()
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    rotating = [head] + [obj for obj in head.children_recursive if obj.type == "MESH"]
    fixed = [obj for obj in meshes if obj not in rotating and obj.name != "Aux_Bearing"]
    rv, rf = triangulated(rotating)
    fv, ff = triangulated(fixed)
    fixed_tree = BVHTree.FromPolygons(fv,ff,all_triangles=True)
    up = Vector((0,0,1))
    world_pivot = head.matrix_world.translation.copy()
    local = [vertex-world_pivot for vertex in rv]
    for degrees in range(360):
        yaw = Matrix.Rotation(radians(degrees),3,up)
        posed = [yaw @ vertex + world_pivot for vertex in local]
        moving_tree = BVHTree.FromPolygons(posed,rf,all_triangles=True)
        if fixed_tree.overlap(moving_tree):
            raise ValueError(f"Roof station intersects vehicle at yaw {degrees}")
    gap = min(v.z for v in rv)-max(v.z for v in fv)
    if gap <= 0:
        raise ValueError("Roof station no longer clears the vehicle's highest plane")
    barrel = bpy.data.objects["Aux_Barrel"]
    front = min((barrel.matrix_world @ vertex.co).y for vertex in barrel.data.vertices)
    if abs(marker.matrix_world.translation.y-front) > .00001:
        raise ValueError("Muzzle marker and lip have different forward positions")
    print(f"Auxiliary turret: 360 yaw samples clear, continuous minimum vertical separation "
          f"{gap*.6:.4f} world m above the original model. The fixed bearing is excluded.")


def run(export_only):
    if not export_only:
        bpy.ops.wm.open_mainfile(filepath=str(BASTION / "source/Bastion.blend"))
        hatch = bpy.data.objects["Turret_Hatch"]
        group = bpy.data.collections.new("Roof station")
        bpy.context.scene.collection.children.link(group)
        palette = materials()
        bearing(hatch,group,palette)
        head = receiver(hatch,group,palette)
        secondary_gun(head,group,palette)
    elif Path(bpy.data.filepath).resolve() != EDITABLE:
        raise ValueError(f"Open {EDITABLE.name} for a hand-edited export")
    verify()
    if not export_only:
        bpy.context.preferences.filepaths.save_version = 0
        bpy.ops.wm.save_as_mainfile(filepath=str(EDITABLE),compress=True)
    DEST.parent.mkdir(parents=True,exist_ok=True)
    export_tank(DEST)


if __name__ == "__main__":
    run("--export-only" in sys.argv)
