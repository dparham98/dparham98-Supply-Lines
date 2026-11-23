"""Bind the current editable marine to a shared, anatomically fitted skeleton.

In background Blender, open a character, run this script, and optionally pass an
output .blend after --. Meshes keep their original world transforms and modifiers.
"""
from mathutils import Matrix, Vector
from pathlib import Path
import math
import sys

import bpy


def rifle_landmarks(asset, rig):
    """Read the replacement prop's grip contacts and bore in armature space."""
    inverse = rig.matrix_world.inverted()
    grip, support, muzzle = [inverse @ asset.objects[f"A_Rifle_{name}_socket"].matrix_world
                             for name in ("trigger", "support", "muzzle")]
    basis = muzzle.to_3x3()
    return (grip.translation, support.translation, muzzle.translation,
            (basis @ Vector((0,1,0))).normalized(), (basis @ Vector((0,0,1))).normalized())


def rifle_pose_signature(asset, rig):
    grip, support, _, forward, up = rifle_landmarks(asset, rig)
    # Muzzle length can change independently of the shoulder and wrist poses.
    return "shoulder-v1:" + ",".join(f"{v:.6f}" for point in (grip,support,forward,up) for v in point)


def _bind_rifle_mesh(obj, rig):
    """Rigid equipment uses the same hand-driven bone in both clips."""
    name = "carbine"
    for group in list(obj.vertex_groups):
        if group.name != name and group.name in rig.data.bones:
            obj.vertex_groups.remove(group)
    group = obj.vertex_groups.get(name) or obj.vertex_groups.new(name=name)
    group.add([v.index for v in obj.data.vertices], 1, "REPLACE")
    mod = next((m for m in obj.modifiers if m.type == "ARMATURE" and m.object == rig), None)
    if mod is None:
        mod = obj.modifiers.new("Marine skeleton", "ARMATURE")
        mod.object = rig
    mod.use_vertex_groups = True
    mod.use_bone_envelopes = False


def bind_fitted_rifle(rig):
    """Fit the new artwork to an existing Round Table rig and retain its actions.

    Run after placing the three rest-pose sockets and the visible rifle meshes.
    The grip frame retains the running carry. A fitted shooting pose is baked
    on the first upgrade, or when a grip contact or the rifle orientation moves.
    """
    asset = bpy.data.collections["Round_Table_Marine_ASSET"]
    if rig not in asset.objects[:] or rig.get("variant") != "A":
        raise ValueError("The fitted rifle belongs to the Round Table Marine")
    bpy.context.view_layer.update()
    _, _, tip, axis, _ = rifle_landmarks(asset, rig)
    previous = bpy.context.view_layer.objects.active
    was_selected = rig.select_get()
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    try:
        marker = rig.data.edit_bones["muzzle"]
        marker.head = tip
        marker.tail = tip + axis * .055
        marker.align_roll(Vector((0,0,1)))
    finally:
        bpy.ops.object.mode_set(mode="OBJECT")
        rig.select_set(was_selected)
        bpy.context.view_layer.objects.active = previous
    for obj in asset.all_objects:
        if obj.type == "MESH" and obj.get("asset_part") == "rifle":
            _bind_rifle_mesh(obj, rig)
    bpy.context.view_layer.update()
    if rig.animation_data:
        shoot = next((s.action for t in rig.animation_data.nla_tracks for s in t.strips
                      if s.action and s.action.name == "Shoot"), None)
        if shoot and shoot.get("rifle_pose") != rifle_pose_signature(asset, rig):
            from combat_cycle import build_shoot
            build_shoot(rig)
    return rig


def smooth_between(value, low, high):
    t = max(0., min(1., (value-low)/(high-low)))
    return t*t*(3-2*t)


def segment_weights(z, joints):
    """Blend adjacent bones at their support levels, with constant end weights."""
    if z <= joints[0][0]:
        return {joints[0][1]: 1.}
    for (lo, a), (hi, b) in zip(joints,joints[1:]):
        if z <= hi:
            if a==b:
                return {a: 1.}
            t = smooth_between(z,lo,hi)
            return {a: 1-t,b: t}
    return {joints[-1][1]: 1.}


