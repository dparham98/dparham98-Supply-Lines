# HUD phase 4: layout

Phase 4 of the approved HUD plan, on branch `feature/hud-layout` from main `57627b9`. Every node path that existing scripts and tests use is kept. The changes are layout properties and new authored nodes.

## Changes

- **Shorter bottom bar.** The base height is 232 px instead of a fixed 300 px.
  - Changes: minimap 176 px, card buttons 30 px, tighter spacing, details text 13 px.
  - The bar grows upward to fit its content. Measured at 1280×900: nothing selected 232 px; Infantry 274 px; Tank about 380 px (it has the longest details); Cargo route page 356 px, the same as main.
- **Status bars** under the health bar (`Info/Bars`).
  - Fuel, for vehicles that use fuel: green normally, amber below 25%, red when empty.
  - Cargo, for Infantry and Cargo vehicles.
  - Health, fuel and cargo bars share a visible track style. The text details are unchanged.
- **Type strip** (`Bottom/Body/Selection`).
  - With more than one unit selected, it shows one button per unit type, for example `Infantry ×2`. Click keeps only that type; Shift-click removes it.
  - It uses eight authored buttons.
- **Alert feed** (`Feed`, top right).
  - Shows up to four positioned alerts from the last 45 s, newest first. Click one to centre the camera there.
  - Alerts come from `skirmish.alert(text, position, key)`:
    - a player vehicle running out of fuel;
    - a player unit being lost;
    - a player building being shot by an enemy, at most once per building every 10 s.
  - The header message line is unchanged.
- **Cargo pages.**
  - Cargo vehicles and Trains get `Orders` and `Delivery route` tabs in the header row, which costs no extra height.
  - Selection opens on the route page, as before. `Orders` shows the regular command card: Move, Stop and Auto-refuel.

## Not included

- The details text is still the full list. Replacing more lines with bars or icons would change strings the existing tests check, so it needs its own pass.
- There are no unit portraits or icons. The strip uses text labels.
- Alerts don't play sounds, and the minimap doesn't mark alert locations.

## Validation

- `tests/hud_layout_test.gd` (headless) checks:
  - bar heights;
  - bar visibility, values and fuel colours;
  - strip buttons and labels, click narrowing and Shift removal;
  - feed ordering, throttling and click focus;
  - the out-of-fuel, unit-lost and building-attack alerts;
  - the cargo page default, the Orders page and the reset on reselect.
- `tests/hud_layout_runtime_check.gd` (rendered) uses real clicks on a Shift-added mixed selection, the strip, a feed entry and the Orders tab. Its screenshots are `mixed_selection`, `tank_bars` and `cargo_orders`.
- All existing headless and rendered checks pass unchanged, except the known `mobile_supply_runtime_check` failure.
  - An early layout put the tabs on their own row. That made the cargo bar 37 px taller, and `mobile_supply_runtime_check` then failed at an earlier step ("Move GUI did not pack supplies") because its world click landed on the HUD.
  - The tabs moved into the header row, and the check is back to its old failure point.
- Needs a human playtest.
