# Depot stock plate

Each of your Depots always shows what it holds on a plate above it: a swatch and amount for energy, iron, wood and
coal (`E 200 · I 60 · W 40 · C 60`). You can see which Depot can pay for something without selecting it.

Asked for in the playtest of 2026-11-18, first only while building, then permanently.

- **Who shows one:** only your own Depots. Enemy Depots, and deployed Cargo trucks, keep their usual storage bar,
  shown when hovered or selected.
- **Where:** it sits above the Depot's health bar. Holding Alt to show everything lifts it clear of the name line.
- **Code:** `map_overlay.gd`: `status_for()` adds a `readout` for your Depots, and `draw_readout()` draws it.
- **Checks:** `tests/placement_guide_test.gd` checks that your Depot always has the plate and an enemy Depot does
  not. The rendered screenshots from `tests/placement_guide_runtime_check.gd` show it above the starting Depot.
