# Fell

The playtest of 2026-11-17 asked for a way to clear trees with Infantry without carrying the wood home.

- **The command:** Fell (F) on the Infantry card, and on any unit that can gather. Click a Forest cell, on the map or the minimap.
- **What the workers do:** they cut down the trees on that cell, then the Forest cells within `fell_radius_cells` (4) of it, nearest first. The wood is left where it falls: they carry nothing and never walk to a Depot. They stop with the state "Felled" when no Forest is left in that circle.
- **Trees they cannot reach:** the worker stops with "Trees unreachable". Felling a nearer cell first may open the way.
- **Queueing:** Shift queues Fell like the other orders.
- **Not a Forest:** a click elsewhere says "Click a forest to fell." and keeps the command waiting.

## Autocast

Asked for on 2026-11-18.

- **Switching it:** right-click the Fell card to switch autocast on or off for the selected Infantry. When it is on for all of them, the card shows **AUTO**. It is off by default.
- **What they do:** an Infantry with autocast on, left idle with no orders, fells the Forest within `fell_radius_cells` (4) of the spot where it was left, nearest first. As with Fell, it keeps no wood.
- **Staying put:** it works round that spot, not round wherever felling takes it, so it does not wander into a forest. When the circle is clear it stays idle.
- **Moving it:** an order moves the spot. When the unit is next left idle, it fells round the new place.
- **Unreachable trees:** after one it cannot reach, it waits 10 seconds before trying again.
- **Enemies first:** an idle unit with an enemy in range fights rather than fells.

## Provisional

- The 4-cell radius is a first guess.
- The axe card (`assets/ui/command_cards/sl_fell.png`) is a stand-in drawn in code by a scratch script, not final art.

## Code and checks

- `command_fell`, `_next_fell` and `_fell` in `scripts/gameplay/unit_agent.gd`; `fell_radius_cells` in `scripts/economy/harvesting_rules.gd`; the "fell" branch of `issue_card_order` in `scripts/gameplay/skirmish.gd`.
- Autocast: `fell_autocast`, `set_fell_autocast` and `_auto_fell` in `unit_agent.gd`; `toggle_fell_autocast` in `skirmish_hud.gd`; the `Fell/Auto` badge in `skirmish_hud.tscn`. `tests/rally_autofell_test.gd` checks it.
- `tests/fell_test.gd` (headless): the patch is cleared, no wood is kept, the worker never walks home, and the card, the F key and the click on a Forest work.
