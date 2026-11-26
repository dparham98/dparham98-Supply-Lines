# Forge model

Asked for on 2026-11-25. This is the Arthurian Knights' upgrade building (docs/UPGRADES.md): an open-sided smithy and armoury that researches the Arms and Mail lines. Its palette is the Keep's and Chapterhouse's: ivory stone, silver, heraldic brass and a slate roof with a team-painted guild gable. It adds timber, leather and amber glass. The materials are named `frg_*`, plus `brass`, `team_color` and `team_color_shadow`.

## The model

- **Size.** True scale in metres. The plinth fills 5.96 x 5.96 m of the 6 x 6 footprint. The chimney reaches 5.15 m.
- **Facing.** The open front faces -Y in Blender, which is +Z in the game, toward the default camera.
- **Budget.** About 17,450 triangles, with flat PBR materials and no image textures.
- **Open-sided.** The gabled roof shelters the rear work bays, so from the game camera you look straight onto the anvil and the yard.

The parts (object names in the GLB):

- `plinth`: staggered flagstones with low stone side walls and coping.
- `hearth`: the firebrick-lined hearth with a segmented stone arch, a hood and a tall banded chimney (back left), plus a coal heap. `hearth_fire` is the fire in its mouth.
- `bellows`: the leather bellows on a timber cradle. `bellows_board` hinges at the nozzle end.
- `frame` and `roof`: timber posts, braces and a low back wall with an amber-glass window. Overlapping slate courses meet at a brass ridge. An anvil sign sits under the projecting guild gable.
- `weapon_rack`: six swords and three lances with team pennons, against the back wall.
- `anvil`, with `anvil_billet` (the hot work) and `anvil_sparks`, on a banded stump.
- `smith`: the smith in a leather apron, holding the billet with tongs. `smith_arm` (pivot at the shoulder) holds the hammer and is modelled at the moment of the blow.
- `trough`: the stone quench trough, with `trough_water` and `quench_steam`.
- `hauberk`: a mail hauberk and coif on a stand, with a team tabard.
- `banner_pole_1`/`_2` and `banner_1`/`_2`: team banners at the front corners. Each banner hinges on its crossbar.
- `smoke_1`..`smoke_8`: chimney smoke.

`forge_death_fx.glb` holds `Flash_Forge`, `fx_fire_*`, `fx_smoke_*` and `fx_debris_*` (stone, timber and slate).

## Clips (24 fps)

| Clip | Length | Use |
|---|---|---|
| Idle | 4 s loop | Low embers in the hearth, a thread of chimney smoke and stirring banners. The smith rests with the hammer on the anvil. |
| Research | 4 s loop | Plays while an upgrade is researched. The bellows pump every 2 s and the hearth flares as they close. The smith raises the hammer overhead and strikes the billet once a second, with a burst of sparks on each blow. Steam rises off the trough (2.2 to 3.9 s), and heavy smoke from the chimney. |
| Build | 4.2 s | Scrubbed by construction progress: the flags, the hearth and chimney, the frame, then the roof lowers on. The anvil, trough, rack and hauberk follow, then the banners, the smith and the fire. |
| Die | 2.7 s | The roof drops, the rack and hauberk topple, the banner poles fall and the chimney leans. The wreck sinks 5 m from 1.8 s. `forge_death_fx` plays `Death` on the same timeline. |

Idle and Research loop through `_subresources` in `forge.glb.import`.

## In the game

- `scenes/models/forge_model.tscn` instances the GLB as `Rig` and runs `scripts/components/research_rig.gd`, as the Foundry does. `show_research(active)` blends between Idle and Research.
- Team paint repaints the gable, the banners, the pennons and the tabard.
- `scenes/gameplay/forge.tscn` takes the model in its `Visuals` slot. Before this it borrowed the Chapterhouse model.
- Selection icon: `assets/ui/renders/forge.png`. Portrait: `assets/ui/portraits/forge.png`. Build card: `sl_build_forge.png`. All come from `render_hud_images.gd -- forge`.

## Rebuilding

```
blender --background --python Blender/Buildings/Forge/build/build_forge.py
blender Blender/Buildings/Forge/Forge.blend --background --python Blender/Buildings/Forge/build/animate_forge.py
blender Blender/Buildings/Forge/Forge.blend --background --python Blender/Buildings/Forge/build/export_forge.py
blender Blender/Buildings/Forge/Forge.blend --background --python Blender/Buildings/Foundry/build/render_review.py -- Blender/Previews/Forge forge turnaround Research Build Die
Godot --path . --script res://scripts/tools/render_hud_images.gd -- forge
```

The helpers come from `Blender/Buildings/Foundry/build/building_kit.py`. Set `SL_BUILDING_KIT` to use another copy.
