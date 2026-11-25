# See to shoot, the Tank and splash

Item 3 of `docs/BALANCE_IMPLEMENTATION_HANDOFF.md` (2026-11-23). The answer to Tanks kiting infantry: a Tank now needs something of its side to see its target.

## Rules

- **A unit fires only at what its side sees now.** `team_sees` in `scripts/gameplay/unit_agent.gd` asks the fog of war (`FogOfWar.visible_to`). That counts everything the fog counts as sight: each unit at its own `vision` (trucks and trains at the fog's `unit_vision`, 20 m), Depots and Keeps at `depot_vision` (36 m), other buildings at `building_vision` (24 m) and build sites at `site_vision` (12 m). The check guards picking targets (`_nearest_opponent`, both units and buildings), keeping one (`_acquire`), an attack order (it closes in rather than firing, and does not back off from an unseen target inside the Tank's minimum range), the shot itself (`_shoot`) and the Tank's roof gun (`scripts/components/close_defense.gd`). The fog updates every 0.2 s, so sight can lag a step behind a fast unit.
- **A map with no fog node is unaffected**: everything counts as seen. First Contact, used by most tests, has no fog; Two Lakes, the balanced map and the Ubermech exercise do.
- **Splash share.** `UnitStats.splash_share` is the share of a hit that units caught in the splash take, other than the one aimed at, rounded. The Tank, the Grenadier and the Azure Dragon have 0.5. A building caught in the splash still takes the full hit; the handoff names units only.
- **Moving-fire arc, in reserve.** `UnitStats.moving_fire_arc` limits fire on the move to an arc centred on the hull's heading. Every unit has 360, which is off. The handoff keeps it as the owner's reserve if Tanks with Drones still kite too well.

## The Tank (`assets/units/tank.tres`)

| | Was | Now |
| --- | --- | --- |
| Sight | 52 | 20 |
| Speed | 6 | 5 |
| Main gun at units | 12 every 1 s | 12 every 1.5 s (notation 12/1.5) |
| Splash | 3 m, full damage | 2 m, half damage |

Range 10–30 m, the roof gun, the 50 every 3 s against Tanks and buildings, moving fire and the price (150 E, 35 I) are unchanged. With sight 20 a Tank alone sees only to 20 m, so its last 10 m of range needs a spotter: a Scout, a Drone, a building.

## Checks

- `tests/see_to_shoot_test.gd` (headless, in the suite): the Tank's numbers and the splash shares; every unit's arc at 360; on Two Lakes a Tank does not pick or fire at a Deforester 25 m away that its side cannot see, picks it once a Scout sees it, and counts a Depot's sight; on First Contact (no fog) a unit sees its target; splash damage 12 to the target and 6 to a bystander (a Grenadier's 10), a shell's burst taking 6, a building taking the full hit; a 90° arc allowing a target ahead and refusing one behind.
- `tests/see_to_shoot_battles_sim.gd` (not in the suite: it takes minutes of game time). Run it with `godot --headless --fixed-fps 30 --path . --script res://tests/see_to_shoot_battles_sim.gd`. Battles on a flattened patch of First Contact with the fog added, adapted from the balance investigation's arena. Result on 2026-11-23:

| Battle | Result |
| --- | --- |
| 2 Tanks kiting, no spotter, against 8 Grenadiers | Grenadiers win in 77 s, all 8 standing |
| 2 Tanks kiting, no spotter, against 6 Questing Marines | Marines win in 81 s, all 6 standing |
| 2 Tanks kiting with a Drone following, against 10 Deforesters | Tanks win in 28 s untouched |
| 5 Tanks attack-moving against 10 Deforesters | Tanks win in 23 s with 2 left and 236 of 750 HP (31%), no longer with 99% |

Not checked by a person: how a Tank that holds its fire for want of sight reads in play, and whether players see why.
