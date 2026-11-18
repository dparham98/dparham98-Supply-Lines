"""Create the concept infantry from the accepted animation rig and editable mesh parts."""
from pathlib import Path
import sys
import bpy
from mathutils import Matrix, Vector

HERE = Path(__file__).resolve().parent
BASE = HERE.parent
sys.dont_write_bytecode = True
sys.path.insert(0, str(HERE))


class Kit:
    def __init__(self, rig, collection):
        self.rig, self.collection = rig, collection
        self.wool = self.mat("Greatcoat • graphite", (.038,.040,.041), 0, .89)
        self.wool_light = self.mat("Greatcoat • folded wool", (.050,.052,.054), 0, .85)
        self.leather = self.mat("Black field leather", (.025,.024,.025), .04, .54)
        self.blacksteel = self.mat("Blued steel", (.035,.039,.042), .53, .48)
        self.gunmetal = self.mat("Brushed gunmetal", (.113,.121,.124), .55, .43)
        self.steel = self.mat("Exposed steel", (.25,.255,.251), .67, .38)
        self.team = self.mat("team_color", (.36,.047,.034), .02, .74)
        self.team.node_tree.nodes['Principled BSDF'].inputs['Specular IOR Level'].default_value=.18

    @staticmethod
    def mat(name,rgb_linear,metallic=0,roughness=.60,emission=0):
        m = bpy.data.materials.get(name)
        if m: return m
        m = bpy.data.materials.new(name)
        m.diffuse_color = (*rgb_linear,1)
        m.use_nodes = True
        bs = m.node_tree.nodes.get("Principled BSDF")
        bs.inputs["Base Color"].default_value = (*rgb_linear,1)
        bs.inputs["Metallic"].default_value = metallic
        bs.inputs["Roughness"].default_value = roughness
        if emission:
            bs.inputs["Emission Color"].default_value = (*rgb_linear,1)
            bs.inputs["Emission Strength"].default_value = emission
        return m

    def mesh(self,name,verts,faces,mats,bone,face_mats=None):
        me = bpy.data.meshes.new(name)
        me.from_pydata(verts,[],faces)
        for m in mats: me.materials.append(m)
        if face_mats is not None:
            for f,i in zip(me.polygons,face_mats,strict=True):
                f.material_index = i
        me.update()
        obj = bpy.data.objects.new(name,me)
        self.collection.objects.link(obj)
        obj.parent = self.rig
        def group_for(key):
            if self.rig.data.bones.get(key) is None: raise ValueError(f"Unknown bone {key}")
            return obj.vertex_groups.get(key) or obj.vertex_groups.new(name=key)
        if isinstance(bone,str):
            group_for(bone).add(list(range(len(verts))),1,'REPLACE')
        else:
            if len(bone)!=len(verts): raise ValueError(f"Incorrect skin weight count on {name}")
            for i,weights in enumerate(bone):
                if isinstance(weights,str): weights={weights:1.}
                for key,w in weights.items():
                    if w>0: group_for(key).add([i],w,'REPLACE')
        mod = obj.modifiers.new("Infantry armature",'ARMATURE')
        mod.object = self.rig
        return obj


def load_rig():
    coll = bpy.data.collections.new("Cyborg infantry")
    bpy.context.scene.collection.children.link(coll)
    wanted = ["infantry_rig2","chainsaw_teeth_rig","Muzzle flash","Muzzle light"]
    with bpy.data.libraries.load(str(BASE.parent/"Infantry.blend")) as (_,dest):
        dest.objects = wanted
    for obj in dest.objects: coll.objects.link(obj)
    rig = bpy.data.objects["infantry_rig2"]
    rig.show_in_front = False
    rig.data.display_type = 'STICK'
    rig.animation_data.use_nla = False
    rig.animation_data.action = bpy.data.actions["Rest"]
    for p in rig.pose.bones: p.matrix_basis = Matrix.Identity(4)
    bpy.context.scene.frame_set(1)
    return rig,coll


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    scene=bpy.context.scene
    scene.render.fps=24
    scene.frame_start,scene.frame_end=1,100
    scene.unit_settings.system='METRIC'
    rig,coll=load_rig()
    kit=Kit(rig,coll)
    import uniform,head,arms
    uniform.build(kit)
    head.build(kit)
    arms.build(kit)
    for obj in list(coll.objects):
        if obj is rig: continue
        if obj.name in {"Muzzle light","Muzzle flash","chainsaw_teeth_rig"}:
            obj.hide_render=False
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action='DESELECT')
    bpy.context.view_layer.objects.active=rig
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type!='VIEW_3D': continue
            sp=area.spaces.active
            sp.shading.color_type='MATERIAL'
            sp.shading.show_cavity=True
            sp.overlay.show_overlays=False
            sp.region_3d.view_perspective='ORTHO'
            sp.region_3d.view_location=(0,0,.89)
            sp.region_3d.view_distance=3.1
            sp.region_3d.view_rotation=Vector((-.34,-1,.13)).to_track_quat('Z','Y')
    bpy.ops.wm.save_as_mainfile(filepath=str(HERE/"Cyborg_Infantry.blend"),compress=True)
    from export_character import export
    export(BASE/"export/infantry.glb")


if __name__=='__main__': build()
