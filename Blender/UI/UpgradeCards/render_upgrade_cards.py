"""Renders the art for the six upgrade command cards (docs/UPGRADES.md) on a clear ground.

  blender --background --python render_upgrade_cards.py

Writes renders/<card>.png (256 px, transparent). scripts/tools/render_hud_images.gd (ART_CARDS) puts each one
inside the card frame as sl_<card>.png. Weapons are the weapon with a rising gold chevron; armour is a plate
or a shield. The Cyborg cards (Foundry) are dark steel and brass; the Knights cards (Forge) are silver, ivory
and heraldic blue. Helpers come from ../../Buildings/Foundry/build/building_kit.py.
"""
import bpy, os, sys
import numpy as np
from math import radians, sin, cos, pi
from mathutils import Vector as V, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
KIT = os.environ.get("SL_BUILDING_KIT") or os.path.normpath(os.path.join(HERE, "..", "..", "Buildings", "Foundry", "build"))
sys.path.insert(0, KIT)
import importlib, building_kit
importlib.reload(building_kit)
from building_kit import *  # noqa: F401,F403

OUT = os.path.join(HERE, "renders")
os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
try:
    scene.render.engine = 'BLENDER_EEVEE_NEXT'
except TypeError:
    scene.render.engine = 'BLENDER_EEVEE'
scene.view_settings.view_transform = 'Standard'
scene.render.film_transparent = True
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'
scene.render.resolution_x = scene.render.resolution_y = 256
w = bpy.data.worlds.new("cards")
scene.world = w
w.use_nodes = True
bg = next(n for n in w.node_tree.nodes if n.type == 'BACKGROUND')
bg.inputs[0].default_value = (0.55, 0.53, 0.5, 1)
bg.inputs[1].default_value = 0.6

material("steel", (0.20, 0.23, 0.26), 0.75, 0.38)
material("steel_dark", (0.07, 0.08, 0.09), 0.6, 0.5)
material("gunmetal", (0.33, 0.36, 0.38), 0.8, 0.3)
material("brass", (0.71, 0.44, 0.12), 0.7, 0.3)
material("gold", (0.95, 0.66, 0.16), 0.85, 0.25, (1.0, 0.62, 0.15), 0.6)
material("cyborg_red", (0.55, 0.05, 0.04), 0.3, 0.45, (1.0, 0.12, 0.05), 1.5)
material("silver", (0.72, 0.75, 0.77), 0.8, 0.28)
material("ivory", (0.83, 0.82, 0.73), 0.3, 0.45)
material("blue", (0.03, 0.09, 0.42), 0.1, 0.55)
material("leather", (0.16, 0.08, 0.04), 0.0, 0.7)
material("timber", (0.2, 0.11, 0.05), 0.0, 0.8)


def light(name, rot, energy, col=(1, 1, 1)):
    d = bpy.data.lights.new(name, 'SUN')
    d.energy = energy
    d.color = col
    o = bpy.data.objects.new(name, d)
    o.rotation_euler = [radians(a) for a in rot]
    scene.collection.objects.link(o)


light("key", (40, 10, -40), 3.6, (1.0, 0.95, 0.88))
light("rim", (-60, 0, 150), 2.2, (0.8, 0.88, 1.0))
cam_d = bpy.data.cameras.new("cam")
cam_d.type = 'ORTHO'
cam = bpy.data.objects.new("cam", cam_d)
scene.collection.objects.link(cam)
scene.camera = cam
cam.location = (0, -10, 0)
cam.rotation_euler = (radians(90), 0, 0)     # looking +Y; X right, Z up on the card


def chevrons(P, n, at, size=0.42):
    """n rising gold chevrons stacked upward from `at` (x, z) on the card."""
    for k in range(n):
        c = V((at[0], -0.4, at[1] + k * size * 0.62))
        P.add(mk_prism([(-size, -size * 0.35), (0, size * 0.25), (size, -size * 0.35), (size, -size * 0.05),
                        (0, size * 0.55), (-size, -size * 0.05)], c, X, Z, -0.06, 0.06), "gold", True)


