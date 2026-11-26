"""Articulated Forester skeleton and skinning, in the modeled two-hand grip.

The same rest coordinates drive the editable file and the exported game meshes.
The head of each foot is the ankle, and the head of each hand is the wrist.
Equipment bones are independent children of the ground root for two-hand poses.
"""
import re
from math import radians

import bpy
from mathutils import Matrix, Quaternion, Vector

import arms_axe
from field_kit import leg_center


SIDE = {"R": -1, "L": 1}
DIGITS = ("index", "middle", "ring", "pinky", "thumb")
GRIPS = {"R": .235, "L": .648}
RIG_NAME = "Forester Skeleton"
RIG_TAG = "forester_skeleton"


def smoothstep(lo, hi, x):
    t = min(1., max(0., (x-lo)/(hi-lo)))
    return t*t*(3.-2.*t)


def hybrid(a, b, blend):
    if blend <= .0001:
        return a
    if blend >= .9999:
        return b
    weights = {n: w*(1-blend) for n, w in a.items()}
    for name, w in b.items():
        weights[name] = weights.get(name, 0.) + w*blend
    return weights


def ring_centers(obj, ring_size, to_armature):
    vertices = obj.data.vertices
    if len(vertices) % ring_size:
        raise ValueError(f"{obj.name} must consist of {ring_size}-vertex rings")
    return [to_armature @ (sum((vertices[i+j].co for j in range(ring_size)), Vector())/ring_size)
            for i in range(0, len(vertices), ring_size)]


def landmarks(root, objects):
    by_name = {obj.name: obj for obj in objects}
    inv = root.matrix_world.inverted_safe()
    points = {}
    for suffix, side in SIDE.items():
        word = "right" if side < 0 else "left"
        palm = by_name["Glove | "+word+" palm"]
        palm_rings = ring_centers(palm, 18, inv @ palm.matrix_world)
        points["wrist."+suffix] = palm_rings[0]
        points["knuckle."+suffix] = palm_rings[-1]
        points["shoulder."+suffix] = Vector((side*.179,.002,1.389))
        points["elbow."+suffix] = Vector((side*(.245 if side<0 else .254),-.034,1.118))
        points["grip."+suffix] = arms_axe.centerline(GRIPS[suffix])
        points["hip."+suffix] = Vector((side*.079+.005,.004,.923))
        points["knee."+suffix] = Vector((*leg_center(side,.475),.475))
        points["ankle."+suffix] = Vector((*leg_center(side,.113),.113))
        x,y = leg_center(side,.09)
        points["ball."+suffix] = Vector((x+side*.007,y-.088,.037))
        points["toe."+suffix] = Vector((x+side*.012,y-.152,.032))
        for i, digit in enumerate(DIGITS):
            thumb = digit == "thumb"
            name = "Hand | "+word+(" thumb" if thumb else f" finger {i+1}")
            obj = by_name[name]
            rings = ring_centers(obj, 16 if thumb else 14, inv @ obj.matrix_world)
            points[digit+"."+suffix] = [rings[j] for j in ((0,2,4,6) if thumb else (0,3,6,9))]
    return points


