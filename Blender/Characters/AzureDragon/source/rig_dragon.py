"""Procedural skinning, vertex-weight assignment, and NLA action utilities for the Azure Dragon."""

from math import sqrt
import bpy
import bmesh
from mathutils import Matrix, Vector


def clamp(v, lo=0.0, hi=1.0):
    return max(lo, min(hi, v))


def smoothstep(lo, hi, x):
    if hi == lo:
        return 0.0 if x < lo else 1.0
    t = clamp((x - lo) / (hi - lo))
    return t * t * (3.0 - 2.0 * t)


def iter_action_fcurves(action):
    """Yield every FCurve in an Action across Blender 4.5 slotted actions and legacy fcurves."""
    if action is None:
        return
    if hasattr(action, "layers") and len(action.layers) > 0:
        for layer in action.layers:
            for strip in layer.strips:
                for slot in action.slots:
                    bag = strip.channelbag(slot)
                    if bag:
                        for fc in bag.fcurves:
                            yield fc
    elif hasattr(action, "fcurves"):
        for fc in action.fcurves:
            yield fc


def stash_action(rig, action, mute=True):
    """Keep an editable action and stash a single-strip NLA track named after the action."""
    data = rig.animation_data_create()
    data.action = None
    for track in list(data.nla_tracks):
        if track.name == action.name:
            data.nla_tracks.remove(track)
    track = data.nla_tracks.new()
    track.name = action.name
    start = int(round(action.frame_range[0]))
    strip = track.strips.new(action.name, start, action)
    strip.name = action.name
    strip.extrapolation = "NOTHING"
    strip.influence = 1.0
    track.mute = mute
    action.use_fake_user = True
    for pb in rig.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    return track


def add_armature_modifier(obj, rig):
    mod = next((m for m in obj.modifiers if m.type == "ARMATURE"), None)
    if mod is None:
        mod = obj.modifiers.new("Azure_Dragon_Skeleton", "ARMATURE")
    mod.object = rig
    mod.use_vertex_groups = True
    mod.use_bone_envelopes = False
    return mod


def clear_vertex_groups(obj):
    for vg in list(obj.vertex_groups):
        obj.vertex_groups.remove(vg)


def set_vertex_weights(obj, vert_weights):
    """Assign normalized {bone_name: weight} dicts per vertex index."""
    clear_vertex_groups(obj)
    groups = {}
    for v_idx, wdict in enumerate(vert_weights):
        total = sum(w for w in wdict.values() if w > 1e-6)
        if total <= 1e-8:
            raise ValueError(f"{obj.name} vertex {v_idx} received zero bone weight")
        for b_name, w in wdict.items():
            if w <= 1e-6:
                continue
            if b_name not in groups:
                groups[b_name] = obj.vertex_groups.new(name=b_name)
            groups[b_name].add([v_idx], w / total, "REPLACE")


def set_rigid_weight(obj, rig, bone_name):
    assert bone_name in rig.data.bones, f"Missing bone {bone_name}"
    clear_vertex_groups(obj)
    vg = obj.vertex_groups.new(name=bone_name)
    vg.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    add_armature_modifier(obj, rig)


def _closest_param_on_polyline(pt, segs):
    """Return cumulative arc-length parameter s along connected polyline segments."""
    best_dist2 = 1e30
    best_s = 0.0
    cum_len = 0.0
    for a, b in segs:
        ab = b - a
        len2 = ab.length_squared
        seg_len = sqrt(len2)
        if len2 < 1e-10:
            u = 0.0
        else:
            u = clamp((pt - a).dot(ab) / len2)
        proj = a + ab * u
        d2 = (pt - proj).length_squared
        if d2 < best_dist2:
            best_dist2 = d2
            best_s = cum_len + u * seg_len
        cum_len += seg_len
    return best_s


