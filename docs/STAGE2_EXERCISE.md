# Stage 2 and 3 exercise

Asked for on 2026-11-25, to play every Stage 2 and Stage 3 change of the balance handoff in one scene, without
building up to it first. It lives on the play-test branch `scratch/stage2-playtest`, which merges PRs #147 to #157
(rules, AI and art).

`scenes/maps/stage2_exercise.tscn` is Two Lakes (`docs/TWO_LAKES_MAP.md`) with the player holding **both factions**
at once. It is written by `scripts/tools/build_stage2_exercise.gd`, which finds legal sites on the map; re-run that
rather than editing the scene by hand.

| Where | What stands there |
| --- | --- |
| West Depot (-184, -8) | 2000 E, 1200 I, 300 W, 300 coal (storage raised to 6000) |
| Beside the Depot | Temple of Science (-185, 1), Foundry (-193, -10) |
| South of the Depot | 2 Derailers, a Drone, an Ubermech, 2 Tanks, 2 Grenadiers, 4 Infantry |
| Keep, north (-202, -60) | 1500 F, 1200 I, 600 W, 300 coal (storage 6000) |
| Beside the Keep | Forge (-202, -69), Wainwright (-194, -65) |
| South of the Keep | 3 Grail Sentinels, 4 Round Table Marines, 2 Questing Marines, 2 Forester Maidens |
| Keep B, further north-east (-164, -100) | 300 F, 400 I, 100 W, no coal: the far end for Knights track |
| Open ground east (-109, -8) | Enemy guard: 4 Infantry and 2 Grenadiers standing clumped |

Everything else is Two Lakes as it is, the East Cyborg AI included, so expect its first attack after a few minutes.
Nothing is researched yet.

Open it straight, not through the menu (the menu would set one faction for you and rebuild the start):

```
Godot --path <checkout of scratch/stage2-playtest> res://scenes/maps/stage2_exercise.tscn
```

`tests/stage2_exercise_test.gd` checks it headless: every building stands on the player's side and pays from the
right stockpile, every unit stands on open ground, the Build page offers both factions' buildings, the Temple,
Foundry and Forge each start their first research, and the Sentinels have reserve to cast.
