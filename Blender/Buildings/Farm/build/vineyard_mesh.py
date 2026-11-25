"""Small mesh builder for the field's batched foliage, fruit, soil and irrigation gear."""
from math import cos, pi, sin

import bpy
import numpy as np
from mathutils import Vector

UP = Vector((0, 0, 1))
X = Vector((1, 0, 0))
WHITE = (1.0, 1.0, 1.0)


def scaled(rgb, factor):
    return tuple(min(1.0, max(0.0, c * factor)) for c in rgb)


def material(name, rgb=WHITE, roughness=.75, metal=0.0, painted=False, alpha=1.0, glow=0.0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*rgb, alpha)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*rgb, 1)
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = metal
    if painted:
        vertex = mat.node_tree.nodes.new("ShaderNodeVertexColor")
        vertex.layer_name = "Pigment"
        mat.node_tree.links.new(vertex.outputs["Color"], shader.inputs["Base Color"])
    if glow:
        shader.inputs["Emission Color"].default_value = (*rgb, 1)
        shader.inputs["Emission Strength"].default_value = glow
    if alpha < 1.0:
        shader.inputs["Alpha"].default_value = alpha
        mat.surface_render_method = 'BLENDED'
        mat.use_transparency_overlap = False
    return mat


class Batch:
    def __init__(self, mat):
        self.mat = mat
        self.vertices = []
        self.faces = []
        self.colors = []
        self.smooth = []
        self.uvs = []

    def patch(self, points, faces, pigments, smooth=False):
        start = len(self.vertices)
        self.vertices.extend(tuple(p) for p in points)
        self.colors.extend([pigments] * len(points) if isinstance(pigments, tuple) else pigments)
        self.faces.extend(tuple(start+i for i in face) for face in faces)
        self.smooth.extend([smooth] * len(faces))

    def tube(self, points, radii, color, sides=6, twist=0.0, smooth=False):
        """Tapered continuous limb with stable ring winding along a bent centreline."""
        pts = [Vector(p) for p in points]
        verts = []
        colors = []
        faces = []
        tangent = None
        for k, (center, radius) in enumerate(zip(pts, radii)):
            direction = (pts[min(len(pts)-1,k+1)] - pts[max(0,k-1)]).normalized()
            if tangent is None:
                tangent = direction.cross(UP if abs(direction.z) < .86 else X).normalized()
            else:
                tangent = (tangent-direction*tangent.dot(direction)).normalized()
            across = direction.cross(tangent)
            for i in range(sides):
                a = 2*pi*i/sides + k*twist
                verts.append(center+radius*(cos(a)*tangent+sin(a)*across))
                colors.append(scaled(color, 0.83 + 0.14*(.5+.5*cos(3*a+.56*k)) + .12*k/len(pts)))
        for k in range(len(pts)-1):
            for i in range(sides):
                j = (i+1)%sides
                faces.append((k*sides+i,k*sides+j,(k+1)*sides+j,(k+1)*sides+i))
        faces.extend([tuple(reversed(range(sides))), tuple(range((len(pts)-1)*sides,len(pts)*sides))])
        self.patch(verts,faces,colors,smooth)

    def ellipsoid(self, center, size, color, sides=7, rings=3, smooth=True, turn=0.0):
        """Faceted fruit, pebbles and small polished metal bodies."""
        center = Vector(center)
        ax, ay, az = size
        verts = [center-Vector((0,0,az))]
        faces = []
        for k in range(1,rings+1):
            lat = -pi*.5+pi*k/(rings+1)
            for i in range(sides):
                ang = turn+2*pi*i/sides+(k%2)*pi/sides*.5
                verts.append(center+Vector((ax*cos(lat)*cos(ang),ay*cos(lat)*sin(ang),az*sin(lat))))
        top = len(verts)
        verts.append(center+Vector((0,0,az)))
        for i in range(sides):
            j = (i+1)%sides
            faces.append((0,j+1,i+1))
            for k in range(rings-1):
                a=1+k*sides+i; b=1+k*sides+j
                faces.append((a,b,b+sides,a+sides))
            faces.append((top, 1+(rings-1)*sides+i,1+(rings-1)*sides+j))
        colors=[scaled(color, .77+.28*((v.z-center.z)/az+1)/2) for v in verts]
        self.patch(verts,faces,colors,smooth)

    def bevel_bar(self, start, end, radius, paint=WHITE, sides=8):
        self.tube([start,end],[radius,radius],paint,sides)

    def bake(self, name, collection, parent=None, origin=(0,0,0)):
        mesh=bpy.data.meshes.new(name)
        o=Vector(origin)
        mesh.from_pydata([tuple(Vector(v)-o) for v in self.vertices],[],self.faces)
        mesh.materials.append(self.mat)
        att=mesh.color_attributes.new(name="Pigment",type="BYTE_COLOR",domain="POINT")
        color=np.ones((len(self.colors),4),dtype=np.float32)
        color[:,:3]=self.colors
        att.data.foreach_set("color",color.ravel())
        mesh.color_attributes.active_color = att
        mesh.polygons.foreach_set("use_smooth", self.smooth)
        if self.uvs:
            uv = mesh.uv_layers.new(name="Pigment map")
            indices = np.zeros(len(mesh.loops),dtype=np.int32)
            mesh.loops.foreach_get('vertex_index',indices)
            uv.data.foreach_set('uv',np.asarray(self.uvs,dtype=np.float32)[indices].ravel())
        mesh.update()
        obj=bpy.data.objects.new(name,mesh)
        collection.objects.link(obj)
        obj.parent=parent
        obj.location=o
        return obj
