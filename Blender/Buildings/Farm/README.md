# Arthurian farm

[Farm.blend](Farm.blend) is the editable windmill, granary and wheat plot. The loading porch faces Blender −Y, which exports as +Z in Godot. Team paint is on the roof and pennant. The building and its effects have separate exports.

| Clip | Playback |
| --- | --- |
| Build | Scrubbed by the construction site's progress |
| Idle | The completed field between work cycles |
| Work | Turning sails, grain sieve and a ripple through the wheat |
| Die | Collapse and removal, accompanied by the effects rig's Death clip |
| Depleted | Cut stubble for art review. The renewable Farm uses Idle and Work in play. |

From this folder, the following command exports the saved working file to the game's model folders and checks it by reimporting the result.

```text
blender -b Farm.blend -P build/export_farm.py -- --to-assets
```

To regenerate the working file, run `build/build_farm.py` in background Blender and then run `build/animate_farm.py` against that file. The [model scene](../../../scenes/models/farm_model.tscn) connects the two exports. See the [farm design and gameplay checks](../../../docs/KNIGHTS_ECONOMY.md) for placement, assignment and Food deliveries.
