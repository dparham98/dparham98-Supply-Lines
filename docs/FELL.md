# Fell

The playtest of 2026-11-17 asked for a way to clear trees with Infantry without carrying the wood home.

- **The command:** Fell (F) on the Infantry card, and on any unit that can gather. Click a Forest cell, on the map or the minimap.
- **What the workers do:** they cut down the trees on that cell, then the Forest cells within `fell_radius_cells` (4) of it, nearest first. The wood is left where it falls: they carry nothing and never walk to a Depot. They stop with the state "Felled" when no Forest is left in that circle.
- **Trees they cannot reach:** the worker stops with "Trees unreachable". Felling a nearer cell first may open the way.
- **Queueing:** Shift queues Fell like the other orders.
- **Not a Forest:** a click elsewhere says "Click a forest to fell." and keeps the command waiting.

## Provisional

- The 4-cell radius is a first guess.
- The axe card (`assets/ui/command_cards/sl_fell.png`) is a stand-in drawn in code by a scratch script, not final art.

## Code and checks

- `command_fell`, `_next_fell` and `_fell` in `scripts/gameplay/unit_agent.gd`; `fell_radius_cells` in `scripts/economy/harvesting_rules.gd`; the "fell" branch of `issue_card_order` in `scripts/gameplay/skirmish.gd`.
- `tests/fell_test.gd` (headless): the patch is cleared, no wood is kept, the worker never walks home, and the card, the F key and the click on a Forest work.
