# Infantry model and animation

The Infantry uses the rigged cyborg from `Blender/Characters/Infantry/Infantry.blend`: a 1.8 m figure with a pistol on one arm and a chainsaw on the other, exported with four clips. The unit agent reports what it is doing each frame and the model plays the matching clip.

## Pieces

- `assets/models/units/infantry.glb` holds the `rig_artpose` collection: skinned body, pistol, chainsaw, eye lens, the `chainsaw_teeth_rig` mesh attached to the `chainsaw` bone, and the animations `Rest` (2 frames), `Run` (0.71 s), `Hack` (1.5 s) and `Shoot` (0.5 s). The import marks Rest, Run and Hack as looping.
- `scenes/models/infantry_model.tscn` wraps the glb turned 180 deg so the face points -Z, and puts `assets/shaders/chainsaw_teeth.gdshader` on the teeth mesh. Its root carries `scripts/components/character_animator.gd`.
- `character_animator.gd`: `set_motion(kind, speed)` records this frame's motion (`run`, `work` or `idle`; it lapses after a frame without a call), `play_action(&"shoot")` plays the shot clip once and then returns to the motion clip, `muzzle_position()` is the `pistol` bone, and the teeth shader's `speed` instance uniform runs while working. Run's playback rate scales with the reported speed against `run_reference_speed` (2 m/s, the Infantry's pace), clamped to 0.5-2x. Clip names are exported properties; a model missing a clip falls back to idle.
- `scripts/gameplay/unit_agent.gd` calls `_animate()` at the end of `_process`: a position change since the last frame is `run`, the states "Gathering" and "Repairing ..." are `work`, anything else is `idle`. `_shoot` calls `play_action(&"shoot")` when a shot fires and starts the tracer at the model's `muzzle_position()` when it has one. Units whose model has no animator (trucks, the prototype hostiles) are unchanged.

## Behaviour and limits

- Only the Infantry scene uses the model. Hostiles keep their prototype; the Depot truck keeps the engineer prototype.
- Hack is used for both wood and iron gathering and for repair, since the saw is the only tool. Construction work is driven elsewhere and shows Rest for now.
- The old static infantry file is kept at `Blender/Backups/Infantry/Infantry_2026-10-15_static.blend`.
- Checks: `tests/infantry_model_test.gd` (headless: clips and loops, size and facing, Run while walking with pace, Hack and teeth while gathering, Shoot once then Rest, muzzle at the pistol) and `tests/infantry_model_runtime_check.gd` (screenshots `infantry_idle`, `infantry_run`, `infantry_hack`, `infantry_shoot`, pickable). How the clips read at play speed, blend timing and the figure's scale next to the tank need a human look.
