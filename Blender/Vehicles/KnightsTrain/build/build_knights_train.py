"""Builds KnightsTrain.blend from nothing: the Arthurian Knights' futuristic coal-fired armored streamliner.

  blender --background --python build_knights_train.py

Everything is rebuilt each run. The car keeps the Astra Streamliner's runtime contract
(Blender/Vehicles/Maglev/Astra_Streamliner/validation/audit/accepted_contract.md), so scripts/rails/train_consist.gd
places it unchanged. The nose is to -Y, Z is up, and all sizes are authored metres (the game scales the car by 0.6).
The contract's nodes, all direct children of train_cargo_root with identity rotation, are at:
  cargo_body (0, 0, 2.5); sled_cargo_front (0, -3, 1) and sled_cargo_rear (0, 3, 1); cargo_coupler_F (0, -5.5, 1.67)
  and cargo_coupler_R (0, 5.5, 1.67); cargo_car_indicator (0, 3.55, 3.6).
scripts/rails/knights_train_model.gd animates the extra parts under cargo_body: firebox_glow, firebox_embers and
stack_smoke_1..5. Nothing here is keyed, so there are no clips.

The look: a single continuous futuristic Ivory-Armor & royal-blue bullet streamliner matching the Knights tech
concept art — faceted aerodynamic nose with recessed cyan headlights and raked panoramic dark-glass cockpit,
unbroken ivory composite fuselage and royal-blue dorsal cowling, front cab door, wide recessed blue-framed
hydraulic troop/cargo boarding vestibule with ribbed steel sill, sculpted brass thermal cooling louvers on the
rear upper shoulders housing the glowing coal-reactor core and dorsal exhaust vents, and shrouded bogie sleds.
"""
import bpy, os, sys
from math import sin, cos, radians, pi
from mathutils import Vector as V, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
KIT = os.environ.get("SL_BUILDING_KIT") or os.path.normpath(os.path.join(HERE, "..", "..", "..", "Buildings", "Foundry", "build"))
sys.path.insert(0, KIT)
import importlib, building_kit
importlib.reload(building_kit)
from building_kit import *  # noqa: F401,F403

OUT = os.path.normpath(os.path.join(HERE, "..", "KnightsTrain.blend"))
bpy.ops.wm.read_factory_settings(use_empty=True)

# Crisp futuristic Arthurian Knights PBR material palette
material("kt_ivory", (0.86, 0.84, 0.75), 0.18, 0.36)
material("kt_ivory_trim", (0.76, 0.74, 0.66), 0.22, 0.42)
material("kt_iron", (0.15, 0.17, 0.20), 0.78, 0.38)
material("kt_iron_dark", (0.07, 0.08, 0.10), 0.70, 0.44)
material("kt_silver", (0.64, 0.68, 0.72), 0.80, 0.30)
material("kt_glass", (0.03, 0.05, 0.09), 0.35, 0.12)
material("kt_interior", (0.02, 0.025, 0.035), 0.15, 0.85)
material("kt_optic", (0.28, 0.82, 1.00), 0.05, 0.15, (0.30, 0.85, 1.00), 5.5)
material("kt_fire", (0.98, 0.48, 0.08), 0.0, 0.35, (1.00, 0.50, 0.10), 6.5)
material("kt_embers", (0.45, 0.08, 0.02), 0.0, 0.50, (0.90, 0.20, 0.04), 1.6)
material("kt_signal", (1.00, 0.72, 0.24), 0.10, 0.25, (1.00, 0.68, 0.20), 4.5)
material("kt_tail", (0.95, 0.16, 0.10), 0.10, 0.25, (0.95, 0.16, 0.10), 3.2)
material("kt_smoke", (0.24, 0.25, 0.27), 0.0, 1.0)
material("brass", (0.76, 0.50, 0.14), 0.76, 0.30)
material("team_color", (0.04, 0.13, 0.52), 0.14, 0.42)

