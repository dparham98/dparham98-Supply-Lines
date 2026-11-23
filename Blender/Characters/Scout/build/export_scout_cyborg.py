# Exports ScoutCyborg_Rig with every mesh, both head looks included (bare head with cyber jaw, and the helmet), and its
# NLA tracks as clips: idle, run, shoot, die.
#   blender -b ScoutCyborg.blend -P export_scout_cyborg.py -- <out.glb>
import bpy, sys
out = sys.argv[sys.argv.index("--")+1]
rig = bpy.data.objects["ScoutCyborg_Rig"]
bpy.ops.object.select_all(action="DESELECT")
hidden = []
for o in [rig]+list(rig.children):
    if o.hide_viewport or o.hide_render or o.hide_get():
        hidden.append((o, o.hide_viewport, o.hide_render, o.hide_get()))
        o.hide_viewport = False; o.hide_render = False; o.hide_set(False)
    o.select_set(True)
bpy.context.view_layer.objects.active = rig
for t in rig.animation_data.nla_tracks: t.mute = False
rig.animation_data.action = None
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_animations=True,
	export_animation_mode="NLA_TRACKS", export_force_sampling=True, export_yup=True, export_apply=False,
	export_skins=True, export_morph=False, export_lights=False, export_cameras=False)
print("EXPORTED", out)
