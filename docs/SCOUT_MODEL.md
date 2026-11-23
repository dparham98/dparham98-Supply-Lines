# Scout model

The Scout is the cyborg skater from `Blender/Characters/Scout/ScoutCyborg.blend` (rig `ScoutCyborg_Rig`, 35 bones): a figure in steel armour over a charcoal suit, on inline skates, with a pump shotgun. It replaced the earlier skater (`Scout.blend`, `assets/models/units/scout.glb`, rig "Skater rig") on 2026-11-19. Its clips are `idle`, `run`, `shoot` and `die`; the first three came with the art, carried over from the earlier Scout. Since 2026-11-22 its shots fly as the infantry bullet (`scenes/gameplay/infantry_bullet.tscn`), not the plain tracer, after a playtest found its attack hard to see. The `shoot` clip itself is only a raise and one small flash; a stronger kick needs the Blender clip reworked.

## The look

- Steel and light steel plates, dark metal, brass trim and tan leather over a charcoal suit; amber glow on the backpack and skates. Blonde hair and ponytail.
- Team colour is the `team_color` material (stripes on the armour, skates, goggles and gun), which `scripts/components/team_paint.gd` paints by default.

## Two heads

Each Scout has a helmet (`Head_Helmet`) or a bare head (`Head_Face`, `Head_HairCap`, `Head_CyberJaw`, `Head_Goggles`). The ponytail shows with both. All of them are in the one GLB, and the `HeadLook` node (`scripts/components/model_look.gd`) picks one at random when the model is created and only switches visibility; set its `look` to 0 (helmet) or 1 (bare) to force one. A corpse is the same model node, so it keeps its head. In the saved scene the bare head is hidden, so the editor shows the helmet.

The art came as two GLBs, one per head (`scout_cyborg.glb` and `scout_cyborg_helmet.glb`). The game's GLB is exported from the working file with both heads in it instead (`build/export_scout_cyborg.py`), so the helmet GLB is not used.

## What came across from Blender

- `assets/models/units/scout_cyborg.glb` holds the rig, the meshes and the clips. `idle` and `run` loop (`scout_cyborg.glb.import`).
- The muzzle flash and the ejected shell are meshes skinned to the `flash` and `shell` bones, which scale up for their frames, so they export as ordinary animation.
- 352 vertices of a dark-metal piece at the base of `Head_CyberJaw` had no bone weights, so they stayed in place when the head moved, and the glTF exporter added a `neutral_bone` for them. They are bound to `head` now.

## What is rebuilt in Godot

- The GLB has no lights or bone attachments. `scenes/models/scout_model.tscn` adds a `Gun` bone attachment with the muzzle light at the barrel's tip, and `character_animator.gd` sets its energy every frame from the `flash` bone's scale: `flash_light_energy * max(0, scale - 0.001)`. The light is off between shots. `flash_light_energy` is 2.0 and `omni_range` 3 m, as on the earlier Scout. No shadows.
- The flash mesh is overridden with an unshaded hot orange, as before.
- `gun_rest_axis` is the barrel's direction in the skeleton at the first frame of `idle`, from the `gun` bone to the `flash` bone at the muzzle: (0.428, -0.255, 0.867).

## Shot timing

The shot goes off 0.4375 s into the `shoot` clip, when the flash is brightest (0.0625 s later than on the earlier Scout, whose flash peaked at 0.375 s). `shot_lead_time` holds that: the unit starts the clip that early, so the wind-up plays before the shot and damage and tracer land on the flash. Combat timing is unchanged. A first shot with no wind-up time joins the clip at the firing frame. A target that leaves range during the wind-up leaves a flash with no shot.

`shoot` is full-body, so a Scout firing on the move glides in the firing pose while the clip plays.

## Death

`die` is one 4.17 s clip: the fall (about 1 s), the corpse lying there with a few twitches for about two seconds, then a short sink into the ground. The art had no death, so it was carried over from the earlier Scout's `die` by `Blender/Characters/Scout/build/scout_die_transfer.py`: on every frame each bone takes the old bone's movement away from its rest pose and applies it to its own rest pose (`clavicle` became `shoulder`, `wheel.L1` became `wheel1.L`), so the two rigs' different rest orientations do not carry over. The bodies are close in size, so the corpse lies where the old one did.

`scripts/gameplay/unit_agent.gd` hands the model to the game when the unit dies and frees the unit at once, so gameplay is unchanged and a corpse cannot be selected, targeted or walked into. The model plays the clip and frees itself when it ends.

`scenes/models/scout_death_fx.tscn` is spawned on the corpse at that moment: oil jets, droplets, splats and a spreading pool, exposed wiring and sparks from `assets/models/effects/scout_death_oil.glb`, keyed to the earlier Scout's fall frame by frame. The carried-over death keeps that timing, so the effect still lines up.

## Rebuilding

Both scripts are in `Blender/Characters/Scout/build` and run in background Blender from that folder:

1. `blender -b ../ScoutCyborg.blend -P scout_die_transfer.py -- inplace` rebuilds `die` from `../Scout.blend` (the earlier Scout, which must be present) and binds the loose jaw vertices. Only needed if the rig changes.
2. `blender -b ../ScoutCyborg.blend -P export_scout_cyborg.py -- <repo>/assets/models/units/scout_cyborg.glb` exports the rig, both heads and the four NLA tracks.

## Checks

- `tests/scout_model_test.gd` (headless): clips and loops, exactly one head visible, size and facing, light off at rest and driven by the flash bone, first shot on the firing frame, barrel on the target, wind-up with no early damage.
- `tests/scout_model_runtime_check.gd` (rendered): saves idle, run, wind-up, flash and shell poses, close views and the flash at play distance. Its output folder must exist before it runs.
