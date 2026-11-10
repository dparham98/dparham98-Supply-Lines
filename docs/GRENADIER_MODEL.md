# Grenadier model

`scenes/gameplay/grenadier.tscn` uses `scenes/models/grenadier_model.tscn`, which instances `assets/models/units/grenadier.glb` and drives it with `scripts/components/character_animator.gd`. The working file is `Blender/Characters/Grenadier/Grenadier.blend`. Its revision from before rigging is in `Blender/Backups/Grenadier/`.

## Rig

36 bones. The body is `root`, `hips`, `spine`, `chest`, `neck`, `head`, arms and legs (`upper_arm`, `forearm`, `hand`, `thigh`, `shin`, `foot`), with `pauldron.L/R` following the upper arms halfway and `pack` riding the chest. The coat has three columns each side (`coat_f`, `coat_s`, `coat_b`), two lengths each (`_lo` is the lower), plus `tabard`.

`gun` is a child of `root`, not of the hand, so she can drop the launcher when she dies. In the other clips her hands are solved onto it. `flash` sits on the muzzle.

Machine limbs are skinned rigidly by mesh island, so plates never stretch. Cloth, torso and neck are skinned by position.

Godot needs node names unique across a glTF, so a mesh must not share a name with a bone. That is why the meshes are called `face` and `tabard_plate`.

## Clips

| Clip | Length | Notes |
| --- | --- | --- |
| Rest | 2.0 s, loops | Slow breathing, launcher carried low at her right. |
| Run | 0.75 s, loops | Launcher held low across the body in both hands, coat swinging from the thighs. A 1.5 m stride, so normal rate at 2 m/s. |
| Shoot | 1.21 s, once | Shouldered and braced. The shot lands 0.125 s in (`shot_lead_time`), and the clip ends in the aimed pose held between shots. |
| Die | 4.17 s, once | The pack ruptures, the launcher falls, her knees go and she drops on her right side. Oil and sparks come from `scenes/models/grenadier_death_fx.tscn`, on the same timeline. |

Clips start at frame 0, so a loop closes without a held frame. The model has no work clip because Grenadiers neither build nor gather.

`gun_rest_axis` on the model scene is the barrel direction in skeleton space on the first frame of Rest. Update it if that pose changes.

## Grenade shot

`scenes/gameplay/grenade_round.tscn` is the model file's grenade, enlarged 1.8 times to read from the game camera, with a team-coloured trail. It flies at 11 m/s in an arc (`arc_ratio` on `scripts/gameplay/projectile.gd`) and tumbles. `scenes/gameplay/grenade_blast.tscn` plays where it lands, with smoke thrown out to about the weapon's 3 m splash radius. Damage lands when the shot is fired, as with every other weapon, so the health change comes slightly before the grenade arrives.

`tests/grenadier_model_test.gd` covers the clips, facing and size, motion, the shot, the grenade and the death. Review renders are `animation_ingame.png` and `grenade_shot_ingame.png` in `Blender/Previews/Grenadier/`.
