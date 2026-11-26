# Play-test exercises (Stage 2 and 3)

Two scenes on Two Lakes for play-testing the Stage 2 and 3 changes on `scratch/stage2-playtest`, one per faction. They replace the earlier `stage2_exercise.tscn`, which put both factions on the player's side.

Both are built by `scripts/tools/build_playtest_exercises.gd`. Re-run it after Two Lakes changes:

```
Godot --headless --path . --script res://scripts/tools/build_playtest_exercises.gd
```

`tests/playtest_exercises_test.gd` checks both: buildings, units, HUD faction, research, the Knights track and train, housing, Sentinel reserve, and 20 s with the AI on.

Open them directly (Run Specific Scene), not through the menu. The East Cyborg AI plays as it does on Two Lakes.

## Both scenes

- **Enemy guard** 75 m east of home, at about (-109, -8): 4 Infantry and 2 Grenadiers.
- **Two enemy mines** 12 m short of the guard, on the way to it. They arm and hide a few seconds after the start.

## Cyborg exercise (`scenes/maps/cyborg_exercise.tscn`)

Inherits Two Lakes.

- **Depot:** 2000 energy, 1200 iron, 300 wood, 300 coal, storage raised to 6000.
- **Buildings by the Depot:** Temple of Science (Minelaying), Foundry (the four upgrade lines) and Tank Factory.
- **Units:** 2 Derailers, a Drone, an Übermech, 2 Tanks, 2 Grenadiers and 4 Infantry, south of the Depot. Two Lakes' own starting Infantry and truck are still there.

## Knights exercise (`scenes/maps/knights_exercise.tscn`)

A text copy of Two Lakes (its Depot can't be taken out by inheriting), with the West Depot, starting Infantry and truck swapped for:
- **Keep** where the Depot stood: 1500 food, 1200 iron, 600 wood, 300 coal, storage 6000.
- **Keep B** about 100 m south-west, with a little stock and 120 coal.
- **Track** laid from the Keep to Keep B (the route Rail would suggest), paid by the Keep.
- **Buildings by the Keep:** Chapterhouse, Forge (Arms, Mail, Slow), Dragon Yard and three Houses.
- **Units:** 3 Grail Sentinels, 4 Round Table Marines, 2 Questing Marines, 2 Warhounds and 3 Forester Maidens, south of the Keep.
