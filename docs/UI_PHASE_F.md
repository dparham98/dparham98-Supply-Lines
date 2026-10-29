# UI phase F: compact command grid and two-column info

This phase was added after D, on branch `feature/ui-compact-grid` from main `f5a2052`. It frees the horizontal space the command card used, ahead of phase E.

## Changes

- **Command grid:** `Commands/Main` is now a 4 × 3 grid of 46 px icon-only tiles, about 200 px wide (the command column is 212 px). Before, the card stretched across about 760 px.
  - Every command has a **fixed slot** (`SLOTS` in `skirmish_hud.gd`): Move top-left, Stop beside it, Attack, then Auto-refuel. Gather, Deliver, Drop and Build make the second row, and Repair, Capture, Deploy and Cancel the third.
  - Production and building actions reuse the slots from the top-left. Commands that never appear on the same card can share a slot.
  - Twelve authored empty slots (`Main/Slots`) stay dimmed, so the layout doesn't move between selections.
- **Labels and tooltips:** labels moved off the tiles and into the tooltip, along with the hotkey, the cost and any reason the action is unavailable.
  - A hover line under the grid repeats the hovered tile's tooltip, or names the armed command ("Attack · click a target. Shift queues, Esc cancels.").
  - The line's space is always reserved, so the bar doesn't jump.
- **Tile states:**
  - Unaffordable production tints the icon amber.
  - Auto-refuel off dims its icon.
  - Disabled tiles stay in their slot with a reason.
- **Build menu as a grid page:** Build opens the structure tiles (Depot, Generator, Barracks, Tank factory, Iron mine, Rail, then Back last) as icons in a 4-column grid, with name and cost in each tooltip. The payer list and local stock stay above the tiles.
- **Two-column info:**
  - `Info` keeps the identity, health, fuel and cargo bars, the round-trip warning and the notes.
  - The new `Context` column holds storage, production, the route, stats, abilities and the command hint.
- **Header:** global Build and the other header buttons are unchanged.

## Interim limits until phase E

- The Cargo route page (the Supply panel) is still about 616 px wide, so while it's shown the Context column is hidden and the notes add "Cargo N / M · Orders tab shows details". The Orders tab shows the full layout. Phase E replaces the route page with grid tiles.
- Build menu tiles have no hotkeys yet.
- The hover line sits above the build tiles on the build page.

## Test changes

- `tests/compact_grid_test.gd` (headless) checks:
  - the grid and column widths;
  - Info and Context side by side and wide enough;
  - every visible tile on its own fixed slot, with no labels on tiles;
  - 12 slots;
  - Tank tiles staying in place;
  - the hover line for an armed command;
  - the Build grid page (four columns, Back last, icon tiles, name and cost tooltips) and Back returning to the card.
- `tests/compact_grid_runtime_check.gd` (rendered):
  - uses real clicks on a Tank, a real hover over its Attack tile, Build, a Generator tile hover, Back and a Depot;
  - checks the HUD fits the window;
  - saves the screenshots `tank_grid`, `build_page` and `depot_grid`.
  - One click right after a screenshot capture is sometimes dropped by the window, so the check retries that one selection click.
- Updated my own earlier tests for labels moving into tooltips (`label_of`), the sections moving to `Context`, the Orders tab for Cargo panel checks, and the 250 px empty-HUD limit, which now includes the reserved hover line.
- No older test was changed. `storage_runtime_check` caught the route-page overflow, which led to the interim limit above.

## Revision after review (2026-10-29)

Feedback: the HUD and minimap changed size between selections, bars were too long, Depot storage belonged under health, stats needed icons and their own rows, and spare width could hold art instead of stretched information.

- **Fixed HUD height of 260 px** for every selection: nothing selected, Infantry, Tank, Cargo on either tab, Depot, the build page and mixed selections. Before this revision, heights ranged from 242 px to 297 px. To fit:
  - The command title line is hidden, since the name is already in Info.
  - The unit-type strip moved into the header row.
  - The route page's spacing is tighter, with a one-line route status, and the hover line is hidden there because that page has no tiles.
  - The build menu's stock line is one line.
- **Minimap:** a square 200 × 200 map inside an even 2 px frame with a 4 px margin (`MapColumn` is now a framed `PanelContainer`).
- **Info:** a fixed 300 px wide, so the health, fuel and cargo bars stay short.
  - Storage (Depot, Cargo vehicle and Train) moved back under the health bar in Info. It shows on the Cargo route page too, so the interim "Cargo N / M" note was removed.
- **Context:** a fixed 250 px wide. Stats are one row each, as icon, label and right-aligned value, with seven new icons: speed, damage, splash, cost, queue, cycle and mode.
- **Ornament:** spare width between Context and the grid is filled by `Ornament` (`scripts/ui/hud_ornament.gd`). It's a framed, hatched panel with corner ticks and a small emblem, and carries no information.
- **Tests:** `compact_grid_test` now asserts the fixed height and square map across selections, plus the fixed Info width. `hud_layout_test` expects exactly 260 px, and the panel tests read Storage from Info.
- **Flaky clicks:** in one full batch, three rendered checks (`command_queue`, `compact_grid` and `feedback_polish`) failed on a click or hover. All three passed in two reruns each, which matches the earlier cases of the real cursor interfering with the test window.
