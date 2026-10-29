# Playtest fixes (2026-10-29)

These fixes come from the first physical playtest of main `1082020`, on branch `fix/playtest-feedback`.

| Feedback | Cause | Fix |
| --- | --- | --- |
| The HUD moves when hovering a command | The hover line wrapped onto extra lines, and pickers appearing above the grid pushed it down | The hover line is one fixed-height line: text is flattened and clipped with an ellipsis, and the full text stays in the tooltip. The supply picker and distant-stop list share one fixed 30 px `OptionRow`, so arming Load or changing selection never moves the grid. The generator's fuel mode and assigned-Depot pickers moved into the Context column. |
| Not every command shows its hotkey | Build-menu tiles and header buttons had no shortcuts | Build tiles: Depot D, Generator G, Barracks B, Tank factory T, Iron mine I, Rail R, Back Esc, each with a corner badge. Header: global Build N and Focus selection Home, with the key in the button text. |
| Invalid commands can be queued (deploying a Depot Truck next to trees) | Deploy acted at the truck's current spot | Deploy is now a placement. A green or red 8 × 8 footprint follows the pointer, only a valid site is accepted or Shift-queued (`can_deploy_at`), and the truck drives there and checks the site again on arrival. |
| Buildings can't be hotkeyed | Control groups only stored units | Ctrl+number with only a friendly building selected saves it, the number recalls it, and a double tap centres on it. |
| Edge scroll triggers while working in the HUD | The bottom HUD let edge pan through | Edge pan doesn't trigger over the HUD. Panning down uses the arrows, middle-drag or the minimap. `edge_pan_test` (baseline) now asserts this. |
| Unclear supply drop-down above the command card | Infantry's pay-from and deliver-to picker was always shown | It shows only when there's a choice of stockpile, and reads "Pay from, deliver to: …". The notes always say "Pays from and delivers to …". |
| Hovering a Depot should show health and the colour-coded storage bar | Only text and a single meter | The map shows the health bar plus a storage bar split by resource for hovered or selected Depots and Cargo vehicles. The hover card shows a health bar and the split storage bar. |
| Armed commands need a cursor indicator | None | An icon and label in the order's colour follow the pointer while a command or placement is armed. The system cursor shape isn't changed, because doing so sends a synthetic mouse-motion event that cancelled button clicks. |
| Attack-move on the ground | Attack needed a target | Attack on open ground is attack-move (`attack_move`): the unit travels to the point, stops to fire at anything in range, then carries on. It's queueable, shows a red ping, and non-combat units just move. |

## Tests

- New: `tests/playtest_fixes_test.gd` (headless) and `tests/playtest_fixes_runtime_check.gd` (rendered, with the screenshots `depot_hover`, `deploy_blocked` and `deploy_preview`).
- Baseline tests changed for the requested behaviour:
  - `edge_pan_test`: the bottom HUD no longer passes edge pan.
  - `generator_runtime_check` and `mobile_supply_runtime_check`: the moved picker paths, and the supply picker is only clicked when shown.
- `map_status_test` (mine) expects the split storage bar on the Depot hover card.