def create_rig(root, objects):
    """Create the rig, reparent and weight all editable artwork, and return the rig."""
    existing = next((o for o in root.children if o.type == "ARMATURE" and o.get(RIG_TAG)), None)
    if existing:
        bind_meshes(existing, objects)
        return existing
    bpy.context.view_layer.update()
    points = landmarks(root, objects)
    data = bpy.data.armatures.new(RIG_NAME)
    rig = bpy.data.objects.new(RIG_NAME, data)
    root.users_collection[0].objects.link(rig)
    rig.parent = root
    rig[RIG_TAG] = True
    rig.show_in_front = True
    data.display_type = "STICK"
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    def bone(name, start, end, parent=None, roll=(0,-1,0), joined=False):
        edit = data.edit_bones.new(name)
        edit.head, edit.tail = Vector(start), Vector(end)
        if parent:
            edit.parent = data.edit_bones[parent]
            edit.use_connect = joined
        direction = (edit.tail-edit.head).normalized()
        ref = Vector(roll)
        if abs(ref.normalized().dot(direction)) > .998:
            ref = Vector((1,0,0))
        edit.align_roll(ref)
        return edit

    bone("root",(0,0,0),(0,-.12,0),roll=(0,0,1))
    spine = [
        ("pelvis",(0,.005,.918)), ("spine.01",(0,.004,1.035)),
        ("spine.02",(0,.004,1.190)), ("chest",(0,.002,1.312)),
        ("neck",(0,.006,1.448)), ("head",(0,.002,1.514))]
    for i,(name,p) in enumerate(spine):
        end = spine[i+1][1] if i+1 < len(spine) else (0,.006,1.705)
        bone(name,p,end,spine[i-1][0] if i else "root",joined=i>0)

    for suffix,side in SIDE.items():
        side_name = lambda name: name+"."+suffix
        pt = lambda name: points[side_name(name)]
        bone(side_name("clavicle"),(side*.026,.005,1.399),pt("shoulder"),"chest")
        for n,s,e,parent,roll in [
            ("upper_arm","shoulder","elbow","clavicle",(0,1,0)),
            ("forearm","elbow","wrist","upper_arm",(0,1,0)),
            ("hand","wrist","knuckle","forearm",arms_axe.AXIS),
            ("thigh","hip","knee","pelvis",(0,1,0)),
            ("shin","knee","ankle","thigh",(0,1,0)),
            ("foot","ankle","ball","shin",(0,0,1)),
            ("toe","ball","toe","foot",(0,0,1)),
        ]:
            bone(side_name(n),pt(s),pt(e),parent if parent=="pelvis" else side_name(parent),
                 roll,joined=n != "thigh")
        for digit in DIGITS:
            coords = pt(digit)
            for i in range(3):
                name = side_name(f"{digit}.{i+1:02}")
                parent = side_name(f"{digit}.{i:02}") if i else side_name("hand")
                bone(name,coords[i],coords[i+1],parent,arms_axe.AXIS,joined=i>0)

    braid = [(-.027,.080,1.573),(-.064,.028,1.499),
             (-.110,-.094,1.411),(-.109,-.128,1.290)]
    for i in range(3):
        bone(f"braid.{i+1:02}",braid[i],braid[i+1],f"braid.{i:02}" if i else "chest",
             (1,0,0),joined=i>0)
    for name, y in [("skirt.front",-.092),("skirt.back",.105)]:
        bone(name,(0,y,.990),(0,y*1.44,.615),"pelvis",(0,1,0))
    bone("tool",points["grip.R"],points["grip.L"],"root",(0,0,1))
    bone("hammer",points["grip.R"],points["grip.R"]+arms_axe.AXIS*.16,"root",(0,0,1))
    bone("load",(0,-.282,1.130),(.14,-.282,1.130),"root",(0,0,1))
    bpy.ops.object.mode_set(mode="OBJECT")
    for name in ("grip.R","grip.L"):
        rig[name] = list(points[name])
    for name,point in {"load_grip.R":(-.163,-.327,1.065),"load_grip.L":(.163,-.327,1.065),
                       "tool_edge":arms_axe.workpiece(-.027,.202),
                       "hammer_face":(-.4387,-.2502,1.2761)}.items():
        rig[name] = list(point)
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
    bind_meshes(rig, objects)
    return rig


def torso_weights(z):
    sections = (("pelvis",1.035),("spine.01",1.161),("spine.02",1.285),("chest",1.430))
    for (lower,a),(upper,b) in zip(sections,sections[1:]):
        if z < b:
            return hybrid({lower:1.},{upper:1.},smoothstep(a-.032,b-.032,z))
    return {"chest":1.}


def mantle_weights(p):
    suffix = "L" if p.x>0 else "R"
    x = abs(p.x)
    w = hybrid(torso_weights(p.z),{"clavicle."+suffix:1.},
               smoothstep(.086,.172,x)*smoothstep(1.278,1.369,p.z))
    # The mantle rides over the sleeve cap. Bring the outer shoulder up
    # with the humerus, while the cloth nearer the throat stays on the yoke.
    follow = smoothstep(.112,.203,x)*smoothstep(1.24,1.312,p.z)
    return hybrid(w,{"upper_arm."+suffix:1.},.99*follow)


