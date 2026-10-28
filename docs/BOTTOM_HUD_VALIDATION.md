# Bottom HUD validation — October 15, 2026

Godot 4.7.2 stable on Windows. Final headless scene import and runtime startup completed without errors. The following checks returned exit code 0 and their explicit pass markers after relevant fixes:

| Check | Result |
| --- | --- |
| tests/bottom_hud_test.gd | BOTTOM_HUD_CHECKS_PASSED |
| tests/skirmish_test.gd | SKIRMISH_CHECKS_PASSED |
| tests/supply_test.gd | SUPPLY_CHECKS_PASSED |
| tests/depot_test.gd | DEPOT_CHECKS_PASSED |
| tests/unit_stats_test.gd | UNIT_STATS_CHECKS_PASSED |
| tests/terrain_test.gd | TERRAIN_CHECKS_PASSED |
| tests/camera_test.gd | CAMERA_CHECKS_PASSED |
| tests/edge_pan_test.gd | EDGE_PAN_CHECKS_PASSED |
| tests/bottom_hud_runtime_check.gd | BOTTOM_HUD_RENDER_CHECK_PASSED |

The new targeted test verifies removal of side panels; selected Depot/unit/generator names and live HP; local production costs; infantry build-menu stock, payer and eligibility; placement through a synthetic mouse event delivered to the actual game handler; selection protection while placing; exact generator payment and recipient; no spending outside builder territory; explicit overlapping-Depot choice; no rich-neighbour fallback when the selected payer is captured; generator selection and damage display; cargo route assignment through the command-card button; minimap coordinate mapping and synthetic click changing camera focus while preserving selection; Move/Attack/Gather targeting; Stop; and safe HUD clearing on selected-building removal.

Existing tests continue to cover local economy/capture/truck deployment, actual cargo path travel and inventory conservation, gathering/printing/ranged fallback combat, unit resources, terrain occupancy/pathing, camera geometry/focus and edge-pan policy. Economy test fixtures now hold a strong reference to their normal inventory configuration in memory, overriding the sandbox iron grant only for their process. This does not change the on-disk 500-iron grant. Initial attempts exposed the need to hold that reference across scene loading; all three economy fixtures passed after correction.

Rendered checks inspect Depot production, infantry orders, infantry local-resource build menu and cargo delivery controls at 1280 × 900, plus cargo layout at 1440 × 960. Images were visually inspected for clipping, legibility, minimap terrain/markers and retained world rendering. Screenshot files and logs are in the chat workspace: bottom_hud_depot.png, bottom_hud_infantry.png, bottom_hud_build.png, bottom_hud_cargo.png, bottom_hud_wide.png, bottom_hud_runtime.log and bottom_hud_runtime_errors.log. Setup and selection use script calls; no physical mouse/keyboard or desktop editor interaction was performed. Synthetic input tests do not certify live mouse feel, interactive popup behavior or physical screen-edge scrolling.

Limits and explicit decisions: minimap is a full-map north-up overview without fog of war or tactical zoom; markers can overlap. Group details show the primary unit and an additional selection count. The new layout is visually checked at the sizes above; smaller windows may crowd it. Infantry builds instantly anywhere valid within its explicitly chosen local Depot territory while remaining inside that territory; no construction duration or builder travel was introduced. Other units are not granted engineering. Depot Trucks retain deployment only, cargo vehicles retain transport only. Building health is provisional (Depot 1000, generator 300), with damage/removal support but no new enemy targeting, repair or building attack commands. HUD now allows edge panning through its interactive area via the existing passthrough metadata; button click handling remains unchanged. Camera/path methods and terrain assets were not modified. No scene-baker test was run because it rewrites unrelated generated terrain scenery.

See BOTTOM_HUD.md for editor testing and exact mechanics, and BOTTOM_HUD_CHANGED.txt for files changed and new generated UID files. Ignored .godot cache is excluded. Before-change copies of existing edited files are in the chat workspace bottom_hud_before folder.


## Subsequent GUI click correction

A reported inability to click Build/Depot commands was reproduced with multi-frame pointer press/release events. The per-frame hide/show cycle cancelled button gestures; direct signal tests missed it. Fixed by applying final visibility once per frame. tests/hud_click_test.gd now passes in both headless and rendered sessions and covers all three Depot production buttons, infantry Build, actual generator/Depot placement clicks, Back, Move and cargo route controls. Bottom HUD, skirmish and supply regressions also passed after this correction. This is simulated GUI input, not physical mouse testing. See HUD_CLICK_FIX.md.


## HUD edge-pan passthrough

Enabled edge_pan_passthrough on the bottom HUD root, so the existing camera ancestor check permits edge panning over its children, including the minimap and buttons. Mouse filters remain unchanged so clicks still reach the GUI. The existing edge-pan test now verifies the saved bottom HUD metadata in addition to edge vectors/navigation. Edge-pan, camera and full multi-frame GUI-click checks passed after this change. No physical mouse test was performed. Files changed: scenes/ui/skirmish_hud.tscn, tests/edge_pan_test.gd, docs/BOTTOM_HUD.md, docs/BOTTOM_HUD_VALIDATION.md and docs/BOTTOM_HUD_CHANGED.txt.
