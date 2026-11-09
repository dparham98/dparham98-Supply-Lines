# Ground tiles

Grass and desert are drawn with the tiles from `Blender/Terrain/GroundTiles.blend`: four variants each, 1 m square in Blender, with 512 px colour and normal textures in `Blender/Terrain/ground_tiles/textures`. Gameplay is not affected. Terrain categories, pathfinding and building rules still come from `assets/maps/terrain_cells.bin` and its 1 m grid.

## How they are drawn

- `scripts/tools/build_ground_tile_arrays.gd` packs the sources into `assets/textures/terrain/ground_tiles_albedo.png` and `_normal.png`, imported as eight-layer texture arrays (layers 0-3 grass, 4-7 desert). Run it after editing a tile.
- `assets/shaders/terrain_surface.gdshader` picks a variant for each tile position from a fixed hash, so the pattern is the same every match. All tiles of a set share identical borders, so any variant can sit beside any other. Tiles are not rotated, because that would break those borders.
- Water, forest floor, mountain ground, ore and cleared forest draw as before.

## Settings (`assets/shaders/terrain_surface.gdshader`, overridable on the material)

| Setting | Value | Meaning |
| --- | --- | --- |
| `tile_metres` | 4 | Ground covered by one tile. At 1 m the art shrinks to about 6 px at the default zoom and reads as flat colour. |
| `feature_share` | 0.2 | Share of tiles using variants 03 and 04 (flowers and dirt, rocks and cracks). The rest use the plain 01 and 02. |
| `surface_tint` | 1 | How much of the soft colour variation in the old map image shows through, which hides repetition from far away. 0 shows the tile colours alone. |

The tint divides `terrain_surface.png` by its mean colour for that ground type (`grass_surface_mean`, `desert_surface_mean`). Near a border that blurry image holds the colour of the neighbouring ground, so large differences are ignored; otherwise the border shows as a dark or bright band.

## Checks

- `tests/ground_tiles_test.gd` (headless): both arrays have eight mipmapped layers, the settings exist, the Ground node uses the saved material, and the gameplay grid is unchanged.
- `tests/ground_tiles_runtime_check.gd` (rendered): grass and desert show tile detail up close, and saves close, play-zoom and whole-map views.

Tile size, feature share and tint were chosen by eye against renders. Grass and desert borders keep the blocky steps of the map.
