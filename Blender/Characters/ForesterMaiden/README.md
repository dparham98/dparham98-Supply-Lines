# Forester Maiden

Open [the editable character](source/ForesterMaiden.blend) in Blender 4.5. The straw sunhat, kerchief, cultivator, axe, building hammer, timber load and harvest basket share the same skeleton. The basket has linen lining, a woven willow body, wrapped handholds and a load of harvested produce.

| Clip | Activity |
| --- | --- |
| Walk | Two-handed travel with the assignment tool |
| Chop | Two-handed axe stroke for a tree or wood stand |
| Gather | Crouch and gather loose material |
| Carry | Walk supporting a material load |
| Build | Brace the work and strike with a mallet |
| Till | Plant the cultivator, draw its tines through the soil and lift |
| CarryFood | Walk holding the full basket level with both hands |

Clips are authored at 24 fps. The first Blender frame is time zero in Godot. The cultivator first touches down on frame 18 of Till. CarryFood takes 32 frames per two steps at the authored speed of 0.84 m/s.

To export hand edits directly to the game, run this from this character folder.

```text
blender -b source/ForesterMaiden.blend -P source/build.py -- --publish-open --glb ../../../assets/models/units/forester_maiden.glb
```

The [model scene](../../../scenes/models/forester_maiden_model.tscn) uses the [Forester animator](../../../scripts/components/forester_animator.gd) to choose each worker's equipment and movement from her current orders. The [Knights economy](../../../docs/KNIGHTS_ECONOMY.md) describes assignment and delivery.