def prepare_bones(armature, asset, tag):
    bones = armature.data.edit_bones
    def add(name, a, b, parent=None, up=(0,-1,0)):
        bone = bones.new(name)
        bone.head,bone.tail = Vector(a),Vector(b)
        if parent:
            bone.parent = bones[parent]
        aim = (bone.tail-bone.head).normalized()
        reference = Vector(up)
        if abs(aim.dot(reference))>.96:
            reference = Vector((0,0,1))
        bone.align_roll(reference)
        return bone
    def obj(suffix):
        return asset.objects[tag+"_"+suffix]
    add("root",(0,0,0),(0,-.17,0),up=(0,0,1))
    spine = [
        ("pelvis",(0,.018,.991),(0,.014,1.075),"root"),
        ("spine.01",(0,.014,1.075),(0,.014,1.20),"pelvis"),
        ("spine.02",(0,.014,1.20),(0,.012,1.34),"spine.01"),
        ("spine.03",(0,.012,1.34),(0,.008,1.565),"spine.02"),
        ("neck",(0,.008,1.565),(0,.004,1.668),"spine.03"),
        ("head",(0,.004,1.668),(0,.004,1.945),"neck"),
    ]
    for spec in spine:
        add(*spec)
    for s,suffix in [(-1,"R"),(1,"L")]:
        shoulder = Vector((s*.30,0,1.48))
        elbow0 = Vector((s*.43,-.005,1.22))
        wrist0 = Vector((s*.48,-.045,.995))
        upper = obj("UpperArm_"+suffix+"_Undersuit").matrix_world
        lower = obj("Forearm_"+suffix+"_Undersuit").matrix_world
        elbow = upper @ elbow0
        wrist = lower @ wrist0
        palm = obj("Glove_"+suffix+"_Palm").matrix_world.translation
        suffix = "." + suffix
        add("clavicle"+suffix,(s*.045,.006,1.50),shoulder,"spine.03",up=(0,0,1))
        add("upper_arm"+suffix,shoulder,elbow,"clavicle"+suffix)
        add("forearm"+suffix,elbow,wrist,"upper_arm"+suffix)
        add("hand"+suffix,wrist,wrist+1.60*(palm-wrist),"forearm"+suffix)
        add("pauldron"+suffix,shoulder,elbow,"clavicle"+suffix)
        hip,knee,ankle = (s*.155,.018,.995),(s*.170,-.004,.560),(s*.180,.012,.160)
        turnout = math.radians(5 if tag=="B" else 7)
        def footpoint(length,z):
            return (s*(.18+length*math.sin(turnout)),.012-length*math.cos(turnout),z)
        ball,toe = footpoint(.137,.050),footpoint(.205,.044)
        add("thigh"+suffix,hip,knee,"pelvis")
        add("cuisse"+suffix,hip,knee,"thigh"+suffix)
        hinge = Vector((s*.155,-.104,1.044))
        add("tasset"+suffix,hinge,hinge+Vector(knee)-Vector(hip),"pelvis")
        add("shin"+suffix,knee,ankle,"thigh"+suffix)
        add("poleyn"+suffix,knee,ankle,"thigh"+suffix)
        add("foot"+suffix,ankle,ball,"shin"+suffix,up=(0,0,1))
        add("toe"+suffix,ball,toe,"foot"+suffix,up=(0,0,1))
    cx = .14 if tag=="B" else 0.
    cape = [(cx,.145,1.495),(cx,.195,1.185),(cx,.267,.815),(cx,.345,.355)]
    tabard = [(0,-.144,1.045),(0,-.156,.81),(0,-.173,.55)]
    for stem,points,parent in [("cape",cape,"spine.03"),("tabard",tabard,"pelvis")]:
        for i,(a,b) in enumerate(zip(points,points[1:])):
            name = f"{stem}.{i+1:02}"
            add(name,a,b,parent)
            parent = name
    if tag == "A" and asset.objects.get("A_Rifle_trigger_socket"):
        grip, _, tip, axis, _ = rifle_landmarks(asset, armature)
    else:
        bore = obj("Carbine_muzzle_bore")
        collar = obj("Carbine_muzzle_collar")
        axis = (bore.matrix_world.translation-collar.matrix_world.translation).normalized()
        points = [bore.matrix_world@v.co for v in bore.data.vertices]
        front = max(p.dot(axis) for p in points)
        face = [p for p in points if front-p.dot(axis)<.00005]
        tip = sum(face,Vector())/len(face)
        grip = obj("Carbine_hand_grip").matrix_world.translation
    add("carbine",grip,grip+axis*.22,"hand.R",up=(0,0,1))
    add("muzzle",tip,tip+axis*.055,"carbine",up=(0,0,1))
    hand = bones["hand.L"]
    add("shield",hand.head,hand.head+Vector((0,-.015,-.180)),"hand.L")
    add("sword",(-.27,.055,.99),(-.305,.06,.58),"pelvis")


