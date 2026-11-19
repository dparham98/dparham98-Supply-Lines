"""Bastion's editable running gear and the stable vertex layout used by Godot.

The six shader-driven meshes use the accepted local topology and pose table.
The export checks their geometry and transforms, preserves their original
POSITION, NORMAL and index buffers, and writes their current artist-editable UVs.
The remaining parts, including sprockets and idlers, export normally.
"""
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import struct
import tempfile

import bpy
import numpy as np
from mathutils import Quaternion


ROOT = next(p for p in Path(__file__).resolve().parents if (p / 'project.godot').exists())
UNIT_DIR = ROOT / 'assets/models/units'
ORIGINAL = UNIT_DIR / 'tank.glb'
DRIVEN = tuple(f'{part}_{side}' for part in ('Track_Links', 'Road_Wheels', 'Return_Rollers')
               for side in ('L', 'R'))
ALL_GEAR = DRIVEN + tuple(f'{part}_{side}' for part in ('Drive_Sprocket', 'Idler_Wheel')
                           for side in ('L', 'R'))


def read_glb(path):
    blob = path.read_bytes()
    length = struct.unpack_from('<I', blob, 12)[0]
    return json.loads(blob[20:20+length]), blob[28+length:]


def write_glb(path, document, buffer):
    document['buffers'][0]['byteLength'] = len(buffer)
    header = json.dumps(document, separators=(',', ':')).encode()
    header += b' ' * (-len(header) % 4)
    buffer += b'\0' * (-len(buffer) % 4)
    total = 28 + len(header) + len(buffer)
    path.write_bytes(struct.pack('<4sIIII', b'glTF', 2, total, len(header), 0x4e4f534a)
                     + header + struct.pack('<II', len(buffer), 0x004e4942) + buffer)


def array(doc, buf, index):
    """All canonical gear accessors use one tightly packed buffer view each."""
    acc = doc['accessors'][index]
    view = doc['bufferViews'][acc['bufferView']]
    width = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3}[acc['type']]
    dtype = {5126: '<f4', 5123: '<u2', 5125: '<u4'}[acc['componentType']]
    if view.get('byteStride') or 'sparse' in acc:
        raise ValueError('Original gear accessor has a different layout')
    return np.frombuffer(buf, dtype=dtype, count=width*acc['count'],
                         offset=view.get('byteOffset', 0)+acc.get('byteOffset', 0)).reshape((-1, width))


def shoe_uv(original_uv, triangles):
    """Map each face's existing UV directions to a clean interior of the stock atlas."""
    result = original_uv.copy()
    # Two triangles form each planar link face. The wide faces use a slightly lighter steel.
    for face, pair in enumerate(triangles.reshape((-1, 6))):
        ids = np.unique(pair)
        coords = original_uv[ids]
        extent = np.maximum(np.ptp(coords, axis=0), 1e-6)
        x, y = (416, 1056) if face % 6 in (2, 3) else (1120, 1152)
        result[ids] = (np.array([x+10, y+10]) + 44*(coords-coords.min(axis=0))/extent) / 2048
    return result


def baked_material():
    mat = bpy.data.materials.new('MAT_Tank_Baked')
    mat.use_nodes = True
    mat.diffuse_color = (.095, .103, .112, 1)
    tree = mat.node_tree
    shader = tree.nodes.get('Principled BSDF')
    for channel, slot in [('BaseColor', 'Base Color'), ('Emission', 'Emission Color'),
                           ('Metallic-T_Tank_Roughness', None)]:
        tex = tree.nodes.new('ShaderNodeTexImage')
        tex.image = bpy.data.images.load(str(UNIT_DIR / f'tank_T_Tank_{channel}.png'), check_existing=True)
        tex.image.pack()
        if slot:
            tree.links.new(tex.outputs['Color'], shader.inputs[slot])
        else:
            tex.image.colorspace_settings.name = 'Non-Color'
            split = tree.nodes.new('ShaderNodeSeparateColor')
            tree.links.new(tex.outputs['Color'], split.inputs['Color'])
            tree.links.new(split.outputs['Green'], shader.inputs['Roughness'])
            tree.links.new(split.outputs['Blue'], shader.inputs['Metallic'])
    shader.inputs['Emission Strength'].default_value = 2.5
    return mat


