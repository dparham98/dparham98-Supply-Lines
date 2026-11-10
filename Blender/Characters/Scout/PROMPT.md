# Scout rework prompt

Rework the Scout to match `Blender/References/Scout_concept.webp`, on the existing rig, and add a second head so a Scout can appear bare-headed or helmeted. The sheet is the target, including its proportions: when the current model and the sheet disagree, follow the sheet. This is an art change. Stats, abilities and gameplay code stay as they are.

Read `AGENTS.md`, `Blender/README.md` and `docs/SCOUT_MODEL.md` first.

## Start from the rigged model

Work in `Blender/Characters/Scout/Scout.blend`. Do not start a new character or build a new rig.

`Blender/Characters/Scout/Scout rigged.blend` is the user's saved copy of the current look. Do not edit it or work from it, because it has no `die` clip or death effect.

First copy `Scout.blend` to `Blender/Backups/Scout/Scout_2026-11-10_before_rework.blend`. Keep editing the one working file, with no numbered copies. Set `save_version = 0` so no new `.blend1` appears, and leave the `Scout.blend1` already in git alone.

Run Blender in the background on that file. Do not use the Blender MCP tools or touch the user's open Blender window, which may hold unsaved work.

```
"C:\Program Files\Blender Foundation\Blender 4.5\blender.exe" <file.blend> --background --python <script> -- <args>
```

## Keep unchanged

The game depends on these names, so keep them even where the shapes change:

- Armature object `Skater rig` with its 39 bones, their names and hierarchy.
- Actions `idle`, `run`, `shoot` and `die`, with their lengths and the shot on the same frame (`shot_lead_time` is 0.375 s).
- Facing -Y, Z up, wheels on the ground. Stay within 1.4 to 2.1 m tall, which `tests/scout_model_test.gd` enforces.
- The objects `Muzzle flash`, `Muzzle light` and `Shell casing`, and their parent bones. `scenes/models/scout_model.tscn` finds them by path.

## Free to change

- Every mesh, and the body's proportions, to match the sheet.
- Bone positions and lengths in the rest pose, so the skeleton fits the new body.
- Keys in the four clips, but only where the new proportions break them, such as feet leaving the ground, hands missing the gun, or limbs clipping armour. Keep the motion itself.
- The gun's shape and pose. The barrel must still run along the `gun` bone with its tip at the `flash` bone, and hands must meet the grip and the `pump` in `idle` and `shoot`. If the barrel's line changes, re-measure `gun_rest_axis` and `gun_sample_time` in the model scene.

## What is there now

| Object | Bound by | Tris before subdivision | UVs |
| --- | --- | --- | --- |
| `Body • armored female` | Armature | 700 | None |
| `Armor • light plates` | Armature | 2,626 | None |
| `Fingers • gloved` | Armature | 824 | None |
| `Hair • blonde ponytail` | Armature (`hair1` to `hair3`) | 464 | None |
| `Skates • inline` | Armature | 716 | None |
| `Head • angular tapered helmet` | Parented to bone `head` | 162 | Yes |
| `Skate wheel L1` to `R4` | Parented to bones | 400 each | None |
| `Shotgun • pump`, `Shotgun pump` | Parented to `gun`, `pump` | 412, 508 | None |

Materials are flat PBR with no image textures. Only the Scout's face may need one (below).

## Stage 1: the head, then stop

Build only the two heads, then show the user and wait for a decision before touching the body. Faces are the riskiest part of this job, and this is the cheap point to stop.