def _mesh_island_centers(mesh):
    """Compute connected-component vertex groupings and centroids for crisp scale/spine skinning."""
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.verts.ensure_lookup_table()
    visited = [False] * len(bm.verts)
    vert_to_center = [Vector((0, 0, 0))] * len(bm.verts)
    for start_v in bm.verts:
        if visited[start_v.index]:
            continue
        stack = [start_v]
        comp = []
        visited[start_v.index] = True
        while stack:
            v = stack.pop()
            comp.append(v)
            for e in v.link_edges:
                ov = e.other_vert(v)
                if not visited[ov.index]:
                    visited[ov.index] = True
                    stack.append(ov)
        center = sum((v.co for v in comp), Vector()) / len(comp)
        for v in comp:
            vert_to_center[v.index] = center
    bm.free()
    return vert_to_center


def weight_along_chain(obj, rig, chain_specs, blend_radius=0.14, by_island=False):
    """Weight vertices (or mesh islands) smoothly along an ordered sequence of (bone_name, p_start, p_end)."""
    segs = [(Vector(a), Vector(b)) for _, a, b in chain_specs]
    nodes = [0.0]
    for a, b in segs:
        nodes.append(nodes[-1] + (b - a).length)
    total_len = nodes[-1]

    if by_island:
        sample_pts = _mesh_island_centers(obj.data)
    else:
        sample_pts = [v.co.copy() for v in obj.data.vertices]

    # Convert obj-space to armature space
    to_arm = rig.matrix_world.inverted() @ obj.matrix_world
    vert_weights = []
    for p_local in sample_pts:
        p = to_arm @ p_local
        s = _closest_param_on_polyline(p, segs)
        # Find active segment index
        seg_idx = 0
        for idx in range(len(segs)):
            if s <= nodes[idx + 1] or idx == len(segs) - 1:
                seg_idx = idx
                break
        b_curr = chain_specs[seg_idx][0]
        w = {b_curr: 1.0}
        # Blend across boundary with previous bone
        if seg_idx > 0 and chain_specs[seg_idx - 1][0] != b_curr:
            dist_prev = s - nodes[seg_idx]
            if dist_prev < blend_radius:
                t = smoothstep(-blend_radius, blend_radius, dist_prev)
                b_prev = chain_specs[seg_idx - 1][0]
                w = {b_prev: 1.0 - t, b_curr: t}
        # Blend across boundary with next bone
        if seg_idx < len(segs) - 1 and chain_specs[seg_idx + 1][0] != b_curr:
            dist_next = nodes[seg_idx + 1] - s
            if dist_next < blend_radius:
                t = smoothstep(-blend_radius, blend_radius, dist_next)
                b_next = chain_specs[seg_idx + 1][0]
                w = {b_curr: t, b_next: 1.0 - t}
        vert_weights.append(w)

    set_vertex_weights(obj, vert_weights)
    add_armature_modifier(obj, rig)


def _bone_seg(rig, name, p_start=None, p_end=None):
    b = rig.data.bones[name]
    return (name, p_start if p_start is not None else b.head_local.copy(),
            p_end if p_end is not None else b.tail_local.copy())


