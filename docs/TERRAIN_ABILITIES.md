# Terrain abilities

Scout forest traversal, Tank forest clearing and Drone flight now use editable MobilityRules resources in assets/movement, referenced by the existing UnitStats files. Other unit stats, supply systems and the original ground navigation remain in place. No new enemy pressure was added.

## Rules and provisional decisions

- Normal ground units: grass/desert only, with existing ground occupancy and diagonal corner restrictions.
- Scout: grass/desert/forest at its supplied movement speed. It shares ground occupancy, cannot pass through buildings/other ground units, and leaves forest unchanged. No forest speed penalty or cover bonus was specified or added.
- Tank: the same forest-capable navigation, but turns each forest cell it physically enters into open grass for the remainder of this match. Merely planning/reserving a route clears nothing. Clearing is instantaneous, free and grants no wood; no rates, costs or salvage were specified. It does not clear mountains, water, ore or authored resource stands. Occupancy is retained, so its current tile cannot be built on until it leaves. Infantry can follow straight cleared lanes. A diagonal Tank route clears only the entered cells; uncleared orthogonal corner cells can still block infantry until the Tank also crosses them.
- Drone: independent air reservations; flies across all map terrain categories, buildings and ground units, within map bounds. Air units reserve their current/next cells and cannot share an air reservation. Factory launch checks the air layer and can succeed while ground exits are blocked. Drone has no harvesting/building/capture/repair or attack abilities.
- Provisional flight presentation: a fixed **12-unit** model/ring elevation authored in drone.tscn, above the default baked props. Root navigation and distances remain on the map plane, so there is no terrain-height/climbing simulation. Existing attacks can target Drones using planar range and splash rules; no anti-air restriction was specified. Tracers point at elevated models. No landing, fuel, altitude controls or vision/fog mechanics were added.
- Original source_map.png, terrain_data.png and terrain_cells.bin are unchanged. Clearing never writes map files. Restarting the match restores the original forest. There is no save-game persistence for terrain changes yet.

## Visual integration

Existing saved MultiMesh forest instances are copied for match-local state, then hidden when crossed cells are cleared; scenery/meshes are not rebuilt at runtime. Current scenery samples one tree per 2x2 patch. Clearing any cell in that patch hides its tree mesh parts, so canopy removal has coarser resolution than the exact one-cell navigation/surface/minimap changes. Adjacent uncleared forest cells remain forest and blocked to ordinary infantry. The saved shader receives a per-match cleared-cell mask and shows bare ground; its default-black mask preserves editor appearance before gameplay. Baked scenery and asset slots remain intact.

## Test in Godot

1. Open scenes/maps/terrain_abilities_exercise.tscn and press **F6**. It starts beside forest with Scout, Tank and Drone already present; the inherited hostile is disabled for this exercise. The normal main scenario is unchanged.
2. Select Scout and right-click inside the trees immediately to its left. It should move through without removing trees.
3. Select Tank and right-click into a different part of that forest. Trees along its route should disappear and bare-ground cells remain. Restart the scene to restore them.
4. Select Drone at its elevated model and right-click beyond the forest or across water/mountains using the minimap to move the camera. It should fly over obstacles. Its movement does not open ground paths.
5. To check normal production, run the main scene, build Barracks/Tank Factory and produce the roster. Costs remain local to their assigned Depot. The 500-iron Depot testing grant remains enabled.

Mobility is editable in assets/movement/{scout,tank,drone}.tres; elevation is editable on Drone scene children. Restart after resource edits. Full validation and exact changed files are in TERRAIN_ABILITIES_VALIDATION.md and TERRAIN_ABILITIES_CHANGED.txt. Automated synthetic events do not constitute live mouse testing.
