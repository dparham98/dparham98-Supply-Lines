# Global pending construction

Implemented October 16, 2026 as the next usability milestone after mixed-unit selection. Work remains in the authoritative C:/Dev/Supply-Lines project. No GitHub or archive updates.

## Player controls and behavior

The bottom HUD header always offers Build, including when nothing is selected or no friendly Depot/funds are available. Its global menu offers Depot, Generator, Barracks, Tank Factory, Iron Mine and individual Rail plans. Existing Infantry/Depot local Build menus retain their immediate, explicitly paid construction behavior.

Choose a kind, then click valid unoccupied terrain anywhere on the map. An amber grid marks an unpaid plan; no energy/iron is spent or reserved. Water/forest/mountain, out-of-map footprints, occupied cells, existing rail and overlapping pending plans are rejected. Mines require a complete empty iron-deposit footprint with reserves. The cursor preview shows valid planning terrain in amber and invalid terrain in red. Successful placement exits placement mode; choose another kind to place another plan. Escape cancels the current placement without deleting existing plans.

The global payer menu explicitly defaults to Auto: nearest covering friendly Depot able to pay. It chooses one living, friendly Depot whose existing territory rules cover the complete footprint and whose local stock holds the entire cost. No pooled balances, hidden transfers, new resource grants or changed prices. Ties use the existing stable source ordering. You can instead pin future plans to one Depot. A pinned plan waits when that Depot is captured, destroyed, freed, uncovered or short of funds; it never silently changes payer. Payer choice is copied at placement, so changing the menu affects subsequent plans only.

Plans check readiness every 0.25 seconds. A new Depot, resource delivery or cleared footprint can make a plan ready. Completion revalidates coverage, ownership, terrain and full funds immediately before one atomic local payment, then instantiates the existing saved building/rail scene. Buildings use their existing grid claims, production, ownership and logistics. New Depots still grant exactly their establishment Infantry and preserve the enabled testing iron policy. Generator/production buildings assign their paying Depot for operation. Shared mines preserve shared ownership and ore reserves; rail registers with the existing network.

Unpaid plans have no physics shape, terrain claim or navigation reservation. Units can cross them. If a unit, direct construction or rail subsequently occupies a plan's site, it waits without spending until the site is valid again. Pending plans cannot overlap each other. Different ready plans are processed in scene order against live balances, so the same resources cannot fund two plans.

Click a plan's grid to inspect its status and cost, then Cancel construction plan to remove it for free. Focus selection works on plans. Clicking another unit, building or plan switches immediately out of the global menu/placement. Background completion leaves unrelated selection and menus alone; a selected completed plan becomes the completed building. Ordinary group selection, camera gestures, contextual orders and GUI click isolation remain intact.

## Exact changed files

- scripts/economy/depot_network.gd: plan specifications, validity/overlap checks, payer choice, atomic completion and planning preview integration.
- scripts/economy/construction_plan.gd (new): unpaid plan lifecycle, wait state, periodic readiness checks, selection transition and cancellation.
- scripts/gameplay/skirmish.gd: global placement mode and event routing.
- scripts/gameplay/skirmish_hud.gd: global/pinned payer menu, plan details and cancellation, and selection-safe menu visibility.
- scripts/units/selection_manager.gd: pending-plan picking and global placement selection precedence.
- scenes/gameplay/construction_plan.tscn (new): authored grid mesh/material and label; no runtime-generated actor/UI geometry.
- assets/shaders/construction_grid.gdshader (new): per-cell amber footprint grid using local mesh coordinates.
- scenes/ui/skirmish_hud.tscn: always-available header Build and contextual Cancel plan controls.
- tests/pending_construction_test.gd (new): construction/stockpile/ownership/navigation regression checks.
- tests/pending_construction_gui_test.gd (new): actual viewport mouse gestures for the global build workflow.
- docs/PENDING_CONSTRUCTION.md (new): this report.
- docs/EXPLICIT_DESIGN_BACKLOG.md: milestone status and remaining follow-ons.

Editor import may generate ordinary Godot .uid metadata for new scripts/shaders. Existing camera scripts, stats/resources, terrain/occupancy implementation, ownership rules, saved maps and local-construction entry points were not rewritten.

## Validation

Run these from PowerShell, substituting the test filename as needed:

