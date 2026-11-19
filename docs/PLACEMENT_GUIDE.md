# Placement guide

While you lay rail or place a building, a panel at the top centre of the screen says what to do next. Nothing
follows the cursor. Asked for in the playtest of 2026-11-18: the reminder should be conspicuous and easy, with a
diagram on the HUD where it helps. The labels that floated over the cursor before are gone.

## Laying rail

**LAY RAIL** shows the three steps as a diagram:

| Step | Shown as |
| --- | --- |
| **1 Click the start** | lit until the first pick |
| **2 Click the end** | lit until the second pick |
| **3 Shape it, click to lay** | lit while the track follows the cursor |

- **Steps done** turn green; steps still to come are dimmed.
- **Under the steps:** the line about the track (for example "14 PIECES · 252 IRON · CLICK LAYS IT"), then the keys
  (Backspace takes back a pick, Enter lays it, Esc cancels).

## Placing a building

**PLAN BARRACKS**, **PLACE DEPOT**, **DEPLOY THE DEPOT** and so on show the footprint colours as a key:

| Colour | Means |
| --- | --- |
| Green | builds here |
| Yellow | short of stock |
| Red | can't go here |

- **The colour under the cursor is lit**, so the key always matches the footprint.
- **Under the key:** the line about the spot (cost, payer, stock in range, or why it is blocked), then the keys.

## Where it sits

- **Position:** top centre, 600 px wide, between the Depot panel (top left) and the storage panel (top right).
- **Clicks:** it never takes clicks, so they reach the map beneath it.

## Code

- **Scene:** the panel is `Guide` in `scenes/ui/skirmish_hud.tscn`, with styles `guide_card` and `guide_step`.
- **HUD:** `skirmish_hud.update_guide()` fills it every frame from `RailNetwork.route_status()` and the rail picks,
  or from `DepotNetwork.placement_title`, `placement_text` and `placement_state`.
- **Placement data:** the previews set those three in `_set_placement`. `DepotNetwork.placement_active()` says
  whether something is being placed.
- **Removed:** the `Status` labels on `RailPreview` (all four maps) and on `construction_preview.tscn`.

## Checks

- `tests/placement_guide_test.gd` (headless) covers:
  - no cursor labels left;
  - the guide hidden when idle;
  - the rail steps lighting in turn;
  - the placement key lighting the state under the cursor;
  - clicks passing through.
- `tests/placement_guide_runtime_check.gd` (rendered) checks the guide sits at the top centre clear of the side
  panels, and saves `guide_rail_start`, `guide_rail_lay` and `guide_place`.
