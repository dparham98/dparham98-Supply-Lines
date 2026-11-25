"""Mesh and packed, UV-mapped timber materials for the Arthurian House."""

from math import atan2, cos, pi, sin
import random

import bmesh
import bpy
import numpy as np
from mathutils import Vector


X, Y, Z = (Vector(v) for v in ((1, 0, 0), (0, 1, 0), (0, 0, 1)))


def material(name, rgb, metal=0.0, rough=.6, emission=0.0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*rgb, 1)
    mat.use_nodes = True
    bs = mat.node_tree.nodes.get("Principled BSDF")
    bs.inputs["Base Color"].default_value = (*rgb, 1)
    bs.inputs["Roughness"].default_value = rough
    bs.inputs["Metallic"].default_value = metal
    if emission:
        bs.inputs["Emission Color"].default_value = (*rgb, 1)
        bs.inputs["Emission Strength"].default_value = emission
    return mat


def wood(name, srgb, seed):
    """One metre along U. Earlywood/latewood waves, pores and cathedral grain."""
    mat = material(name, tuple((c / 255) ** 2.2 for c in srgb), rough=.57)
    width, height = 768, 384
    v, u = np.mgrid[0:height, 0:width] / np.array([height, width])[:, None, None]
    rng = np.random.default_rng(seed)
    warp = (.016 * np.sin(2*pi*(u + v)) + .013*np.sin(2*pi*(u*2-v))
            + .005*np.cos(2*pi*(4*u + 2*v)))
    phase = v + warp
    ring = (.5 + .5 * np.sin(2*pi*phase*17))**6
    fiber = (.5 + .5 * np.sin(2*pi*(phase*43 + .27*np.sin(2*pi*u*3))))**9
    curl = np.sqrt(np.sin(pi*(u-.22))**2 * .085 + np.sin(pi*(v-.48))**2)
    cathedrals = (.5 + .5*np.cos(curl*139))**5 * np.exp(-curl**2*10)
    pores = rng.normal(0, .020, (height,width))
    grain = 1.075 - .145*ring - .067*fiber - .14*cathedrals + pores + .022*np.sin(2*pi*phase*5)
    rgb = np.clip(np.array(srgb)[None,None,:]*grain[:,:,None]/255,0,1)
    pixels = np.ones((height,width,4),dtype=np.float32)
    pixels[:,:,:3] = rgb
    img = bpy.data.images.new(name + "_grain", width, height, alpha=False)
    img.colorspace_settings.name = "sRGB"
    img.pixels.foreach_set(pixels.ravel())
    img.pack()
    tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = img
    mat.node_tree.links.new(tex.outputs["Color"],mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"])
    return mat


class Assembly:
    """Combine individual pieces into one editable mesh for each construction stage."""
    def __init__(self, name, pivot, group, bevel=.008):
        self.name = name
        self.pivot = Vector(pivot)
        self.group = group
        self.bevel = bevel
        self.verts, self.faces, self.slots, self.face_mats, self.uvs = [], [], [], [], []
        self.rng = random.Random(name)

    def solid(self, coords, faces, mat, fiber=X):
        pts = [Vector(v) for v in coords]
        fiber = Vector(fiber).normalized()
        start = len(self.verts)
        self.verts.extend(v - self.pivot for v in pts)
        if mat not in self.slots:
            self.slots.append(mat)
        ix = self.slots.index(mat)
        off_u, off_v = self.rng.random(),self.rng.random()
        for face in faces:
            self.faces.append(tuple(start+i for i in face))
            self.face_mats.append(ix)
            normal = (pts[face[1]]-pts[face[0]]).cross(pts[face[2]]-pts[face[0]]).normalized()
            along = fiber - normal * fiber.dot(normal)
            if along.length < .08:
                along = normal.cross(Z if abs(normal.z)<.8 else Y)
            along.normalize()
            across = normal.cross(along)
            self.uvs.append([(off_u+pts[i].dot(along)*.85,off_v+pts[i].dot(across)*1.63) for i in face])

    def prism(self, poly, delta, mat, fiber=X):
        poly = [Vector(p) for p in poly]
        n = len(poly)
        coords = poly + [p+Vector(delta) for p in poly]
        faces = [tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]
        faces.extend((i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n))
        self.solid(coords,faces,mat,fiber)

    def block(self, center, size, mat, fiber=None):
        cx,cy,cz = center
        a,b,c = (d/2 for d in size)
        self.prism([(cx-a,cy-b,cz-c),(cx+a,cy-b,cz-c),(cx+a,cy+b,cz-c),(cx-a,cy+b,cz-c)],
                   (0,0,2*c),mat, fiber if fiber is not None else (X,Y,Z)[max(range(3),key=lambda i:size[i])])

    def beam(self, a, b, width, depth, mat, reference=Y):
        a,b = Vector(a),Vector(b)
        axis = (b-a).normalized()
        depth_axis = Vector(reference) - axis*axis.dot(reference)
        if depth_axis.length < .05:
            depth_axis = X - axis*axis.x
        depth_axis.normalize()
        w = axis.cross(depth_axis).normalized()*width/2
        d = depth_axis*depth/2
        self.prism([a+w+d,a-w+d,a-w-d,a+w-d], b-a, mat, axis)

    def disk(self, at, axis, r, h, mat, sides=12):
        n = Vector(axis).normalized()
        u = n.cross(Z if abs(n.z)<.8 else Y).normalized()
        v = n.cross(u).normalized()
        ring = [Vector(at)+r*(cos(pi*2*i/sides)*u+sin(pi*2*i/sides)*v) for i in range(sides)]
        self.prism(ring, n*h, mat, u)

    def finish(self):
        mesh = bpy.data.meshes.new(self.name)
        mesh.from_pydata(self.verts,[],self.faces)
        for mat in self.slots:
            mesh.materials.append(mat)
        tex = mesh.uv_layers.new(name="Timber grain")
        for poly,ix,uvs in zip(mesh.polygons,self.face_mats,self.uvs):
            poly.material_index=ix
            for li,uv in zip(poly.loop_indices,uvs):
                tex.data[li].uv=uv
        bm = bmesh.new()
        bm.from_mesh(mesh)
        bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
        bm.to_mesh(mesh)
        bm.free()
        mesh.update()
        ob=bpy.data.objects.new(self.name,mesh)
        bpy.context.collection.objects.link(ob)
        ob.parent=self.group
        ob.location=self.pivot
        if self.bevel:
            bevel=ob.modifiers.new("Machined edges","BEVEL")
            bevel.width=self.bevel
            bevel.segments=1
            bevel.limit_method="ANGLE"
            bevel.angle_limit=.52
            bevel.harden_normals=True
            bevel.use_clamp_overlap=True
            normal=ob.modifiers.new("Planar normals","WEIGHTED_NORMAL")
            normal.keep_sharp=True
        return ob


def trim(section, points, width, depth, mat):
    for a,b in zip(points,points[1:]):
        section.beam(a,b,width,depth,mat)


def tapered_leaf(part, tip, base, breadth, side, mat):
    a,b=Vector(base),Vector(tip)
    mid=a.lerp(b,.53)
    c=Vector(side).normalized()*breadth
    part.prism([a,mid+c,b,mid-c],(0,.009,.008),mat,b-a)
