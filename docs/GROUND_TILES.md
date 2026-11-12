# Ground tiles

Grass, desert, water and forests are drawn with the tiles from `Blender/Terrain/GroundTiles.blend`: four variants each, 1 m square in Blender, with 512 px colour and normal textures in `Blender/Terrain/ground_tiles/textures`. The file also holds mountain tiles, which the game does not use. Gameplay is not affected. Terrain categories, pathfinding and building rules still come from `assets/maps/terrain_cells.bin` and its 1 m grid.

## How they are drawn

- `scripts/tools/build_ground_tile_arrays.gd` packs the sources into `assets/textures/terrain/ground_tiles_albedo.png` and `_normal.png`, imported as twelve-layer texture arrays (layers 0-3 grass, 4-7 desert, 8-11 water). Run it after editing a tile.
- `assets/shaders/terrain_surface.gdshader` picks a variant for each tile position from a fixed hash, so the pattern is the same every match. All tiles of a set share identical borders, so any variant can sit beside any other. Tiles are not rotated, because that would break those borders.
- Forest floor uses the grass tiles. Water keeps its animated ripple on top of the tiles. Ground around the mountains uses the desert tiles darkened to stony earth (see [MOUNTAINS.md](MOUNTAINS.md)). Ore and cleared forest draw as before. Coal cells (category 6, balanced map only) draw as the desert tiles with their colour taken out and darkened by `coal_shade`.

## Settings (`assets/shaders/terrain_surface.gdshader`, overridable on the material)

| Setting | Value | Meaning |
| --- | --- | --- |
| `tile_metres` | 4 | Ground covered by one tile. At 1 m the art shrinks to about 6 px at the default zoom and reads as flat colour. |
| `feature_share` | 0.2 | Share of tiles using variants 03 and 04 (flowers and dirt, rocks and cracks, sparkle and foam). The rest use the plain 01 and 02. |
| `surface_tint` | 1 | How much of the soft colour variation in the old map image shows through, which hides repetition from far away. 0 shows the tile colours alone. |

The tint divides `terrain_surface.png` by its mean colour for that ground type (`grass_surface_mean` and the matching desert, water and forest values). Near a border that blurry image holds the colour of the neighbouring ground, so large differences are ignored; otherwise the border shows as a dark or bright band.

## World-scale look

Open ground (grass, forest floor and desert) gets four layers on top of the tiles, all in `terrain_surface.gdshader` and all drawing only. Gameplay still reads `terrain_cells.bin`, so the drawn line can differ from the real cell border by about a metre.

- **Soft border:** `assets/textures/terrain/ground_blend.png` holds each cell's distance from the desert and grass border, slightly blurred to round off the steps. Noise makes the line wander. Rebuild it after the map cells change: `godot --headless --path . --script res://scripts/tools/build_ground_blend_map.gd`. It stays lossless (`detect_3d/compress_to=0` in its `.import`). Another map passes `-- --cells=... --output=...` ([BALANCED_MAP.md](BALANCED_MAP.md)).
- **Colour patches:** broad drifts about 64 m across and smaller dry patches about 17 m across, plus dry straw on the grass beside desert.
- **Breakup:** a larger copy of the tile pattern at a scale that never lines up with the 4 m tiles.
- **Relief:** gentle slopes lit by the sun. The bent normal is length-limited, because past that limit the surface renders black.
- **Noise:** the hash works on whole numbers on purpose. A float hash can give the two cells that share a grid corner different values, which draws a straight dark seam along the cell edge.

| Setting | Value | Meaning |
| --- | --- | --- |
| `border_wander` | 0.65 | How far the line wanders, in metres. |
| `border_softness` | 0.28 | Half-width of the crossfade, in metres. |
| `dry_margin`, `dry_strength` | 6, 0.55 | Width of the dry strip beside desert, and how dry it gets. |
| `macro_strength` | 1 | Strength of the colour patches. |
| `breakup_strength` | 0.55 | Strength of the larger tile pattern. |
| `grass_relief`, `desert_relief` | 0.5, 1 | Strength of the relief on each. |

## Forests

The four forest overlays (pine, broadleaf, mixed and sparse) replace the old cone trees. Each of the 1,646 forest spots holds one patch, chosen at bake time, so a Tank clearing a cell removes the patch on that 2 x 2 tile area as before.

- `assets/models/terrain/forest_tile_01.obj` to `_04.obj` are simplified exports of about 700 triangles against 2,830 to 4,796 in the Blender file, which keeps full detail. All 1,646 at full detail would be about 6 million faces.
- `scenes/terrain/forest_tile_01.tscn` to `_04.tscn` scale a patch by 4, which makes trees about 3 m tall. As modelled they are 0.75 m, shorter than a Scout.
- They are assigned to `forest_tile_scenes` on `terrain.tscn` and baked into `terrain_landmarks.tscn` by its **Rebuild terrain scenery** button. Without that list the baker falls back to `tree_scene`.

## Checks

- `tests/ground_tiles_test.gd` (headless): both arrays have twelve mipmapped layers, the settings exist, the blend map agrees with the map cells, the Ground node uses the saved material, the gameplay grid is unchanged, and all 1,646 forest spots use the four patches within the triangle budget.
- `tests/ground_tiles_runtime_check.gd` (rendered): grass and desert show tile detail up close, open grass has no black spots, the noise has no seams, and saves close, play-zoom, whole-map, forest and water views.

Tile size, forest scale, feature share and tint were chosen by eye against renders. Water and mountain-foot borders keep the blocky steps of the map.
