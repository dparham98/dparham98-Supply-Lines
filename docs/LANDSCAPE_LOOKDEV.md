# Landscape look-development slice

One part of the map is drawn as sculpted landscape, as a trial before any rollout: real height, blended ground, a shoreline, rock faces, woodland and scenery. Everything else on the map is drawn as before. Gameplay is not affected. Terrain categories, pathfinding and building rules still come from `assets/maps/terrain_cells.bin` and its flat 1 m grid, and units stay at height 0.

The slice is map cells 44-166 by 56-128 (122 x 72 m, north-west). No 60 x 60 m square of the map holds grass, desert, water, forest and a mountain foot together, and this is the smallest rectangle that does without cutting the mountain in half. It is the `region` of `assets/terrain/landscape_settings.tres`.

## How it is made

Everything is rebuilt from the map cells, so a change to the layout needs no hand work:

```bash
godot --headless --path . --script res://scripts/tools/build_landscape.gd
godot --headless --path . --script res://scripts/tools/rebuild_terrain_scenery.gd
```

The second command does what **Rebuild terrain scenery** on `scenes/maps/terrain.tscn` does. Nothing is generated while the game runs.

- `scripts/tools/landscape_builder.gd` turns the cells into smooth distance fields (shore, rock edge, forest, ore) at 4 pixels per metre, with the blocky corners rounded and the lines made to wander, and gives a height for every point.
- `build_landscape.gd` saves the fields (`assets/textures/terrain/landscape_fields.res`), the ground mesh and the water mesh (`assets/models/terrain/landscape_ground.res`, `landscape_water.res`), and sets the `landscape_region` cut-out on the flat ground and old mountain materials so they do not draw inside the region.
- `scripts/tools/landscape_baker.gd`, called by `terrain_baker.gd`, stands the kit on the ground and saves it in `scenes/maps/terrain_landmarks.tscn` under `Landscape` (`Ground`, `Water`, `Scatter`, `Forest`). Each placement is decided by a hash of its own cell, so changing some cells only changes the scenery around them. Batches are split into 64 m squares so off-screen ones are not drawn.

## Height

- Walkable grass, desert and forest only dip, by at most 7 cm (`walkable_relief`), so nothing drawn at height 0 is buried and units do not visibly float. The rolling look of open ground comes from the shading it already had.
- Water: the drawn shoreline sits 0.9 m inside the Water cells (`shore_inset`), so a unit on the last land cell stays dry. The bank drops to 1.7 m below the surface.
- Rock stays inside the Mountain cells apart from rounding of about 0.4 m at corners: a first wall of 3 to 5 m, a ledge, a second wall where the rock is wide enough, and a stepped top. Where the rock is wide, crests stand up out of the top as peaks. The peak is capped at 10.6 m because Drones fly at 12 m. Snow lies on level rock above 8.1 m (`snow_line` in `landscape_rock.gdshaderinc`), so only the tallest rock carries it.
- Heights return to 0 over the last 4 m at the region edge, so the slice meets the flat map.

## Ground and water

`assets/shaders/landscape_ground.gdshader` draws open grass and desert exactly as `terrain_surface.gdshader` does, so the two meet without a seam; change the shared settings in both. On top it blends, from the fields: forest litter, churned earth on cleared cells, ore ground, scree at the rock foot, a beach, wet ground at the waterline, the bed under water, and the rock itself. Inside the region only, grass also gets darker clumps (where the baker stands tall grass) and worn bare patches.

`assets/shaders/landscape_water.gdshader` takes its depth from the shore field: clear green shallows over the bed, the map's water colour in the deep, foam lines and a foam edge. At the region edge it becomes the flat map's water.

## Kit

`Blender/Terrain/build/build_landscape_kit.py` builds every piece and writes `Blender/Terrain/LandscapeKit.blend`, one OBJ per piece in `assets/models/terrain/kit`, a wrapper scene per piece in `scenes/terrain/kit` and a contact sheet in `Blender/Previews/Terrain`. The scenes are assigned on `landscape_settings.tres`, which `terrain.tscn` holds in its `landscape` slot.

