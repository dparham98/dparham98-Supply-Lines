# Team markers

The visual audit of the balanced map found that units are small dark shapes at play zoom, and nothing on them says whose they are. A unit made by an enemy-held Depot looks exactly like yours.

Every unit now stands on a flat rounded marker on the ground, in its side's colour: a solid rim with a faint fill. Player units are green, enemy units red and neutral units grey. These are the colours the map overlay and minimap already use, now kept in one place, `scripts/units/team_colors.gd`.

## How it is built

- `assets/shaders/team_marker.gdshader` draws the shape: a rectangle with fully rounded ends, so round units get a circle and long vehicles an oblong.
  - The rim is 0.16 m wide, and never thinner than about 1.5 pixels when zoomed out.
  - The shader is unshaded and transparent, casts no shadow and writes no depth.
  - Two per-instance settings drive it: `team_color` and `half_size`.
- `assets/materials/units/team_marker.tres` is the one material every marker shares.
- Each unit scene in `scenes/gameplay` has a `Visuals/TeamMarker` node, saved in the scene and visible in the editor.
  - It holds a `PlaneMesh` sized to the model, with `half_size` set to half the mesh size.
  - It sits under `Visuals`, so it turns with the unit.
  - It is tagged `not_selectable`, so it takes no part in picking, outlines or shot aim points.
- `unit_agent.gd` sets `team_color` when the unit is ready, and again whenever `team` changes after that. It changes only that one setting; nothing is created at runtime.

| Unit | Marker (m) | Notes |
| --- | --- | --- |
| Infantry | 1.7 × 1.7 | |
| Scout, Grenadier | 1.5 × 1.5 | |
| Hostile, Ubermech | 2.0 × 2.0 | |
| Motorcycle | 1.4 × 3.0 | |
| Drone | 2.6 × 2.6 | Just under the drone at 12 m, not on the ground: on the ground it showed well below the drone on screen, on top of other units' markers |
| Tank | 4.0 × 6.8 | Centred 0.4 m forward of the unit's origin |
| Cargo vehicle | 2.4 × 5.4 | |
| Depot Truck | 3.8 × 15.8 | |
| Train | 2.8 × 7.2 | 0.4 m up, on the track bed |

The legacy scenes in `scenes/units` (used only by `supply_lines_world.tscn`) are unchanged.

## Team paint on the models

Some surfaces of the models are painted in the unit's side colour too. The paint is darker than the marker colour, so it sits with the rest of the model: green `team_paint_player.tres`, red `team_paint_enemy.tres` and grey `team_paint_neutral.tres` in `assets/materials/units`.

- `scripts/components/team_paint.gd` finds every surface whose imported material is named `team_color`. It also takes the names listed in the model root's `team_materials` metadata. It sets the side's saved paint as that surface's override; nothing else on the model changes.
- `unit_agent.gd` calls it with the marker, so the paint follows the side in the same way. A corpse keeps the paint it died with.
- The player's units were trimmed in oxblood red, the colour that marks the enemy everywhere else. Those trims are now team paint.

| Model | Painted surfaces |
| --- | --- |
| Cargo vehicle, Depot Truck, Train | `team_color` (truck cab, bed and lid; Depot Truck bulkhead and floors; train body) |
| Motorcycle | `team_color` (faction fangs) and `moto_oxblood` (frame and rider's jacket) |
| Drone | `team_color` (faction fang) and `Oxide red` (arms and ducts) |
| Scout | `Scout red trim` (armour and skates) |
| Grenadier | `Oxblood trim` |
| Infantry, Tank, Ubermech, Hostile | None: there is no team surface to paint |

At play zoom the paint reads clearly on the Cargo vehicle, Depot Truck and Motorcycle, and less on the Drone. On the Scout and Grenadier the trims are too small to tell apart, so the ground marker still does most of the work there.

## Health bars

Health bars already exist in `MapOverlay` (`docs/UI_PHASE_C.md`) and are drawn in the team colour. They show while a unit is damaged, selected or hovered, or while **Alt** is held, so a fresh army shows none. This change does not alter that rule.

## Checks

- `tests/team_paint_test.gd` (headless) checks:
  - each painted model, on both sides, has its team surfaces in the side's paint and no other surface overridden;
  - the unpainted models are left alone;
  - an unknown side is painted neutral.
- `tests/team_marker_test.gd` (headless) checks every unit scene:
  - it has the marker, with the shared material;
  - the marker's size matches its mesh;
  - it sits at ground level (the Drone's just under it);
  - it is left out of picking and casts no shadow;
  - its colour matches the unit's side, including a unit made for the enemy.
- It also checks that the map overlay uses the shared colours.

## Not yet done

- Infantry and the Tank carry no team paint. The Infantry has no accent material to give it, and the Tank's look is one baked texture. Both need team surfaces made in Blender: a separate `team_color` material for the Infantry, and a team mask for the Tank.
- The Scout's and Grenadier's trims could be made larger in Blender to read at play zoom.
- Buildings have no marker.
- Markers are hidden under trees and rock like everything else at ground level.