```powershell
& C:/Dev/Tools/Godot_v4.7.2-stable_win64_console.exe --headless --path C:/Dev/Supply-Lines --script res://tests/pending_construction_test.gd
& C:/Dev/Tools/Godot_v4.7.2-stable_win64_console.exe --headless --path C:/Dev/Supply-Lines --script res://tests/pending_construction_gui_test.gd
```

pending_construction_test passes: unfunded and out-of-range plans, exact once-only payment, occupancy blocking/clearing, duplicate-plan prevention, invalid terrain/mine rejection, construction after new Depot coverage, pinned-payer isolation, enemy/dead/freed sources, free cancellation, no pooling, all six paid completions, rail registration, assigned operating Depots, establishment Infantry, and mine reserve/shared-ownership conservation.

pending_construction_gui_test passes headlessly and in rendered Vulkan on NVIDIA RTX 5070 Ti. It sends real press/release/motion events across multiple frames through Viewport.push_input, rather than emitting button signals. Checks global Build without selection/funds, UI click isolation, unpaid world placement, grid selection and Cancel, direct selection switching, process-driven completion after funding, preserving another selected unit, and Escape.

Also passed headlessly: hud_click_test, bottom_hud_test, skirmish_test, supply_test, depot_correction_test, engineering_batch_test, production_batch_test, rail_batch_test, mobile_supply_test, harvesting_batch_test, storage_batch_test, generator_batch_test, camera_test, edge_pan_test, unit_stats_test and selection_usability_test. Existing event tests still exercise local Build and immediate placement.

Native OS mouse input confirmed the playable main scene's global header button, out-of-range Generator plan, unchanged 500-energy/500-iron Depot balance, plan inspection/Focus, and cancellation. A final live session loaded the corrected per-cell grid and larger label. The final session is left open with one unpaid out-of-range Generator plan for inspection; this validation plan is runtime-only.

Logs live in the Supply Lines chat workspace: pending_test.log, pending_gui.log, pending_gui_rendered.log, pending_live_final.log and pending_<existing-test-name>.log. Rendered runs report the restricted runtime's existing shader-cache-folder warning; tests and rendering complete. Shader compilation, script parsing and the new workflows pass.

## Manual reproduction

1. Restart resource_skirmish.tscn. Deselect everything, then click header Build. Choose Generator and click valid land beyond your Depot territory: an amber cell grid appears, with no change in local resources.
2. Click the plan. Inspect its unpaid status; Focus moves the camera to it. Cancel removes it without a refund/payment because nothing was spent.
3. Create a plan within territory while the Depot lacks enough energy/iron. Deliver the missing resources: the plan completes automatically and deducts one full local cost.
4. Create a remote plan, then establish a friendly Depot whose territory covers it. With enough stock in that Depot, it completes without selecting Infantry. Verify Generator/production operation uses that payer; new Depots grant their one Infantry.
5. Choose a specific payer before placing. Keep it short of funds or capture it while another covering Depot is wealthy: the plan must wait. Cancel/recreate with Auto to change policy.
6. Move a unit onto a waiting site, then fund the Depot: no spending until the unit clears the footprint. Move through other unpaid grids to confirm no new collision/pathfinding blockers.
7. While global Build/placement is open, click another unit/building. Test mixed box selection, right-click group movement, minimap, Q/E/edge pan/zoom and ordinary local Build. UI clicks must not issue world commands or add extra plans.

## Remaining limits and next work

- Plans are match-local; no save/load system, construction timer, builder animation or terrain preparation was added. Completion remains instant once requirements hold, matching existing construction.
- Global plans use Depots only. Existing explicit Infantry construction from deployed mobile supplies remains available. Automatically using a deployed mobile stockpile without Infantry would change current construction prerequisites and is deferred.
- Plans may be placed on currently valid empty terrain, not on top of existing buildings/units or unsuitable terrain. If blocked after placement, they wait. They do not reserve resources or block pathfinding, so direct construction can take their space.
- Pinned payer cannot be edited on an existing plan in this milestone; cancel and recreate. Auto is an explicit opt-in/default mode, while existing local-build explicit payer semantics remain intact.
- No batch rail drawing, plan drag repositioning, area cancellation, queue priority UI, fog-of-war restrictions, large-plan-count performance certification or multiplayer authority system.
- Next: permit route assignment between any two controlled Depots independent of the vehicle's current coverage, preserving capacity, ownership and valid path/rail connectivity.
- Next: reachable perimeter approach cells for all-side harvesting and Depot delivery; validate collisions, reservations and resource conservation separately from click bounds.