C = bpy.data.collections.new("knights_train")
bpy.context.scene.collection.children.link(C)
root = empty(C, "train_cargo_root", Matrix.Identity(4), None, 0.5)


def fin(P, name, world, parent=root, sharp=0.22):
    return finish(C, P, name, world, parent, sharp=sharp)


def sym_ring(pts_pos_x):
    """Build a closed counter-clockwise ring in (X, Y, Z) from right-side points (bottom-center to top-center)."""
    ring = [V(p) for p in pts_pos_x]
    for x, y, z in reversed(pts_pos_x):
        if abs(x) > 1e-5:
            ring.append(V((-x, y, z)))
    return ring


# ================================================================= body (fixed), origin at (0, 0, 2.5)
P = Part()

# --- 1. Armored Lower Chassis & Continuous Underbody Skirt ---
P.box("kt_iron", (0, 0.05, 1.28), (2.96, 9.70, 0.34), None, 0.03)
# Front armored snowplow / cowcatcher valence (swept inward, split down center)
plow_rings = [
    sym_ring([(0.54, -5.36, 0.94), (1.06, -5.18, 0.96), (1.28, -4.85, 1.18), (0.94, -5.20, 1.48), (0.48, -5.32, 1.48)]),
    sym_ring([(0.68, -4.55, 0.96), (1.42, -4.45, 0.98), (1.58, -4.35, 1.24), (1.56, -4.35, 1.54), (0.68, -4.55, 1.54)]),
]
P.add(mk_loft(plow_rings), "kt_ivory_trim", False)
# Dark armored lower chin lip & crisp flush plow vent recesses
P.box("kt_iron_dark", (0, -5.16, 0.94), (2.06, 0.46, 0.12), None, 0.02)
for sx in (-1, 1):
    P.box("kt_iron_dark", (sx * 0.44, -5.26, 1.22), (0.14, 0.06, 0.34), rot_z(radians(-sx * 14)))
    P.box("kt_iron_dark", (sx * 0.86, -5.10, 1.22), (0.14, 0.06, 0.34), rot_z(radians(-sx * 28)))

# Side lower armored skirt panels bridging between bogie cutouts (Y = -1.6..+1.6) and ends
for sx in (-1, 1):
    P.box("kt_iron", (sx * 1.56, 0.0, 1.34), (0.20, 3.25, 0.36), None, 0.02)
    P.box("kt_ivory_trim", (sx * 1.62, 0.0, 1.44), (0.10, 3.20, 0.14), None, 0.01)
    # Short rear skirt behind rear bogie
    P.box("kt_iron", (sx * 1.56, 4.78, 1.34), (0.20, 0.88, 0.36), None, 0.02)
    # Continuous dark chassis beltline strip
    P.box("kt_iron_dark", (sx * 1.65, 0.95, 1.54), (0.08, 8.65, 0.12), None, 0.01)

# --- 2. Unified Full-Length Faceted Ivory-Armor Streamliner Hull (Y = -5.42 .. +5.22) ---
# Every ring has the exact same vertex count (10 verts) for clean, sharp faceted hard-surface planes.
hull_rings = [
    # Ring 0: Front nose tip (compact hexagonal bullet prow)
    sym_ring([
        (0.56, -5.40, 1.50),
        (1.04, -5.22, 1.76),
        (1.06, -5.16, 2.26),
        (0.76, -4.82, 2.74),
        (0.46, -4.64, 2.90),
    ]),
    # Ring 1: Forward cheek / light-bar transition
    sym_ring([
        (1.18, -4.78, 1.50),
        (1.52, -4.62, 1.84),
        (1.56, -4.50, 2.52),
        (1.18, -4.18, 3.06),
        (0.84, -4.02, 3.26),
    ]),
    # Ring 2: Raked cockpit shoulder -> main fuselage width
    sym_ring([
        (1.56, -3.55, 1.50),
        (1.68, -3.50, 1.88),
        (1.68, -3.45, 2.74),
        (1.56, -3.28, 3.38),
        (1.16, -3.18, 3.64),
    ]),
    # Ring 3: Forward cab section
    sym_ring([
        (1.58, -2.20, 1.50),
        (1.68, -2.20, 1.88),
        (1.68, -2.20, 3.28),
        (1.56, -2.20, 3.44),
        (1.18, -2.20, 3.64),
    ]),
    # Ring 4: Rear fuselage end (bulkhead)
    sym_ring([
        (1.58, 5.20, 1.50),
        (1.68, 5.20, 1.88),
        (1.68, 5.20, 3.28),
        (1.56, 5.20, 3.44),
        (1.18, 5.20, 3.64),
    ]),
]
P.add(mk_loft(hull_rings), "kt_ivory", False)