def card(name, build, ortho=3.6, tilt=(12, 0, 22)):
    coll = bpy.data.collections.new(name)
    scene.collection.children.link(coll)
    for c in scene.collection.children:
        bpy.context.view_layer.layer_collection.children[c.name].exclude = c is not coll
    P = Part()
    build(P)
    ob = finish(coll, P, name, Matrix.Identity(4), None, 0.6)
    ob.rotation_euler = [radians(a) for a in tilt]
    cam_d.ortho_scale = ortho
    scene.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)
    print("WROTE", scene.render.filepath)


def rifle(P, a, mat_body, mat_accent):
    """A rifle lying along angle a (radians from +X), centred on the origin of the card plane."""
    d, n = V((cos(a), 0, sin(a))), V((-sin(a), 0, cos(a)))
    R = basis(d, V((0, 1, 0)), n)
    P.box(mat_body, d * -0.2, (1.6, 0.18, 0.26), R, 0.03)                           # receiver
    P.box(mat_body, d * -1.25 - n * 0.08, (0.7, 0.16, 0.34), R, 0.04)               # stock
    P.box(mat_body, d * -0.35 - n * 0.32, (0.16, 0.14, 0.4), basis(d, V((0, 1, 0)), n) @ rot_y(radians(-15)), 0.02)  # grip
    P.box(mat_body, d * 0.2 - n * 0.3, (0.18, 0.14, 0.45), R, 0.02)                 # magazine
    P.cyl(mat_body, d * 0.55, d * 1.55, 0.07, seg=12)                               # barrel
    P.cyl(mat_accent, d * 1.45, d * 1.65, 0.1, seg=12)                              # muzzle
    P.box(mat_accent, d * -0.1 + n * 0.19, (0.6, 0.1, 0.1), R, 0.02)                # scope rail
    P.cyl("cyborg_red", d * 0.12 + n * 0.19 + V((0, -0.06, 0)), d * 0.12 + n * 0.19 + V((0, -0.1, 0)), 0.05, seg=10)


def infantry_weapons(P):
    rifle(P, radians(28), "steel", "brass")
    chevrons(P, 2, (0.95, -1.05), 0.46)


def cuirass(P, metal, trim, rivets=True):
    P.add(mk_loft([[V((x, 0, z)) for x, z in ((-0.85, -0.9), (0.85, -0.9), (0.95, 0.5), (0.5, 0.95), (-0.5, 0.95), (-0.95, 0.5))],
                   [V((x * 0.8, -0.35, z * 0.9)) for x, z in ((-0.85, -0.9), (0.85, -0.9), (0.95, 0.5), (0.5, 0.95), (-0.5, 0.95), (-0.95, 0.5))]]),
          metal, True)
    P.box(trim, (0, -0.37, 0.1), (0.12, 0.04, 1.4), None, 0.01)                     # centre ridge
    for z in (-0.35, -0.65):
        P.box(trim, (0, -0.33, z), (1.45, 0.05, 0.08), None, 0.01)                   # belly lames
    for sx in (-1, 1):
        P.add(mk_ico((sx * 0.95, -0.05, 0.72), 0.32, (1.1, 0.8, 0.7)), metal, True)   # pauldrons
        if rivets:
            for k in range(4):
                P.rivet((sx * 0.6, -0.33, 0.6 - k * 0.35), (0, -1, 0), 0.05)


def infantry_armour(P):
    cuirass(P, "gunmetal", "brass")
    P.add(mk_ico((0, -0.4, 0.45), 0.09), "cyborg_red", True)


