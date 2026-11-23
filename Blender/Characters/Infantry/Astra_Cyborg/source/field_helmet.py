"""Pressed-steel infantry helmet, in head bind-space millimetres."""
from math import atan2, cos, pi, sin
from pathlib import Path
import struct
import tempfile
import zlib

import bpy
import numpy as np
from mathutils import Vector


# From the inner brim, around the rolled bead, up the skirt and across the
# crown. Each section gives its two radii, front, side and rear height, and Y.
PROFILE = (
    (164,155,191,132,122,-4.4), (181,173,190,129,119,-4.8),
    (184.8,177.3,190.6,129.7,119.8,-4.9), (187.1,179.7,192.8,132,122,-4.9),
    (187.3,180,195.3,134.6,124.6,-4.9), (185.7,178.7,197.7,137,127,-4.8),
    (182.2,175.3,199.1,139.6,129.9,-4.7), (167,161,212,169,160,-.9),
    (156,151,228,203,196,2.8), (152,147.5,251,239,235,5.0),
    (140,136.2,285,279,276,7.4), (118,115.7,319,318,314.8,8.8),
    (87.8,86.2,346,345,342.5,9.2), (53,52,361.5,361,360.4,9.2),
    (25,24.6,367.6,367.4,367.4,9.2), (8,7.9,369.3,369.3,369.3,9.2),
)
HALF_STRIPE = 32.
SEGMENTS = 88


def section(step):
    # Cubic interpolation gives the slightly raised visor and dipped nape one
    # continuous reflection. The small control sections physically form the hem.
    i=min(int(step),len(PROFILE)-2)
    t=step-i
    a,b,c,d=[PROFILE[max(0,min(len(PROFILE)-1,j))] for j in (i-1,i,i+1,i+2)]
    return tuple(v+.5*t*((w-u)+t*((2*u-5*v+4*w-x)+t*(3*v-3*w+x-u)))
                 for u,v,w,x in zip(a,b,c,d))


def shell_point(step,angle):
    rx,ry,front,side,back,offset=section(step)
    c=cos(angle)
    z=side+(front-side)*max(0,c)**2.2+(back-side)*max(0,-c)**1.65
    return Vector((rx*sin(angle),offset-ry*c,z))


def shell_normal(step,angle):
    tx=shell_point(step,angle+.0005)-shell_point(step,angle-.0005)
    ty=shell_point(min(len(PROFILE)-1,step+.002),angle)-shell_point(max(0,step-.002),angle)
    return tx.cross(ty).normalized()


def graphite_finish(material):
    # A tile of fine ceramic-blast grain and scattered shallow scuffs. Pack the
    # linear roughness and metalness channels together as a native glTF map.
    size=256
    rng=np.random.default_rng(140)
    y,x=np.mgrid[:size,:size]
    rough=.441+rng.normal(0,.031,(size,size))
    rough+=.023*np.cos(2*pi*(2*x+3*y)/size)*np.sin(2*pi*(4*x-y)/size)
    for _ in range(34):
        cx,cy=rng.integers(size,size=2)
        angle=rng.uniform(.05,.42)
        for j in range(int(rng.integers(2,9))):
            rough[int(cy+j*sin(angle))%size,int(cx+j*cos(angle))%size]-=.032
    pixels=np.empty((size,size,3),dtype=np.uint8)
    pixels[:,:,0]=255
    pixels[:,:,1]=(255*np.clip(rough,0,1)).astype(np.uint8)
    pixels[:,:,2]=129
    def chunk(tag,data):
        return struct.pack(">I",len(data))+tag+data+struct.pack(">I",zlib.crc32(tag+data))
    data=(b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">2I5B",size,size,8,2,0,0,0))
          +chunk(b"IDAT",zlib.compress(b"".join(b"\0"+row.tobytes() for row in pixels),9))+chunk(b"IEND",b""))
    with tempfile.TemporaryDirectory() as temp:
        path=Path(temp)/"infantry_helmet_finish.png"
        path.write_bytes(data)
        image=bpy.data.images.load(str(path))
        image.name="Infantry helmet finish"
        image.colorspace_settings.name='Non-Color'
        image.pack()
        image.filepath="//"+path.name
    nodes,links=material.node_tree.nodes,material.node_tree.links
    tex=nodes.new("ShaderNodeTexImage")
    tex.image=image
    channels=nodes.new("ShaderNodeSeparateColor")
    links.new(tex.outputs['Color'],channels.inputs['Color'])
    shader=nodes['Principled BSDF']
    links.new(channels.outputs['Green'],shader.inputs['Roughness'])
    links.new(channels.outputs['Blue'],shader.inputs['Metallic'])


