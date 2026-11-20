# Ubermech exercise

Asked for on 2026-11-19, to play the Ubermech walker (`Blender/Characters/Ubermech`) without building up to it first.

`scenes/maps/ubermech_exercise.tscn` is Two Lakes (`docs/TWO_LAKES_MAP.md`) with three changes:

- **A Tank Factory already stands** east of the player's Depot, at (-170, 0, -18): inside the Depot's range and clear of its truck strip, so it pays from that Depot.
- **Two player Ubermechs** (`Ubermech`, `UbermechB`) stand in the yard south of the Depot.
- **The Depot holds 800 E and 200 I** instead of 200 E and 60 I, enough for two more Ubermechs (250 E and 60 I each).

Everything else is Two Lakes as it is, including the enemy Ubermech at the east camp.

Open it with:

```
Godot --path . res://scenes/maps/ubermech_exercise.tscn
```

`tests/ubermech_exercise_test.gd` checks it headless: the factory stands in the Depot's range, both Ubermechs carry the walker model on open ground, and the factory builds an Ubermech paid by the Depot.
