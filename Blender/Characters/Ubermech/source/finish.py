"""Sparse chipped paint and service scratches on the exposed edges of large castings."""
import random
from collections import defaultdict
from zlib import crc32

import bpy
from mathutils import Vector

import mech


# Castings with exposed painted edges, preferred face normal and wear density.
# Emblems, instrument lenses, bearings and the face are separate clean parts.
PANELS = [
    ("Shoulder | front casting", "front", 20),
    ("Shoulder | faction flash", "front", 7),
    ("Shoulder | rear inspection cover", "back", 8),
    ("Pod | side cassette", "out", 8),
    ("Pod | service cover", "top", 7),
    ("Forearm | shield enamel", "front", 9),
    ("Forearm | segmented cheek", "any", 4),
    ("Central breastplate", "front", 14),
    ("Raised gorget wing", "front", 6),
    ("Rib armor", "front", 4),
    ("Hanging central coat armor", "front", 12),
    ("Upper thigh shield", "front", 7),
    ("Kneecap striking plate", "front", 6),
    ("Greave front strike face", "front", 10),
    ("Outboard greave skirt", "out", 6),
    ("Greave team chevron", "out", 4),
    ("Instep sliding tongue", "top", 5),
]
MATERIALS=("edge","joint","steel")


def panel_edges(obj,graph,side):
    evaluated=obj.evaluated_get(graph)
    data=evaluated.to_mesh()
    try:
        outward=1 if obj["joint"].endswith(".L") else -1
        view={"front":(0,-1,0),"back":(0,1,0),"out":(outward,0,0),"top":(0,0,1)}
        polygons=list(data.polygons)
        if side=="any":
            direction=max(polygons,key=lambda p:p.area).normal
        else:
            direction=Vector(view[side])
        active={p.index for p in polygons if p.area>.012 and p.normal.dot(direction)>.57}
        edges=defaultdict(list)
        for p in polygons:
            for key in p.edge_keys:
                edges[key].append(p.index)
        candidates=[]
        for key,faces in edges.items():
            outside=[i for i in faces if i in active]
            if len(outside)!=1:
                continue
            face=polygons[outside[0]]
            a,b=(obj.matrix_world @ data.vertices[v].co for v in key)
            length=(b-a).length
            if length<.09:
                continue
            norm=(obj.matrix_world.to_3x3() @ face.normal).normalized()
            along=(b-a)/length
            inward=norm.cross(along)
            ctr=obj.matrix_world @ face.center
            if (ctr-a).dot(inward)<0:
                inward=-inward
            depth=(ctr-a).dot(inward)
            if depth>.014:
                candidates.append((a,b,along,inward,norm,length,depth))
        return candidates
    finally:
        evaluated.to_mesh_clear()


def cut(batch,centre,along,inward,normal,length,width,material,rng,offset):
    verts,faces,indices=batch
    # Tapered ends, uneven shoulder and one angular notch. No rectangular
    # metallic confetti, and the small scratches do not enlarge the silhouette.
    corners=[(-.52,-.08),(-.29,-.42),(.06,-.31),(.20,-.50),(.48,-.18),
             (.52,.10),(.12,.33),(-.08,.49),(-.38,.23)]
    p=centre+normal*offset
    new=[p+along*(length*x)+inward*(width*y*rng.uniform(.80,1.16)) for x,y in corners]
    if (new[1]-new[0]).cross(new[2]-new[0]).dot(normal)<0:
        new.reverse()
    faces.append(tuple(range(len(verts),len(verts)+len(new))))
    indices.append(material);verts.extend(new)


def build(pieces):
    """Return additional rigid meshes to append to the list passed to rig.create."""
    bpy.context.view_layer.update()
    graph=bpy.context.evaluated_depsgraph_get()
    batches=defaultdict(lambda:([],[],[]))
    for obj in sorted(pieces,key=lambda p:p.name):
        profile=next((entry for entry in PANELS if obj.name.startswith(entry[0])),None)
        if not profile:
            continue
        _,side,count=profile
        edges=panel_edges(obj,graph,side)
        if not edges:
            continue
        rng=random.Random(crc32(obj.name.encode("utf8")))
        batch=batches[obj["joint"]]
        weights=[edge[5] for edge in edges]
        for i,edge in enumerate(rng.choices(edges,weights=weights,k=count)):
            a,b,along,inward,norm,span,depth=edge
            t=rng.uniform(.17,.83)
            scale=min(1.,span/.29)
            gouge=i%8==5
            length=rng.uniform(.042,.082)*scale if gouge else rng.uniform(.012,.044)*scale
            width=rng.uniform(.0028,.0056) if gouge else rng.uniform(.0055,.014)*scale
            inset=min(depth*.38,rng.uniform(.016,.047) if gouge else rng.uniform(.0045,.032))
            tilt=rng.uniform(-.48,.65) if gouge else rng.uniform(-.24,.26)
            if gouge:
                inset=max(inset,length*abs(tilt)*.5+width*.6)
            direction=(along+inward*tilt).normalized()
            across=(inward-along*tilt).normalized()
            centre=a.lerp(b,t)+inward*inset
            mat="joint" if gouge else rng.choices(MATERIALS,weights=(55,26,19))[0]
            cut(batch,centre,direction,across,norm,length,width,mat,rng,.0011)
            if gouge or (length>.027 and rng.random()<.43):
                edge_centre=centre+across*width*.31+direction*length*.09
                cut(batch,edge_centre,direction,across,norm,length*.60,width*.29,
                    "edge" if gouge else "steel",rng,.00135)
    result=[]
    for joint,(verts,faces,indices) in sorted(batches.items()):
        obj=mech.mesh("Paint wear | "+joint,verts,faces,"edge",joint)
        obj.data.materials.append(mech.material("joint"))
        obj.data.materials.append(mech.material("steel"))
        for poly,mat in zip(obj.data.polygons,indices):
            poly.material_index=MATERIALS.index(mat)
        result.append(obj)
    return result
