# HUD phase 3: command queue

Phase 3 of the approved HUD plan, on branch `feature/command-queue` from main `94a4717`. These are new controls, not recovered design.

## Controls

- **Shift-right-click** adds the right-click order to each selected unit's queue. This uses the same choice of attack, gather, deliver, repair, capture or move as a plain right-click.
- **Shift-click with an armed card command** (Move, Attack, Gather, Repair, Capture) queues it and keeps the command armed for more targets. A plain click or Esc ends it.
- A **plain order** (right-click, card command, Deliver) replaces the queue.
- **Stop** clears the queue.
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

## Waypoint markers

- `WaypointMarkers` in `resource_skirmish.tscn` pools instances of the authored `scenes/gameplay/waypoint_marker.tscn`: a yellow disc with a number.
- It shows the current destination as 1 and each queued destination after it, for selected player units only. Markers renumber as the queue advances and disappear when the unit is idle or deselected.
- Markers sit on the ground plane (y = 0), like other ground-plane picking, and have no connecting lines.

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
  - marker counts, numbering and hiding;
  - the Cargo refuel rate.
- `tests/command_queue_runtime_check.gd` (rendered) uses a real selection click and three real Shift-right-clicks. Its screenshots are `queue_markers` and `queue_progress`.
- Needs a human playtest.
