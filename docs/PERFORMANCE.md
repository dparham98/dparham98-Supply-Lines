# Big-battle performance

Two Lakes is meant for up to six players, so a few hundred units on the map at once will be normal. A stress test on 2026-11-19 put that load on the game: a full economy, production, three trains and waves of 280 units (140 a side) meeting in open ground. Nothing broke (no crash, hang, script error or leak), but the frame rate fell far too low. This page records where the time went, what has been changed, and what is still to do.

## Where a frame went

Measured in a 250–300 unit fight with the camera on it, before the changes below:

| Part | Time a frame | Why |
|---|---|---|
| Unit scripts | 20–40 ms | Every armed unit asked every unit on the map for a target, every frame. Lane checks sampled every 0.25 m. |
| Map overlay and minimap | about 22 ms | For every actor, every frame, the overlay searched its whole model for meshes, for hover and again for every health bar. A cache of hidden labels emptied itself once past 512 actors. The minimap redrew every felled cell and track piece every frame. |
| Drawing | 20–30 ms | About 25,000–32,000 draw calls. Each unit is many meshes, one draw call per material on each, drawn again for each of the sun's 4 shadow cascades (out to 340 m). |
| Death and impact effects | grows through a fight | Each death effect is 54–202 animated pieces for 4–6 seconds. Fifty deaths put thousands of animated meshes on the map. |

Draw calls a unit makes in each pass (main view or one shadow cascade):

| Unit | Surfaces | Distinct materials |
|---|---|---|
| Tank | 144 | 18 |
| Motorcycle | 98 | 16 |
| Scout | 88 | 17 |
| Drone | 72 | 14 |
| Grenadier | 69 | 20 |
| Infantry | 33 | 28 |
| Cargo truck | 36 | 9 |

## What changed

- **Targets** (`docs/COMBAT_BATCH.md`, Targeting in big battles):
  - Units look only among units near them (`scripts/combat/unit_grid.gd`).
  - A unit with nothing in its sights looks round every 0.2 s, not every frame.
- **Lanes** (`docs/PATHING.md`): each line is walked cell by cell (`terrain_grid.gd` `segment_open`), not sampled every 0.25 m.
- **Units' own upkeep:**
  - A unit's claim name is built once.
  - Its labels are written only when what they show changes.
  - A model with no BackLoad is not searched for one every frame.
- **Picking meshes** (`selection_bounds.gd`):
  - Each actor's list of pickable meshes is kept for about a second.
  - It is looked for again at once when a child is added to or taken from Visuals, or when a kept mesh leaves the tree.
  - Whether each mesh is shown, and where, is still read every time.
- **Map overlay** (`map_overlay.gd`):
  - Hover is found again when the pointer moves, and otherwise every 6 frames.
  - Bars and icons are worked out only for actors on or near the screen (160 px margin).
  - The hidden-label record no longer empties itself.
- **Minimap** (`tactical_minimap.gd`): drawn again every 0.1 s, and at once when the camera moves.
- **Effects nobody can see** (`skirmish.gd` `in_view`):
  - A unit dying more than a fifth of a screen beyond the edge leaves no corpse to play out its death.
  - A shell bursting there shows no burst.
  - Without a window (the headless checks), everything counts as seen.
- **Death clips in a crowd** (added 2026-11-22): at most 12 unit death clips play at once (`unit_agent.gd` `DEATH_CLIPS_MAX`). A unit dying while 12 are playing goes at once, as an off-screen death does. Buildings are not counted or capped.

## Measured

| Test | Before | After |
|---|---|---|
| Headless, 300-unit fight, fixed 1/30 s step | 6–10 fps | 30–34 fps |
| With the window, camera centred on a 250–300 unit fight | 11–13 fps | 14–17 fps |
| With the window, second wave (about 330 units) | 7–8 fps | 25–31 fps |

## Measured again on 2026-11-22

After fog of war, the Ubermech and the new infantry model reached main, a battle-only test (`battle_stress.gd`, kept in the session scratchpad): Two Lakes, no economy or enemy AI, 20 of each of the 7 unit types a side (280 units), then a second wave 30 s later, camera centred on the fight, vsync off, an RTX 5070 Ti. Figures are frames a second at about 280 units, and the mean from 10 s on.

| Build | Rendered, at 280 units | Rendered, mean | Headless (1/30 s step), mean |
|---|---|---|---|
| main (8716fa7) | 4 | 10.3 | 36.4 |
| This branch before the death clip cap | 10–14 | 11.8 (one wave) | 57.0 |
| This branch with the cap | 14 | 16.8 (one wave) | |

Where a rendered frame goes on this branch at about 270 units:

- **Unit scripts:** about 22 ms (`unit_agent` `_process`), with 35 ms for all scripts.
- **Engine work for the unit models:** about 45 ms. Hiding every unit's Visuals took a frame's process time from about 90 to 45 ms and doubled the frame rate. Freezing the animations saved little, so the cost is the models' many nodes (transforms) rather than the clips.
- **Drawing:** 20–30 ms of render CPU for about 29,000 draw calls. With unit shadows off, it is about 10,000 draw calls and 12 ms.

Pieces per unit model now (each MeshInstance3D is a transform to update and at least one draw call per pass):

| Unit | Mesh pieces | Surfaces |
|---|---|---|
| Tank | 59 | 144 |
| Motorcycle | 38 | 98 |
| Scout | 25 | 113 |
| Deforester (infantry) | 24 | 55 |
| Grenadier | 18 | 69 |
| Drone | 15 | 72 |
| Ubermech | 2 | 14 |

The Ubermech, one skinned mesh, shows what the others could be.

## Still to do

The remaining cost is mostly the unit models: their pieces, and drawing them.

- **Fewer draw calls per unit:** merge each model's pieces that share a material and move together. The Tank's 144 surfaces would become at most 18 per pass, and similarly for the others. This is work on the Blender files. It shouldn't change how the units look, but each model needs checking by eye.
- **Shadows:**
  - The sun's shadows reach 340 m with 4 cascades, and units off screen are drawn into them.
  - Fewer cascades or a shorter reach would cut drawing a lot, but it changes the look. A graphics-quality setting may be the right home for it.
- **Unit scripts:** walking is still the largest per-unit cost. A simulation step slower than the frame (units deciding 10–20 times a second, with their models moved smoothly in between) would cut it further. Godot's own physics interpolation was tried and made things worse at this node count (about 18,000 nodes), so it would need to be hand-written.
