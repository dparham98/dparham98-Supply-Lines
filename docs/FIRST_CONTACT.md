# First Contact — playable resource loop

Press F6 with scenes/maps/resource_skirmish.tscn open, or F5 to run the project. Restart Scenario resets the map and bank. F / Focus Depot returns the camera; the existing edge/arrow/zoom/rotation controls are shared.

1. Left-click the cyan infantry below the Depot. A green ring marks selection. Drag a box to select several infantry.
2. Right-click the marked orange Ore deposit to the left. Infantry approach on valid land, extract Ore, carry it to the Depot and repeat. Only delivered cargo becomes spendable; deselecting does not cancel work.
3. After 20 Ore is delivered, click Print Infantry. The cost is charged once; after 3 seconds the new unit appears at an open exit. A blocked exit waits with its paid order intact.
4. Select the new unit, then right-click the red Hostile above the Depot. It approaches and fires at range. Units defend while idle; enemies hold their ground and return fire.
5. A delivery, a completed print and a kill complete the scenario. If all infantry die without enough funds or a queued unit, restart.

Right-click open land to move. Right-click the Depot to return any carried Ore. Cargo is retained when changing orders and lost on unit death. A depleted deposit stops gathering; its last cargo is still delivered. Combat orders keep working while deselected. The old A attack-move action is not part of this scenario's controls.

## Edit and extend

- scenes/maps/resource_skirmish.tscn: current playable entry; authored terrain, camera, actors, resource and UI.
- scenes/maps/supply_lines_world.tscn: preserved terrain/legacy combat review scene.
- scenes/gameplay/infantry.tscn and hostile.tscn: health, speed, ranged combat and harvesting settings on root; replace imported models through Visuals > Model Scene.
- scenes/gameplay/depot.tscn: infantry scene, cost, duration, queue cap and footprint on root; Visuals model slot.
- scenes/gameplay/ore_deposit.tscn: amount and generic resource name.
- scenes/ui/skirmish_hud.tscn: saved UI layout, instructions and action buttons.
- scripts/gameplay: isolated scenario rules, unit state machine, resource, printer, HUD and tracer behavior.

Organizational parents must remain untransformed; units use ground pivots and flat Y=0 targeting. Terrain rules and source map are shared unchanged. The new scenario does not replace the old actor scripts or change the Blender file. Printed units instantiate the saved scene; static authored visuals never depend on procedural runtime mesh creation. Shot effects instantiate a reusable tracer scene.

Units claim their current/next grid cells, wait and replan around occupied routes, and release their claims when killed. This is a small grid-based prototype, not a full crowd solver; dense formations or narrow bottlenecks can stall. Resource/building approach searches a small set of nearby cells. Terrain blocks movement; ranged fire currently ignores terrain occlusion. No ammo, research, construction, recruitment animation or audio yet.

tests/skirmish_test.gd validates selection/context orders, unpaid production rejection, resource accounting, paid production, deselected movement/combat, a ranged kill, victory, queue cap, blocked exits, death-cell release and finite extraction. Existing terrain, camera and scene tests remain useful against the preserved review world. Costs are prototype choices; see RECOVERED_DESIGN.md.
