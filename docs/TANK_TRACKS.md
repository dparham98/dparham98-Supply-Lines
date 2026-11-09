# Tank tracks

The Tank's tracks roll with its ground speed. Nothing is built at runtime and `assets/models/units/tank.glb` is unchanged.

- `scripts/components/tank_rig.gd` is the script on `scenes/models/tank_model.tscn`. It extends the turret script. The unit agent reports travel through `set_drive()`, as it does for the Cargo truck.
- Each side keeps its own travel distance. Both run at ground speed. A heading change runs the sides against each other for `pivot_hold` seconds, because RTS turns happen in a frame or two.
- `assets/shaders/tank_running_gear.gdshader` moves the merged meshes.
  - `Track_Links_L/R` hold 37 identical links of 24 vertices each, in loop order. The shader slides each link rigidly toward the pose of the link ahead, so `roll` from 0 to 1 is one link pitch and the loop repeats seamlessly.
  - `Road_Wheels_L/R` and `Return_Rollers_L/R` hold rows of wheels along Z. Each wheel turns about its own centre by `roll` radians.
- `Drive_Sprocket_L/R` and `Idler_Wheel_L/R` are single wheels and turn as nodes.
- The shader indexes links by vertex order, and its pose table was generated from the mesh. If the Tank is re-exported with a different track, regenerate the table. `tests/tank_model_runtime_check.gd` fails if the import changes the vertex count or the link grouping.
- Checks: `tests/tank_tracks_test.gd` (headless: travel at world scale, stopping, pivot, unit agent) and `tests/tank_model_runtime_check.gd` (rendered: the links move in a low side view).
