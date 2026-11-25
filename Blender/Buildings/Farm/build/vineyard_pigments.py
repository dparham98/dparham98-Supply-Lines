"""Packed hand-shaped vineyard pigments. Everything needed by the GLB lives in the blend."""
import bpy
import numpy as np


def field(grid,size,seed):
    rng=np.random.default_rng(seed)
    points=rng.random((grid,grid)).astype(np.float32)
    k=np.arange(size)*grid/size
    i=k.astype(int); f=k-i
    f=f*f*(3-2*f)
    a=points[np.ix_(i,i)]; b=points[np.ix_(i,(i+1)%grid)]
    c=points[np.ix_((i+1)%grid,i)]; d=points[np.ix_((i+1)%grid,(i+1)%grid)]
    return (a*(1-f)+b*f)*(1-f[:,None])+(c*(1-f)+d*f)*f[:,None]


def packed(name,image):
    h,w,_=image.shape
    img=bpy.data.images.new(name,w,h,alpha=True)
    img.alpha_mode='STRAIGHT'
    img.pixels.foreach_set(image.astype(np.float32).ravel())
    img.pack()
    return img


def image_pigment(mat,img,clip=False):
    tree=mat.node_tree
    bs=tree.nodes.get("Principled BSDF")
    tex=tree.nodes.new("ShaderNodeTexImage")
    tex.image=img
    color=tree.nodes.new("ShaderNodeMixRGB")
    color.blend_type='MULTIPLY'
    color.inputs[0].default_value=1
    vertex=next(node for node in tree.nodes if node.type=="VERTEX_COLOR")
    tree.links.new(vertex.outputs["Color"],color.inputs[1])
    tree.links.new(tex.outputs["Color"],color.inputs[2])
    tree.links.new(color.outputs["Color"],bs.inputs["Base Color"])
    if clip:
        # glTF recognizes the threshold math as an opaque alpha-cutout (no sorting).
        math=tree.nodes.new("ShaderNodeMath");math.operation='GREATER_THAN'
        math.inputs[1].default_value=.47
        tree.links.new(tex.outputs['Alpha'],math.inputs[0])
        tree.links.new(math.outputs[0],bs.inputs['Alpha'])
        mat.surface_render_method='DITHERED'
        mat.use_backface_culling=False
    return tex


def leaf_paint(material,outline):
    n=384
    y,x=np.mgrid[-.16:1.02:complex(n),-.62:.62:complex(n)]
    inside=np.zeros_like(x,dtype=bool)
    for i,(xa,ya) in enumerate(outline):
        xb,yb=outline[(i+1)%len(outline)]
        if abs(yb-ya)<1e-7:continue
        inside^=((ya>y)!=(yb>y)) & (x<(xb-xa)*(y-ya)/(yb-ya)+xa)
    grain=field(8,n,230)*.13+field(24,n,68)*.10+field(59,n,45)*.09+field(167,n,25)*.06
    # Deep olive toward the sinus, broken sun-flecking toward outer lobes.
    tone=.56+.20*y+.15*abs(x)+grain
    vein=np.zeros_like(x)
    def line(x0,y0,x1,y1,width,strength):
        nonlocal vein
        dx=x1-x0;dy=y1-y0
        t=np.clip(((x-x0)*dx+(y-y0)*dy)/(dx*dx+dy*dy),0.,1.)
        dist=(x-x0-t*dx)**2+(y-y0-t*dy)**2
        thickness=width*(1-.62*t)
        vein=np.maximum(vein,np.exp(-dist/(thickness**2))*(1-.32*t)*strength)
    line(0,.01,0,.98,.013,1.)
    for sign in (-1,1):
        for endx,endy in ((.49,.55),(.42,.15),(.31,.69)):
            line(0,.021,sign*endx,endy,.010,.78)
        for j in range(1,7):
            y0=.13+.105*j
            x1=(.40-.038*j)*sign
            line(0,y0,x1,y0+.14,.0045,.56)
            line(x1*.47,y0+.073,x1*.85,y0+.18,.0027,.34)
        for j in range(1,4):
            x0=sign*.11*j;y0=.12*j
            line(x0,y0,x0+sign*.15,y0+.015,.004,.41)
    pinpricks=(field(58,n,269)>.83)*.085
    image=np.ones((n,n,4),np.float32)
    image[:,:,0]=np.clip(tone*.96+vein*.32+pinpricks,0,1)
    image[:,:,1]=np.clip(tone+vein*.22,0,1)
    image[:,:,2]=np.clip(tone*.77+vein*.14,0,1)
    image[:,:,3]=inside.astype(np.float32)
    image_pigment(material,packed("Painted grape leaf • veins and lobes",image),True)


def dirt_paint(material):
    n=512
    crumbles=field(28,n,92)
    fine=field(184,n,104)
    flecks=np.random.default_rng(842).random((n,n))
    grain=.36+.31*field(7,n,54)+.13*field(51,n,74)+.13*fine+.19*crumbles+.09*flecks
    grain+=np.clip((crumbles-.66)*2.4,0,.17)
    grain-=np.clip((.31-fine)*.9,0,.22)
    image=np.ones((n,n,4),np.float32)
    tan=np.clip((flecks-.89)*2,0,.18)*np.clip((fine-.46)*2,0,1)
    image[:,:,0]=np.clip(grain+tan,0,1)
    image[:,:,1]=np.clip(grain*.96+tan*.96,0,1)
    image[:,:,2]=np.clip(grain*.89+tan*.8,0,1)
    image_pigment(material,packed("Vineyard loam • mineral grain",image))
