# Melee pursuit

Item 1 of the Round 3 handoff, 2026-11-25. A Warhound sent to attack a unit on the move used to stop as soon as it was in reach, bite, watch the target run out of its 2.6 m and wait half a second to set off again. Against a fleeing Scout it landed a bite every three seconds or so.

## Who

A **melee pursuer** is a unit that fires on the move (`fire_while_moving`) with an attack range of at most `melee_range` (4 m). For now that is the Warhound only: `fire_while_moving` is now on in `assets/units/warhound.tres`.

## What it does

On an attack order against a moving target:
- **Keeps closing:** it doesn't stop while the target is in reach. It stops only once within `pursuit_stop_distance` (1.6 m), and sets off again as soon as the target moves.
- **Strikes on the move:** it bites its target whenever it is in reach, without stopping.
- **Heads where the target is going:** within `pursuit_replan_within` (12 m) it plans toward the cell the target is heading for, not where it stands, and plans again every `pursuit_replan_seconds` (0.15 s) instead of every 0.5 s. So it closes along the target's line instead of trailing it.

A target that stands still is attacked as before.

The numbers are on `UnitStats` (`scripts/units/unit_stats.gd`); the code is `_melee_pursuer`, `_closing_in` and `_route_pursuit` in `scripts/gameplay/unit_agent.gd`.

## Checked

`tests/stage3_bugfixes_test.gd`: a Warhound starting 3 m behind a Scout running at 8 m/s kills it within 10 s (about 5 s). With the old behaviour it landed 3 bites in 10 s.
