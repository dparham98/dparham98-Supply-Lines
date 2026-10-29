# UI phase A: shared theme and command card

Phase A of `UI_OVERHAUL_PLAN.md`, on branch `feature/ui-theme-card` from main `757c1af`.

## Changes

- **Shared theme** (`assets/ui/supply_lines_theme.tres`), applied to `Bottom`, `Feed` and the playtest panel.
  - A slate, teal and amber palette.
  - Button, option and checkbox states: normal, hover, pressed, disabled and focus.
  - Text fields, tooltips and popup menus.
  - Godot's default font at 14 px.
- **Icons:** 26 project-drawn SVGs in `assets/ui/icons/`, white strokes tinted by the theme (teal normally, white on hover, dim when disabled).
- **Command card tiles:**
  - Each tile has an icon, a short sentence-case label (Move, Gather, Deliver, Drop, Repair, Capture, Build…) and a corner badge with its hotkey. The longer descriptions moved into tooltips.
  - Tiles are 38 px tall, up from 30 px.
  - Keys moved out of the label text and into the `Key` badge on each button.
- **Consistent order:** Move, Stop, Attack, Gather, Deliver, Drop, Repair, Capture, then production, Build, Deploy, Auto-refuel and building actions.
- **Production tiles:** the name over the cost ("Cargo vehicle / 100 E · 20 I"). When the paying Depot can't afford it, the text turns amber and the tooltip says what's missing ("Needs 20 more iron…"). The tile stays clickable, and an unaffordable press still gets the existing refusal message.
- **Disabled with a reason:** Drop, Deploy/Pack supplies, Assign route, Pause and Cancel stay visible when unavailable, and their tooltip explains why.
- **Header:** the header buttons, including global Build, keep their positions and functions and pick up the theme.

## Not included

- **Card positions still shift:** the card shows only the actions a selection supports, so tile positions move between unit types. Fixed slots for every action would need empty placeholder tiles.
- **Supply panel:** its route controls are themed but otherwise unchanged. Phase E replaces them.

## Validation

- `tests/ui_theme_card_test.gd` (headless) checks:
  - the shared theme on every top-level HUD control;
  - an icon and matching key badge on every bound button;
  - the card order and short labels with tooltips;
  - tile height;
  - the Drop reason appearing and clearing;
  - affordable versus unaffordable production tiles;
  - global Build in the header.
- `tests/ui_card_runtime_check.gd` (rendered) uses real clicks on Infantry, a Tank and a Depot. Its screenshots are `infantry_card`, `tank_card` and `depot_card`.
- `hud_hotkeys_test`, `hud_hotkeys_runtime_check` and `review_fixes_test` now read keys from the badge instead of the label text. No other test was changed.
