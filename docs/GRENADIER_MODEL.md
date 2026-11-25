# Grenadier model

`scenes/gameplay/grenadier.tscn` uses `scenes/models/grenadier_model.tscn`, which instances `assets/models/units/grenadier.glb` and drives it with `scripts/components/character_animator.gd`. The working file is `Blender/Characters/Grenadier/Grenadier.blend`. Its revision from before rigging is in `Blender/Backups/Grenadier/`.

## Portrait looks

The unit has two matching model and portrait sets in `Blender/Characters/Grenadier/looks`. **The game uses Goggles** (chosen 2026-11-24): `assets/models/units/grenadier.glb` and `assets/ui/portraits/grenadier.png` are the Goggles pair. **Goggles** wears brass-rimmed field goggles over the eyes. **NoGoggles** exposes the same grey-green eyes and steel cheek plate. Both use the same fitted peaked cap, swept blonde hair and full animation rig. The 720 × 408 portrait is rendered from the corresponding playable GLB in Rest.

From the project root, switch both playable assets with `python Blender/Characters/Grenadier/use_look.py NoGoggles` or `python Blender/Characters/Grenadier/use_look.py Goggles`. Let the Godot editor finish importing before running the game. Select the Grenadier to see the matching portrait in the HUD.

The editable source is `Blender/Characters/Grenadier/Grenadier.blend`. Toggle the `goggles` mesh to compare the looks in Blender. To regenerate both models after an edit, run Blender 4.5 in background mode with the working file and `-P Blender/Characters/Grenadier/export_looks.py`. To refresh either portrait, run Blender with `-b --factory-startup -P Blender/Characters/Grenadier/render_portrait.py -- <look-folder>/grenadier.glb <look-folder>`. The renderer writes the full master and the game PNG. Run the look switch again to publish that pair.

## Full-body studio views

The Grenadier wears a fitted cuirass, a lined greatcoat with walking vents, articulated leg armor, and strapped field boots. The field pack, belt pouches, gloves, and launcher furniture carry modeled detail for close-up portraits.

`Blender/Previews/Grenadier/` contains front and rear views (`Grenadier-body.jpg`), close-ups of the armor, pack and boots (`Grenadier-detail.jpg`), a four-angle sheet (`turnaround.png`), and the Godot turntable (`turntable.mp4`).

To render a look in Blender 4.5, run this command from the project root with Blender on your executable path. Substitute `NoGoggles` to render the alternate look. The final argument names the shots. Omit `--shots` and its list to render every view, including the running and braced poses.

```shell
blender -b --factory-startup -P Blender/Characters/Grenadier/render_body.py -- Blender/Characters/Grenadier/looks/Goggles/grenadier.glb Grenadier-studio --shots front rear armor kit boots
```

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

`scenes/gameplay/grenade_round.tscn` is the model file's grenade, enlarged 1.8 times to read from the game camera, with a team-coloured trail. It flies at 11 m/s in an arc (`arc_ratio` on `scripts/gameplay/projectile.gd`) and tumbles. `scenes/gameplay/grenade_blast.tscn` plays where it lands, with smoke thrown out to about the weapon's 3 m splash radius. Damage lands when the grenade arrives (`damage_on_impact`, see `docs/TURRET_AIM.md`), since the playtest of 2026-11-17.

`tests/grenadier_model_test.gd` covers the clips, facing and size, motion, the shot, the grenade and the death. Review renders are `animation_ingame.png` and `grenade_shot_ingame.png` in `Blender/Previews/Grenadier/`.
