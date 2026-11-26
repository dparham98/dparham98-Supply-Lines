"""Build the two editable glTF effect clips. Run with Python from any checkout."""
import json
import math
import struct
from pathlib import Path


ASSETS = Path(__file__).resolve().parents[3] / "assets/models/projectiles"
INTERVAL = 1 / 12
TINY = 0.001
WHITE = (1.0, 0.99, 0.83)
LEMON = (1.0, 0.77, 0.32)
GOLD = (1.0, 0.28, 0.023)
EMBER = (0.50, 0.055, 0.004)
STEEL = (0.065, 0.095, 0.116)


def mul(v, k):
    return tuple(k * n for n in v)


def add(a, b):
    return tuple(x + y for x, y in zip(a, b))


def unit(v):
    return mul(v, 1 / math.sqrt(sum(n * n for n in v)))


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1],
            a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0])


def twist(v, angle):
    c, s = math.cos(angle), math.sin(angle)
    return (v[0] * c - v[1] * s, v[0] * s + v[1] * c, v[2])


class Burst:
    """One skinned, unlit draw surface. Each animated joint carries a flash or chip."""

    def __init__(self, name):
        self.name = name
        self.nodes = [{"name": "EffectRoot", "children": [1, 2]},
                      {"name": "Facets", "mesh": 0, "skin": 0},
                      {"name": "Bones", "children": []}]
        self.joints = [2]
        self.vertices = []
        self.keys = []

    def part(self, name):
        index = len(self.nodes)
        self.nodes.append({"name": name})
        self.nodes[2]["children"].append(index)
        self.joints.append(index)
        return len(self.joints) - 1

    def point(self, joint, start, direction, length, radius, shoulder, palette):
        # A broad shoulder and long taper survive at map scale. Separate face values
        # give the outer flakes a copper edge against pale terrain.
        axis = unit(direction)
        ref = (0, 1, 0) if abs(axis[1]) < .90 else (1, 0, 0)
        right = unit(cross(axis, ref))
        up = cross(axis, right)
        rim_center = add(start, mul(axis, length * shoulder))
        ring = [add(rim_center, mul(vector, radius)) for vector in
                (right, up, mul(right, -1), mul(up, -1))]
        tip = add(start, mul(axis, length))
        for i in range(4):
            a, b = ring[i], ring[(i + 1) % 4]
            edge = palette[1] if i in (0, 3) else palette[2]
            for tri, colors in (((start, b, a), (palette[0], edge, edge)),
                                ((a, b, tip), (edge, edge, palette[3]))):
                normal = unit(cross(add(tri[1], mul(tri[0], -1)), add(tri[2], mul(tri[0], -1))))
                for vertex, color in zip(tri, colors):
                    self.vertices.append((vertex, normal, (*color, 1.), (joint, 0, 0, 0), (1., 0., 0., 0.)))

    def track(self, joint, path, times, values):
        self.keys.append((self.joints[joint], path, times, values))

    def scales(self, joint, times, factors):
        self.track(joint, "scale", times, [(max(TINY, s),) * 3 for s in factors])

    def save(self, path):
        buffer = bytearray()
        views, accessors = [], []

        def accessor(rows, kind, element_type=5126, target=None, bounded=False):
            components = {"SCALAR": 1, "VEC3": 3, "VEC4": 4, "MAT4": 16}[kind]
            rows = [(v,) for v in rows] if components == 1 else list(rows)
            fmt = "<" + {5126: "f", 5121: "B"}[element_type] * components
            offset = len(buffer)
            for row in rows:
                buffer.extend(struct.pack(fmt, *row))
            view = {"buffer": 0, "byteOffset": offset, "byteLength": len(buffer) - offset}
            if target:
                view["target"] = target
            entry = {"bufferView": len(views), "componentType": element_type, "count": len(rows), "type": kind}
            if bounded:
                entry.update(min=list(map(min, zip(*rows))), max=list(map(max, zip(*rows))))
            views.append(view)
            accessors.append(entry)
            buffer.extend(b"\0" * (-len(buffer) % 4))
            return len(accessors) - 1

        attributes = {}
        columns = list(zip(*self.vertices))
        for column, semantic, kind, number in zip(columns, ["POSITION", "NORMAL", "COLOR_0", "JOINTS_0", "WEIGHTS_0"],
                                                   ["VEC3", "VEC3", "VEC4", "VEC4", "VEC4"], [5126, 5126, 5126, 5121, 5126]):
            attributes[semantic] = accessor(column, kind, number, 34962, semantic == "POSITION")
        identity = tuple(float(r == c) for c in range(4) for r in range(4))
        bind = accessor([identity] * len(self.joints), "MAT4")
        animation = {"name": self.name, "samplers": [], "channels": []}
        for node, prop, times, values in self.keys:
            sampler = len(animation["samplers"])
            animation["samplers"].append({"input": accessor(times, "SCALAR", bounded=True),
                                          "output": accessor(values, "VEC3"), "interpolation": "LINEAR"})
            animation["channels"].append({"sampler": sampler, "target": {"node": node, "path": prop}})
        gltf = {"asset": {"version": "2.0", "generator": "Supply Lines / Round Table Marine effects"},
                "scene": 0, "scenes": [{"nodes": [0]}], "nodes": self.nodes,
                "skins": [{"name": "EffectBones", "skeleton": 2, "joints": self.joints, "inverseBindMatrices": bind}],
                "meshes": [{"name": self.name + "Facets", "primitives": [{"attributes": attributes, "material": 0}]}],
                "materials": [{"name": "HotMetal", "extensions": {"KHR_materials_unlit": {}},
                               "doubleSided": True, "pbrMetallicRoughness": {"metallicFactor": 0, "roughnessFactor": 1}}],
                "extensionsUsed": ["KHR_materials_unlit"], "animations": [animation],
                "accessors": accessors, "bufferViews": views, "buffers": [{"byteLength": len(buffer)}]}
        header = json.dumps(gltf, separators=(",", ":")).encode()
        header += b" " * (-len(header) % 4)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(struct.pack("<4sIII4s", b"glTF", 2, 28 + len(header) + len(buffer), len(header), b"JSON")
                         + header + struct.pack("<I4s", len(buffer), b"BIN\0") + buffer)