def _bind_wing_membrane(obj, rig, side):
    """Weight the 4-panel wing membrane grid cleanly across wing_forearm, wing_arm, chest, spine.01, and fingers 1..4."""
    tag = "L" if side > 0 else "R"
    rows, cols = 16, 8
    verts_per_side = (rows + 1) * (cols + 1)
    verts_per_panel = 2 * verts_per_side
    expected = 4 * verts_per_panel
    n_verts = len(obj.data.vertices)
    if n_verts != expected:
        raise ValueError(f"{obj.name} vertex count {n_verts} != expected {expected}")

    finger_bones = [f"wing_finger_{k}.{tag}" for k in range(1, 5)]
    forearm_b = f"wing_forearm.{tag}"
    arm_b = f"wing_arm.{tag}"

    vert_weights = []
    for k in range(n_verts):
        p_idx = k // verts_per_panel
        rem = (k % verts_per_panel) % verts_per_side
        r = rem // (cols + 1)
        c = rem % (cols + 1)
        u = r / rows   # 0 at wrist/leading edge -> 1 at scalloped trailing tip
        v = c / cols   # 0 at finger a -> 1 at finger b / body anchor

        w = {}
        if p_idx < 3:
            fa = finger_bones[p_idx]
            fb = finger_bones[p_idx + 1]
            # Blend from forearm wrist hub at u=0 into the two framing fingers
            w_wrist = 1.0 - smoothstep(0.0, 0.22, u)
            w_f = 1.0 - w_wrist
            w[forearm_b] = w_wrist
            w[fa] = w.get(fa, 0.0) + w_f * (1.0 - v)
            w[fb] = w.get(fb, 0.0) + w_f * v
        else:
            # Panel 3 spans f4_pts (v=0) to body_anchor (v=1), with u=0 bridging wrist->elbow->shoulder root
            fa = finger_bones[3]
            # Body anchor bone blend along u (0 at shoulder root -> 1 at lumbar flank)
            w_spine = smoothstep(0.40, 0.88, u)
            w_chest = 1.0 - w_spine

            # Along u=0..0.24, smoothly transition through wing_forearm -> wing_arm -> chest
            lead_mix = 1.0 - smoothstep(0.0, 0.24, u)
            # Finger side weight vs body side weight
            v_body = smoothstep(0.08, 0.92, v)
            v_fin = 1.0 - v_body

            # Non-leading interior weight
            w_f4 = (1.0 - lead_mix) * v_fin
            w_b_chest = (1.0 - lead_mix) * v_body * w_chest
            w_b_spine = (1.0 - lead_mix) * v_body * w_spine

            # Leading edge patagium bridge: v=0 wrist, v=0.5 elbow, v=1.0 shoulder root
            w_l_fore = lead_mix * max(0.0, 1.0 - v * 2.2)
            w_l_arm = lead_mix * max(0.0, 1.0 - abs(v - 0.5) * 2.2)
            w_l_chest = lead_mix * smoothstep(0.55, 1.0, v)

            for b_name, val in [
                (fa, w_f4),
                (forearm_b, w_l_fore),
                (arm_b, w_l_arm),
                ("chest", w_b_chest + w_l_chest),
                ("spine.01", w_b_spine),
            ]:
                if val > 1e-6:
                    w[b_name] = w.get(b_name, 0.0) + val

        vert_weights.append(w)

    set_vertex_weights(obj, vert_weights)
    add_armature_modifier(obj, rig)


def _bind_by_y_axis(obj, rig, stops, blend_radius=0.14):
    """Weight vertices smoothly along -Y/+Y coordinates given ordered (bone_name, y_val) stops."""
    to_arm = rig.matrix_world.inverted() @ obj.matrix_world
    vert_weights = []
    for v in obj.data.vertices:
        y = (to_arm @ v.co).y
        # Sort direction: stops can be increasing or decreasing in Y; measure distance along index
        # Assume stops are strictly monotonic in y
        increasing = stops[-1][1] >= stops[0][1]
        best_i = 0
        for i in range(len(stops) - 1):
            y_mid = 0.5 * (stops[i][1] + stops[i + 1][1])
            if (increasing and y >= y_mid) or (not increasing and y <= y_mid):
                best_i = i + 1
        w = {}
        b_cur, y_cur = stops[best_i]
        # Compute blend against adjacent stops based on midpoint crossing
        if best_i > 0:
            b_prev, y_prev = stops[best_i - 1]
            y_mid = 0.5 * (y_prev + y_cur)
            dist = (y - y_mid) if increasing else (y_mid - y)
            if dist < blend_radius:
                t = smoothstep(-blend_radius, blend_radius, dist)
                w = {b_prev: 1.0 - t, b_cur: t}
        if not w and best_i < len(stops) - 1:
            b_next, y_next = stops[best_i + 1]
            y_mid = 0.5 * (y_cur + y_next)
            dist = (y_mid - y) if increasing else (y - y_mid)
            if dist < blend_radius:
                t = smoothstep(-blend_radius, blend_radius, dist)
                w = {b_cur: t, b_next: 1.0 - t}
        if not w:
            w = {b_cur: 1.0}
        vert_weights.append(w)
    set_vertex_weights(obj, vert_weights)
    add_armature_modifier(obj, rig)


