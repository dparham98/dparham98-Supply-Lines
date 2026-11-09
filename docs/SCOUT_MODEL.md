# Scout model

The Scout uses the rigged skater from `Blender/Characters/Scout/Scout.blend`: a 1.67 m figure on inline skates with a pump shotgun, exported with three clips (`idle`, `run`, `shoot`). Earlier versions of the file are in git history.

## What came across from Blender

- `assets/models/units/scout.glb` holds the rig (39 bones), the meshes and the clips. Subdivision is off in the export (11,192 triangles against 63,768 at the file's full levels); the file itself keeps its levels.
- The muzzle flash and the ejected shell are meshes on bones that scale up for their frames, so they export as ordinary animation.
- `animation/fps` is 24 to match the file, and `idle` and `run` loop (`scout.glb.import`).

## What is rebuilt in Godot

- In Blender the muzzle light's energy is a driver: `42 * max(0, flash scale - 0.001)`. Drivers do not export, so `character_animator.gd` applies the same relationship every frame: `flash_light_energy * max(0, flash bone scale - 0.001)` on the imported light. The light is off between shots.
- Godot brightness is not Blender watts. `flash_light_energy` (2.0) and `omni_range` (3 m) in `scenes/models/scout_model.tscn` were set by eye against renders, so the flash lights the helmet and armour without burning out the ground. No shadows.
- The flash mesh's 14x emission clips to flat white without Blender's view transform, so `scenes/models/scout_model.tscn` overrides it with an unshaded hot orange.

## Shot timing

The shot goes off 0.375 s into the `shoot` clip, on the flash. `shot_lead_time` holds that: the unit starts the clip that early, so the wind-up plays before the shot and damage and tracer land on the flash. Combat timing is unchanged. A first shot with no wind-up time joins the clip at the firing frame. A target that leaves range during the wind-up leaves a flash with no shot.

`shoot` is full-body, so a Scout firing on the move glides in the firing pose while the clip plays.

## Checks

- `tests/scout_model_test.gd` (headless): clips and loops, size and facing, light off at rest and driven by the flash bone, first shot on the firing frame, barrel on the target, wind-up with no early damage.
- `tests/scout_model_runtime_check.gd` (rendered): saves idle, run, wind-up, flash and shell poses, close views and the flash at play distance.
