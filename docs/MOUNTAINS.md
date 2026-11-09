# Mountains

The mountains are one sculpted mesh generated in Godot from the Mountain cells of `assets/maps/terrain_cells.bin`, replacing the scattered cones. It is scenery only. Mountain cells stay blocked exactly as before, and units, pathfinding and building rules do not read the mesh. The mountain tiles in `Blender/Terrain/GroundTiles.blend` are not used.

## How it is made

`scripts/tools/build_mountain_mesh.gd` writes `assets/models/terrain/mountains.res` and the two rock textures. It is run by hand, then **Rebuild terrain scenery** on `terrain.tscn` bakes the mesh into `terrain_landmarks.tscn`, so nothing is generated while the game runs.

```bash
godot --headless --path . --script res://scripts/tools/build_mountain_mesh.gd
```

- **Shape:** height rises with distance from the edge of the mountain area, then ridged noise raises crests and cuts valleys. Smaller ridges run down the flanks.
- **Outline:** the map cells are blocky, so vertices wander by up to about 3 m from them to give a natural edge. Rock can therefore overlap the first few metres of walkable ground and hide a unit standing right at the foot.
- **Size:** 2 vertices per metre, 166,824 triangles. Settings are the constants at the top of the script.

## Height

Peaks are capped at 11 m because Drones fly at 12 m. Taller mountains would need Drone height or flight rules to change.

## Rock (`assets/shaders/mountain_rock.gdshader`)

Colour comes from height, slope, strata bands and a hollows value stored in the vertex colours. Two scales of a generated fracture texture are projected along the three world axes so steep faces do not smear, with a matching normal map. Snow sits on gentle ground above `snow_line`, 7.8 m. These are uniforms and can be tuned on `assets/materials/terrain/mountain_massif.tres`.

The ground under and around the mountains uses the desert tiles darkened to stony earth (`stony_tint` in `terrain_surface.gdshader`), for the places where the wandering outline leaves Mountain cells uncovered.

## Checks

- `tests/mountains_test.gd` (headless): the mesh is in the saved scenery with its material, the old cones are gone, the triangle budget holds, peaks stay under Drone height, tall rock stays near Mountain cells, and Mountain cells stay blocked.
- `tests/mountains_runtime_check.gd` (rendered): lit rock and shadow near the player Depot, and saves play-zoom, close and whole-map views.

The look was set by eye against renders at the default camera angle. At the closest zoom the rock looks softer than it does at play distance.
