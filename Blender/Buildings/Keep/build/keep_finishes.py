"""Packed, directional oak grain and the Keep's fixed-color enameled iron."""

from math import pi

import bpy
import numpy as np
from mathutils import Vector


def timber_finish(name, srgb, seed):
    """A small repeating timber image whose U axis follows the fitted board."""
    width, height = 384, 256
    v, u = np.mgrid[0:height, 0:width] / np.array([height,width])[:,None,None]
    rng=np.random.default_rng(seed)
    sweep=v+.012*np.sin(2*pi*(u+v))+.010*np.sin(2*pi*(u*2-v))+.004*np.cos(2*pi*(3*u+2*v))
    rings=(.5+.5*np.sin(2*pi*sweep*17))**6
    fiber=(.5+.5*np.sin(2*pi*(sweep*53+.25*np.sin(2*pi*u*2))))**7
    curl=np.sqrt(np.sin(pi*(u-.38))**2*.084+np.sin(pi*(v-.58))**2)
    cathedral=(.5+.5*np.cos(curl*145))**6*np.exp(-curl**2*7)
    grain=1.09-.185*rings-.075*fiber-.15*cathedral+rng.normal(0,.014,(height,width))
    pixels=np.ones((height,width,4),dtype=np.float32)
    pixels[:,:,:3]=np.clip(np.array(srgb)[None,None,:]*grain[:,:,None]/255,0,1)
    image=bpy.data.images.new(name+"_grain",width,height,alpha=False)
    image.colorspace_settings.name="sRGB"
    image.pixels.foreach_set(pixels.ravel())
    image.pack()
    mat=bpy.data.materials.new(name)
    mat.use_nodes=True
    rgb=tuple((x/255)**2.2 for x in srgb)
    mat.diffuse_color=(*rgb,1)
    bsdf=mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value=.57
    sample=mat.node_tree.nodes.new("ShaderNodeTexImage")
    sample.image=image
    mat.node_tree.links.new(sample.outputs["Color"],bsdf.inputs["Base Color"])
    return mat


def assign_timber_uv(mesh):
    """Use the longest in-plane edge on each fitted wood face for grain direction."""
    wood={i for i,mat in enumerate(mesh.materials) if mat.name in ("Honey_Oak","Smoked_Oak","Heart_Oak")}
    if not wood:
        return
    mesh.update()
    layer=mesh.uv_layers.new(name="Joinery")
    for polygon in mesh.polygons:
        if polygon.material_index not in wood:
            continue
        positions=[mesh.vertices[i].co for i in polygon.vertices]
        edges=[positions[(i+1)%len(positions)]-p for i,p in enumerate(positions)]
        along=max(edges,key=lambda d:d.length_squared).normalized()
        if along.length_squared<.5:
            continue
        across=polygon.normal.cross(along).normalized()
        offset=(polygon.index*.1397)%1
        for loop_i,p in zip(polygon.loop_indices,positions):
            layer.data[loop_i].uv=(along.dot(p)*.77+offset,across.dot(p)*1.75+offset)