def build(k,to_world):
    shell=k.mat("helmet_graphite",(.042,.046,.048),.51,.44)
    rim=k.mat("helmet_rolled_edge",(.079,.081,.080),.59,.36)
    liner=k.mat("helmet_gasket",(.019,.018,.016),.03,.78)
    graphite_finish(shell)
    materials=[liner,rim,shell,k.team,k.blacksteel,k.gunmetal]
    points,faces,indices,corner_normals=[],[],[],[]
    vertex_ids={}
    def polygon(vertices,mat):
        ids=[]
        for pos,normal in vertices:
            key=tuple(round(n,5) for n in pos)
            if key not in vertex_ids:
                vertex_ids[key]=len(points)
                points.append(to_world(pos))
            ids.append(vertex_ids[key])
        if len(set(ids))==len(ids):
            faces.append(ids)
            indices.append(mat)
            corner_normals.extend(tuple(normal) for pos,normal in vertices)

    def partition(vertices,cut):
        # Split faces at the actual edges of the painted stripe. Its shared
        # normals follow the steel beneath it, including at the pole.
        low,high=[],[]
        for a,b in zip(vertices,vertices[1:]+vertices[:1]):
            da,db=a[0].x-cut,b[0].x-cut
            (low if da<0 else high).append(a)
            if da*db<0:
                t=da/(da-db)
                v=(a[0].lerp(b[0],t),a[1].lerp(b[1],t).normalized())
                low.append(v)
                high.append(v)
        return low,high

    def panel(vertices,paint):
        xs=[p.x for p,n in vertices]
        if not paint or max(xs)<=-HALF_STRIPE or min(xs)>=HALF_STRIPE:
            polygon(vertices,2)
        elif min(xs)>=-HALF_STRIPE and max(xs)<=HALF_STRIPE:
            polygon(vertices,3)
        else:
            left,rest=partition(vertices,-HALF_STRIPE)
            middle,right=partition(rest,HALF_STRIPE)
            for portion,mat in [(left,2),(middle,3),(right,2)]:
                if len(portion)>=3:
                    polygon(portion,mat)

    steps=[0,1,2,3,4,5,6]+[j+t for j in range(6,15) for t in (.5,1)]
    angles=[2*pi*i/SEGMENTS for i in range(SEGMENTS)]
    rings=[[(shell_point(s,a),shell_normal(s,a)) for a in angles] for s in steps]
    down=Vector((0,0,-1))
    polygon([(p,down) for p,n in reversed(rings[0])],0)
    for row,(lo,hi) in enumerate(zip(rings,rings[1:])):
        for i in range(SEGMENTS):
            j=(i+1)%SEGMENTS
            quad=[lo[i],lo[j],hi[j],hi[i]]
            if steps[row]<6:
                polygon(quad,0 if steps[row]<2 else 1)
            else:
                panel(quad,steps[row]>=10)
    pole=(Vector((0,9.2,369.5)),Vector((0,0,1)))
    for i in range(SEGMENTS):
        polygon([rings[-1][i],rings[-1][(i+1)%SEGMENTS],pole],3)

    def fitting(step,angle,profile,band_materials,cap_material):
        # Low, spun vent eyelets and shallow suspension pins seat normal to
        # the local shell; a dished gunmetal well catches light inside the vent.
        angle*=pi/180
        centre=shell_point(step,angle)
        axis=shell_normal(step,angle)
        tangent=(shell_point(step,angle+.005)-shell_point(step,angle-.005)).normalized()
        vertical=axis.cross(tangent).normalized()
        count=28
        rings=[]
        for radius,height in profile:
            rings.append([centre+height*axis+radius*(tangent*cos(2*pi*i/count)+vertical*sin(2*pi*i/count)) for i in range(count)])
        for j,(lo,hi) in enumerate(zip(rings,rings[1:])):
            dr=profile[j+1][0]-profile[j][0]
            dh=profile[j+1][1]-profile[j][1]
            def normal(i):
                ray=tangent*cos(2*pi*i/count)+vertical*sin(2*pi*i/count)
                return (dh*ray-dr*axis).normalized()
            for i in range(count):
                m=(i+1)%count
                polygon([(lo[i],normal(i)),(lo[m],normal(m)),(hi[m],normal(m)),(hi[i],normal(i))],band_materials[j])
        polygon([(p,axis) for p in rings[-1]],cap_material)

    for sign in (-1,1):
        fitting(9.35,sign*87,[(8.6,-.6),(8.8,.35),(8,1.8),(6.2,2.9),(4.6,2.9),(3.5,1.7),(3.4,.15)],
                [2,2,5,5,4,4],0)
        for angle in (53,142):
            fitting(8.72,sign*angle,[(4.4,-.35),(4.4,.5),(3.7,1.35),(2.2,1.95),(.7,2.16)],
                    [4,2,2,2],2)

    obj=k.mesh("helmet_shell_and_colourband",points,faces,materials,"head",indices)
    mesh=obj.data
    for p in mesh.polygons:
        p.use_smooth=True
    mesh.normals_split_custom_set(corner_normals)
    uv=mesh.uv_layers.new(name='Finish')
    # Four repeats around the shell, in physical proportion to the meridian.
    for p in mesh.polygons:
        coords=[]
        for i in p.loop_indices:
            x,y,z=points[mesh.loops[i].vertex_index]
            coords.append(((atan2(x,-(y-.034))/(2*pi))%1,(z-1.54)*4.2))
        across=max(u for u,v in coords)-min(u for u,v in coords)>.5
        for i,(u,v) in zip(p.loop_indices,coords):
            uv.data[i].uv=((u+int(across and u<.5))*4,v)
    return obj
