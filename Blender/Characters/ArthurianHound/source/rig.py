"""Articulated skeleton and a calm standing pose for the Arthurian hound."""
import bpy
from mathutils import Vector

def create(pieces):
    data=bpy.data.armatures.new("Hound skeleton")
    rig=bpy.data.objects.new("Hound rig",data)
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active=rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    def bone(name,head,tail,parent=None):
        b=data.edit_bones.new(name)
        b.head=Vector(head)*.78
        b.tail=Vector(tail)*.78
        if parent:
            b.parent=data.edit_bones[parent]
    bone("Body",(0,.2,.78),(0,-.32,.85))
    bone("Neck",(0,-.33,.85),(0,-.64,1.16),"Body")
    bone("Head",(0,-.64,1.16),(0,-.92,1.17),"Neck")
    bone("Tail",(0,.60,.80),(0,.96,.45),"Body")
    for name,side in (("L",1),("R",-1)):
        x=side*.23
        for prefix,y,knee,ankle in (("Front",-.40,(-.43,.48),(-.44,.12)),("Hind",.47,(.60,.48),(.67,.12))):
            top=(x,y,.79)
            mid=(x,knee[0],knee[1])
            end=(x,ankle[0],ankle[1])
            bone(prefix+"Upper."+name,top,mid,"Body")
            bone(prefix+"Lower."+name,mid,end,prefix+"Upper."+name)
            bone(prefix+"Paw."+name,end,(x,ankle[0]-.12,.045),prefix+"Lower."+name)
    bpy.ops.object.mode_set(mode='OBJECT')
    for p in pieces:
        joint=p.get("joint")
        if not joint: continue
        if joint not in data.bones: raise ValueError("Missing joint "+joint+" for "+p.name)
        p.parent=rig
        group=p.vertex_groups.new(name=joint)
        group.add(list(range(len(p.data.vertices))),1,'REPLACE')
        mod=p.modifiers.new("Hound skeleton",'ARMATURE')
        mod.object=rig
    action=bpy.data.actions.new("Rest")
    rig.animation_data_create()
    rig.animation_data.action=action
    for frame in (1,49):
        for name in ("Body","Neck","Head","Tail"):
            p=rig.pose.bones[name]
            p.rotation_mode='XYZ'
            p.rotation_euler=(0,0,0)
            p.keyframe_insert(data_path="rotation_euler",frame=frame,group=name)
    rig.animation_data.action=None
    track=rig.animation_data.nla_tracks.new()
    track.name="Rest"
    track.strips.new("Rest",1,action)
    bpy.context.scene.frame_set(1)
    return rig