def bind_mesh(obj, rig):
    name = obj.name.lower()
    hint = obj.get("rig_hint")
    gear = obj.get("asset_part")
    if gear == "rifle":
        _bind_rifle_mesh(obj, rig)
        return
    cape = "cape" in name and "shoulder_drape" not in name
    tabard = "tabard" in name
    head = "_head_" in name or obj.get("source_component")=="head"
    if head:
        bone = "neck" if "neck" in name and not any(k in name for k in ["helmet","nape"]) else "head"
    elif tabard:
        bone = "tabard.01"
    elif cape:
        bone = "cape.01"
    elif gear in {"carbine","shield","sheathed_sword"}:
        bone = {"carbine":"carbine","shield":"shield","sheathed_sword":"sword"}[gear]
    elif "shoulder_drape" in name:
        bone = "spine.03"
    elif not hint:
        raise ValueError(f"Missing skeletal assignment for {obj.name}")
    elif any(k in name for k in ["_heraldic_pauldron","_heraldic_sun","_heraldic_sword"]):
        bone = "pauldron."+hint[-1]
    elif "_poleyn" in name:
        bone = "poleyn."+hint[-1]
    elif "_sliding_tasset_" in name:
        bone = "tasset."+hint[-1]
    elif "_raised_cuisse_" in name:
        bone = "cuisse."+hint[-1]
    elif "_toe_cap_" in name:
        bone = "toe."+hint[-1]
    else:
        bone = hint
    if bone not in rig.data.bones:
        raise ValueError(f"Unknown bone {bone} on {obj.name}")

    soft = any(k in name for k in ("arming_breeches","quilted_knee","torso_undersuit",
                                   "boot_sole","boot_welt","leather_boot"))
    if not (cape or tabard or soft):
        group = obj.vertex_groups.new(name=bone)
        group.add(list(range(len(obj.data.vertices))),1.,"REPLACE")
    else:
        groups = {}
        for v in obj.data.vertices:
            x,y,z = obj.matrix_world@v.co
            if cape:
                weights = segment_weights(z,[(.49,"cape.03"),(.89,"cape.02"),
                                             (1.25,"cape.01"),(1.505,"spine.03")])
            elif tabard:
                weights = segment_weights(z,[(.68,"tabard.02"),(.91,"tabard.01"),
                                             (1.026,"tabard.01"),(1.054,"pelvis")])
                # The center is fastened under the clasp. Upper corners can lift
                # off the belt when the side tassets advance.
                if "pelvis" in weights:
                    free = .90*smooth_between(abs(x),.024,.080)*weights["pelvis"]
                    weights["pelvis"] -= free
                    weights["tabard.01"] = weights.get("tabard.01",0.)+free
            elif "arming_breeches" in name:
                pelvis = smooth_between(z,.865,1.055)
                left = smooth_between(x,-.038,.038)
                weights = {"pelvis":pelvis,"thigh.L":(1-pelvis)*left,
                           "thigh.R":(1-pelvis)*(1-left)}
            elif "quilted_knee" in name:
                side = hint[-1]
                weights = segment_weights(z,[(.495,"shin."+side),(.551,"poleyn."+side),
                                             (.612,"thigh."+side)])
            elif "torso_undersuit" in name:
                weights = segment_weights(z,[(1.03,"pelvis"),(1.13,"spine.01"),
                                             (1.27,"spine.02"),(1.425,"spine.03")])
            else:
                side = hint[-1]
                toe = smooth_between(-y,.099,.174)
                weights = {"foot."+side:1-toe,"toe."+side:toe}
            for name_,weight in weights.items():
                if weight>0:
                    if name_ not in groups:
                        groups[name_] = obj.vertex_groups.new(name=name_)
                    groups[name_].add([v.index],weight,"REPLACE")
    mod = obj.modifiers.new("Marine skeleton","ARMATURE")
    mod.object = rig
    mod.use_vertex_groups = True
    mod.use_bone_envelopes = False


def rig_marine():
    asset, = [c for c in bpy.data.collections if c.name.endswith("_ASSET")]
    existing = [o for o in asset.objects if o.type=="ARMATURE"]
    if existing:
        return existing[0]
    root, = [o for o in asset.objects if o.type=="EMPTY" and not o.parent]
    meshes = [o for o in asset.objects if o.type=="MESH"]
    tag = next(o.name[0] for o in meshes if o.name.endswith("_Torso_Undersuit"))
    rig = bpy.data.objects.new("Marine_Rig",bpy.data.armatures.new("Arthurian skeleton"))
    asset.objects.link(rig)
    rig.parent = root
    rig.show_in_front = True
    rig.data.display_type = "STICK"
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    prepare_bones(rig,asset,tag)
    bpy.ops.object.mode_set(mode="OBJECT")
    for obj in meshes:
        bind_mesh(obj,rig)
    root["asset_status"] = "Articulated human marine"
    rig["variant"] = tag
    bpy.context.scene.render.fps = 24
    bpy.context.scene.render.fps_base = 1
    return rig


def stash_action(rig,action):
    """Keep an editable action and a muted, single-strip export track in rest."""
    data = rig.animation_data_create()
    data.action = None
    for track in list(data.nla_tracks):
        if track.name==action.name:
            data.nla_tracks.remove(track)
    track = data.nla_tracks.new()
    track.name = action.name
    strip = track.strips.new(action.name,int(action.frame_range[0]),action)
    strip.extrapolation = 'NOTHING'
    strip.influence = 1.
    track.mute = True
    action.use_fake_user = True
    for pb in rig.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    bpy.context.scene.frame_start = 0
    bpy.context.scene.frame_end = max([int(s.frame_end) for t in data.nla_tracks for s in t.strips]+[1])
    bpy.context.scene.frame_set(0)
    bpy.context.view_layer.update()


if __name__=="__main__":
    rig_marine()
    output = Path(sys.argv[sys.argv.index("--")+1]) if "--" in sys.argv else Path(bpy.data.filepath)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(output),compress=True)
