# Depot panels

These panels come from the playtest of main at 8ee9b55 (2026-11-15). They replace the Depot card's Energy ceiling (E) and Coal kept (Q) tiles.

Under them, a selected Barracks or Tank Factory of yours shows its Production speed panel (docs/PRODUCTION_POWER.md).

## When they show

Both panels show for one of your Depots, the Depot in context (`context_depot` in `skirmish_hud.gd`), while you have selected:

- that Depot;
- a Generator or production building that uses it;
- an Iron Mine or construction plan in its range. If several of your Depots cover it, the nearest one is used.

They do not show for units, for other sides' buildings, or for a building outside every one of your Depots' ranges.

## Top left: energy

- **Energy stock:** the energy the Depot holds now against its storage, for example "1,240 / 2,000 E" (playtest of 9eaed10).
- **Energy banking:** a bar of how fast the Depot's Generators are banking energy now (`generation_rate`), measured against the most they could bank with every one running on its faster fuel (`peak_generation_rate`). The value reads "+5.0 E/s", "0 E/s" or "No Generators".
- When nothing is banking, a note says why, from the first assigned Generator's state line (for example "Paused · Depot at its 600 E ceiling" or "Waiting · 60 coal kept for vehicles"). With no Generators it says to build one in the Depot's range.
- **Energy ceiling** slider: 0 to the Depot's storage capacity, in 50 E steps. All the way right reads "No ceiling".
- **Coal kept for vehicles** slider: 0 to 300, in steps of 10.
- The sliders take no keyboard focus, so arrow keys and hotkeys keep working. They set `energy_ceiling` and `coal_reserve` on the Depot directly (`set_energy_ceiling`, `set_coal_reserve`). The rules for both are unchanged (`docs/GENERATOR_LIMITS.md`).
- If the playtest tools (F10) are open, the panel moves below them.

## Top right: storage

- The Depot's storage bar and legend, the same section the bottom panel used to show.
- Your own Depot and Generators no longer show storage in the bottom panel. Other sides' Depots still do, and Cargo trucks and Trains still show what they carry there.
- The alert feed moves down below the storage panel while it shows.

## Removed

- The Depot card's Energy ceiling and Coal kept tiles, their `command_energy_ceiling` and `command_coal_reserve` actions, and the Depot card's stats for them.
- The preset lists and `cycle_energy_ceiling` / `cycle_coal_reserve` in `depot.gd`.
- The Depot card keys are now D, V, T, C and X.

## Checks

- `tests/generator_limits_test.gd` (headless) now checks:
  - the sliders' snapping and limits;
  - both panels show for your Depot and set its values;
  - the banking bar and its note;
  - a Generator shows its Depot's panels;
  - another side's Depot shows neither;
  - the feed moves and returns.
- `tests/depot_panels_runtime_check.gd` (rendered) saves `depot_panels.png` and checks that the panels are on screen, clear of each other and of the bottom HUD, with the feed below.
- `selection_panels_test` reads your Depot's storage from the top-right panel. `command_cards_test` counts 46 tiles. `hud_hotkeys_test` expects Depot keys D, V, T, C.