# --- 3. Continuous Royal-Blue Faceted Dorsal Roof Cowling (Y = -4.55 .. +5.20) ---
roof_rings = [
    sym_ring([(0.44, -4.52, 2.88), (0.64, -4.38, 3.02), (0.34, -4.26, 3.16)]),
    sym_ring([(0.82, -3.96, 3.24), (1.02, -3.86, 3.42), (0.64, -3.76, 3.62)]),
    sym_ring([(1.16, -3.10, 3.60), (1.28, -3.05, 3.74), (0.86, -2.98, 4.02)]),
    sym_ring([(1.20, -1.80, 3.60), (1.30, -1.80, 3.76), (0.88, -1.80, 4.04)]),
    sym_ring([(1.20, 5.18, 3.60), (1.30, 5.18, 3.76), (0.88, 5.18, 4.04)]),
]
P.add(mk_loft(roof_rings), "team_color", False)

# Crisp white-ivory dorsal accent pinstripe along the roof crease & brass nose brow lip
for sx in (-1, 1):
    P.box("kt_ivory_trim", (sx * 1.24, 1.15, 3.63), (0.08, 8.15, 0.08), None, 0.01)

# --- 4. Raked Panoramic Armored Cockpit Windshield & Glowing Cyan Optics ---
# Crisp dark armored wrap-around windshield sitting cleanly proud of the sloped prow cheeks
wind_rings = [
    sym_ring([(0.56, -5.06, 2.52), (1.06, -4.82, 2.56), (1.46, -4.22, 2.66), (1.64, -3.48, 2.74)]),
    sym_ring([(0.44, -4.54, 3.04), (0.86, -4.34, 3.10), (1.24, -3.82, 3.24), (1.48, -3.32, 3.34)]),
]
P.add(mk_loft(wind_rings), "kt_glass", False)
# Sleek dark upper & lower windshield trim sills + corner mullions
wind_sill_lo = [
    sym_ring([(0.58, -5.09, 2.46), (1.09, -4.84, 2.50), (1.49, -4.23, 2.60), (1.66, -3.48, 2.68)]),
    sym_ring([(0.56, -5.05, 2.56), (1.06, -4.81, 2.60), (1.46, -4.21, 2.70), (1.64, -3.48, 2.78)]),
]
P.add(mk_loft(wind_sill_lo), "kt_iron_dark", False)
for sx in (-1, 1):
    P.cyl("kt_iron", (sx * 0.62, -5.04, 2.54), (sx * 0.50, -4.52, 3.06), 0.05, seg=6)
    P.cyl("kt_iron", (sx * 1.12, -4.78, 2.58), (sx * 0.92, -4.30, 3.12), 0.05, seg=6)
# Bright glowing cyan central cockpit sensor/visor bar directly under the blue nose brow
P.box("kt_optic", (0, -4.56, 3.00), (0.62, 0.14, 0.10), rot_x(radians(-38)), 0.01)

