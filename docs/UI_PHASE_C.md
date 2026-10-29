# UI phase C: map status

Phase C of `UI_OVERHAUL_PLAN.md`, on branch `feature/ui-map-status` from main `44851c1`.

## Approach (differs from the plan)

The plan called for a reusable status scene placed in each actor's scene. Instead, one screen-space overlay (`MapOverlay` in `skirmish_hud.tscn`, script `scripts/ui/map_overlay.gd`) draws every mark in a single pass, the way the minimap already draws its markers:

- Bars stay the same size on screen at every zoom level.
- The roughly 20 actor scenes are untouched, and their authored labels stay visible in the editor.
- The overlay hides each actor's always-on `Label3D` text (Status, Cargo, Label, Progress) when the game runs. Placement ghosts and waypoint numbers keep their labels.

## What appears, and when

| Mark | When |
| --- | --- |
| Health bar in the team colour | Damaged, selected or hovered, or **Alt** held |
| Name above the bar | Alt held |
| Production progress (teal, no text) | Depot or production building with something queued |
| Carried cargo (resource colour) | Infantry carrying materials |
| Storage nearly full (amber) | Depot or deployed Cargo vehicle at 90% or more |
| Under attack (red) | For 3 s after each hit |
| Generator paused (amber) | Generator disabled |
| Exit blocked (amber) | A finished unit waiting for a free exit cell |
| Mine depleted (grey) | No iron left |
| Low fuel (amber) or out of fuel (red) | Fuel-using vehicles |
| Capture ring in the capturing side's colour | A Depot being captured |
| Dashed route line with an arrow | A selected Cargo vehicle or Train on a route |
| "+10 iron" pop-up, rising and fading over 1.5 s | Infantry deliveries and Cargo unloading |
| Hover card | Pointer over a unit, building, resource, pile, deposit or plan |

The hover card shows the name, the owner and health, and either the remaining amount or storage, with a small meter.

Alt is the Input Map action `map_show_all`.

## Supporting changes

- `skirmish.gd`:
  - `mark_attacked` and `recently_attacked`, with times pruned beyond 64 entries.
  - `delivered(target, kind, amount)` and the `resources_delivered` signal.
- `unit_agent.gd` marks hit targets and reports deliveries. `cargo_vehicle.gd` reports unloading.
- `production_building.gd` exposes `exit_blocked`.

## Not included

- Construction plans: there's no dashed footprint outline. They show through the hover card and a health bar on hover.
- Territory and supply rings are unchanged; they already show on selection.
- Click pings, target highlights and hover rings, which are phase D.

## Validation

- `tests/map_status_test.gd` (headless) checks:
  - labels hidden at runtime;
  - the health bar rules (full health, damaged, selected, hovered, Alt);
  - progress only while producing;
  - the storage warning at and below 90%;
  - the under-attack window;
  - the capture ring;
  - the depleted mine;
  - the carry bar;
  - the low-fuel icon;
  - the route line only for a selected routed vehicle;
  - picking the hover target and the Depot and pile hover cards;
  - a delivery pop-up from a real Infantry delivery.
- `tests/map_status_runtime_check.gd` (rendered) uses a real click on a routed truck and a real pointer over the Depot. Its screenshots are `map_status` and `map_show_all`.
