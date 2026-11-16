# Selection portraits and Shift-drag

These changes come from the playtest of main at 8ee9b55 (2026-11-15).

## Shift-drag adds to the selection

- With units selected, hold Shift and drag a box: the boxed units join the selection and the ones already selected stay. Shift-click on a unit still adds or removes that one unit.
- This was already meant to work, but any key event during a drag cancelled the box. Holding Shift repeats its key event, so the box was dropped before the mouse was released.
- `selection_manager.gd` now ignores Shift, Ctrl, Alt and Meta, and key repeats, while a box is being dragged. Any other key, or another mouse button, still cancels it.

## Portraits of every selected unit

- With more than one unit selected, the bottom Info column shows one portrait per unit instead of the first unit's health, bars and details.
  - The name reads "N units selected", replacing "Infantry · +N selected".
  - The state line says which unit the card and stats show; its portrait is outlined.
- **Portraits:**
  - Each one shows the unit's icon and a health bar: green, amber below 60%, red below 30%.
  - They are grouped by type, in the order the types were first selected, so the outlined unit is always first.
  - There are 33 authored slots (`Info/Portraits/P1`–`P33`, 11 by 3). A larger selection says how many more are not shown.
- **Clicks:**
  - Click: only that unit.
  - Shift-click: remove that unit.
  - Ctrl-click: only that unit's type.
  - Ctrl+Shift-click: remove that type.
- The tooltip names the unit, its health and its state.
- **The header type strip (`Infantry ×9`, …) is gone.**
  - With five or more types it overflowed the header and pushed the Restart button off screen.
  - The portraits show the same breakdown, and Ctrl-click narrows by type as the strip did.

## Checks

- `tests/selection_portraits_test.gd` (headless) checks:
  - Shift held and repeating during a drag keeps the box, and the Shift-box adds a unit to an existing selection;
  - another key still cancels a drag;
  - one portrait per unit, the count in the name, health and details hidden;
  - the outlined first portrait, icons, health colours and tooltips;
  - Shift-click removes a unit, and a click keeps only one.
- `tests/selection_portraits_runtime_check.gd` (rendered) selects 26 mixed units and checks that the portraits fit inside the Info column. It saves `selection_portraits.png`.
- `hud_layout_test` checks that the strip is gone and that Ctrl-click and Ctrl+Shift-click work on types. `hud_layout_runtime_check` narrows to the Tank with a real click on its portrait.
