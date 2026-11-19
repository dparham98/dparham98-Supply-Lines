# Coal mines

Coal lies in the ground and is taken through a mine built on its seam. The mine is the old pithead of [IRON_MINE_MODEL.md](IRON_MINE_MODEL.md): the same building, scene and script as an Iron Mine on an ore field. Agreed on 2026-11-16. Before this, Infantry dug coal straight out of a cell and each emptied cell became open ground.

No coal seam has a mine at the start of a game. Iron is different: on Two Lakes every mine site starts with its mine ([TWO_LAKES_MAP.md](TWO_LAKES_MAP.md)).

## Rules

- **Building.** Build, then Coal Mine (C, the pick-and-lump card), and place it on Coal cells. The Iron Mine tile (A) no longer takes a seam, and the Coal Mine takes nothing else. It takes the mine's ordinary 2 x 2 footprint, all of it on coal, and costs **0 energy / 25 iron** (`EngineeringRules.mine_energy_cost`, `mine_iron_cost`). Because a queued mine plan needs no energy, it needs no covering Depot range: any truck or Infantry carrying 25 iron to the footprint can establish a mine on a distant seam. The plan kind is `coal_mine` (`DepotNetwork.is_mine_kind`, `plan_terrain_valid`); a built mine on coal is named Coal Mine. Placed by a selected builder from a Depot's card, the one Mine tile still takes either (`DepotNetwork.mine_spot`, `mine_scene_for`, `TerrainGrid.ore_footprint_valid`).
- **One mine to a seam.** A seam that has a mine takes no second one (`TerrainGrid.coal_mine_at`).
- **It yields the whole seam.** The mine's reserve is everything left in the connected field of Coal cells it stands on, not just the cells under it (`TerrainGrid.mine_coal`, `coal_field_remaining`).
- **Shared.** Like every mine, any side's Infantry can gather from it and repair it.
- **The ground stays.** Mining does not dig cells out. A seam stays ground that nothing walks or builds on, also when it is empty; the mine then shows its worked-out state.
- **Gathering.** Right-click the mine, or right-click any cell of its seam. A right-click on a seam with an unfinished Mine plan orders selected trucks to fetch iron and Infantry to construct it; on a seam with no mine or plan it says "Build a Mine on this coal seam before gathering coal."
- **Trees.** Seams lie inside forest. Workers ordered to construct a mine plan or gather from a built coal mine behind uncut trees with no other way there fell the trees on a roughly straight line to its footprint (`FellLane`, docs/FELL.md), leaving the wood where it falls and keeping any carried iron. This comes before the old rule that lets a builder with no way to the footprint work from anywhere in reach of its centre (docs/BUILDER_TOUCH.md), so a site behind trees gets its lane; a builder already standing in reach when ordered still works from there, or the player can open a lane first with Fell (`docs/FELL.md`).

## The old rule

`coal_needs_mine` on `assets/economy/harvesting_rules.tres` (`scripts/economy/harvesting_rules.gd`) is on by default. Off, a right-click on a Coal cell orders Infantry to dig it by hand as before, and emptied cells open up. The digging code (`TerrainGrid.harvest_coal`, `coal_source`, the worker's felling of a way in) is all still there, and the older tests that exercise it turn the rule off.

## Files

- `scripts/economy/iron_mine.gd`: `on_coal` is set when the mine stands on Coal cells; it then yields coal from the seam and its label names coal.
- `scripts/terrain/terrain_grid.gd`: `mine_coal`, `coal_mine_at`, and coal accepted by `ore_footprint_valid`.
- `scripts/gameplay/skirmish.gd`: the two gather orders on a Coal cell.
- `tests/coal_mine_test.gd` (headless, Two Lakes).

## Not done yet

- The Build card still calls the button an Iron Mine.
- The minimap and the hover card over a seam still describe the cell, not the mine's reserve.
- The opponent-less maps' timing notes (`BALANCED_MAP.md`, "first coal in reach") were worked out for digging by hand and have not been redone.
- Nothing has been played.