def blender_xyz(data):
    converted = data[:, [0, 2, 1]].copy()
    converted[:, 1] *= -1
    return converted


def geometry_signature(obj):
    mesh = obj.data
    digest = hashlib.sha256()
    for collection, field, size, dtype in [
            (mesh.vertices, 'co', 3, np.float32),
            (mesh.loops, 'vertex_index', 1, np.int32),
            (mesh.corner_normals, 'vector', 3, np.float32)]:
        data = np.empty(len(collection)*size, dtype)
        collection.foreach_get(field, data)
        digest.update(data.tobytes())
    digest.update(np.round(np.asarray(obj.matrix_basis), 6).tobytes())
    return digest.hexdigest()


def add_running_gear(hull):
    doc, binary = read_glb(ORIGINAL)
    nodes = {n['name']: n for n in doc['nodes']}
    material = baked_material()
    collections = {}
    for side in ('L', 'R'):
        collection = bpy.data.collections.new('Running gear ' + side)
        bpy.context.scene.collection.children.link(collection)
        collections[side] = collection
    for name in ALL_GEAR:
        node = nodes[name]
        primitive = doc['meshes'][node['mesh']]['primitives'][0]
        attributes = primitive['attributes']
        positions = blender_xyz(array(doc, binary, attributes['POSITION']))
        normals = blender_xyz(array(doc, binary, attributes['NORMAL']))
        faces = array(doc, binary, primitive['indices']).reshape((-1, 3))
        uv = array(doc, binary, attributes['TEXCOORD_0']).copy()
        if name.startswith('Track_Links'):
            uv = shoe_uv(uv, faces)
        uv[:, 1] = 1 - uv[:, 1]
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(positions.tolist(), [], faces.tolist())
        mesh.update()
        for polygon in mesh.polygons:
            polygon.use_smooth = True
        mesh.normals_split_custom_set_from_vertices(normals.tolist())
        layer = mesh.uv_layers.new(name='UVMap')
        layer.data.foreach_set('uv', uv[faces.ravel()].ravel())
        obj = bpy.data.objects.new(name, mesh)
        collections[name[-1]].objects.link(obj)
        obj.parent = hull
        x, y, z = node['translation']
        obj.location = (x, -z, y)
        x, y, z, w = node.get('rotation', [0, 0, 0, 1])
        obj.rotation_mode = 'QUATERNION'
        obj.rotation_quaternion = Quaternion((w, x, -z, y))
        mesh.materials.append(material)
        if name in DRIVEN:
            obj['shader_geometry_sha256'] = geometry_signature(obj)


def current_uv(obj, original):
    mesh = obj.data
    layer = mesh.uv_layers.active
    if not layer:
        raise ValueError(f'{obj.name} requires a UV map for the running-gear shader')
    uv = np.full((len(mesh.vertices), 2), np.nan, np.float32)
    for loop in mesh.loops:
        x, y = layer.data[loop.index].uv
        coord = (x, 1-y)
        old = uv[loop.vertex_index]
        if np.isfinite(old[0]) and not np.allclose(old, coord, rtol=0, atol=1e-7):
            raise ValueError(f'{obj.name} has a new UV seam requiring an extra shader vertex')
        uv[loop.vertex_index] = coord
    if np.isnan(uv).any():
        raise ValueError(f'{obj.name} contains an unreferenced shader vertex')
    # Keep untouched imported UV bytes, including rounding lost during V-flip.
    return original if np.allclose(uv, original, atol=1e-7, rtol=0) else uv


