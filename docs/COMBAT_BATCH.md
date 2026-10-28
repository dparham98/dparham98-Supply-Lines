# Combat batch

User confirmed: notation is damage / seconds between attacks. Infantry 8/1, Scout 8/2, Grenadier 20/3, Tank 12/1, Motorcycle 16/2, Übermech 12/5 now drive gameplay. Grenadier deals 40/3 against tanks/buildings; Tank deals 50/3 against tanks/buildings. Drone remains unarmed because attack and range were never specified. The explicit unresolved-stat compatibility fallback remains available; the existing hostile prototype retains its scene-defined combat values.

## Editable rules and implementation decisions

Edit `assets/units/*.tres` in Godot's Inspector, then restart. UnitStats contains base attack, heavy attack, splash radius and moving-fire flag. Supplied costs, health, movement, vision and range are preserved.

- Scout, Tank and Motorcycle fire during existing movement routes, without chasing incidental targets or cancelling movement. Explicit Attack still approaches then stops at range. Idle defense and moving fire choose enemy units only; no new enemy building-hunting behavior.
- Grenadier and Tank splash is instantaneous at the primary target's center, provisional radius **3 map units**, inclusive boundary, measured between actor centers. Radius is editable. Other units have no splash.
- Each victim takes its own class damage. Tanks are identified by unit ID; buildings by selectable_buildings group. The primary victim determines the whole shot's cooldown (Tank: 1 second normally, 3 against heavy targets). Secondary victims can lie beyond weapon range but within splash radius. One hit per victim, no friendly fire or neutral damage. No damage falloff, projectile travel, armor or line-of-sight rules were specified or added.
- Attack card can target hostile units or owned hostile buildings. Infantry right-click continues to capture enemy Depots/mines; use Attack explicitly to damage them. Other armed units right-click hostile buildings to attack. Attacks reject invalid, dead, neutral, friendly and out-of-range targets.
- No new enemy pressure, forest navigation/clearing, Drone flight or tentative death/jamming effects in this batch.

## Editor checks

Run the main resource_skirmish scene. Build Barracks/Tank Factory using Infantry's Build card and their assigned local Depot; select the building to produce its roster. Select each unit to see base attack and special attack/moving-fire details in the HUD. Existing hostile combat is unchanged; the corrected Infantry attack is weaker than the previous fallback, so send supporting infantry rather than expecting one infantry to win alone.

For precise combat coverage run `tests/combat_batch_test.gd` with Godot's --script option; it exercises actual actor scenes, movement, splash, cooldowns and Attack-card building targeting without changing the main scenario. No physical/live mouse input is implied by automated checks.
