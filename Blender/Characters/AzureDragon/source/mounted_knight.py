"""Fit the project's Round Table Marine to the Azure Dragon's actual war saddle."""
import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Euler, Matrix, Quaternion, Vector


SEAT = "Rider_Mount"
UPPER = "Rider_Upper"
SADDLE_SHIFT = Vector((0, .370, .182))
PLACEMENT = Vector((0, .413, 1.092))


def refresh():
    bpy.context.view_layer.update()


def world_rotation(bone, rotation):
    basis = rotation @ bone.bone.matrix_local.to_quaternion()
    bone.matrix = Matrix.LocRotScale(bone.head.copy(), basis, Vector((1, 1, 1)))
    refresh()


def aim(bone, direction):
    base = bone.bone.tail_local - bone.bone.head_local
    world_rotation(bone, base.normalized().rotation_difference(Vector(direction).normalized()))


def fit_marine(avatar):
    """Use the marine's native armor rig to form a seated pose before rebinding."""
    avatar.animation_data_clear()
    bones = avatar.pose.bones
    for bone in bones:
        bone.matrix_basis = Matrix.Identity(4)
    refresh()
    axis = Vector((1, 0, 0))
    for name, angle in (("spine.01", 5), ("spine.02", 7), ("spine.03", 7), ("head", 2)):
        world_rotation(bones[name], Quaternion(axis, math.radians(angle)))
    grips = {}
    for side, s in (("L", 1), ("R", -1)):
        # Both knees go forward and out around the barrel. Feet return under the hip.
        thigh = bones["thigh." + side]
        aim(thigh, (s * .386, -.16, -.088))
        aim(bones["shin." + side], (s * .169, .315, -.18))
        aim(bones["poleyn." + side], (s * .099, .178, -.323))
        aim(bones["tasset." + side], (s * .21, .008, -.31))
        world_rotation(bones["foot." + side], Quaternion(Vector((0, 0, 1)), math.radians(s * 6)))
        world_rotation(bones["toe." + side], Quaternion(Vector((0, 0, 1)), math.radians(s * 6)))
        elbow = Vector((s * .322, -.135, 1.22))
        upper = bones["upper_arm." + side]
        aim(upper, elbow - upper.head)
        aim(bones["pauldron." + side], (s * .012, -.072, -.25))
        fore = bones["forearm." + side]
        aim(fore, (s * -.089, -.205, .02))
        hand = bones["hand." + side]
        aim(hand, (s * -.055, -.040, -.024))
        # The source wrist-to-palm distance is stable on both sides even though
        # glTF's leaf-bone lengths differ between the rifle and support hands.
        grips[side] = hand.head.copy() + Vector((s * -.05, -.04, -.025)).normalized() * .072 + PLACEMENT
    for name, angle in (("cape.01", 30), ("cape.02", 44), ("cape.03", 52),
                        ("tabard.01", -59), ("tabard.02", -70)):
        world_rotation(bones[name], Quaternion(axis, math.radians(angle)))
    sword = bones["sword"]
    world_rotation(sword, Quaternion(axis, math.radians(52)))
    m = sword.matrix.copy()
    m.translation += Vector((-.199, .128, -.012))
    sword.matrix = m
    refresh()
    return grips


def add_upper_bone(rig):
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bone = rig.data.edit_bones.new(UPPER)
    socket = rig.data.edit_bones[SEAT]
    socket.head += SADDLE_SHIFT
    socket.tail += SADDLE_SHIFT
    bone.head = Vector((0,.06,1.87)) + SADDLE_SHIFT
    bone.tail = bone.head + Vector((0,-.025,.58))
    bone.align_roll(Vector((0, -1, 0)))
    bone.parent = rig.data.edit_bones[SEAT]
    bpy.ops.object.mode_set(mode="OBJECT")