# Recessed dark front light-bar groove & twin glowing cyan LED headlights
nose_band = [
    sym_ring([(0.54, -5.42, 1.66), (1.10, -5.22, 1.72), (1.48, -4.72, 1.80)]),
    sym_ring([(0.56, -5.36, 1.88), (1.14, -5.16, 1.94), (1.52, -4.66, 2.02)]),
]
P.add(mk_loft(nose_band), "kt_iron_dark", False)
for sx in (-1, 1):
    # Primary horizontal cyan headlight
    P.box("kt_optic", (sx * 0.72, -5.32, 1.80), (0.44, 0.14, 0.12), rot_z(radians(-sx * 20)), 0.02)
    # Corner cyan marker light
    P.box("kt_optic", (sx * 1.24, -5.02, 1.86), (0.24, 0.12, 0.10), rot_z(radians(-sx * 48)), 0.01)
# Clean horizontal nose armor seam strip (no protruding fin!)
nose_seam = [
    sym_ring([(0.58, -5.30, 2.18), (1.14, -5.10, 2.22), (1.56, -4.54, 2.28)]),
    sym_ring([(0.58, -5.28, 2.24), (1.14, -5.08, 2.28), (1.56, -4.52, 2.34)]),
]
P.add(mk_loft(nose_seam), "kt_iron_dark", False)

# --- 5. Side Crew Cab Doors, Panel Seams & Recessed Hydraulic Troop Boarding Vestibule ---
for sx in (-1, 1):
    # Subtle dark architectural hull panel lines (clean sci-fi plating)
    for y in (-2.75, -1.15, 1.78, 4.45):
        P.box("kt_iron_dark", (sx * 1.685, y, 2.48), (0.02, 0.04, 1.74))
    P.box("kt_iron_dark", (sx * 1.685, 1.45, 2.04), (0.02, 7.20, 0.04))

    # Front crew cab door (Y = -2.42 .. -1.62)
    P.box("kt_iron", (sx * 1.68, -2.02, 2.38), (0.05, 0.78, 1.56), None, 0.01)
    P.box("kt_ivory_trim", (sx * 1.70, -2.02, 2.38), (0.04, 0.68, 1.46), None, 0.01)
    P.box("kt_glass", (sx * 1.715, -2.02, 2.74), (0.03, 0.42, 0.46), None, 0.01)
    P.box("brass", (sx * 1.72, -1.78, 2.24), (0.03, 0.10, 0.05))

    # Signature Hydraulic Troop / Cargo Boarding Vestibule (Y = -0.35 .. +1.55)
    # Royal-blue armored doorframe
    P.box("team_color", (sx * 1.69, 0.60, 2.48), (0.10, 1.98, 1.92), None, 0.02)
    # Dark recessed interior boarding bay
    P.box("kt_interior", (sx * 1.72, 0.60, 2.44), (0.08, 1.64, 1.72))
    # Split hydraulic armored pocket doors slightly recessed
    for sy_d in (-1, 1):
        P.box("kt_ivory_trim", (sx * 1.71, 0.60 + sy_d * 0.62, 2.44), (0.06, 0.36, 1.66), None, 0.01)
        P.box("team_color", (sx * 1.73, 0.60 + sy_d * 0.62, 2.44), (0.03, 0.24, 1.48))
    # Overhead doorway status light strip
    P.box("kt_optic", (sx * 1.74, 0.60, 3.34), (0.05, 1.10, 0.07))
    # Folded ribbed metallic boarding ramp sill flush along doorway base
    P.box("kt_silver", (sx * 1.72, 0.60, 1.54), (0.16, 1.68, 0.12), None, 0.02)
    for k in range(5):
        ry = -0.04 + k * 0.32
        P.box("kt_iron", (sx * 1.78, ry, 1.54), (0.06, 0.08, 0.13))

    # Subtle heraldic royal-blue + gold stripe badge forward of the boarding bay (clean, modern, non-medieval)
    P.box("team_color", (sx * 1.69, -0.76, 2.66), (0.04, 0.56, 0.42), None, 0.01)
    P.box("brass", (sx * 1.71, -0.76, 2.66), (0.03, 0.08, 0.32))
    P.box("brass", (sx * 1.71, -0.76, 2.66), (0.03, 0.32, 0.08))