def skirt_weights(p):
    # The fore and rear pieces open at their vents. Overlapping apron, hems
    # and linen share the same field, so the outer layer stays on top.
    side = smoothstep(-.040,.040,p.x)
    joints = hybrid({"thigh.R":1.},{"thigh.L":1.},side)
    to_legs = .77+.23*smoothstep(.008,.067,abs(p.x))
    loose = hybrid({"skirt.front" if p.y<=.005 else "skirt.back":1.},joints,to_legs)
    return hybrid({"pelvis":1.},loose,1-smoothstep(.838,.997,p.z))


def leg_weights(p, suffix, bones):
    def w(b):
        return {b+"."+suffix:1.}
    knee = bones["shin."+suffix].head_local.z
    ankle = bones["foot."+suffix].head_local
    if p.z >= ankle.z+.048:
        return hybrid(w("shin"),w("thigh"),smoothstep(knee-.059,knee+.066,p.z))
    shin = smoothstep(ankle.z-.045,ankle.z+.047,p.z)
    toe = (1-smoothstep(ankle.y-.144,ankle.y-.071,p.y))*(1-smoothstep(.05,.092,p.z))
    return hybrid(hybrid(w("foot"),w("toe"),toe),w("shin"),shin)


def closest_segment(p, a, b):
    edge = b-a
    t = min(1.,max(0.,(p-a).dot(edge)/edge.length_squared))
    return (p-a-edge*t).length_squared,t


def finger_weights(p, names, bones):
    segments = [closest_segment(p,bones[n].head_local,bones[n].tail_local) for n in names]
    i = min(range(3),key=lambda j: segments[j][0])
    t = segments[i][1]
    if i<2 and t>.60:
        return hybrid({names[i]:1.},{names[i+1]:1.},.5*smoothstep(.60,1.,t))
    if i>0 and t<.40:
        return hybrid({names[i-1]:1.},{names[i]:1.},.5+.5*smoothstep(0,.40,t))
    if i==0 and t<.24:
        return hybrid({"hand."+names[i][-1]:1.},{names[i]:1.},.70+.30*smoothstep(0,.24,t))
    return {names[i]:1.}


def arm_weights(p, suffix, bones, part):
    arm,fore,wrist = ("upper_arm."+suffix,"forearm."+suffix,"hand."+suffix)
    elbow_pos = bones[fore].head_local
    if part == "sleeve":
        shoulder = bones[arm].head_local
        axis = (elbow_pos-shoulder).normalized()
        near = (p-shoulder).dot(axis)
        return hybrid({"clavicle."+suffix:1.},{arm:1.},.35+.65*smoothstep(-.001,.043,near))
    if part == "bracer":
        return {fore:1.}
    axis = (bones[wrist].head_local-elbow_pos).normalized()
    upper=(elbow_pos-bones[arm].head_local).normalized()
    bend=(axis+upper).normalized()
    # Elbow crease follows an oblique plane between humerus and radius.
    w = hybrid({arm:1.},{fore:1.},smoothstep(-.041,.043,(p-elbow_pos).dot(bend)))
    return hybrid(w,{wrist:1.},.86*smoothstep(-.023,.019,(p-bones[wrist].head_local).dot(axis)))


def skin_rule(obj,bones):
    """Choose construction-aware weights so overlays follow their parent surface."""
    part = obj.get("part","")
    name = obj.name.lower()
    prop = {"WoodcuttingAxe":"tool","FarmingTool":"tool","BuildingHammer":"hammer","MaterialLoad":"load","FoodBasket":"load","HarvestGrapes":"load",
            "Sunhat":"head","Kerchief":"head"}.get(part)
    if prop:
        return prop
    if part == "Head":
        if "neck and throat" in name:
            def neck(p):
                w=hybrid({"chest":1.},{"neck":1.},smoothstep(1.414,1.483,p.z))
                return hybrid(w,{"head":1.},smoothstep(1.481,1.539,p.z))
            return neck
        return "head"
    if part == "Hair":
        if name.startswith(("plait","loose braid end")):
            def braid(p):
                w=hybrid({"braid.03":1.},{"braid.02":1.},smoothstep(1.395,1.427,p.z))
                w=hybrid(w,{"braid.01":1.},smoothstep(1.484,1.516,p.z))
                return hybrid(w,{"head":1.},smoothstep(1.543,1.584,p.z))
            return braid
        return "head"
    if part == "Arms":
        suffix = "R" if "right" in name else "L"
        if "thumb" in name or "finger" in name or "nail" in name:
            finger = "thumb" if "thumb" in name else DIGITS[int(re.search(r"(finger|nail) (\d)",name).group(2))-1]
            names=[f"{finger}.{i:02}.{suffix}" for i in range(1,4)]
            return names[-1] if "nail" in name else lambda p: finger_weights(p,names,bones)
        kind = name.split(" |",1)[0]
        if kind in {"arm","sleeve","bracer"}:
            return lambda p: arm_weights(p,suffix,bones,kind)
        return "hand."+suffix
    if part == "Field Kit":
        # Boot/legging pieces carry the side suffix added during construction.
        leg = re.search(r" ([lr])(?:\.\d+)?$",name)
        if leg:
            return lambda p: leg_weights(p,leg.group(1).upper(),bones)
        return "pelvis"
    if part == "Garments":
        if name.startswith(("linen skirt","turned linen hem","bound vent","indigo side gore","gore hem",
                            "forester's heraldic apron","tabard","chevron hem","fine thread above chevron",
                            "apron ","harvest sprig")):
            return skirt_weights
        return mantle_weights
    raise ValueError(f"No skin assignment for {obj.name!r} (part {part!r})")