def append_driven(doc, binary):
    source, source_bin = read_glb(ORIGINAL)
    # Godot prefixes extracted image names with the GLB filename. The Blender inputs
    # already carry that prefix. Keep identical images under their glTF source names
    # so a drop-in replacement reuses the three textures bound by tank_model.tscn.
    def image_key(document, payload, image):
        view = document['bufferViews'][image['bufferView']]
        offset = view.get('byteOffset', 0)
        return hashlib.sha256(payload[offset:offset+view['byteLength']]).digest()
    image_names = {image_key(source, source_bin, image): image['name'] for image in source['images']}
    for image in doc.get('images', []):
        source_name = image_names.get(image_key(doc, binary, image))
        if source_name:
            image['name'] = source_name
    source_nodes = {n['name']: n for n in source['nodes']}
    hull = next(n for n in doc['nodes'] if n['name'] == 'Tank_Hull')
    buffer = bytearray(binary[:doc['buffers'][0]['byteLength']])
    for name in DRIVEN:
        obj = bpy.data.objects[name]
        if (not obj.parent or obj.parent.name != 'Tank_Hull' or obj.modifiers or obj.data.shape_keys
                or geometry_signature(obj) != obj.get('shader_geometry_sha256')):
            raise ValueError(f'{name} geometry, hierarchy or pivot changed. Its stock running-gear shader '
                             'requires the accepted vertex layout. Regenerate the pose table for a new layout.')
        source_node = source_nodes[name]
        source_mesh = source['meshes'][source_node['mesh']]
        prim = source_mesh['primitives'][0]
        target = deepcopy(prim)
        for key, index in [*prim['attributes'].items(), ('indices', prim['indices'])]:
            data = array(source, source_bin, index)
            if key == 'TEXCOORD_0':
                data = current_uv(obj, data)
            raw = data.tobytes()
            buffer.extend(b'\0' * (-len(buffer) % 4))
            view = {'buffer': 0, 'byteOffset': len(buffer), 'byteLength': len(raw),
                    'target': 34963 if key == 'indices' else 34962}
            buffer.extend(raw)
            accessor = dict(source['accessors'][index], bufferView=len(doc['bufferViews']))
            doc['bufferViews'].append(view)
            number = len(doc['accessors'])
            doc['accessors'].append(accessor)
            if key == 'indices':
                target['indices'] = number
            else:
                target['attributes'][key] = number
        mat_name = obj.data.materials[0].name
        target['material'] = next(i for i, m in enumerate(doc['materials']) if m['name'] == mat_name)
        hull.setdefault('children', []).append(len(doc['nodes']))
        doc['nodes'].append(dict(source_node, mesh=len(doc['meshes'])))
        doc['meshes'].append({'name': name, 'primitives': [target]})
    return buffer


def export_tank(destination):
    """Export the selected tank subtree and preserve the six shader-addressed buffers."""
    destination = Path(destination).resolve()
    destination.parent.mkdir(parents=True, exist_ok=True)
    root = bpy.data.objects['Tank_Root']
    original_selection = list(bpy.context.selected_objects)
    active = bpy.context.view_layer.objects.active
    try:
        bpy.ops.object.select_all(action='DESELECT')
        for obj in [root, *root.children_recursive]:
            if obj.name not in DRIVEN:
                obj.select_set(True)
        bpy.context.view_layer.objects.active = root
        with tempfile.TemporaryDirectory() as tmp:
            intermediate = Path(tmp) / 'model.glb'
            bpy.ops.export_scene.gltf(filepath=str(intermediate), export_format='GLB', use_selection=True,
                                      export_apply=True, export_animations=False, export_extras=False,
                                      export_yup=True, export_cameras=False, export_lights=False)
            doc, binary = read_glb(intermediate)
            buffer = append_driven(doc, binary)
            write_glb(destination, doc, buffer)
    finally:
        bpy.ops.object.select_all(action='DESELECT')
        for obj in original_selection:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = active
