# Round 3: tiered vision and unit stats

Item 2 of the Round 3 balance handoff (2026-11-25). Sight is now tiered: spotters see far, line units see about as far as they shoot, and the long guns (Grenadier, Questing Marine) see less far than they shoot, so they need a spotter or the flash of an enemy's shot.

## Unit table

The numbers live in `assets/units/*.tres`. "Bonus" is what each Attack upgrade level adds to a weapon's hit (see Upgrades below).

| Unit | Health | Range | Sight (was) | Attack | Bonus |
| --- | --- | --- | --- | --- | --- |
| Deforester | | | 20 (30) | | +1 |
| Scout | | | 42 (50) | | +1 |
| Grenadier | | 19 (18) | 14 (32) | | +2, vs armour +4 |
| Derailer | | | 26 (30) | | +2 |
| Drone | 40 (30) | | 32 (60) | | |
| Tank | | | 18 (20) | | +2, vs armour +5 |
| Ubermech | | | 24 (30) | | laser +4, laser vs armour (8) +1, pods +6 |
| Forester Maiden | | 2.4 (none) | 24 (30) | 5 every 1.2 s (none) | 0 |
| Warhound | | 3.2 (2.6) | 44 (52) | 5 every 1 s (7) | +1 |
| Round Table Marine | | | 19 (32) | vs armour 3 (2) | +1, vs armour +1 |
| Grail Sentinel | | | 22 (32) | | +1 |
| Questing Marine | | 21 (19) | 15 (34) | 16 every 2 s (14) | +2, vs armour +4 |
| Azure Dragon | 240 (180) | 9 (8) | 28 (40) | 32 every 2.4 s (28 every 3 s); vs armour 45 every 2.4 s (every 3 s) | +3, vs armour +5 |

Blank cells are unchanged. The Warhound also detects at 15 m (was 10; `docs/MINES.md`) and lands its bites on the move (item 1, `docs/MELEE_PURSUIT.md`).

## The Azure Dragon is a giant

`UnitStats.giant` is a new flag. The Dragon is now `armoured = false, giant = true`:
- **Class:** it is a light target (`CombatResolver.target_class`), so weapons hit it with their normal damage, not their heavy damage. A Grenadier's shell does 20 to it, not 40.
- **Giant:** the flag marks it for the Questing Marine's Sundering Lances (item 3), which work on armoured and giant units.

`UnitStats.coal_cost` is also new, for item 5's coal prices. Nothing uses it yet.

## Upgrades: a bonus per weapon

Each Attack level used to add 10% of the weapon's base damage, at least 1. Now it adds a fixed bonus per weapon, set on the unit's stats:
- `attack_upgrade_bonus`: the main weapon against light units, flyers and buildings it fires its normal damage at;
- `heavy_upgrade_bonus`: the main weapon's heavy damage (against armour and buildings);
- `second_upgrade_bonus`: the second weapon (the Ubermech's pods).

All three default to 1. `Upgrades.with_attack(attacker, base, bonus)` adds `level × bonus`; `CombatResolver.upgrade_bonus(attacker, target, weapon)` picks the bonus for the hit. The unit card shows the bonus. The Tank's roof gun keeps its own bonus (item 1, `docs/BASTION_TANK.md`).

## Muzzle flash

A unit that fires is revealed to the other side for 1.2 s, in a 3 m disc round where it stood (`muzzle_reveal_seconds` and `muzzle_reveal_radius` on `scenes/gameplay/fog_of_war.tscn`). So a Grenadier that fires from beyond the enemy's sight can be shot back by anything in range. The roof gun's shots flash too.

`FogOfWar.reveal_shot(shooter)` stamps the disc at once and keeps it until it expires; each fog update stamps the live ones again. On a map with no fog nothing changes.

## The Forester Maiden fights back

The Forester is now armed: 5 every 1.2 s at 2.4 m, with no Attack bonus. She is `defensive_only`:
- she never picks a target on her own, and doesn't fire on the move;
- when something hits her (`provoked_by`), she attacks it, unless she is a Farmer, carrying a load, or under an order other than idle, gather, fell, construct or repair;
- the urge lasts `retaliate_seconds` (5 s) after the hit;
- an attack order works as for any unit.

## Raided Farmers shelter

While enemies stand on a Farm's field (a raid), its Farmer walks to within 6 m of the covering Keep (`KnightsRules.farm_raid_shelter_distance`) and waits there ("Farm raided · sheltering at Keep"). She goes back to farming once the raid clears. The covering Hearth-Wain will count too once it exists (item 6).

## Checks

- `tests/tiered_vision_and_dragon_test.gd` (headless, in the suite):
  - the table above;
  - on Two Lakes two Grenadiers 17 m apart can't see each other and hold their fire; once a Scout spots the target, the enemy Grenadier fires, shows to the player, still shows 1 s later and is gone by 1.3 s;
  - the Dragon is a light target: a Grenadier deals it 20 and a Tank 12, a Sentinel can heal it, and two breaths (32) kill a Grenadier where one does not;
  - Attack I adds the Grenadier's +2 and +4 and the Tank's +2 and +5;
  - an idle Forester doesn't attack an enemy beside her; one Warhound beats one Forester, who hurts it fighting back; two Foresters beat one Warhound.
- `tests/knights_economy_test.gd`: a raided Farmer shelters within 6 m of the Keep.
- Updated for the new numbers: `armour_class_test`, `arthurian_faction_test`, `minelaying_test`, `see_to_shoot_test`, `upgrades_test`.

Not checked by a person: how the shorter sight plays, and whether the muzzle flash reads on screen (the reveal is a fog stamp; there is no new flash art).
