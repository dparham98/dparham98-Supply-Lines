"""Shared hard-surface construction tools for the Ubermech, in Blender world space."""
from math import cos, pi, sin
from pathlib import Path
import random
import struct
import tempfile
import zlib

import bmesh
import bpy
from mathutils import Vector
import numpy as np


# sRGB paint, metallic fraction, roughness, emission strength.
PALETTE = {
    "graphite": ("363337", .53, .49, 0), "plate": ("4b4749", .50, .49, 0),
    "edge": ("6d6765", .68, .44, 0), "joint": ("29282b", .76, .39, 0),
    "steel": ("99918b", .81, .31, 0), "black": ("19191c", .22, .58, 0),
    "ivory": ("c5aa92", .44, .40, 0), "bone_shadow": ("867164", .54, .46, 0),
    "enamel": ("a62619", .52, .34, 0), "team_color": ("be3624", .44, .40, 0),
    "glow_red": ("fc1908", .22, .34, 1.3), "glow_core": ("ffc596", .08, .28, 2.6),
    "white": ("dbd4c5", .25, .50, 0), "warning": ("ec9237", .48, .41, .12),
}


def color(hex_color):
    srgb = [int(hex_color[i:i+2], 16)/255 for i in (0, 2, 4)]
    return tuple(c/12.92 if c <= .04045 else ((c+.055)/1.055)**2.4 for c in srgb)+(1,)


def finish_texture(key, hex_color):
    # A repeatable square of fine cast-metal variation with scattered fine nicks.
    # Pack the same PNG used as base color into both the editable file and glTF.
    size = 384
    seed = list(PALETTE).index(key)+81
    rng = np.random.default_rng(seed)
    choice = random.Random(seed)
    base = np.array([int(hex_color[i:i+2],16) for i in (0,2,4)])
    grain = rng.normal(0, 2.1, (size,size))
    y,x = np.indices((size,size))
    for frequency, strength in [(2,1.7),(5,1.2),(13,.8)]:
        grain += strength*np.sin((x+2*y)*2*pi*frequency/size+choice.random()*3)*np.cos(y*2*pi*frequency/size)
    pixels = np.clip(base+grain[:,:,None],0,255).astype(np.uint8)
    for _ in range(83):
        cx,cy = choice.randrange(size), choice.randrange(size)
        length = choice.uniform(1.2,7.5); angle=choice.uniform(0,pi)
        for j in range(int(length*2)):
            px,py = int(cx+.5*j*cos(angle))%size,int(cy+.5*j*sin(angle))%size
            pixels[py,px] = base + np.array((23,20,17))*choice.uniform(.28,1)
    def chunk(tag, data):
        return struct.pack(">I",len(data))+tag+data+struct.pack(">I",zlib.crc32(tag+data))
    png = (b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",size,size,8,2,0,0,0))
           +chunk(b"IDAT",zlib.compress(b"".join(b"\0"+row.tobytes() for row in pixels),9))+chunk(b"IEND",b""))
    name = "Ubermech_"+key+"_finish"
    with tempfile.TemporaryDirectory() as temp:
        path=Path(temp)/(name+".png")
        path.write_bytes(png)
        image=bpy.data.images.load(str(path))
        image.name=name
        image.pack()
        image.filepath="//"+name+".png"
    return image


def material(key):
    if isinstance(key,bpy.types.Material):
        return key
    mat=bpy.data.materials.get(key)
    if mat:
        return mat
    tone,metal,rough,emission=PALETTE[key]
    mat=bpy.data.materials.new(key)
    mat.diffuse_color=color(tone)
    mat.use_nodes=True
    bsdf=mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value=mat.diffuse_color
    bsdf.inputs["Metallic"].default_value=metal
    bsdf.inputs["Roughness"].default_value=rough
    if emission:
        bsdf.inputs["Emission Color"].default_value=mat.diffuse_color
        bsdf.inputs["Emission Strength"].default_value=emission
    if key in {"graphite","plate","edge"}:
        tex=mat.node_tree.nodes.new("ShaderNodeTexImage")
        tex.image=finish_texture(key,tone)
        mat.node_tree.links.new(tex.outputs["Color"],bsdf.inputs["Base Color"])
    return mat