**Bare head (from the sheet's HEAD DETAIL).** Strong, angular female face, pale skin, a steel cyborg plate along the jaw and cheek. Blonde hair in a high ponytail with loose strands at the temples. Dark headband with a blue-grey band, and round brass-rimmed goggles with amber lenses pushed up on the forehead. High black collar with red edging.

Do not script facial detail vertex by vertex. Make a simple, clean head mesh, unwrap it, and project or paint the sheet's face onto it as a texture of about 1024 px. Let the goggles, hair and jaw plate carry the character. The target is passable at a close-up and clean at game distance, not realistic.

**Helmet.** Keep the existing helmet shape. Retexturing it is explicitly allowed, so give it the sheet's worn gunmetal with red trim. Make sure the ponytail still comes out of it cleanly.

Both heads go on the `head` bone as separate objects with clear names, such as `head_bare` and `head_helmet`, with hair and goggles as their own objects if they differ. Do not name a mesh the same as any bone, because Godot would then rename the bone.

**Show the user:** a turnaround of each head, one close portrait, and a Godot render at the game's camera distance. If the face does not pass, offer these options and let the user pick: goggles down over the eyes, or the 3D generator. The generator runs in the user's Blender and may cost a credit, so use it only with their approval.

## Stage 2: the body

Silhouette first, since this is an RTS seen from a high camera: (1) segmented steel limb plates and large shoulder plates, (2) backpack with an amber panel, (3) chunky inline skates with four amber-lit wheels, (4) ponytail, (5) shotgun.

Rebuild the body to the sheet's FRONT, SIDE and BACK views: a tall, athletic figure with long legs, a narrow waist, full hips and glutes, a full chest under fitted plates, and slim arms. Set up orthographic comparisons against those views before detailing, and fit the rig's rest pose to the new body.

- **Palette.** Charcoal bodysuit, worn gunmetal plates, oxblood red piping, tan-brown leather, amber glow only on the backpack and skates.
- **Torso.** Fitted steel chest plates over the bodysuit, red edging, high collar. Leather belt with a plain buckle and pouches on both hips.
- **Limbs.** Segmented arms and legs in steel with red channels down the outside of the legs, faceted knee plates, long shin guards, articulated steel gloves. A holster on the right thigh.
- **Backpack.** Central block with an upright amber panel, side canisters, shoulder straps. Bind it to `chest`.
- **Shotgun.** Reshape to the sheet: skeletal stock, pistol grip, top rail, ribbed brown pump. See the aim rule above.

Parent rigid plates to a single bone where that works, and copy weights from the existing meshes for anything that deforms. Check `run`, `shoot` and `die` at the elbows, knees, hips and neck for tearing and clipping.

Budget about 25,000 exported triangles, up from about 11,000. The body meshes have no UVs, so stay with flat PBR materials, matching the other units, unless a texture clearly earns its cost.

**Insignia.** No real-world insignia, flags or symbols. The iron crosses on the sheet's shoulder plates become the faction fang, the `faction_fang` mesh in `Blender/Vehicles/Drone/Drone.blend`. The sheet's title-block logo is not part of the model, and the belt buckle and chest badge stay plain.

## Death effect

Collection `scout_death_fx`, switched off in the view layer, is keyed to the body frame by frame. New proportions will almost certainly move the body away from it, so expect to rebake it. `Cyber_Guts_Chest`, `Cyber_Guts_Neck`, the oil coats, jets and pool must sit on the new chest and neck with both heads, then re-export `assets/models/effects/scout_death_oil.glb`. The script that first built it may still be at `C:\Users\video\AppData\Local\Temp\claude\60df2e8a5fe9c284\b5732938-6bae-4d13-8497-d079c9e8c3a1\scratchpad\death_build.py`, which has a Scout branch. It is a useful guide if it's there, but don't depend on it.

## Export and game

Export to `assets/models/units/scout.glb` with subdivision off, animations as actions, glTF Binary, +Y up, apply modifiers, lights on. Confirm the GLB has exactly the clips `idle`, `run`, `shoot` and `die`, and none of the file's `*_Death` actions. Keep the existing `scout.glb.import`, because it holds the loop settings.

Each Scout picks one head at random when it is created, which is the default unless the user says otherwise. Both heads are authored in the model scene and the choice only switches their visibility, because gameplay scripts must not create visuals at runtime. Do it in a small component on `scenes/models/scout_model.tscn`, and make sure a corpse keeps the head it had.

## Checks

Godot is `C:\Dev\Tools\Godot_v4.7.2-stable_win64_console.exe`.

- Run `tests/scout_model_test.gd`, and extend it to check that exactly one head is visible.
- Run `tests/scout_model_runtime_check.gd` (rendered) and look at the output yourself.
- Render both variants in Godot at game distance and close up, including `run`, `shoot` and a death, and save them to `Blender/Previews/Scout`.
- A test passes only with exit code 0, no `ERROR:` or `SCRIPT ERROR` lines, and its `*_PASSED` marker.
- Headless checks never count as visual verification.

## Finish

Work on a `feature/scout-rework` branch from `origin/main` in your own worktree. This prompt and `Scout_concept.webp` may exist only in `C:\Dev\Supply-Lines`, so copy them in if they are missing. Commit and open a draft PR only when the user asks, and never merge without their explicit approval.

Update the Scout entry in `Blender/README.md` and `docs/SCOUT_MODEL.md`.
