# Fell

The playtest of 2026-11-17 asked for a way to clear trees with Infantry without carrying the wood home.

- **The command:** Fell (F) on the Infantry card, and on any unit that can gather. Click a spot, or drag a box, on the map; the minimap takes a click.
- **A click:** the workers fell a roughly straight lane to the spot: the unbroken trees on the grid line from the worker to it, between the spot and the open ground on the worker's side. A spot on a coal seam, a lake or open ground walled in by trees gets the lane up to its edge. Then they clear the Forest cells within `fell_radius_cells` (1) of the spot, nearest first.
- **A box:** the workers fell every Forest cell in the box, nearest first. A cell with no walk to it gets a lane of its own.
- **No path search:** the lane is the grid line, not the fewest trees, so it is cheap to work out again after each tree. A worker that cannot walk to the lane's first tree cuts every tree on the line instead; if that fails too, the cell is given up and the worker stops with "Trees unreachable" at the end.
- **The wood** is left where it falls: they carry nothing, keep any load they already have, and never walk to a Depot. They stop with the state "Felled".
- **Queueing:** Shift queues Fell like the other orders.
- **Nothing to fell:** a click with no trees on the line or round the spot says "Nothing to fell: the way there is already open."; an empty box says "No trees to fell in that box." Both keep the command waiting.

## Autocast

Asked for on 2026-11-18.

- **Switching it:** right-click the Fell card to switch autocast on or off for the selected Infantry. When it is on for all of them, the card shows **AUTO**. It is off by default.
- **What they do:** an Infantry with autocast on, left idle with no orders, fells the Forest within `autocast_fell_radius_cells` (4) of the spot where it was left, one cell at a time, nearest first. A cell it cannot walk to gets a Fell lane, which stays inside that circle. As with Fell, it keeps no wood.
- **Staying put:** it works round that spot, not round wherever felling takes it, so it does not wander into a forest. When the circle is clear it stays idle.
- **Moving it:** an order moves the spot. When the unit is next left idle, it fells round the new place.
- **Unreachable trees:** after one it cannot reach, it waits 10 seconds before trying again.
- **Enemies first:** an idle unit with an enemy in range fights rather than fells.

## Provisional

- The 1-cell end radius (`fell_radius_cells = 1`) keeps lane cuts narrow while clearing a small pocket at the target.
- The axe card (`assets/ui/command_cards/sl_fell.png`) is a stand-in drawn in code by a scratch script, not final art.

## Code and checks

- The lane: `scripts/terrain/fell_lane.gd`. `command_fell`, `_fell_target`, `_next_fell` and `_fell` in `scripts/gameplay/unit_agent.gd`; `fell_radius_cells` in `scripts/economy/harvesting_rules.gd`; `order_fell`, `order_fell_box` and the Fell drag in `scripts/gameplay/skirmish.gd`.
- `tests/fell_test.gd` (headless): the patch is cleared, no wood is kept, the worker never walks home, a deep cell and a seam get lanes, a box is cleared, the messages, and the card and the F key.
- Autocast: `fell_autocast`, `set_fell_autocast` and `_auto_fell` in `unit_agent.gd`; `autocast_fell_radius_cells` in `harvesting_rules.gd`; `toggle_fell_autocast` in `skirmish_hud.gd`; the `Fell/Auto` badge in `skirmish_hud.tscn`. `tests/rally_autofell_test.gd` checks it.