# --- 6. Signature Rear Sculpted Brass Thermal Cooling Louver Nacelles (Y = +2.10 .. +4.70) ---
for sx in (-1, 1):
    # Sleek flush-integrated brass cooling housing hugging the angled upper roof shoulder (matches concept art!)
    P.box("brass", (sx * 1.36, 3.40, 3.56), (0.34, 2.58, 0.56), rot_y(radians(sx * 36)), 0.03)
    P.box("kt_interior", (sx * 1.44, 3.40, 3.58), (0.20, 2.32, 0.40), rot_y(radians(sx * 36)))
    # 7 crisp vertical brass cooling ribs / slats across each shoulder nacelle
    for k in range(7):
        y = 2.36 + k * 0.346
        P.box("brass", (sx * 1.48, y, 3.60), (0.18, 0.11, 0.48), rot_y(radians(sx * 36)), 0.01)
    # Flush lower side cooling louver vent & maintenance panel on rear ivory flank
    P.box("kt_ivory_trim", (sx * 1.69, 3.40, 2.38), (0.05, 2.15, 1.28), None, 0.02)
    P.box("kt_iron_dark", (sx * 1.71, 3.40, 2.38), (0.03, 1.98, 0.04))
    P.box("brass", (sx * 1.70, 3.40, 3.06), (0.05, 2.20, 0.06), None, 0.01)

# Dorsal brass thermal-coal exhaust manifold on the rear roof (Y = +2.15 .. +4.55)
P.box("brass", (0, 3.35, 4.02), (1.64, 2.40, 0.18), None, 0.03)
P.box("kt_iron_dark", (0, 2.65, 4.08), (1.18, 0.76, 0.14), None, 0.02)  # forward exhaust stack port
P.box("kt_iron_dark", (0, 4.18, 4.08), (1.18, 0.52, 0.14), None, 0.02)  # aft exhaust vent
for y in (2.42, 2.65, 2.88, 4.05, 4.30):
    P.box("brass", (0, y, 4.12), (1.28, 0.07, 0.08))

# --- 7. Rear Armored Bulkhead & Corridor Vestibule Diaphragm (Y = +5.20 .. +5.38) ---
P.box("kt_iron", (0, 5.26, 2.48), (1.56, 0.22, 1.96), None, 0.04)
P.box("kt_interior", (0, 5.34, 2.46), (1.18, 0.10, 1.68))
for sx in (-1, 1):
    P.box("kt_tail", (sx * 1.24, 5.22, 2.04), (0.32, 0.08, 0.12), None, 0.01)
    P.cyl("brass", (sx * 1.04, 5.24, 1.62), (sx * 1.04, 5.42, 1.62), 0.14, 0.16, seg=10)

body = fin(P, "cargo_body", T((0, 0, 2.5)), sharp=0.22)

# --- Animated Coal-Thermal Reactor Parts (parented to cargo_body for knights_train_model.gd) ---
# Glowing thermal coal-reactor core visible behind the sculpted rear brass louver slats!
P = Part()
for sx in (-1, 1):
    P.box("kt_fire", (sx * 1.44, 3.40, 3.58), (0.12, 2.18, 0.28), rot_y(radians(sx * 36)))
P.box("kt_fire", (0, 2.65, 4.08), (0.98, 0.58, 0.08))
fin(P, "firebox_glow", T((0, 3.20, 3.62)), body)

P = Part()
for sx in (-1, 1):
    P.box("kt_embers", (sx * 1.42, 3.40, 3.52), (0.10, 2.10, 0.18), rot_y(radians(sx * 36)))
