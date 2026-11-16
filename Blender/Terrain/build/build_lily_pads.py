"""Writes the lily pad clusters that float near the shore. Plain Python, no Blender needed:

  python Blender/Terrain/build/build_lily_pads.py

Writes assets/models/terrain/kit/lily_pads_01.obj and _02.obj and their scenes in scenes/terrain/kit. Colours are
on the vertices in display space, as the rest of the landscape kit; UV is zero, so the pads neither sway nor mottle.
"""
import math
import os
import random

ROOT = os.getcwd()
MODELS = os.path.join(ROOT, "assets", "models", "terrain", "kit")
SCENES = os.path.join(ROOT, "scenes", "terrain", "kit")

PAD = (0.16, 0.34, 0.13)
PAD_LIGHT = (0.3, 0.46, 0.17)
PAD_OLD = (0.36, 0.38, 0.14)
PETAL = (0.9, 0.86, 0.84)
PETAL_PINK = (0.86, 0.6, 0.66)
HEART = (0.88, 0.7, 0.2)


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


class Mesh:
    def __init__(self):
        self.vertices = []
        self.normals = []
        self.faces = []

    def vertex(self, position, colour, normal=(0.0, 1.0, 0.0)):
        self.vertices.append((position, colour))
        self.normals.append(normal)
        return len(self.vertices)

    def pad(self, rng, x, z, radius, height):
        """A round leaf with a notch cut to its middle, slightly dished."""
        tone = mix(mix(PAD, PAD_LIGHT, rng.random()), PAD_OLD, rng.random() ** 3)
        turn = rng.random() * math.tau
        segments = 11
        centre = self.vertex((x, height, z), mix(tone, PAD_LIGHT, 0.5))
        rim = []
        for index in range(segments + 1):
            # The notch takes about a twelfth of the circle.
            angle = turn + 0.26 + (math.tau - 0.52) * index / segments
            wobble = radius * (1.0 + rng.uniform(-0.06, 0.06))
            rim.append(self.vertex((x + math.cos(angle) * wobble, height + 0.012, z + math.sin(angle) * wobble), mix(tone, PAD, 0.35)))
        for a, b in zip(rim, rim[1:]):
            # Counter-clockwise seen from above.
            self.faces.append((centre, b, a))

    def flower(self, rng, x, z, size, height):
        colour = mix(PETAL, PETAL_PINK, rng.random())
        heart = self.vertex((x, height + size * 0.35, z), HEART)
        for ring, (count, reach, lift) in enumerate(((7, 1.0, 0.25), (5, 0.6, 0.6))):
            start = rng.random() * math.tau
            for index in range(count):
                angle = start + math.tau * index / count
                half = math.pi / count * 0.8
                tip = self.vertex((x + math.cos(angle) * size * reach, height + size * lift, z + math.sin(angle) * size * reach), colour)
                left = self.vertex((x + math.cos(angle - half) * size * reach * 0.45, height + size * 0.08, z + math.sin(angle - half) * size * reach * 0.45), mix(colour, PETAL, 0.5))
                right = self.vertex((x + math.cos(angle + half) * size * reach * 0.45, height + size * 0.08, z + math.sin(angle + half) * size * reach * 0.45), mix(colour, PETAL, 0.5))
                self.faces.append((heart, right, left))
                self.faces.append((left, right, tip))

    def save(self, name):
        with open(os.path.join(MODELS, name + ".obj"), "w", newline="\n") as handle:
            handle.write("# Written by Blender/Terrain/build/build_lily_pads.py\no %s\n" % name)
            for position, colour in self.vertices:
                handle.write("v %.5f %.5f %.5f %.4f %.4f %.4f\n" % (position + colour))
            handle.write("vt 0.0 0.0\n")
            for normal in self.normals:
                handle.write("vn %.3f %.3f %.3f\n" % normal)
            for face in self.faces:
                handle.write("f " + " ".join("%d/1/%d" % (index, index) for index in face) + "\n")
        with open(os.path.join(SCENES, name + ".tscn"), "w", newline="\n") as handle:
            handle.write("\n".join([
                "[gd_scene format=3]",
                '[ext_resource type="Mesh" path="res://assets/models/terrain/kit/%s.obj" id="mesh"]' % name,
                '[ext_resource type="Material" path="res://assets/materials/terrain/landscape_foliage.tres" id="material"]',
                '[node name="%s" type="Node3D"]' % "".join(part.capitalize() for part in name.split("_")),
                '[node name="Mesh" type="MeshInstance3D" parent="."]',
                'material_override = ExtResource("material")',
                "cast_shadow = 0",
                'mesh = ExtResource("mesh")']) + "\n")
        print("%s %d triangles" % (name, len(self.faces)))


def cluster(name, seed, pads, spread, flowers):
    rng = random.Random(seed)
    mesh = Mesh()
    placed = []
    while len(placed) < pads:
        angle = rng.random() * math.tau
        out = spread * math.sqrt(rng.random())
        radius = rng.uniform(0.11, 0.21)
        x, z = math.cos(angle) * out, math.sin(angle) * out
        if any(math.hypot(x - px, z - pz) < (radius + pr) * 0.85 for px, pz, pr in placed):
            continue
        placed.append((x, z, radius))
        mesh.pad(rng, x, z, radius, 0.015 + 0.004 * len(placed))
    for index in range(flowers):
        x, z, radius = placed[index * 2 % len(placed)]
        mesh.flower(rng, x + radius * 0.9, z + radius * 0.4, 0.085, 0.03)
    mesh.save(name)


cluster("lily_pads_01", 11, 7, 0.55, 2)
cluster("lily_pads_02", 23, 4, 0.4, 0)
