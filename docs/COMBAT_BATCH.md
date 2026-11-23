# Combat batch

User confirmed: notation is damage / seconds between attacks. Infantry 8/1, Scout 8/2, Grenadier 20/3, Tank 12/1, Motorcycle 16/2, Übermech 12/5 now drive gameplay. Grenadier deals 40/3 against tanks/buildings; Tank deals 50/3 against tanks/buildings. Drone remains unarmed because attack and range were never specified. The explicit unresolved-stat compatibility fallback remains available; the existing hostile prototype retains its scene-defined combat values.

## Editable rules and implementation decisions

Edit `assets/units/*.tres` in Godot's Inspector, then restart. UnitStats contains base attack, heavy attack, splash radius and moving-fire flag. Supplied costs, health, movement, vision and range are preserved.

- Scout, Tank and Motorcycle fire during existing movement routes, without chasing incidental targets or cancelling movement. Explicit Attack still approaches then stops at range. Idle defense and moving fire choose enemy units only; no new enemy building-hunting behavior.
- Grenadier and Tank splash is instantaneous at the primary target's center, provisional radius **3 map units**, inclusive boundary, measured between actor centers. Radius is editable. Other units have no splash.
- Each victim takes its own class damage. Tanks are identified by unit ID; buildings by selectable_buildings group. The primary victim determines the whole shot's cooldown (Tank: 1 second normally, 3 against heavy targets). Secondary victims can lie beyond weapon range but within splash radius. One hit per victim, no friendly fire or neutral damage. No damage falloff, projectile travel, armor or line-of-sight rules were specified or added.
- Attack card can target hostile units or owned hostile buildings. Infantry right-click continues to capture enemy Depots/mines; use Attack explicitly to damage them. Other armed units right-click hostile buildings to attack. Attacks reject invalid, dead, neutral, friendly and out-of-range targets.
- Forced fire: the Attack card (A, then click) also takes a friendly unit or building when nothing hostile is under the pointer, and fires on it until it dies, so its death animation plays. It counts only for that order's target; splash, right-click, attack-move and idle defence still spare friendlies (`tests/friendly_attack_test.gd`).
- No new enemy pressure, forest navigation/clearing, Drone flight or tentative death/jamming effects in this batch.

## Targeting in big battles

Armed units look for the nearest opponent in range (`unit_agent.gd` `_nearest_opponent`, and the Bastion roof gun's `close_defense.gd`). They used to ask every unit on the map, every frame, so the work grew with the square of the units: a battle of a few hundred ran at a few frames a second.

- **Near units only:** they now ask the skirmish's `units_near`. It buckets the units into 16 m squares (`scripts/combat/unit_grid.gd`), filled once a frame and again when a unit joins or leaves. It hands back the units in the squares round the asker, with 2 m to spare for the buckets being up to a frame old. Distance is measured from where each unit stands now, as before, and what may be hit (`CombatResolver.can_hit`) is unchanged.
- **On a timer:** a unit with nothing in its sights looks round every 0.2 s (`TARGET_SCAN_SECONDS`), not every frame. It keeps shooting what it found while that stays in range and can be hit, and looks again at once when that target dies or leaves. So an enemy walking into range is noticed within 0.2 s, and a unit no longer switches to a nearer enemy in the middle of a fight.
- **Checks:** `tests/battle_lookup_test.gd` checks that the buckets miss nobody the whole group would find, that 60 mixed units each pick the opponent the old way picks, and the timer rules above.

## Editor checks

Run the main resource_skirmish scene. Build Barracks/Tank Factory using Infantry's Build card and their assigned local Depot; select the building to produce its roster. Select each unit to see base attack and special attack/moving-fire details in the HUD. Existing hostile combat is unchanged; the corrected Infantry attack is weaker than the previous fallback, so send supporting infantry rather than expecting one infantry to win alone.

For precise combat coverage run `tests/combat_batch_test.gd` with Godot's --script option; it exercises actual actor scenes, movement, splash, cooldowns and Attack-card building targeting without changing the main scenario. No physical/live mouse input is implied by automated checks.
