# The Arthurian vineyard

[Farm.blend](Farm.blend) holds the editable 10 × 10 m plot and its destruction effect. The field has six rows of seven mature vines with individually folded, lobed leaves and hanging grape bunches. A team-painted service port marks the irrigation system at the edge. Two hovering carriages carry pale reservoirs, outboard nozzles and paired fans of atomized water. Their flight paths leave the ground open on all four sides.

| Clip | Visible action |
| --- | --- |
| Idle | Carriages hover at their row ends, vines stir, and the nozzles are dry |
| Work | Two carriages water opposite halves of the vineyard, sweep 5.4 m along their rows and return over an eight-second loop |
| Build | Soil beds, vines and irrigation gear appear in stages as the site progresses |
| Die | The carriages lose lift, the vines fold and the field clears |
| Depleted | An alternate stripped-vine pose for art review |

The `farm` collection contains the model. `farm_death_fx` contains one `Death` clip with a small valve flash, spilled water, leaves and landing dust. The editable file opens in Idle with this effect collection excluded. To view another clip, change the active NLA track on its objects. The water and optics follow `Irrigator_West` and `Irrigator_East`. Each carriage includes a `Water_West` or `Water_East` child, scaled near zero outside Work.

From the Farm folder, use Blender 4.5 to recreate and verify the source and exports:

```text
blender -b --factory-startup -P build/build_farm.py
blender -b Farm.blend -P build/animate_farm.py
blender -b Farm.blend -P build/export_farm.py
blender -b Farm.blend -P build/render_review.py
```

The export script reimports both GLBs and checks their clips, footprint, material paint, and the moving spray rig. Pigments for soil, dry herbs, leaves, fruit and machinery use glTF vertex colours. The fine loam, lobed leaf cutouts and soft spray also use packed textures. Pass `-- --to-assets` to the exporter to write into the gameplay asset directories.