def vehicle_weapons(P):
    a = radians(24)
    d, n = V((cos(a), 0, sin(a))), V((-sin(a), 0, cos(a)))
    R = basis(d, V((0, 1, 0)), n)
    P.box("steel", d * -0.9, (1.0, 0.7, 0.62), R, 0.08)                             # turret cheek
    P.cyl("steel_dark", d * -0.4, d * 1.4, 0.17, 0.13, seg=14)                       # barrel
    P.cyl("gunmetal", d * -0.4, d * 0.1, 0.24, seg=14)                               # mantlet collar
    P.cyl("gunmetal", d * 1.35, d * 1.75, 0.2, seg=14)                               # muzzle brake
    for s in (-1, 1):
        P.box("steel_dark", d * 1.55 + V((0, s * 0.12, 0)), (0.12, 0.06, 0.3), R)
    P.cyl("brass", d * 0.55, d * 0.75, 0.15, seg=14)
    chevrons(P, 2, (0.95, -1.1), 0.46)


def vehicle_armour(P):
    P.add(mk_prism([(-1.15, -0.8), (1.15, -0.8), (1.35, 0.35), (0.7, 0.95), (-0.7, 0.95), (-1.35, 0.35)],
                   (0, 0, 0), X, Z, -0.2, 0.2), "gunmetal", True)                    # glacis plate
    P.add(mk_prism([(-0.95, -0.6), (0.95, -0.6), (1.1, 0.3), (0.55, 0.75), (-0.55, 0.75), (-1.1, 0.3)],
                   (0, -0.21, 0), X, Z, -0.05, 0.05), "steel", True)                 # applique
    for x, z in ((-0.95, -0.55), (0.95, -0.55), (-1.0, 0.25), (1.0, 0.25), (-0.5, 0.65), (0.5, 0.65), (0, -0.6), (0, 0.7)):
        P.rivet((x, -0.27, z), (0, -1, 0), 0.07)
    P.box("brass", (0, -0.27, 0.05), (1.2, 0.04, 0.12), None, 0.02)
    P.box("brass", (0, -0.27, 0.05), (0.12, 0.04, 0.9), None, 0.02)


def arms(P):
    a = radians(62)
    d, n = V((cos(a), 0, sin(a))), V((-sin(a), 0, cos(a)))
    R = basis(d, V((0, 1, 0)), n)
    P.add(mk_prism([(-0.25, -0.1), (1.55, -0.1), (1.85, 0), (1.55, 0.1), (-0.25, 0.1)], d * -0.6, d, n, -0.03, 0.03),
          "silver", True)                                                            # blade
    P.box("silver", d * -0.0 + V((0, -0.035, 0)), (1.2, 0.01, 0.03), R)              # fuller
    P.box("brass", d * -0.88, (0.1, 0.14, 0.75), R, 0.02)                            # cross guard
    P.cyl("leather", d * -0.93, d * -1.32, 0.06, seg=10)                              # grip
    P.add(mk_ico(d * -1.4, 0.11), "brass", True)                                     # pommel
    P.add(mk_ico(d * -0.88 + V((0, -0.08, 0)), 0.06), "blue", True)                   # jewel
    chevrons(P, 2, (0.85, -1.1), 0.46)


def mail(P):
    shield = [(-0.95, 0.95), (0.95, 0.95), (0.95, 0.1), (0.6, -0.6), (0, -1.1), (-0.6, -0.6), (-0.95, 0.1)]
    P.add(mk_prism(shield, (0, 0, 0), X, Z, -0.12, 0.12), "blue", True)
    rim = [(x * 1.1, z * 1.07 + 0.02) for x, z in shield]
    P.add(mk_prism(rim, (0, 0.03, 0), X, Z, -0.1, 0.1), "silver", True)
    P.box("ivory", (0, -0.14, 0.05), (0.26, 0.04, 1.5), None, 0.01)                  # cross
    P.box("ivory", (0, -0.14, 0.4), (1.25, 0.04, 0.26), None, 0.01)
    P.add(mk_ico((0, -0.17, 0.4), 0.12), "brass", True)


card("upgrade_infantry_weapons", infantry_weapons)
card("upgrade_infantry_armour", infantry_armour)
card("upgrade_vehicle_weapons", vehicle_weapons)
card("upgrade_vehicle_armour", vehicle_armour)
card("upgrade_arms", arms)
card("upgrade_mail", mail)