def pulse_times(beat, relative, values):
    start = beat * INTERVAL
    # Hold earlier/later flashes out of sight until their own pulse begins.
    if beat:
        return [0., start - .004] + [start + t for t in relative], [0., 0.] + values
    return list(relative), values


def muzzle():
    fx = Burst("Fire")
    for beat, (strength, angle) in enumerate(((1., -.18), (.88, .47), (1.04, -.53))):
        jet = fx.part("Flame" + str(beat + 1))
        fx.point(jet, (0, 0, 0), (0, 0, -1), .52, .105, .24, (WHITE, WHITE, LEMON, GOLD))
        # Petals depart the bore, independent of camera orientation.
        for i, vector in enumerate(((.75, .31, -.66), (-.64, .49, -.64), (.04, -.72, -.64))):
            fx.point(jet, (0, 0, -.035), twist(vector, angle), (.27, .24, .22)[i],
                     .042, .25, (WHITE, LEMON, GOLD, EMBER))
        times, scales = pulse_times(beat, [0., .014, .035, .053], [strength, strength, .52 * strength, 0.])
        fx.scales(jet, times, scales)
    fx.save(ASSETS / "round_table_muzzle_fx.glb")


def impact():
    fx = Burst("Impact")
    directions = [
        ((-.76, .47, -.45), .53, .23), ((.75, .32, -.54), .47, .22),
        ((.04, .89, -.45), .55, .23), ((.26, -.52, -.78), .35, .17),
        ((-.55, -.28, -.76), .41, .17),
    ]
    for beat, angle in enumerate((-.20, .33, -.47)):
        strike = fx.part("Contact" + str(beat + 1))
        fx.point(strike, (0, -.165, -.046), (0, 1, -.05), .33, .132, .50, (GOLD, WHITE, LEMON, WHITE))
        fx.point(strike, (-.16, 0, -.041), (1, 0, -.025), .32, .071, .48, (EMBER, WHITE, GOLD, LEMON))
        times, scales = pulse_times(beat, [0., .019, .046, .065], [1., 1., .41, 0.])
        fx.scales(strike, times, scales)
        for i, (axis, travel, length) in enumerate(directions):
            direction = unit(twist(axis, angle))
            joint = fx.part("Chip%d_%d" % (beat + 1, i + 1))
            fx.point(joint, (0, 0, 0), direction, length, .046 if i < 3 else .034,
                     .25, (WHITE, LEMON, GOLD, STEEL if i in (0, 3) else EMBER))
            ts, size = pulse_times(beat, [0., .019, .052, .081, .116], [.83, 1., .86, .48, 0.])
            fx.scales(joint, ts, size)
            distances = [0.] * (len(ts) - 5) + [.044, .080, travel * .5, travel * .76, travel]
            positions = [add((0, 0, -.054), mul(direction, d)) for d in distances]
            fx.track(joint, "translation", ts, positions)
    fx.save(ASSETS / "round_table_impact_fx.glb")


if __name__ == "__main__":
    muzzle()
    impact()