def bind_all_meshes(col, rig):
    """Bind every mesh in the azure_dragon collection to Azure_Dragon_Rig and verify 100% coverage."""
    objs = {obj.name: obj for obj in col.objects if obj.type == "MESH"}

    # 1. Spine, Neck, Tail & Surface Scales/Scutes/Spines
    # Continuous polyline from tail tip -> pelvis -> spine.01 -> chest -> neck -> occiput
    spine_chain = [
        _bone_seg(rig, "tail.05"),
        _bone_seg(rig, "tail.04"),
        _bone_seg(rig, "tail.03"),
        _bone_seg(rig, "tail.02"),
        _bone_seg(rig, "tail.01"),
        _bone_seg(rig, "pelvis", Vector((0, 0.60, 1.35)), Vector((0, 0.12, 1.40))),
        _bone_seg(rig, "spine.01"),
        _bone_seg(rig, "chest"),
        _bone_seg(rig, "neck.01"),
        _bone_seg(rig, "neck.02"),
        _bone_seg(rig, "head", Vector((0, -1.04, 2.20)), Vector((0, -1.06, 2.23))),
    ]
    for name, by_island, rad in [
        ("Dragon_Body", False, 0.15),
        ("Dragon_Belly_Scutes", False, 0.11),
        ("Dragon_Body_Scales", True, 0.12),
        ("Dragon_Dorsal_Spines", True, 0.12),
    ]:
        if name in objs:
            weight_along_chain(objs[name], rig, spine_chain, blend_radius=rad, by_island=by_island)

    # 2. Head & Horns (100% rigid head) + Jaw + Tongue
    for name in objs:
        if (
            name in ("Dragon_Skull", "Dragon_Head_Details", "Dragon_Upper_Teeth", "Dragon_Mouth_Upper")
            or name.startswith(("Dragon_Crown_Horn_", "Dragon_Brow_Spike_", "Dragon_Temple_Horn_", "Dragon_Cheek_Spike_"))
        ):
            set_rigid_weight(objs[name], rig, "head")
        elif name in ("Dragon_Mandible", "Dragon_Lower_Teeth"):
            set_rigid_weight(objs[name], rig, "jaw")

    if "Dragon_Tongue" in objs:
        to_arm = rig.matrix_world.inverted() @ objs["Dragon_Tongue"].matrix_world
        vw = []
        for v in objs["Dragon_Tongue"].data.vertices:
            y = (to_arm @ v.co).y
            t = smoothstep(-1.05, -1.20, y)
            vw.append({"head": 1.0 - t, "jaw": t} if t < 0.99 else {"jaw": 1.0})
        set_vertex_weights(objs["Dragon_Tongue"], vw)
        add_armature_modifier(objs["Dragon_Tongue"], rig)

    # 3. Forelegs & Hindlegs + Feet + Scales + Hock Spurs
    for side in (-1.0, 1.0):
        tag = "L" if side > 0 else "R"

        fore_chain = [
            _bone_seg(rig, "chest", Vector((side * 0.18, -0.54, 1.32)), rig.data.bones[f"fore_upper.{tag}"].head_local),
            _bone_seg(rig, f"fore_upper.{tag}"),
            _bone_seg(rig, f"fore_lower.{tag}"),
            _bone_seg(rig, f"fore_foot.{tag}"),
        ]
        if f"Dragon_Foreleg_{tag}" in objs:
            weight_along_chain(objs[f"Dragon_Foreleg_{tag}"], rig, fore_chain, blend_radius=0.11, by_island=False)
        if f"Dragon_Foreleg_Scales_{tag}" in objs:
            weight_along_chain(objs[f"Dragon_Foreleg_Scales_{tag}"], rig, fore_chain[1:3], blend_radius=0.09, by_island=True)

        for name, ob in objs.items():
            if name.startswith(f"Dragon_Forefoot_{tag}_"):
                if name.endswith("_Paw"):
                    to_arm = rig.matrix_world.inverted() @ ob.matrix_world
                    vw = []
                    for v in ob.data.vertices:
                        z = (to_arm @ v.co).z
                        t_up = smoothstep(0.14, 0.21, z) * 0.45
                        vw.append({f"fore_foot.{tag}": 1.0 - t_up, f"fore_lower.{tag}": t_up})
                    set_vertex_weights(ob, vw)
                    add_armature_modifier(ob, rig)
                else:
                    set_rigid_weight(ob, rig, f"fore_foot.{tag}")

        hind_chain = [
            _bone_seg(rig, "pelvis", Vector((side * 0.18, 0.52, 1.28)), rig.data.bones[f"hind_thigh.{tag}"].head_local),
            _bone_seg(rig, f"hind_thigh.{tag}"),
            _bone_seg(rig, f"hind_shin.{tag}"),
            _bone_seg(rig, f"hind_ankle.{tag}"),
            _bone_seg(rig, f"hind_foot.{tag}"),
        ]
        if f"Dragon_Hindleg_{tag}" in objs:
            weight_along_chain(objs[f"Dragon_Hindleg_{tag}"], rig, hind_chain, blend_radius=0.11, by_island=False)
        if f"Dragon_Hindleg_Scales_{tag}" in objs:
            weight_along_chain(objs[f"Dragon_Hindleg_Scales_{tag}"], rig, hind_chain[1:3], blend_radius=0.09, by_island=True)
        if f"Dragon_Hock_Spur_{tag}" in objs:
            set_rigid_weight(objs[f"Dragon_Hock_Spur_{tag}"], rig, f"hind_shin.{tag}")

        for name, ob in objs.items():
            if name.startswith(f"Dragon_Hindfoot_{tag}_"):
                if name.endswith("_Paw"):
                    to_arm = rig.matrix_world.inverted() @ ob.matrix_world
                    vw = []
                    for v in ob.data.vertices:
                        z = (to_arm @ v.co).z
                        t_up = smoothstep(0.14, 0.21, z) * 0.45
                        vw.append({f"hind_foot.{tag}": 1.0 - t_up, f"hind_ankle.{tag}": t_up})
                    set_vertex_weights(ob, vw)
                    add_armature_modifier(ob, rig)
                else:
                    set_rigid_weight(ob, rig, f"hind_foot.{tag}")

        # 4. Wings
        wing_arm_chain = [
            _bone_seg(rig, "chest", Vector((side * 0.12, -0.24, 1.54)), rig.data.bones[f"wing_arm.{tag}"].head_local),
            _bone_seg(rig, f"wing_arm.{tag}"),
            _bone_seg(rig, f"wing_forearm.{tag}"),
        ]
        if f"Dragon_Wing_Arm_{tag}" in objs:
            weight_along_chain(objs[f"Dragon_Wing_Arm_{tag}"], rig, wing_arm_chain, blend_radius=0.12, by_island=False)
        if f"Dragon_Wing_Thumb_Claw_{tag}" in objs:
            set_rigid_weight(objs[f"Dragon_Wing_Thumb_Claw_{tag}"], rig, f"wing_forearm.{tag}")
        if f"Dragon_Wing_Edge_Spur_{tag}" in objs:
            set_rigid_weight(objs[f"Dragon_Wing_Edge_Spur_{tag}"], rig, f"wing_finger_1.{tag}")

        for k in range(1, 5):
            if f"Dragon_Wing_Finger_{tag}_{k}" in objs:
                set_rigid_weight(objs[f"Dragon_Wing_Finger_{tag}_{k}"], rig, f"wing_finger_{k}.{tag}")
            if f"Dragon_Wing_Tip_Claw_{tag}_{k}" in objs:
                set_rigid_weight(objs[f"Dragon_Wing_Tip_Claw_{tag}_{k}"], rig, f"wing_finger_{k}.{tag}")

        if f"Dragon_Wing_Membrane_{tag}" in objs:
            _bind_wing_membrane(objs[f"Dragon_Wing_Membrane_{tag}"], rig, side)

    # 5. Armor & Leather Tack
    for name, b_name in [
        ("Dragon_Chest_Barding", "chest"),
        ("Dragon_Chest_Shield", "chest"),
        ("Dragon_Shoulder_Barding_L", "pauldron.L"),
        ("Dragon_Shoulder_Barding_R", "pauldron.R"),
        ("Dragon_War_Saddle_Seat", "spine.01"),
        ("Dragon_Saddle_Skirt", "spine.01"),
        ("Dragon_Girth_Straps", "spine.01"),
        ("Dragon_Crupper_Plate_0", "pelvis"),
        ("Dragon_Crupper_Plate_1", "pelvis"),
        ("Dragon_Crupper_Plate_2", "tail.01"),
        ("Dragon_Flank_Tasset_L", "flank_tasset.L"),
        ("Dragon_Flank_Tasset_R", "flank_tasset.R"),
        ("Dragon_Foreleg_Greave_L", "fore_lower.L"),
        ("Dragon_Foreleg_Greave_R", "fore_lower.R"),
        ("Dragon_Hindleg_Greave_L", "hind_ankle.L"),
        ("Dragon_Hindleg_Greave_R", "hind_ankle.R"),
    ]:
        if name in objs:
            set_rigid_weight(objs[name], rig, b_name)

    for tag in ("L", "R"):
        s_name = f"Dragon_Shoulder_Strap_{tag}"
        if s_name in objs:
            _bind_by_y_axis(objs[s_name], rig, [("chest", -0.78), (f"pauldron.{tag}", -0.45)], blend_radius=0.10)

    if "Dragon_Reins" in objs:
        _bind_by_y_axis(
            objs["Dragon_Reins"], rig,
            [("head", -0.98), ("neck.02", -0.84), ("neck.01", -0.66), ("chest", -0.44), ("spine.01", -0.22)],
            blend_radius=0.10
        )

    # 6. Fire Breath Long-Cone FX & Dynamic Plumes
    for name in ("Dragon_Fire_Cone_Core", "Dragon_Fire_Cone_Mid", "Dragon_Fire_Cone_Outer"):
        if name in objs:
            _bind_by_y_axis(
                objs[name], rig,
                [
                    ("breath_seg_0", -2.42),
                    ("breath_seg_1", -4.29),
                    ("breath_seg_2", -6.17),
                    ("breath_seg_3", -8.04),
                ],
                blend_radius=0.55
            )

    for k in range(6):
        p_name = f"Dragon_Fire_Plume_{k}"
        if p_name in objs:
            set_rigid_weight(objs[p_name], rig, f"breath_plume_{k}")

    # 7. Final Integrity Verification across every single mesh in the collection
    valid_bones = set(rig.data.bones.keys())
    total_verts = 0
    for name, ob in objs.items():
        if not any(m.type == "ARMATURE" and m.object == rig for m in ob.modifiers):
            raise ValueError(f"Missing Armature modifier on {name}")
        vgs = ob.vertex_groups
        for v in ob.data.vertices:
            total_w = sum(g.weight for g in v.groups if vgs[g.group].name in valid_bones)
            if total_w < 0.99:
                raise ValueError(f"{name} vertex {v.index} has invalid bone weight sum {total_w:.4f}")
        total_verts += len(ob.data.vertices)
    print(f"Verified skinning on {len(objs)} meshes ({total_verts} vertices), 0 unbound vertices.")