| Pieces | Triangles each | Placed |
| --- | --- | --- |
| `cliff_01` to `_03` | about 880 | In a wall along the rock edge and along the ledge, turned to face out, stretched to the wall's height |
| `boulder_01` to `_03` | about 350 | At the rock foot and on its top, on Mountain cells only |
| `stones_01` to `_03` | 48 to 102 | On scree, desert, beaches and bare patches |
| `shore_rock_01`, `_02` | 227 | In the shallows |
| `conifer_01` to `_03`, `broadleaf_01` to `_03` | 210 to 990, trunk and leaves together | One on just under half of the Forest cells |
| `ore_01` to `_03` | about 260 | One on each Ore spot, in place of the old ore rocks |
| `log_01`, `mossy_rock_01` | 73, 198 | Under the trees |
| `fern_01`, `_02`, `bush_01`, `_02` | 25 to 70 | Under the trees, at the forest edge, in thickets |
| `tall_grass`, `tuft`, `flower`, `dry_tuft`, `dry_bush`, `reeds` | 15 to 75 | Meadow clumps, open grass, desert, rock tops, green shores |

Cliffs, boulders and shore rocks start as piles of blocks, which `erode()` fuses into one weathered rock. Rock pieces carry only baked shading; `landscape_kit_rock.gdshader` gives them the same projected rock as the ground (`landscape_rock.gdshaderinc`), so a cliff piece matches the hill it stands in. Plants carry their colour in the vertex colours and sway in the wind (`landscape_foliage.gdshader`).

## Forest

The wood is old growth: tall spruces with drooping boughs, and broadleaves with leaning, moss-footed trunks that fork into limbs. Bark is drawn as furrows by `landscape_foliage.gdshader` on anything the kit marks as wood (UV.y of 1). Their leaves and needles are flat sprays cut out by `assets/textures/terrain/leaf_atlas.png`, which the kit script draws, exported as `<tree>_leaves.obj` and drawn by `landscape_leaves.gdshader`; each tree scene holds its trunk and its leaves. The floor is moss and litter with ferns, mossy rocks and fallen logs.

Each Forest cell in the region has its own tree (54% of cells, `tree_share`) and low growth, standing inside that cell. Trees reach about 10.7 m at their largest, under the 12 m Drones fly at. When a cell is cleared, by a Tank or by harvesting its last wood, `scripts/terrain/forest_state_visuals.gd` fells exactly the pieces on it: a tree topples about its foot over 1.25 s, bounces once and sinks away over 1.1 s, and low growth shrinks. Which way it falls comes from the cell, so a trunk and its leaves go down together. Only saved batch instances are moved. The ground shader draws churned earth there from the same match-local mask.

The tree shaders read that mask too: whatever would hide a cleared cell from the camera is cut away, so a lane and the units in it show past the trees in front, and the sun reaches the lane. Units inside standing forest are still hidden by it. The old 2 x 2 patches keep their places in their batches with no size inside the region, so the 1,646 spot count and their clearing are unchanged elsewhere.

## Lighting (`scenes/maps/lighting.tscn`, all maps)

Sun from the west-south-west at 38 degrees, so shadows fall to the right and show relief; softer shadows over a 340 m range; ambient occlusion; light fog; ACES tone mapping with a small contrast and saturation adjustment. This changes the whole game's look, not only the slice.

## Cost

Measured with `tests/landscape_lookdev_runtime_check.gd` at 1600 x 900, close view of the wood:

| | Draw calls | Primitives in frame |
| --- | --- | --- |
| Before | 20 | 566,000 |
| With the slice | 141 | 858,000 |
| With the slice, mountain close-up | 174 | 1,040,000 |
| With the slice and the old-growth wood | 213 | 864,000 |

The slice is 430,000 triangles over 8,784 square metres: 70,000 ground, 1,200 water, the rest scenery.

## Checks

- `tests/landscape_lookdev_test.gd` (headless): the slice is saved in the scenery, walkable ground stays within the relief limit, rock stays under Drone height, the edge meets the flat map, forest pieces stand on Forest cells, boulders stand on Mountain cells, the triangle budget holds, and clearing a cell opens it.
- `tests/landscape_lookdev_runtime_check.gd` (rendered): saves play-zoom, wide and close views, and a view with a lane cleared through the wood.

## Known limits

- Scenery on walkable cells (grass, bushes, stones) does not move aside for buildings or rails.
- A Scout inside standing forest is hidden by the trees; only cleared cells are opened to view.
- The slice edge shows where the new shore meets the old blocky water.
- Rock pieces are scripted: blocks fused, cut into beds, cracked and thinned in `erode()`. The 3D generator was not available when they were made.
- The whole-map view is hazier than before, because fog grows with camera distance.
