# Fell

The playtest of 2026-11-17 asked for a way to clear trees with Infantry without carrying the wood home.

- **The command:** Fell (F) on the Infantry card, and on any unit that can gather. Click a spot, or drag a box, on the map; the minimap takes a click.
- **A click:** the workers fell a roughly straight lane to the spot: the unbroken trees on the grid line from the worker to it, between the spot and the open ground on the worker's side. A spot on a coal seam, a lake or open ground walled in by trees gets the lane up to its edge. Then they clear the Forest cells within `fell_radius_cells` (1) of the spot, nearest first.
- **A box:** the workers fell every Forest cell in the box, nearest first. A cell with no walk to it gets a lane of its own.
- **No path search:** the lane is the grid line, not the fewest trees, so it is cheap to work out again after each tree. A worker that cannot walk to the lane's first tree cuts every tree on the line instead; if that fails too, the cell is given up and the worker stops with "Trees unreachable" at the end.
- **The wood** is left where it falls: they carry nothing, keep any load they already have, and never walk to a Depot. They stop with the state "Felled".
- **Queueing:** Shift queues Fell like the other orders.
- **Nothing to fell:** a click with no trees on the line or round the spot says "Nothing to fell: the way there is already open."; an empty box says "No trees to fell in that box." Both keep the command waiting.

## Provisional

- The 1-cell end radius (`fell_radius_cells = 1`) keeps lane cuts narrow while clearing a small pocket at the target.
- The axe card (`assets/ui/command_cards/sl_fell.png`) is a stand-in drawn in code by a scratch script, not final art.

## Code and checks

- The lane: `scripts/terrain/fell_lane.gd`. `command_fell`, `_fell_target`, `_next_fell` and `_fell` in `scripts/gameplay/unit_agent.gd`; `fell_radius_cells` in `scripts/economy/harvesting_rules.gd`; `order_fell`, `order_fell_box` and the Fell drag in `scripts/gameplay/skirmish.gd`.
- `tests/fell_test.gd` (headless): the patch is cleared, no wood is kept, the worker never walks home, a deep cell and a seam get lanes, a box is cleared, the messages, and the card and the F key.
