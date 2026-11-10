# Drone model

The Drone is `assets/models/units/drone.glb`, wrapped by `scenes/models/drone_model.tscn` and placed in `scenes/gameplay/drone.tscn` at the unit's `Visuals` height of 12 m. The working file is `Blender/Vehicles/Drone/Drone.blend`.

## Clips

The model has no skeleton. Its parts are separate objects under `drone_root`, animated with one NLA track per object, and the tracks of the same name merge into one glTF clip. All clips start at frame 0 and run at 24 fps.

| Clip | Length | Loop | What it does |
| --- | --- | --- | --- |
| `Rest` | 2 s | Yes | Hovers with a slow bob while the sensor scans. |
| `Run` | 1 s | Yes | Leans nose down with the ducts swung forward. |
| `Die` | 4.67 s | No | Takes a hit, loses `duct_FL`, spirals to the ground, bounces and comes to rest low on the damaged side, then sinks out of sight. |

Rotors turn a whole number of times in each loop, so the loops close exactly. `Rest` and `Run` are set to loop in `drone.glb.import`.

`scripts/components/character_animator.gd` plays the clips, with the Run pace set by `run_reference_speed = 6.0`. It needs no new code because the skeleton parts of that script are optional.

## Death

When the unit dies, the game moves the model out of the unit and plays `Die` where it was. `Die` assumes flat ground 12 m below the model, at Z = -12 in Blender. On a slope the wreck and oil pool can sit slightly above or below the terrain.

`scenes/models/drone_death_fx.tscn` plays `assets/models/effects/drone_death_fx.glb` as a child of the model. It holds the smoke trail, sparks, impact flash and fire, flames on the wreck, thrown scrap and spreading oil. Its `Death` clip shares `Die`'s timeline, so rebuild the two together. The `Spark_Main` scale drives the crash light.

## Checks

`tests/drone_model_test.gd` covers the clips, loop closure, size and facing, counter-rotating rotors, Run at the unit's pace, the torn duct, the fall and the wreck removing itself.