def mesh(name, verts, faces, mat, group, bevel=0):
    data=bpy.data.meshes.new(name)
    data.from_pydata(verts,[],faces)
    data.update()
    bm=bmesh.new()
    bm.from_mesh(data)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bm.to_mesh(data)
    bm.free()
    uv=data.uv_layers.new(name="UVMap")
    for poly in data.polygons:
        n=poly.normal
        major=max(range(3),key=lambda i:abs(n[i]))
        for idx in poly.loop_indices:
            x,y,z=data.vertices[data.loops[idx].vertex_index].co
            u,v=((y,z),(x,z),(x,y))[major]
            uv.data[idx].uv=(u*.85,v*.85)
    obj=bpy.data.objects.new(name,data)
    collection=bpy.data.collections.get(group)
    if collection is None:
        collection=bpy.data.collections.new(group)
        bpy.context.scene.collection.children.link(collection)
    collection.objects.link(obj)
    obj["joint"]=group
    data.materials.append(material(mat))
    if bevel>0:
        mod=obj.modifiers.new("Machined chamfers","BEVEL")
        mod.width=bevel
        mod.segments=1 if bevel>.02 else 2
        mod.harden_normals=True
        if mat in {"plate","graphite"} and bevel>=.03:
            data.materials.append(material("edge"))
            mod.material=1
        wn=obj.modifiers.new("Weighted panel normals","WEIGHTED_NORMAL")
        wn.keep_sharp=True
    return obj


def shell(name, levels, mat, group, bevel=.025):
    count=len(levels[0][1])
    verts=[(x,y,z) for z,row in levels for x,y in row]
    faces=[tuple(reversed(range(count)))]
    for k in range(len(levels)-1):
        for i in range(count):
            j=(i+1)%count
            faces.append((k*count+i,k*count+j,(k+1)*count+j,(k+1)*count+i))
    faces.append(tuple(range(len(verts)-count,len(verts))))
    return mesh(name,verts,faces,mat,group,bevel)


def box(name,center,size,mat,group,bevel=.035):
    x,y,z=center
    a,b,c=[k*.5 for k in size]
    corners=[(x-a,y-b),(x+a,y-b),(x+a,y+b),(x-a,y+b)]
    return shell(name,[(z-c,corners),(z+c,corners)],mat,group,bevel)


def rod(name,a,b,radius,mat,group,sides=16,bevel=.012):
    a,b=Vector(a),Vector(b)
    axis=(b-a).normalized()
    u=axis.orthogonal().normalized()
    v=axis.cross(u)
    ring=[radius*(cos(2*pi*i/sides)*u+sin(2*pi*i/sides)*v) for i in range(sides)]
    vs=[p+d for p in (a,b) for d in ring]
    fs=[list(range(sides)),list(range(sides,2*sides))]
    fs += [(i,(i+1)%sides,(i+1)%sides+sides,i+sides) for i in range(sides)]
    return mesh(name,vs,fs,mat,group,bevel)


def ellipsoid(name,center,radii,mat,group,segments=24,rings=12):
    c=Vector(center); rx,ry,rz=radii
    verts=[c+Vector((0,0,-rz))]
    faces=[]
    for j in range(1,rings):
        lat=pi*j/rings-pi/2
        for i in range(segments):
            lon=2*pi*i/segments
            verts.append(c+Vector((rx*cos(lat)*cos(lon),ry*cos(lat)*sin(lon),rz*sin(lat))))
    top=len(verts)
    verts.append(c+Vector((0,0,rz)))
    for i in range(segments):
        j=(i+1)%segments
        faces.extend([(0,1+j,1+i),(top,top-segments+i,top-segments+j)])
        for k in range(rings-2):
            a=1+k*segments
            faces.append((a+i,a+j,a+j+segments,a+i+segments))
    return mesh(name,verts,faces,mat,group)
