# Scout model

The Scout uses the rigged skater from `Blender/Characters/Scout/Scout.blend`: a 1.72 m figure on inline skates with a pump shotgun, exported with four clips (`idle`, `run`, `shoot`, `die`). It was reworked on 2026-11-10 to `Blender/References/Scout_concept.webp`, on the same rig. Earlier versions of the file are in git history and `Blender/Backups/Scout`.

## The look

- Charcoal bodysuit, steel plates with oxblood red edging, tan leather belt and pouches, a holster on the right thigh, a backpack with an amber panel and chunky skates with amber hubs and light bars. Amber is the only glow.
- The concept's crosses are not used. Both shoulder plates carry the faction fang instead, and the buckle and chest badge are plain.
- Materials are flat PBR. Two textures are the exception: `scout_head_basecolor` (the face, hair and ponytail) and `scout_helmet_basecolor`. Godot extracts both next to the GLB as `scout_scout_*_basecolor.png`.

## Two heads

Each Scout has a helmet (`head_helmet`) or a bare head (`head_bare`, `head_bare_hair`, `head_bare_goggles`). Both are in `scenes/models/scout_model.tscn`. The `HeadLook` node (`scripts/components/model_look.gd`) picks one at random when the model is created and only switches visibility; set its `look` to 0 (helmet) or 1 (bare) to force one. A corpse is the same model node, so it keeps its head. In the saved scene the bare head is hidden, so the editor shows the helmet.

## What changed on the rig

The 39 bones, their names and hierarchy are unchanged. In the rest pose:

- Everything above the wheels is 2.8 cm higher, for the taller skates.
- The shoulder joints are 2.7 cm closer to the spine on each side, to match the concept's narrower shoulders.

The motion in the clips is unchanged. Because the shoulders moved, `idle`, `run` and `shoot` were re-keyed on four bones so the gun stays in the right hand and the left hand stays on the pump: `gun`, `upper_arm.L`, `forearm.L` and `hand.L` now have a key on every frame. `die` was rebuilt from the same poses, resting on the new body.

The barrel still runs along the `gun` bone with its tip at the `flash` bone, so `gun_rest_axis`, `gun_sample_time` and `shot_lead_time` in the model scene are unchanged.

## What came across from Blender

- `assets/models/units/scout.glb` holds the rig, the meshes and the clips. Subdivision is off in the export (about 20,600 triangles with both heads; only the helmet has subdivision levels in the file).
- The muzzle flash and the ejected shell are meshes on bones that scale up for their frames, so they export as ordinary animation.
- `animation/fps` is 24 to match the file, and `idle` and `run` loop (`scout.glb.import`).

## What is rebuilt in Godot

- In Blender the muzzle light's energy is a driver: `42 * max(0, flash scale - 0.001)`. Drivers do not export, so `character_animator.gd` applies the same relationship every frame: `flash_light_energy * max(0, flash bone scale - 0.001)` on the imported light. The light is off between shots.
- Godot brightness is not Blender watts. `flash_light_energy` (2.0) and `omni_range` (3 m) in `scenes/models/scout_model.tscn` were set by eye against renders, so the flash lights the head and armour without burning out the ground. No shadows.
- The flash mesh's 14x emission clips to flat white without Blender's view transform, so `scenes/models/scout_model.tscn` overrides it with an unshaded hot orange.

## Shot timing

The shot goes off 0.375 s into the `shoot` clip, on the flash. `shot_lead_time` holds that: the unit starts the clip that early, so the wind-up plays before the shot and damage and tracer land on the flash. Combat timing is unchanged. A first shot with no wind-up time joins the clip at the firing frame. A target that leaves range during the wind-up leaves a flash with no shot.

`shoot` is full-body, so a Scout firing on the move glides in the firing pose while the clip plays.

## Death

`die` is one 4.17 s clip: the fall (about 1 s), the corpse lying there with a few twitches for about two seconds, then a short sink into the ground. `scripts/gameplay/unit_agent.gd` hands the model to the game when the unit dies and frees the unit at once, so gameplay is unchanged and a corpse cannot be selected, targeted or walked into. The model plays the clip and frees itself when it ends.

`scenes/models/scout_death_fx.tscn` is spawned on the corpse at that moment: oil jets, droplets, splats and a spreading pool, exposed wiring and sparks from `assets/models/effects/scout_death_oil.glb`, which is keyed to the body's movement frame by frame. Its wounds are on the chest plate, the neck and the throat inside the collar, which both heads share. To change the timing or length, change the clip and rebuild the effect together in Blender.

## Rebuilding

The scripts are in `Blender/Characters/Scout/build` and run in background Blender:

1. `build_heads.py` on the pre-rework backup adds the two heads.
2. `build_body.py` on that result replaces the body, gear, skates, shotgun and ponytail, adjusts the rest pose and re-keys the gun and left arm.
3. `death_build.py -- <repo> <scratch folder> scout` rebuilds `die` and the effect, exports both GLBs and saves.

Each step expects the file the previous one produced; `build_body.py` does not run twice on its own output.

## Checks

- `tests/scout_model_test.gd` (headless): clips and loops, exactly one head visible, size and facing, light off at rest and driven by the flash bone, first shot on the firing frame, barrel on the target, wind-up with no early damage.
- `tests/scout_model_runtime_check.gd` (rendered): saves idle, run, wind-up, flash and shell poses, close views and the flash at play distance. Its output folder must exist before it runs.
