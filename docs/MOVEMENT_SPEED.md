# Movement speed

The playtest of 2026-11-17 doubled the movement speed of every unit.

| What | Before | Now |
| --- | --- | --- |
| Infantry, Grenadier, Übermech | 2 | 4 |
| Scout | 4 | 8 |
| Tank | 3 | 6 |
| Motorcycle, Drone | 6 | 12 |
| Depot truck (`move_speed`) | 3 | 6 |
| Rail cargo (`rail_rules.tres`) | 8 | 16 |
| Supply cargo (`supply_rules.tres`, `cargo_speed`, newly set) | 4 (the default) | 8 |

Speeds are in metres per second, `movement_speed` in `assets/units/*.tres`.

The travel times and timelines in `docs/BALANCED_MAP.md`, `docs/TWO_LAKES_MAP.md` and `docs/ECONOMY_REPORT.md` were worked out before this and are now about twice too long for any leg that is walking or driving. They have not been redone.
