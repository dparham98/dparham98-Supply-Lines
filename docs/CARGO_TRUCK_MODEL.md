# Cargo truck model and articulation

The Cargo vehicle uses the authored truck from `Blender/Vehicles/CargoTruck/CargoTruck.blend`. The file has no baked animation clips; it is built as a rigid hierarchy with pivots, and the game moves those parts from what the vehicle is doing.

## Pieces

- `assets/models/units/cargo_truck.glb` holds the `cargo_truck` collection's meshes and empties: `truck_root` > `chassis` with the `cab`, the `cargo_bed` (carrying the `cargo_lid` with its `cargo_indicator`, and the `rear_ramp`), the `exhaust_stack`, the `steer_FL`/`steer_FR` pivots holding the front wheels, and the four fixed wheels. Eight untextured materials; `sensor_red`, `warning_amber` and `cargo_signal` emit.
- `scenes/models/cargo_truck_model.tscn` wraps the glb at the world scale 0.6 (about 4.8 m long and 2 m tall; the Tank uses the same factor) turned 180 deg so the cab faces -Z, and names every articulated node for the component on its root, `scripts/components/vehicle_rig.gd`.
- `vehicle_rig.gd`: `set_drive(speed, turn, delta)` each frame the owner moves rolls the wheels by the ground distance covered (`wheel_radius` in model units, scaled by the wrapper) and steers the front pivots toward the heading change (full lock at `steer_full_rate`); `set_hatches(open)` swings the lid to +60 deg and the ramp to -125 deg at `hatch_speed_degrees`; `set_load(fraction)` raises the indicator by 0.32 while anything is aboard. The Tank's turret and the Infantry's clips use their own components; this one has no AnimationPlayer.
- `scripts/gameplay/unit_agent.gd` reports travel at the end of `_process` for any model with `set_drive`; `scripts/economy/cargo_vehicle.gd` opens the hatches while deployed, deploying, packing or transferring at a stop, and reports the cargo fraction (loose stock plus crate slots over capacity).

## Behaviour and limits

- Only `cargo_vehicle.tscn` uses the model; Trains and Depot trucks keep their placeholders.
- The `team_color` surfaces (cab, bed, lid) are left as authored; there are no enemy trucks to tint yet.
- Checks: `tests/cargo_truck_model_test.gd` (headless: facing, size, wheel roll and steer from travel, hatches with deployment and unloading, indicator with crates) and `tests/cargo_truck_model_runtime_check.gd` (screenshots `truck_road` and `truck_open`). Scale beside the Tank and Infantry, wheel and steer feel, and the hatch timing need a human look.
