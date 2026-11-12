# Pathing, turning and ranges

## Smooth paths

Routes are still found on the 1 m grid with A* (`terrain_grid.gd` `actor_path`, diagonals only past open corners). Units no longer walk them cell centre to cell centre. `unit_agent.gd` `_walk` instead heads for the farthest route cell it can reach in a straight, clear lane:

- **The aim:** of the next 32 route cells (`AIM_LOOKAHEAD`), the last one first, then a halving search for the farthest one reachable in a straight lane. A lane is clear when every cell under the line, and 0.35 m either side of it (`LANE_HALF_WIDTH`), is open to the unit. This keeps runs off building corners and out of diagonal gaps.
- **Re-aiming:** the aim is chosen again each time the unit crosses into a new cell, and when it reaches the aim. On open ground a unit within 32 cells of its goal walks one straight line to it. Longer routes bend gently toward the goal.
- **Fallback:** when even the next cell is out of a straight lane (a unit stopped off centre beside an obstacle), it goes back through its own cell's centre first.
- **Cells held:** a unit claims each cell as it crosses into it and lets go of the one it left, so it holds exactly the cell it stands in. If the next cell is taken by then, it stops at the edge, waits half a second and plans again, as before.
- **The end:** the route's last cell is reached exactly on its centre, including goals on an interaction radius.
- **Kept:** `_moving_to` is the cell being headed for, so the order loop, cargo trucks and the Train (which has its own rail walk) are unchanged. Fuel, forest clearing and moving fire work as before.

## Turning

A travelling unit turns its body toward the way it is going at its turn rate, rather than snapping:

- At full speed within 20 degrees of the heading, slowing in proportion beyond that, and turning on the spot at 90 degrees or more.
- **Turn rates** (degrees a second): `turn_rate` on `UnitStats` (`assets/units/*.tres`), or on the scene for units without stats.

| Unit | Turn rate |
|---|---|
| Infantry, Grenadier, Scout | 540 |
| Drone | 270 |
| Motorcycle | 240 |
| Übermech | 120 |
| Depot Truck, Cargo Truck | 120 (on the scene) |
| Tank | 90 |
| Hostile (no stats) | 360 |

- Shooting still faces the target at once, and gathering still faces the source.

## Attack approach

An attack order now plans toward the nearest open cell to the target (`_route_toward`) and stops as soon as the target is in range. Before, it searched rings of cells at the edge of the range, which became costly with the longer ranges and could pick a cell on the far side. Repair, construction and capture keep their ring search over their short reaches.

## Ranges and vision

Attack ranges were about four times what fits the map: the camera sits 95 m out, and a 5 m rifle shot was nearly point blank. At the user's request they were scaled up about 4x. Vision is 1.3 to 2 times the range, and Scout and Drone see farthest. Vision is still a number on the HUD only; there is no fog of war or spotting.

| Unit | Range (was) | Vision (was) |
|---|---|---|
| Infantry | 20 (5) | 30 (7) |
| Grenadier | 24 (6) | 32 (5) |
| Scout | 14 (3) | 50 (8) |
| Motorcycle | 16 (3) | 30 (7) |
| Tank | 40 (10) | 52 (7) |
| Übermech | 28 (6) | 36 (8) |
| Drone | unspecified | 60 (9) |
| Hostile (scene value) | 20 (10) | none |

- The Tank shell flies at 40 m/s (was 20) and the grenade at 20 m/s (was 11), so their flights stay about a second at the new ranges. Damage still lands when the shot is fired.
- Splash radius (3) and the Depot's radii are unchanged.

## Checks

`tests/smooth_path_test.gd` (headless):

- An Infantry run of 20 cells east and 7 south stays within 5 cm of the straight line, ends on the goal cell's centre and faces along the run.
- The unit holds exactly its own cell every frame.
- A Tank facing away never turns faster than 90 degrees a second, pivots on the spot for about a second without moving, then drives on.
- A unit standing on the line is gone around, never through.
