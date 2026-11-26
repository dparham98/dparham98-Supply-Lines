"""Shared surface finishes and modeling helpers for the Forester Maiden."""
from math import atan2, cos, pi, sin
from pathlib import Path

import bpy
import bmesh
import numpy as np
from mathutils import Vector

# Display swatches are sRGB. Blender nodes and glTF factors expect linear RGB.
PALETTE = {
    "linen": ("Field linen", "d2bfa4", 0, .83),
    "linen_shadow": ("Linen binding", "ad987a", 0, .85),
    "navy": ("team_color", "223c66", .015, .77),
    "navy_shadow": ("team_color_shadow", "192b45", 0, .80),
    "gold": ("Antique gilt", "bf8e47", .68, .34),
    "leather": ("Oiled chestnut", "71492e", .01, .61),
    "leather_dark": ("Cordovan leather", "45332c", .01, .61),
    "iron": ("Field iron", "53575d", .66, .43),
    "steel": ("Tempered steel", "afb8c1", .80, .27),
    "skin": ("Sunwarmed skin", "bf8b70", 0, .56),
    "trousers": ("Walnut twill", "524238", 0, .85),
    "boot": ("Burnished boot hide", "594030", .015, .55),
    "sole": ("Stacked leather soles", "39302c", 0, .72),
    "welt": ("Boot welting", "815f44", .01, .63),
    "thread": ("Waxed flax", "af9168", 0, .78),
    "brass_dark": ("Aged bronze recesses", "765533", .60, .45),
}

def linear(hex_value):
    rgb = [int(hex_value[i:i+2], 16) / 255 for i in (0, 2, 4)]
    return tuple(c / 12.92 if c <= .04045 else ((c + .055) / 1.055) ** 2.4 for c in rgb)

def mat(key):
    name, tint, metallic, rough = PALETTE[key]
    material = bpy.data.materials.get(name)
    if material:
        return material
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    col = (*linear(tint), 1)
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = col
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = rough
    material.diffuse_color = col
    if key == "skin":
        shader.inputs["Subsurface Weight"].default_value = .046
        shader.inputs["Subsurface Scale"].default_value = .010
    return material