def bind_meshes(rig, objects):
    """Attach deform groups and append the armature after all modeling modifiers."""
    bpy.context.view_layer.update()
    inv = rig.matrix_world.inverted_safe()
    bones = rig.data.bones
    for obj in objects:
        if obj.type!="MESH" or obj == rig:
            continue
        world = obj.matrix_world.copy()
        to_armature = inv @ world
        rule = skin_rule(obj,bones)
        for group in list(obj.vertex_groups):
            if group.name in bones:
                obj.vertex_groups.remove(group)
        group_cache = {}
        def group(name):
            if name not in group_cache:
                group_cache[name]=obj.vertex_groups.new(name=name)
            return group_cache[name]
        if isinstance(rule,str):
            group(rule).add(list(range(len(obj.data.vertices))),1.,"REPLACE")
        else:
            # Match opposing sides of each small phalanx and elbow ring. The
            # glove lining and exposed finger keep the same cross-section
            # through a bend, including the inner face of the curled grip.
            segment_size = 0
            if obj.get("part")=="Arms":
                name = obj.name.lower()
                if name.startswith("arm |"):
                    segment_size = 28
                elif "thumb" in name:
                    segment_size = 16
                elif "finger" in name:
                    segment_size = 14
            centers = ring_centers(obj,segment_size,to_armature) if segment_size else []
            for v in obj.data.vertices:
                pos = centers[v.index//segment_size] if centers else to_armature @ v.co
                scores = sorted(rule(pos).items(),key=lambda item:-item[1])[:4]
                scores = [(name,w) for name,w in scores if w>.0002]
                total=sum(w for _,w in scores)
                for name,w in scores:
                    group(name).add([v.index],w/total,"REPLACE")
        obj.parent = rig
        obj.matrix_parent_inverse = Matrix.Identity(4)
        obj.matrix_basis = to_armature
        mod = next((m for m in obj.modifiers if m.type=="ARMATURE" and m.object==rig),None)
        if not mod:
            mod=obj.modifiers.new("Forester skin","ARMATURE")
        mod.object=rig
        mod.use_deform_preserve_volume=False
        index=obj.modifiers.find(mod.name)
        if index!=len(obj.modifiers)-1:
            obj.modifiers.move(index,len(obj.modifiers)-1)
    bpy.context.view_layer.update()


def open_hand(rig, suffix, amount):
    """Uncurl each digit along its rest knuckle plane. Caller keys the rotations."""
    strength=min(1.,max(0.,amount))
    bones=rig.data.bones
    for digit in DIGITS:
        names=[f"{digit}.{i:02}.{suffix}" for i in range(1,4)]
        axes=[(bones[n].tail_local-bones[n].head_local).normalized() for n in names]
        bend_axis=axes[0].cross(axes[1]).normalized()
        for i,name in enumerate(names):
            desired=(axes[i].rotation_difference(axes[i-1]) if i else
                     Quaternion(bend_axis,radians(-22 if digit=="thumb" else -30)))
            rest=bones[name].matrix_local.to_quaternion()
            rig.pose.bones[name].rotation_quaternion=Quaternion().slerp(rest.inverted()@desired@rest,strength)
