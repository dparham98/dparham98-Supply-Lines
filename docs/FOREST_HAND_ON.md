# Wood cutters move on by themselves

From the playtest of main at 9eaed10 (2026-11-15).

## What changed

An Infantry cutting wood no longer stops when its Forest cell runs out. It moves on to the next Forest cell itself, as workers on a coal field already do.

- **Which cell it picks:** the nearest cell to the one it just cut, out to `forest_search_cells` (10 cells) in `HarvestingRules`. That keeps it eating into the edge it has opened. When two cells are equally near, it takes the one on its own side.
  - The search is `TerrainGrid.next_forest_cell`, and the hand-on is `next_source` on `forest_harvest_source.gd`.
- **Partial loads:** a worker whose cell runs out before its load is full now moves on to the next cell and keeps filling. Before, it walked home part-loaded.
  - This also applies to coal cells, which already moved on.
  - It does not apply to iron, which has no next cell.
- **After a trip home:** the worker goes back to the cell it was handed on to.
- **Turning it off:** set `forest_search_cells` to 0. A worker then stops when its cell runs out, as before.
- **Coal workers felling a way in** (`docs/BALANCED_MAP.md`) still go back to their coal when the tree in the way is down.

## Tests

`tests/forest_hand_on_test.gd` (headless, balanced map) checks that:

- a worker moves on to a neighbouring Forest cell when its cell runs out;
- it keeps its part load while it moves on;
- it goes on cutting and delivering by itself;
- a search of 0 cells stops it when its cell runs out.