def map_material(mat, originals):
    # Keep the dragon and knight on the same faction swatches.
    base = mat.name.rsplit(".", 1)[0] if mat.name[-4:-3] == "." and mat.name[-3:].isdigit() else mat.name
    return originals.get(base, mat)


def set_deform(obj, rig, upper_factors):
    seat, upper = obj.vertex_groups.new(name=SEAT), obj.vertex_groups.new(name=UPPER)
    by_value = {}
    for index, w in enumerate(upper_factors):
        by_value.setdefault(round(min(1, max(0, w)), 3), []).append(index)
    for w, indices in by_value.items():
        if w < 1:
            seat.add(indices, 1-w, "REPLACE")
        if w > 0:
            upper.add(indices, w, "REPLACE")
    mod = obj.modifiers.new("Dragon and rider", "ARMATURE")
    mod.object = rig
    mod.use_bone_envelopes = False
    obj.parent = rig


def compress_mesh(obj, ratio):
    # Merge the GLB shading seams before simplifying. Retain all material boundaries.
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=.000006)
    bm.to_mesh(obj.data)
    bm.free()
    if ratio >= 1:
        return
    active = bpy.context.view_layer.objects.active
    bpy.context.view_layer.objects.active = obj
    mod = obj.modifiers.new("Mounted level of detail", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = ratio
    mod.use_collapse_triangulate = True
    bpy.ops.object.modifier_move_to_index(modifier=mod.name, index=0)
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.context.view_layer.objects.active = active


def bake_part(src, name, rig, col, originals):
    evaluated = src.evaluated_get(bpy.context.evaluated_depsgraph_get())
    data = bpy.data.meshes.new_from_object(evaluated, preserve_all_data_layers=True,
                                           depsgraph=bpy.context.evaluated_depsgraph_get())
    data.name = "Mounted_Knight_" + name
    data.transform(Matrix.Translation(PLACEMENT) @ evaluated.matrix_world)
    obj = bpy.data.objects.new(data.name, data)
    col.objects.link(obj)
    for i, original in enumerate(data.materials):
        data.materials[i] = map_material(original, originals)
    factors, soles = [], {"L": [], "R": []}
    for v, baked in zip(src.data.vertices, data.vertices):
        # Body posture can flex above the seat. Boots and saddle stay together.
        if name == "Head":
            factor = 1.0
        elif name == "Sword":
            factor = 0.0
        else:
            factor = 0.0
            for g in v.groups:
                bn = src.vertex_groups[g.group].name
                if bn.startswith(("cape", "clavicle", "upper_arm", "forearm", "hand", "pauldron", "head", "neck")):
                    factor += g.weight
                elif bn.startswith("spine."):
                    factor += {"spine.01":.20, "spine.02":.62, "spine.03":1.0}.get(bn, 0) * g.weight
        factors.append(factor)
        if name == "Armor" and v.co.z < .040 and -.249 < v.co.y < -.095:
            soles["L" if v.co.x > 0 else "R"].append(baked.co.copy())
    # Both the donor's old indices and its group definitions must be removed.
    obj.vertex_groups.clear()
    bm = bmesh.new()
    bm.from_mesh(data)
    deform = bm.verts.layers.deform.active
    if deform:
        for v in bm.verts:
            v[deform].clear()
    bm.to_mesh(data)
    bm.free()
    set_deform(obj, rig, factors)
    arm = obj.modifiers[0]
    arm.show_viewport = False
    compress_mesh(obj, {"Armor":.26, "Head":.065, "Sword":.60, "Cloth":1}[name])
    arm.show_viewport = True
    return obj, soles


def tack(col, rig, grips, soles, originals):
    verts, faces, mats, weights = [], [], [], []
    def strap(points, width, depth, across, material, levels):
        start = len(verts)
        for i, p in enumerate(points):
            p = Vector(p)
            forward = (Vector(points[min(i+1, len(points)-1)]) - Vector(points[max(i-1, 0)])).normalized()
            right = Vector(across)
            right = (right - forward * right.dot(forward)).normalized()
            normal = forward.cross(right).normalized()
            for s,t in ((-1,-1),(1,-1),(1,1),(-1,1)):
                verts.append(p + s*.5*width*right + t*.5*depth*normal)
                weights.append(levels[i])
        for i in range(len(points)-1):
            for j in range(4):
                a = start + i*4
                faces.append((a+j, a+(j+1)%4, a+4+(j+1)%4, a+4+j))
                mats.append(material)
        faces.extend([(start+3,start+2,start+1,start),tuple(range(start+4*(len(points)-1),start+4*len(points)))])
        mats.extend([material,material])
    for side, s in (("L",1),("R",-1)):
        contact = soles[side]
        if not contact:
            raise RuntimeError("No points on the mounted boot sole")
        foot = sum(contact,Vector()) / len(contact)
        foot.z = min(p.z for p in contact) - .007
        left, right = min(p.x for p in contact)-.011, max(p.x for p in contact)+.011
        crown = Vector((foot.x, foot.y+.008, foot.z+.193))
        # D-shaped iron around the boot. Flat tread below the ball of the foot.
        iron = [crown, (left+.016,foot.y,foot.z+.125), (left,foot.y,foot.z+.025),
                (left+.012,foot.y,foot.z), (right-.012,foot.y,foot.z),
                (right,foot.y,foot.z+.025), (right-.016,foot.y,foot.z+.125), crown]
        strap(iron,.040,.016,(0,1,0),1,[0]*len(iron))
        seat = Vector((s*.235,.075,1.752)) + SADDLE_SHIFT
        shoulder = Vector((s*.38,.065,1.685)) + SADDLE_SHIFT
        strap([seat,shoulder,shoulder.lerp(crown,.48),crown],.030,.011,(0,1,0),0,[0]*4)
    mesh = bpy.data.meshes.new("Mounted_Knight_Tack")
    mesh.from_pydata(verts, [], faces)
    mesh.materials.append(originals["Harness_Leather"])
    mesh.materials.append(originals["Heraldic_Brass"])
    for p,index in zip(mesh.polygons,mats):
        p.material_index=index
    mesh.update()
    obj = bpy.data.objects.new(mesh.name,mesh)
    col.objects.link(obj)
    set_deform(obj,rig,weights)


def fit_reins(col, rig, grips):
    """Continue the halter to each actual palm, tracking the moving head and torso."""
    obj = col.objects["Dragon_Reins"]
    old = obj.data
    mesh = bpy.data.meshes.new("Dragon_Reins_Fitted")
    mesh.materials.append(old.materials[0])
    verts, faces, influences = [], [], []
    for side, sign in (("L",1),("R",-1)):
        grip = grips[side]
        path = [Vector((sign*.16,-.96,2.02)), Vector((sign*.245,-.88,1.982)),
                Vector((sign*.285,-.71,1.947)), Vector((sign*.295,-.55,1.970)),
                grip+Vector((sign*.024,-.084,-.054)), grip, grip+Vector((0,.024,-.008))]
        bones = ["head","head","neck.02","neck.01",UPPER,UPPER,UPPER]
        start = len(verts)
        for index in range(25):
            u = index/4
            span = min(int(u),len(path)-2)
            t = u-span
            a,b,c,d = [path[max(0,min(len(path)-1,span+k))] for k in (-1,0,1,2)]
            pt = .5*(2*b+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t**3)
            tangent = (-a+c + 2*(2*a-5*b+4*c-d)*t + 3*(-a+3*b-3*c+d)*t*t).normalized()
            wide = Vector((0,0,1))-tangent*tangent.z
            wide.normalize()
            normal = tangent.cross(wide).normalized()
            for w,h in ((-1,-1),(1,-1),(1,1),(-1,1)):
                verts.append(pt+w*.014*wide+h*.0045*normal)
                weights = {bones[span]:1-t}
                weights[bones[span+1]] = weights.get(bones[span+1],0)+t
                influences.append(weights)
            if index:
                row=start+4*(index-1)
                for j in range(4):
                    faces.append((row+j,row+(j+1)%4,row+4+(j+1)%4,row+4+j))
        faces.extend([tuple(reversed(range(start,start+4))),tuple(range(start+96,start+100))])
    mesh.from_pydata(verts,[],faces)
    mesh.update()
    obj.data=mesh
    obj.vertex_groups.clear()
    groups={}
    for i,weights in enumerate(influences):
        for bone,weight in weights.items():
            if weight <= 0: continue
            if bone not in groups:
                groups[bone]=obj.vertex_groups.new(name=bone)
            groups[bone].add([i],weight,"REPLACE")
    if not old.users:
        bpy.data.meshes.remove(old)


def add_response(rig):
    anim = rig.animation_data
    context_scene = bpy.context.scene
    prev_frame = context_scene.frame_current
    prev_mutes = {t.name:t.mute for t in anim.nla_tracks}
    upper = rig.pose.bones[UPPER]
    upper.rotation_mode = "XYZ"
    for track in anim.nla_tracks:
        track.mute = True
    for track in anim.nla_tracks:
        strip = track.strips[0]
        action = strip.action
        anim.action = action
        if action.slots:
            anim.action_slot = strip.action_slot
        first, last = map(float, action.frame_range)
        for i in range(17):
            t = i/16
            if track.name == "Walk":
                pitch = -3.5 + 2.3*math.sin(math.tau*t-.42)
                roll = 1.15*math.sin(math.tau*t+.28)
            elif track.name == "FireBreath":
                brace = math.sin(math.pi*t)**2
                pitch, roll = -8*brace, 0
            else:
                pitch, roll = .62*math.sin(math.tau*t), 0
            # Desired axes are defined in armature space, independent of bone roll.
            q = Euler(tuple(math.radians(v) for v in (pitch,roll,0)),"XYZ").to_quaternion()
            rest = upper.bone.matrix_local.to_quaternion()
            upper.rotation_euler = (rest.inverted() @ q @ rest).to_euler("XYZ")
            upper.keyframe_insert("rotation_euler", frame=first+(last-first)*t, group=UPPER)
        anim.action = None
    upper.matrix_basis = Matrix.Identity(4)
    for track in anim.nla_tracks:
        track.mute=prev_mutes[track.name]
    context_scene.frame_set(prev_frame)


def saddle_and_crest(col,rig,head,originals):
    # Two padded wooden bars carry the raised saddle clear of the wing roots.
    col.objects["Dragon_War_Saddle_Seat"].data.transform(Matrix.Translation(SADDLE_SHIFT))
    col.objects["Dragon_Saddle_Skirt"].data.transform(Matrix.Translation((0,.37,-.048)))
    col.objects["Dragon_Girth_Straps"].data.transform(Matrix.Translation((0,.30,-.038)))
    vertices,faces,indices=[],[],[]
    def rings(series, bands):
        start=len(vertices)
        n=len(series[0])
        for ring in series:
            vertices.extend(ring)
        for i, (r0,r1) in enumerate(zip(series,series[1:])):
            for j in range(n):
                a=start+i*n
                faces.append((a+j,a+(j+1)%n,a+n+(j+1)%n,a+n+j))
                indices.append(bands(i,j))
        faces.extend([tuple(start+j for j in range(n-1,-1,-1)),tuple(start+(len(series)-1)*n+j for j in range(n))])
        indices.extend([bands(0,0),bands(len(series)-2,0)])
    def make(name,upper,slots):
        mesh=bpy.data.meshes.new(name)
        mesh.from_pydata(vertices,[],faces)
        for m in slots:
            mesh.materials.append(originals.get(m) or bpy.data.materials[m])
        for p,index in zip(mesh.polygons,indices):
            p.material_index=index
        mesh.update()
        obj=bpy.data.objects.new(name,mesh)
        col.objects.link(obj)
        set_deform(obj,rig,[upper]*len(vertices))
        vertices.clear(); faces.clear(); indices.clear()
    for s in (-1,1):
        sections=[]
        for y,half,base,top in [(-.20,.10,1.59,1.728),(-.13,.19,1.56,1.705),
              (-.02,.217,1.54,1.681),(.12,.223,1.51,1.69),(.24,.20,1.49,1.714),(.29,.13,1.48,1.72)]:
            x=.032
            base-=SADDLE_SHIFT.z
            # Outer edge is padded below a dark leather band and brass seam.
            sections.append([Vector((s*xx,y,z))+SADDLE_SHIFT for xx,z in [
                (x,base+.07),(half+.008,base), (half+.018,base+.052),
                (half+.014,base+.062),(half+.011,top-.02),(half-.012,top),(x,top+.005)]])
        rings(sections,lambda i,j: (0 if j in (0,1) else 1 if j==2 else 2))
    make("Mounted_Knight_Saddle_Tree",0,["Saddle_Leather_Dark","Heraldic_Brass","Harness_Leather"])
    high=max(v.co.z for v in head.data.vertices)
    summit=[v.co for v in head.data.vertices if v.co.z>high-.009 and abs(v.co.x)<.07]
    crown=sum(summit,Vector())/len(summit)
    # Brass crest bracket, then a swept horsehair plume with an ivory ridge.
    for name,section,slots in [
        ("bracket",[(-.064,-.008,.024,.008),(-.037,.010,.030,.017),(.017,.019,.031,.023),(.066,.008,.025,.015)],["Heraldic_Brass"]),
        ("plume",[(-.057,.016,.009,.011),(-.038,.054,.026,.041),(-.012,.092,.036,.057),
                  (.036,.124,.040,.058),(.092,.138,.039,.050),(.155,.134,.035,.044),
                  (.213,.115,.027,.039),(.268,.080,.019,.03),(.305,.039,.004,.015),(.326,.018,.001,.002)],["team_color","Ivory_Armor","team_color_shadow"]),
    ]:
        series=[]
        for y,z,w,h in section:
            series.append([crown+Vector((w*math.cos(2*math.pi*k/10),y,z+h*math.sin(2*math.pi*k/10))) for k in range(10)])
        rings(series,lambda i,j: 0 if name=="bracket" else 1 if j in (2,3) else 2 if j in (6,7) else 0)
        make("Mounted_Knight_Crest_"+name,1,slots)


def install(col, rig, marine_path):
    """Install five rider meshes in col, bound to the same rig as the saddle."""
    marine_path = Path(marine_path).resolve(strict=True)
    originals = dict(bpy.data.materials.items())
    scene = bpy.context.scene
    original_frame, timeline = scene.frame_current, (scene.frame_start, scene.frame_end)
    prior = set(bpy.data.objects)
    prior_actions = set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=str(marine_path), import_pack_images=True)
    added = set(bpy.data.objects) - prior
    avatar, = [o for o in added if o.type == "ARMATURE"]
    donor = {o.data.name.split(".")[0]:o for o in added if o.type=="MESH" and o.find_armature() == avatar}
    grips = fit_marine(avatar)
    add_upper_bone(rig)
    for name in ("Armor","Cloth","Head","Sword"):
        piece, contact = bake_part(donor[name],name,rig,col,originals)
        if name == "Armor":
            soles = contact
        elif name == "Head":
            head=piece
    saddle_and_crest(col,rig,head,originals)
    tack(col,rig,grips,soles,originals)
    fit_reins(col,rig,grips)
    for obj in added:
        bpy.data.objects.remove(obj,do_unlink=True)
    for action in set(bpy.data.actions) - prior_actions:
        bpy.data.actions.remove(action)
    add_response(rig)
    scene.frame_start, scene.frame_end = timeline
    scene.frame_set(original_frame)
    bpy.context.view_layer.objects.active = rig
    refresh()
