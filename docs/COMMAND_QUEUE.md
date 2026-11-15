# HUD phase 3: command queue

Phase 3 of the approved HUD plan, on branch `feature/command-queue` from main `94a4717`. These are new controls, not recovered design.

## Controls

- **Shift-right-click** adds the right-click order to each selected unit's queue. This uses the same choice of attack, gather, deliver, repair, capture or move as a plain right-click.
- **Shift-click with an armed card command** (Move, Attack, Gather, Repair, Capture) queues it and keeps the command armed for more targets. A plain click or Esc ends it.
- A **plain order** (right-click, card command, Deliver) replaces the queue.
- **Stop** and **Drop materials** clear the queue.
- Queuing on an idle unit starts the order at once.

## Rules

- `UnitAgent.order_queue` holds `{kind, target, point}` entries. When the unit's order becomes idle, the next entry starts in the same frame.
- When each order counts as finished:

  | Order | Finished when |
  | --- | --- |
  | Move | the unit arrives, or no route exists |
  | Attack | the target dies or can no longer be hit |
  | Repair | the building reaches full health, or the target is lost |
  | Capture | the building is captured, or the target is lost |
  | Deliver | the cargo is unloaded (unless it resumes a gather) |

- **Gather never finishes** while the source lasts, because it loops between gathering and delivering. Orders queued behind it wait, so queue gather last. Delivering to a selected Cargo vehicle behaves the same way.
- Entries whose target is gone, or that the unit refuses, are skipped.
- **Out of fuel** pauses the queue without dropping it. It resumes once the vehicle has refuelled.
- Assigning a supply route clears a Cargo vehicle's or Train's queue. Repeating routes never go idle.

## Queue path

- Queued orders show as a yellow dashed line on the ground. It runs from the unit through its current destination and then each queued destination in order. It replaced the numbered disc markers on 2026-11-15.
- It is drawn for selected player units that have at least one order queued. A single order with nothing queued shows no line. The line shortens as the queue advances and goes when the queue empties or the unit is deselected.
- The HUD's map overlay draws it (`queue_lines()` in `map_overlay.gd`), in screen space beside the dashed Cargo route lines, so it is drawn over models and stays visible. The old `WaypointMarkers` node and `waypoint_marker.tscn` are removed.

## Fix included

- An idle or manually driven Cargo vehicle or Train ticked fuel twice per frame (once itself, once in `UnitAgent`), so it refuelled at double the configured rate. `_skip_fuel_tick` now prevents the second tick.
- A regression check measures 5 coal per second; it read 10 per second before the fix.

## Validation

- `tests/command_queue_test.gd` (headless) checks:
  - starting immediately when idle, Shift-right-click through `issue_order`, order sequencing, reaching each waypoint, and finishing;
  - plain replacement and Stop;
  - attack finishing on a kill, freed targets being skipped, and gather holding the queue;
  - Shift card orders staying armed;
  - out of fuel pausing and then resuming;
  - a route assignment clearing the queue;
  - the dashed path's points and dashes, and no path for an idle or stopped unit;
  - the Cargo refuel rate.
- `tests/command_queue_runtime_check.gd` (rendered) uses a real selection click and three real Shift-right-clicks. Its screenshots are `queue_path` and `queue_progress`.
- Needs a human playtest.
