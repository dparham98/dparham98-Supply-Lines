# Build page, hint tooltips and map picking

Quality-of-life changes requested after PR #17. They replace parts of [PLAYTEST_FIXES_2026_10_29.md](PLAYTEST_FIXES_2026_10_29.md) and [UI_PHASE_F.md](UI_PHASE_F.md) (the hover line and the `OptionRow` pickers).

## Building

- **Global Build is B** (was N). On the build page B places Barracks, so the header Build button is disabled while the page is open: B, B builds Barracks.
- **No local build menus.** Infantry and Depots lost their Build tile and page. Everything is built through the header Build page as plans ([PENDING_CONSTRUCTION.md](PENDING_CONSTRUCTION.md)). Depots still print Depot trucks, Cargo vehicles and Trains.
- **Deployed Cargo vehicles pay plans** inside their supply radius, as Infantry building from truck stock did before. That includes deployed Trains, which are mobile supplies too. Rails still need a Depot. A Generator or production building paid by a vehicle starts with no assigned Depot; assign one from its Context column.
- **Rail stays armed** after each plan so a line can be laid tile by tile; Esc or right-click finishes.
- **Pin payer (P)** replaces the build page's payer dropdown:
  - unpinned, each plan pays from the nearest covering stockpile able to pay ("PAYS: AUTO");
  - Pin opens the map prompt; clicking a Depot or deployed Cargo vehicle on the map or minimap makes new plans pay only from it;
  - pressing Pin again returns to Auto. Existing plans keep the payer they were placed with.

## Hints

- The selection's hint no longer has a line in the Context column. It's the tooltip of the Info and Context columns.
- The hover line under the grid is gone. Each tile's name, key and detail are in its tooltip.
- Tooltips open after 0.25 s (`gui/timers/tooltip_delay_sec`).

## Picking a stop on the map

The dropdown row above the command card is removed, both the distant-stop list and the Infantry "Pay from, deliver to" picker.

- **Load and Unload** replace the card with a prompt and a Cancel tile (Esc). Eligible stops pulse on the minimap:
  - left-click a Depot (or deployed Cargo vehicle, for trucks) on the map or its minimap marker;
  - a crate, or open ground for Unload, still works on the map;
  - Shift queues and keeps the prompt;
  - right-click on the map or minimap cancels.
- Right-click now cancels **any** armed command or placement instead of giving an order.
- **Workers** always pay from and deliver to the nearest covering stockpile, unless you right-click a specific Depot. Their notes name it. Repairs without an explicit payer use the nearest stockpile covering the worker, as the removed picker did by default.

## Notes

- `DepotNetwork.construct*`, `bind_builder` and the game's `placing_*` flags still exist and are used by economy tests, but no UI reaches them now.
- The pick prompt sits where the card was, so the HUD keeps its fixed 260 px height.

## Validation

- Headless: `bottom_hud_test` (no Build tile, hint tooltips, Pin by map pick, minimap Load pick, right-click and Cancel), `playtest_fixes_test` (B and Pin keys, prompt position), `mobile_supply_test` (truck-paid Depot plan, no truck-paid rail), plus the build and stop steps of the other GUI suites moved to the Build page and map picking.
- Rendered: `rail_runtime_check` clicks a minimap marker for Load and saves `rail_pick_prompt`; `compact_grid_runtime_check` waits for a tile tooltip before `tank_grid`; `mobile_supply_runtime_check` pins payers by clicking them on the map.
- Not playtested by a human.
