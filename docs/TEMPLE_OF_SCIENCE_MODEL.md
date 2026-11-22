# Temple of Science model

Asked for on 2026-11-19. The look is an armoured temple combined with an observatory: columns, armour, brass and glow, an observatory dome and a glowing orb. There is no concept sheet. It sits in the family of the Barracks, Tank Factory and Generator, and its materials are the Generator's palette, renamed `tos_*`.

## The model

- **Size.** True scale in metres. The plinth fills 5.8 x 5.8 m of the 6 x 6 footprint. The orb's rings reach 6.6 m, just above the Depot, so the Temple reads as a landmark.
- **Facing.** In Blender the door faces -Y. In the game that is +Z, toward the default camera, as for the other buildings.
- **Budget.** About 16,700 triangles, with flat PBR materials and no image textures.

The parts:

- **Plinth.** Three stepped, chamfered terraces with brass edges and hazard edging in front of the door. A `team_color` banner sits on each corner of the lowest terrace.
- **Drum.** The octagonal cella in riveted armour plates. Seven of its faces carry a tall cyan research slit in a brass frame. The front face holds the armoured double `door`, with a lit lintel above it.
- **Columns.** Eight armoured octagonal columns on the drum's corners, with brass bases, rings and capitals, and a cyan conduit strip down each.
- **Entablature.** The octagonal ring the columns carry, with a `team_color` frieze, brass studs and a brass cornice. Over the door is a gabled pediment with a `team_color` tympanum and the faction fang (`pediment_fang`, black, from the Drone).
- **Dome.** A brass collar and a `team_color` band, then a ribbed gunmetal observatory dome. A 30° shutter slit in the dome faces the camera. The `telescope` (pivot on its trunnion) tilts out through the slit.
- **Pylons.** Four sensor pylons with cyan tips stand on the top terrace.
- **Armillary.** A `mast` on the dome's crown carries the `Armillary` empty. Under it are `Orb` (one surface, material `tos_orb`, emissive), `RingA` and `RingB`.

## In the game

- `scenes/models/temple_of_science_model.tscn` is the GLB scene, with `scripts/components/temple_model.gd` on its root.
- That script turns `Armillary` and brightens `Armillary/Orb` while research runs. It copies the orb's imported StandardMaterial3D into a per-Temple override.
- Team paint (`scripts/components/team_paint.gd`) repaints every surface whose material is `team_color`: the frieze, the tympanum, the dome band and the corner banners.
- There are no Build or Die clips yet. The construction site shows the plan grid, and the Temple leaves no wreck.

## Rebuilding

```
blender --background --python Blender/Buildings/TempleOfScience/build/build_temple.py
blender Blender/Buildings/TempleOfScience/TempleOfScience.blend --background --python Blender/Buildings/TempleOfScience/build/export_temple.py
blender Blender/Buildings/TempleOfScience/TempleOfScience.blend --background --python Blender/Buildings/TempleOfScience/build/render_review.py -- Blender/Previews/TempleOfScience turnaround dome door
Godot --path . --script res://scripts/tools/render_hud_images.gd -- temple
```

The HUD renderer views models from -Z, so the icon shows the Temple from behind, as it does the Barracks.
