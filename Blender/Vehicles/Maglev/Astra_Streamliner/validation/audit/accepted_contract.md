# Accepted train geometry and runtime contract

The reference checkout was `dd11af9bbd272cd951b6ce193762a319f40651c3`. The accepted Blender file is `Blender/Vehicles/Maglev/MaglevTrain.blend`. Its staging scene contains engine and cargo assemblies, track references and a scale figure. The game instantiates only the cargo assembly. `scenes/gameplay/train.tscn` loads `scenes/models/train_model.tscn`, whose only car is `Car1` from `assets/models/units/maglev_train_cargo.glb`. The prototype therefore needs one powered cargo GLB. The driving nose and freight compartment can share the fixed car body. The default consist has no joint between vehicles.

## Dimensions and pivots

Blender units are metric at 1.0. The accepted staged cargo root is at Blender (0, 5.5, 0). The engine root is at (0, −6.5, 0). Each exported root is recentered individually. The train's nose points down Blender −Y, with +Z up. The glTF import preserves unit scale, converts the nose to +Z and up to +Y, and applies its root scale of 1.0. The saved car wrapper and its runtime placement both apply 0.6 uniformly.

The following transform origins are local to the unscaled exported car. All children are direct children of the root. Rotation and scale are identity throughout.

| Node | glTF/Godot X, Y, Z (m) | Role |
| --- | --- | --- |
| `train_cargo_root` | 0, 0, 0 | Ground reference on the car centreline |
| `cargo_body` | 0, 2.50, 0 | Fixed body datum |
| `sled_cargo_front` | 0, 1.00, 3.00 | Leading track follower |
| `sled_cargo_rear` | 0, 1.00, −3.00 | Trailing track follower |
| `cargo_coupler_F` | 0, 1.67, 5.50 | Forward coupling marker |
| `cargo_coupler_R` | 0, 1.67, −5.50 | Rear coupling marker |
| `cargo_car_indicator` | 0, 3.60, −3.55 | Cargo signal at rest |

The original vertices span X ±1.83 m, Y 0.68–3.97 m, Z ±5.45 m. The fixed body starts at Y 1.22 m. Each sled spans 2.40 m wide and 2.80 m long. The lowest sled surface is 0.32 m below its pivot. After the wrapper scale the train is 2.196 m wide, 1.974 m tall and 6.540 m long, with its lowest surface at Y 0.408 m. Both coupling datums stand 0.030 world m past the extreme end surfaces. The imported accepted asset contains four meshes, 15 material surfaces, 1,516 triangles, eight PBR materials and zero textures, skins or clips. Per-object bounds and transforms are in `accepted_cargo_nodes.json`.

## Track, movement and cargo

The track width is 3.0 world m. The straight is 4.8 m long. The tightest curve and both fork branches use radius 12.0 m. The rail centreline is at Y 0. The runtime poses the sled origins at Y 0.6 m and follows the local tangent at each end. The rigid body bridges the 3.6 m straight-line distance between the sleds. Its origin uses the chord midpoint. The authored gap between adjacent cars' nearest sled pivots is 5.0 m before wrapper scale (3.0 world m), available to the consist code for a multi-car configuration.

`train.gd` moves forward along the current ordered line. A return route orders the sampled line in the opposite direction. `train_consist.gd` aims the same named leading end along the new travel direction. The train has no dedicated reversing clip or cab-swap animation. `cargo_vehicle.gd` takes its runtime capacity (300), speed (8 m/s) and health (80) from `assets/economy/rail_rules.tres`. One train carries 12 standard 25-unit crates. Its sole cargo indicator rises by 0.32 local m (0.192 world m) when (stock + reserved)/capacity exceeds 0.001. It returns to its stored local origin at empty. The signal material stays on the mesh throughout this motion.

`scripts/components/team_paint.gd` selects imported surfaces named `team_color` and applies per-instance surface overrides. `unit_agent.gd` triggers the operation when ready and when ownership changes. The shipped player, enemy and neutral paint resources are green, red and grey. The requested blue assignment belongs to the standalone review palette. A game import using the normal player palette should therefore show green.

## Measurement

`reference_sha256_before.json` records eleven accepted source and export hashes from before modeling. `measure.py` reads actual GLB position/index accessors, applies the glTF node transforms and measures both models in the same space. `mesh_metrics.json` contains exported counts, bounds and two geometric checks. It projects orthographic rays at 50° elevation from eight headings to estimate the visible silhouette occupied by team material and the load indicator. A separate estimate samples 50,000 area-weighted points on the fixed body and tests for an unobstructed view from 17 upper or horizontal directions. It also intersects the two independently yawed sleds and chord-placed body against the quarter turn and both fork branches at 55 interior poses each. The forks are set to their settled branch routes. A further 77 poses traverse the straight. It checks the rail owner-status cube separately. On the accepted train, this surface passes inside the underside as the train goes over it. The accepted car clears the modeled track bed by 0.048 world m at the sampled points. The analytic sweep includes the raised branch blade and lowered straight blade. The separate Godot route test executes the movement logic.
