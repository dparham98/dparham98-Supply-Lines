class_name LandscapeSettings
extends Resource
## Sculpted landscape for part of the map (docs/LANDSCAPE_LOOKDEV.md). Everything it draws is rebuilt from
## terrain_cells.bin inside `region`: run scripts/tools/build_landscape.gd, then Rebuild terrain scenery.

## Map cells covered. The flat ground and the old mountains are not drawn inside it.
@export var region := Rect2i(44, 56, 122, 72)
@export var scatter_seed: int = 5521
@export_group("Shape")
## Height of the water surface below the walkable ground, in metres.
@export var water_level: float = -0.32
## Depth of the bed below the water surface far from the shore.
@export var bank_depth: float = 1.7
## Metres the drawn shoreline sits inside the Water cells, so units on the last land cell stay dry.
@export var shore_inset: float = 0.9
## Deepest dip of walkable ground. Units stay at height 0, so this is how far they can appear to float.
@export var walkable_relief: float = 0.07
## Highest rock. Drones fly at 12 m.
@export var peak: float = 10.6
@export_group("Built meshes")
@export var ground_mesh: Mesh
@export var water_mesh: Mesh
@export_group("Kit scenes")
## Rock faces set into the mountain edge, facing outwards along local +Z.
@export var cliff_scenes: Array[PackedScene] = []
## Large rocks at the mountain foot and on its top. Never placed on walkable cells.
@export var boulder_scenes: Array[PackedScene] = []
## Small stones, low enough for units to pass over.
@export var stone_scenes: Array[PackedScene] = []
## Rocks standing in the shallows.
@export var shore_rock_scenes: Array[PackedScene] = []
## Ore breaking the surface, one group on each Ore spot in place of the old ore rocks.
@export var ore_scenes: Array[PackedScene] = []
@export var reed_scenes: Array[PackedScene] = []
@export var bush_scenes: Array[PackedScene] = []
@export var dry_bush_scenes: Array[PackedScene] = []
@export var tuft_scenes: Array[PackedScene] = []
@export var dry_tuft_scenes: Array[PackedScene] = []
## Stands on the darker clumps the ground shader draws in the grass.
@export var tall_grass_scenes: Array[PackedScene] = []
@export var flower_scenes: Array[PackedScene] = []
@export_group("Forest")
## One tree stands on most Forest cells and is hidden when that cell is cleared.
@export var conifer_scenes: Array[PackedScene] = []
@export var broadleaf_scenes: Array[PackedScene] = []
## Low growth on Forest cells, hidden with the cell.
@export var undergrowth_scenes: Array[PackedScene] = []
## Share of Forest cells that hold a tree.
@export_range(0.1, 1.0, 0.01) var tree_share: float = 0.54
