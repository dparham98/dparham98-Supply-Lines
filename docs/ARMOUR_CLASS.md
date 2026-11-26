# Armour class and the Ubermech

Item 8 of the balance handoff (`docs/BALANCE_IMPLEMENTATION_HANDOFF.md` on the balance branch), 2026-11-25.

## Armour class

Every target has one class (`CombatResolver.target_class`), checked in this order:

1. **Building:** anything in `selectable_buildings`.
2. **Armoured:** a unit whose `armoured` flag is set.
   - For most units the flag comes from `UnitStats.armoured`: the Tank and Ubermech. The Azure Dragon was armoured until Round 3; it is now a light target with the `giant` flag (`docs/ROUND3_UNIT_STATS.md`).
   - The Cargo truck, Depot truck and Train have no UnitStats, so it is set on their scenes.
3. **Flyer:** a unit on the air layer, such as the Drone.
4. **Light:** everything else.

A weapon's heavy damage (`heavy_target_damage` and `heavy_target_interval`) applies to armoured units and buildings. Before, it applied to buildings and to any unit whose id was `tank`. So the Grenadier's 40, the Questing Marine's 38 and the Tank's 50 now also land on the Ubermech, trucks and trains.

## Weapons by target

`UnitStats.targets` lists the classes the main weapon fires at; it is all four by default.

A unit can have a second weapon, set with these `UnitStats` fields:
- `second_damage`
- `second_interval`
- `second_range`
- `second_min_range`
- `second_targets`

**Choosing a weapon (`unit_agent.weapon_for`):**
- The second weapon fires when it suits the target's class and the target is between its minimum range and its range.
- Otherwise the main weapon fires, if it fires at that class and is in range.
- Otherwise the unit can't fire at that target from where it is.

**Range:**
- `in_attack_range` asks whether either weapon can fire. So an attack order or attack-move stops at the range of the weapon that suits the target.
- Target scans look as far as the longer weapon reaches (`weapon_reach()`).
- A unit with no weapon for a target's class won't take an attack order on it (`fires_at`).

**Reload:** the two weapons share one reload. A shot takes the interval of the weapon that fired it.

## Ubermech (`assets/units/ubermech.tres`)

| | Now | Was |
| --- | --- | --- |
| Health | 360 | 120 |
| Speed | 4 | 4 |
| Sight | 24 (Round 3; was 30) | 36 |
| Class | armoured | light |
| Cost | 250 E / 60 I | unchanged |
| Laser (main) | 40 every 1.5 s at 16 m, against light units, flyers and armour; 8 against armour | 12 every 5 s at 20 m |
| Missile pods (second) | 60 every 3 s at 6 to 34 m, against armour and buildings only | none |

**What it fires at:**
- A light unit or a flyer gets the laser.
- An armoured unit gets the pods from 6 to 34 m, and the laser's 8 when it is nearer than 6 m.
- A building gets only the pods.

**The spotter gap:** its sight is 24 and the pods reach 34, and it fires only at what its side sees (`docs/SEE_TO_SHOOT.md`). So the last 10 m of the pods' reach need a spotter.

**The model:** the walker plays its laser pulse or its six-pod volley to match the weapon that fired (`ubermech_animator.gd` `use_weapon`).

## HUD

The unit card now shows:
- the heavy damage as **Vs armour** (it was "Vs buildings");
- the second weapon, and the classes the main weapon fires at when that isn't all four;
- **Armoured** for armoured units.

## Checks

- **`tests/armour_class_test.gd` (headless) covers:**
  - each unit's class;
  - heavy damage following the flag;
  - the Ubermech's choice of weapon by class and range, including the pods' 6 m minimum and 34 m reach;
  - a laser shot landing 40.
- **`tests/ubermech_battles_sim.gd`:** the handoff's battle check. It isn't in the suite; run it with `--fixed-fps 30`.
  - Three Ubermechs should beat 10 Deforesters, 28 Scouts and 5 Tanks, each on its own.
  - They should lose to 11 Grenadiers.