fin(P, "firebox_embers", T((0, 3.40, 3.52)), body)

# Stack smoke puffs rising cleanly from the dorsal brass thermal exhaust port at (0, 2.65, 4.20)
for k in range(5):
    P = Part()
    c = V((0, 2.65, 4.20))
    P.add(mk_ico(c, 0.30, (1, 1, 0.82), None, 2), "kt_smoke")
    fin(P, "stack_smoke_%d" % (k + 1), T(c), body, sharp=0.87)

# ================================================================= shrouded heavy maglev / bogie sleds
for name, y in (("sled_cargo_front", -3.0), ("sled_cargo_rear", 3.0)):
    P = Part()
    P.box("kt_iron_dark", (0, y, 1.16), (2.10, 1.35, 0.24), None, 0.03)
    for sx in (-1, 1):
        # Heavy armored bogie sideframe
        P.box("kt_iron", (sx * 1.18, y, 0.90), (0.34, 2.65, 0.38), None, 0.04)
        P.box("kt_iron_dark", (sx * 1.32, y, 0.90), (0.10, 2.20, 0.22), None, 0.02)
        # Twin recessed heavy bogie drive drums / wheel hubs
        for wy in (-0.82, 0.82):
            P.cyl("kt_iron_dark", (sx * 1.02, y + wy, 0.84), (sx * 1.34, y + wy, 0.84), 0.34, seg=14)
            P.cyl("kt_silver", (sx * 1.30, y + wy, 0.84), (sx * 1.38, y + wy, 0.84), 0.16, seg=12)
            P.cyl("brass", (sx * 1.36, y + wy, 0.84), (sx * 1.40, y + wy, 0.84), 0.08, seg=10)
        # Brass hydraulic suspension coil & under-rail maglev contact pads
        P.cyl("brass", (sx * 1.24, y, 0.88), (sx * 1.24, y, 1.14), 0.08, seg=8)
        for k in (-1, 0, 1):
            P.box("brass", (sx * 1.00, y + k * 0.78, 0.69), (0.36, 0.48, 0.05), None, 0.01)
            P.box("kt_optic", (sx * 1.00, y + k * 0.78, 0.67), (0.24, 0.34, 0.02))
    P.cyl("brass", (0, y, 1.04), (0, y, 1.36), 0.18, seg=12)
    fin(P, name, T((0, y, 1.0)), sharp=0.35)

# ================================================================= couplers & retractable dorsal telemetry indicator
for name, y in (("cargo_coupler_F", -5.5), ("cargo_coupler_R", 5.5)):
    P = Part()
    s = -1 if y < 0 else 1
    P.box("kt_iron", (0, y - s * 0.14, 1.67), (0.34, 0.34, 0.22), None, 0.02)
    P.add(mk_annulus(V((0, y, 1.67)), 0.08, 0.16, 0.08, seg=12), "brass", True)
    fin(P, name, T((0, y, 1.67)))

# Sleek flush dorsal load-status pylon at (0, 3.55, 3.6) — rises cleanly +0.32 m out of the roof when loaded!
P = Part()
L = V((0, 3.55, 3.60))
P.box("kt_iron", L + Z * 0.24, (0.64, 0.56, 0.48), None, 0.03)
P.box("brass", L + Z * 0.48, (0.70, 0.62, 0.08), None, 0.02)
P.box("kt_signal", L + Z * 0.34, (0.68, 0.40, 0.16), None, 0.01)
P.box("team_color", L + Z * 0.54, (0.54, 0.46, 0.08), None, 0.02)
fin(P, "cargo_car_indicator", T(L))

bpy.context.view_layer.update()
tris = 0
for o in C.all_objects:
    if o.type == 'MESH':
        o.data.calc_loop_triangles()
        tris += len(o.data.loop_triangles)
print("TRIS", tris)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=OUT)
print("SAVED", OUT, len(C.all_objects), "objects")