def mesh(name, vertices, faces, finish, smooth=True):
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    data.update()
    bm = bmesh.new()
    bm.from_mesh(data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(data)
    bm.free()
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(mat(finish) if isinstance(finish, str) else finish)
    for poly in data.polygons:
        poly.use_smooth = smooth
    return obj

def loops(name, rings, finish, smooth=True, cap=True):
    n = len(rings[0])
    faces = []
    if cap:
        faces.append(tuple(reversed(range(n))))
    for i in range(len(rings)-1):
        for j in range(n):
            a,b=i*n+j,i*n+(j+1)%n
            faces.append((a,b,b+n,a+n))
    if cap:
        faces.append(tuple(range((len(rings)-1)*n,len(rings)*n)))
    return mesh(name, [p for ring in rings for p in ring], faces, finish, smooth)

def cord(name, points, radius, finish, sides=6):
    points = [Vector(p) for p in points]
    rings=[]
    normal=None
    for i, p in enumerate(points):
        tangent=(points[min(i+1,len(points)-1)]-points[max(0,i-1)]).normalized()
        if normal is None or abs(normal.dot(tangent)) > .97:
            axis=Vector((0,0,1)) if abs(tangent.z)<.85 else Vector((0,1,0))
            normal=tangent.cross(axis).normalized()
        normal=(normal-tangent*normal.dot(tangent)).normalized()
        binormal=tangent.cross(normal)
        rings.append([p+radius*(normal*cos(2*pi*j/sides)+binormal*sin(2*pi*j/sides)) for j in range(sides)])
    return loops(name,rings,finish)

def bevel(obj, width, segments=2):
    mod=obj.modifiers.new("Rounded edges","BEVEL")
    mod.width, mod.segments = width, segments
    mod.harden_normals=True
    obj.modifiers.new("Face normals","WEIGHTED_NORMAL").keep_sharp=True
    return obj

def volume(name, center, half_size, finish, euler=(0,0,0), radius=0):
    bpy.ops.mesh.primitive_cube_add(size=2, location=center)
    obj=bpy.context.object
    obj.name=name
    for v in obj.data.vertices:
        for i in range(3):
            v.co[i] *= half_size[i]
    obj.rotation_euler=euler
    obj.data.materials.append(mat(finish))
    if radius:
        bevel(obj,radius)
    return obj

# A small periodic PBR normal tile gives the cloth a visible yarn and the
# leather a subdued grain in the portrait, with mipmaps at RTS distance.
def surface_tiles(kind):
    n=192
    y,x=np.mgrid[0:n,0:n].astype(np.float32)*2*pi/n
    if kind=="Weave":
        warp=np.cos(12*x+.24*np.sin(6*y))
        weft=np.cos(12*y+.24*np.sin(6*x))
        alternate=np.tanh(2*np.cos(6*x)*np.cos(6*y))
        height=(warp*(1+.60*alternate)+weft*(1-.60*alternate))*.56
        height+=.06*np.sin(24*x+6*y)
        # Short slubs and irregular yarn dye remain visible where the normal
        # specular is too soft to distinguish linen from smooth metal.
        slubs=np.maximum(0,np.sin(12*x+.23*np.sin(3*y)))**6
        slubs*=np.maximum(0,np.cos(2*y+3*x))**3
        albedo=.932+.025*height-.061*slubs+.014*np.sin(2*y+np.sin(3*x))
    else:
        height=(np.sin(12*x+4*np.sin(5*y))*.42+np.sin(17*y+3*np.cos(6*x))*.29+
                .17*np.cos(15*x-21*y+np.cos(5*x))+.10*np.cos(33*x+25*y))
        albedo=.945+.045*height+.014*np.sin(2*x+2*y+np.sin(3*y))
    dx=(np.roll(height,-1,axis=1)-np.roll(height,1,axis=1))
    dy=(np.roll(height,-1,axis=0)-np.roll(height,1,axis=0))
    vector=np.stack((-dx,-dy,np.ones_like(dx)),axis=-1)
    vector/=np.linalg.norm(vector,axis=-1,keepdims=True)
    pixels=np.ones((n,n,4),dtype=np.float32)
    pixels[:,:,:3]=vector*.5+.5
    image=bpy.data.images.new("Forester "+kind+" normal", n, n, alpha=False)
    image.colorspace_settings.name="Non-Color"
    image.pixels.foreach_set(pixels.ravel())
    image.pack()
    pigment=bpy.data.images.new("Forester "+kind+" variation",n,n,alpha=False)
    pigment.colorspace_settings.name="sRGB"
    pixels[:,:,:3]=np.clip(albedo[:,:,None],0,1)
    pigment.pixels.foreach_set(pixels.ravel())
    pigment.pack()
    return image,pigment

def add_cheek_pigment():
    # This small offset map samples freckles and warm/cool cheek variation
    # from the reference. It leaves the eyes and facial landmarks to the sculpt.
    skin=bpy.data.images["Forester | facial complexion"]
    detail=bpy.data.images.load(str(Path(__file__).with_name("cheek_pigment.png")))
    try:
        detail.colorspace_settings.name="Non-Color"
        if tuple(skin.size)!=tuple(detail.size):
            raise ValueError("Cheek pigment and complexion UV sizes differ")
        color=np.empty(len(skin.pixels),np.float32)
        offset=np.empty_like(color)
        skin.pixels.foreach_get(color)
        detail.pixels.foreach_get(offset)
        rgb=color.reshape(-1,4)[:,:3]
        rgb[:]=np.clip(rgb+(offset.reshape(-1,4)[:,:3]-128/255)/6,0,1)
        skin.pixels.foreach_set(color)
        skin.update()
        skin.pack()
    finally:
        bpy.data.images.remove(detail)

def finish_textiles(objects):
    keys={"Weave":("linen","linen_shadow","navy","navy_shadow","trousers"),
          "Grain":("leather","leather_dark","boot","welt")}
    targets={}
    for kind,names in keys.items():
        image,pigment=surface_tiles(kind)
        for key in names:
            material=mat(key)
            targets[material]=.033 if kind=="Weave" else .027
            nodes=material.node_tree.nodes
            tex=nodes.new("ShaderNodeTexImage")
            tex.image=image
            normal=nodes.new("ShaderNodeNormalMap")
            normal.inputs["Strength"].default_value=.27 if kind=="Weave" else .19
            material.node_tree.links.new(tex.outputs["Color"],normal.inputs["Color"])
            material.node_tree.links.new(normal.outputs["Normal"],nodes["Principled BSDF"].inputs["Normal"])
            texture=nodes.new("ShaderNodeTexImage")
            texture.image=pigment
            color=nodes.new("ShaderNodeMix")
            color.data_type="RGBA"
            color.blend_type="MULTIPLY"
            color.inputs[0].default_value=1.0
            first,second=[s for s in color.inputs if s.type=="RGBA"]
            second.default_value=material.diffuse_color
            material.node_tree.links.new(texture.outputs["Color"],first)
            result=next(s for s in color.outputs if s.type=="RGBA")
            material.node_tree.links.new(result,nodes["Principled BSDF"].inputs["Base Color"])
    for obj in objects:
        if obj.type!="MESH" or not any(m in targets for m in obj.data.materials):
            continue
        data=obj.data
        uv=data.uv_layers.active
        if not uv:
            uv=data.uv_layers.new(name="Surface grain")
        transform=obj.matrix_world
        rotation=transform.to_3x3().inverted_safe().transposed()
        for polygon in data.polygons:
            material=data.materials[polygon.material_index] if data.materials else None
            if material not in targets:
                continue
            nx,ny,nz=map(abs,(rotation@polygon.normal).normalized())
            ax,bx=(0,1) if nz>max(nx,ny) else ((1,2) if nx>ny else (0,2))
            size=targets[material]
            for li in polygon.loop_indices:
                point=transform@data.vertices[data.loops[li].vertex_index].co
                uv.data[li].uv=(point[ax]/size,point[bx]/size)
