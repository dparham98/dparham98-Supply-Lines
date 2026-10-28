# Selection usability milestone

Implemented October 16, 2026 in C:/Dev/Supply-Lines after inspecting AGENTS.md, the referenced Camera movement fix conversation, current milestone/backlog reports, the selection autoload, skirmish input, HUD/menu state, camera controls, visual slots and existing occupancy/navigation methods.

## Behavior

- Left-drag at least 6 viewport pixels to select all friendly units whose projected visual bounds overlap the rectangle, including mixed types. Either drag direction works. Buildings and enemies are excluded. A translucent rectangle appears while dragging; each selected unit retains its existing selection feedback. A click replaces selection; empty clicks clear it.
- Right-click issues the existing context order to all selected units. Move card also applies to all selected units. Each unit retains its own movement layer, occupancy, reservation and routing rules. Trains still require friendly rails; deployed vehicles pack through their existing movement behavior. Unsupported orders remain ignored by the individual unit controller.
- Group HUD shows the number selected. Details and contextual controls use the first selected unit; supported group commands still iterate the selection.
- Clicking another actor while Build is open selects it and closes Build without Back. Clicking an actor while construction/rail placement or Move targeting is armed selects it and cancels that mode before spending construction resources. Ordinary context/supply panels follow selection immediately.
- Explicit Attack/Gather/Repair/Capture target modes retain their target click so those gameplay actions remain usable; Escape cancels targeting. These are targeting modes, not open menus.
- World selection starts only from unhandled left-button input. A release over GUI cancels the world drag. GUI-origin presses do not start selection or issue world orders. Keyboard input, other mouse buttons (including camera wheel/middle gestures), and window focus loss cancel a pending drag. Maximum travel determines drag versus click even when the pointer returns toward its start. Camera and edge-pan scripts are unchanged.
- Click picking casts a camera ray against each visible mesh's local AABB under the actor's Visuals slot, transforming the ray into mesh space. It selects the nearest hit, replacing arbitrary 28/50-pixel circles. Depot foundation edges, rotated/scaled model pieces and other actor model slots are included. Labels, selection rings, territory rings and status indicators outside Visuals are excluded. The same helper supplies context-order picking and projected drag bounds.
- Physics shapes, terrain cells/claims, collision, route assignment, stats, ownership and logistics were not modified.

## Exact changed files

1. scripts/units/selection_manager.gd — visual-bound picking, mixed box selection, menu switching and gesture cleanup.
2. scripts/units/selection_bounds.gd — new reusable visual picking/projected bounds helper.
3. scripts/gameplay/skirmish.gd — placement/Move selection precedence and shared context picking.
4. scripts/gameplay/skirmish_hud.gd — saved rectangle updates and group count/hint.
5. scenes/ui/skirmish_hud.tscn — authored noninteractive rectangle Panel and style.
6. tests/selection_usability_test.gd — new event-driven regression test.
7. docs/SELECTION_USABILITY.md — this report.
8. docs/EXPLICIT_DESIGN_BACKLOG.md — milestone status and requested follow-ons.

Godot may generate .gd.uid/import metadata when the project is next imported in the editor. No GitHub or archived project workflow was used.

## Automated validation

Use the installed executable C:/Dev/Tools/Godot_v4.7.2-stable_win64_console.exe. For example, from PowerShell:

```powershell
& C:/Dev/Tools/Godot_v4.7.2-stable_win64_console.exe --headless --path C:/Dev/Supply-Lines --script res://tests/selection_usability_test.gd
```

The new test passes both headlessly and rendered with Vulkan/NVIDIA RTX 5070 Ti. It pushes mouse events through the viewport, verifies mixed Infantry/Scout selection, group move orders plus actual navigation progress and separate occupancy cells, reverse drag gestures, Depot foundation edge picking, switching out of armed construction without payment, UI right-click isolation, release-over-UI cancellation and middle-button cancellation. It stops background processing for deterministic checks.

Also passed: hud_click_test (headless and rendered), skirmish_test, terrain_test, camera_test, edge_pan_test, bottom_hud_test, supply_test, depot_correction_test, unit_stats_test, rail_batch_test, mobile_supply_test, engineering_batch_test, combat_batch_test and harvesting_batch_test. Run any by substituting its filename in the command above. Remove --headless for rendered event validation. Renderer emitted a shader-cache-folder warning under the restricted runtime; rendering and tests completed successfully. Logs are in the Supply Lines chat workspace, including selection_final.log, selection_rendered.log and hud_rendered.log.

## Live desktop validation and manual reproduction

Native desktop mouse input confirmed in the playable main scene: Infantry selection; opening Build; clicking the Depot foundation edge to switch directly and close Build; using the Depot Cargo button; drag-selecting Infantry and newly printed Cargo together (HUD displayed 2 friendly units); right-clicking open land (both entered movement and visibly moved). This was native OS input, in addition to the automated viewport events. The running game is left open for inspection; this test session spent one Cargo production cost only in runtime memory.

1. Restart/play resource_skirmish.tscn. Print Cargo, or produce other friendly unit types.
2. Drag a box around different friendly types in both directions. Check group count and highlights; right-click open land. Verify rails still constrain any selected Train.
3. Select Infantry, open Build, click Depot foundation corners/edges or a different unit. Repeat after arming Generator placement. Selection should switch, menu/preview close, and stocks remain unchanged.
4. Use Move, Attack, Repair and Capture cards with appropriate targets. Confirm targeted actions still work and Escape cancels them.
5. Click buttons and blank HUD areas with left/right buttons. Start a world drag and release over HUD; then click elsewhere. Check no world order or stale rectangle occurs. Try middle-button/wheel/keyboard camera actions during a drag.
6. At different zoom/yaw settings, click actual model parts rather than labels, and confirm nearby empty ground does not select them. Recheck edge pan, Q/E orbit/release, wheel zoom, production, gathering and delivery.

## Remaining limits and follow-ons

- Mesh AABBs approximate visible mesh pieces rather than exact triangles/skinned silhouettes. Picking does not perform terrain/prop occlusion testing; actors behind scenery can still be selected. Replacing art automatically changes bounds; very detailed models may need a cached/custom pick proxy later.
- Box overlap uses projected mesh rectangles; this is intersection selection rather than full containment. No Shift-add/toggle selection or control groups in this milestone. Box selection is available in ordinary selection mode; armed construction retains empty-ground placement semantics.
- Group movement shares a destination and existing per-unit nearest-free-cell routing. No formation planner, synchronized arrival or new crowd solver. First-selected contextual controls may omit abilities belonging only to other selected types; right-click movement remains available to the group.
- Large-army picking performance and every imported animation pose were not certified. Live testing covered Infantry/Cargo; deterministic mixed-unit navigation covered Infantry/Scout and existing rail tests covered Train restrictions.
- Next: global Build button with unpaid pending footprints until friendly local supply/resources reach them; no pooling or premature spending.
- Next: allow assigning routes between any two controlled Depots independent of current vehicle coverage, while retaining ownership, capacity and valid movement/rail connectivity checks.
- Next: all-side harvesting and delivery using reachable perimeter approach cells for resources and Depots, with collision/reservation and conservation tests. Selection bounds do not alter those approach rules.
