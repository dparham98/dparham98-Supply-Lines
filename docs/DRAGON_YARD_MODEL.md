# Dragon Yard model

Asked for on 2026-11-25. The Dragon Yard is the Arthurian Knights' 6 x 6 production building (docs/KNIGHTS_RAIL.md). It raises the Azure Dragon, orders the coal train, and lets Keeps lay track. It replaces the Wainwright and its model. Its palette is the Keep's and Chapterhouse's: ivory stone, timber, brass and a team-blue roof. The materials are named `dyd_*`, plus `brass`, `team_color` and `team_color_shadow`.

## The model

- **Size.** True scale in metres. The plinth fills 5.96 x 5.96 m of the 6 x 6 footprint. The pen ridge is at 4.9 m. The roost's perch is at 5.4 m and its pennant reaches 6.0 m.
- **Facing.** The pen's open front faces -Y in Blender, which is +Z in the game, toward the default camera.
- **Budget.** About 9,100 triangles, with flat PBR materials and no image textures.

The parts (object names in the GLB):

- `plinth`: a stone kerb with flagstones, and planks under the works corner.
- `pen`: the dragon pen.
  - A stone-footed ivory hall with buttresses and amber lancets.
  - A 3.3 x 3.3 m open front between two piers that carry team banners. The Azure Dragon is 3.6 m across and 3.2 m tall.
  - A timber lintel, a straw floor and a dark back.
- `roof`: the team-blue gable roof with gilded verges. The front gable shows the Knights' star.
- `nest`, `egg` (pivot at its base) and `egg_motes`: a dragon egg in a straw nest, with blue motes that circle it as it quickens.
- `trough`: a feed trough with meat, and hay bales.
- `roost_tower`: the roost, a crenellated stone tower.
  - `perch`: the timber perch on forked posts, with a ring and chain.
  - `pennant_pole` and `pennant`: the team pennant.
- `track`: a short length of track with a buffer stop, and spare rails.
- `wagon` and `wagon_wheel_1`..`4`: a coal wagon on the track, team panel on its side. The wheels turn about X.
- `forge` and `forge_fire`: a forge against the pen wall, with a chimney and bellows.
- `anvil` and `sparks`: the anvil, with a hot bar on it.
- `smith` and `smith_arm`: the smith. The arm pivots at the shoulder and is modelled at the blow.
- `keeper` and `keeper_arm`: the dragon keeper, in a team apron. The arm pivots at the shoulder and holds a pitchfork with a forkful of hay.
- `brazier` and `brazier_fire`: a brazier at the mouth of the pen.
- `banner_pole` and `banner`: the team banner at the front left corner.
- `smoke_1`..`smoke_4`: forge smoke.

`dragon_yard_death_fx.glb` holds `Flash_DragonYard`, `fx_fire_*`, `fx_smoke_*` and `fx_debris_*`.

## Clips (24 fps)

| Clip | Length | Use |
|---|---|---|
| Idle | 4 s loop | Plays while nothing is being made. The smith strikes the anvil every 2 s, with a spray of sparks. The egg stirs, with a few slow motes. The fires flicker, a thread of smoke rises from the forge, and the banner and pennant stir. |
| Work | 4 s loop | Plays while the Yard raises a dragon. The egg rocks and swells, and its motes race round it. The keeper forks hay into the pen twice. The smith strikes twice a second. The forge roars and smokes. The coal wagon is worked 0.35 m along its track and back, its wheels turning. |
| Build | 4.2 s | Scrubbed by construction progress, in this order: the plinth and track, the pen and the roost; the roof lowers on; the perch, the yard's furniture and the wagon; the workers last, then the egg. |
| Die | 2.7 s | The roof drops into the pen, the roost topples outward and the wagon tips off the track. The brazier and banner fall. The wreck sinks 5 m from 1.8 s. `dragon_yard_death_fx` plays `Death` on the same timeline. |

Idle and Work loop through `_subresources` in `dragon_yard.glb.import`.

## In the game

- `scenes/models/dragon_yard_model.tscn` instances the GLB as `Rig` and runs `scripts/components/production_rig.gd`, with `print_clip = Work` and `print_loops = true`.
  - Idle plays while it stands and Build follows construction.
  - Work loops while a dragon is being raised, then Idle returns when the dragon has left.
  - Die plays with `dragon_yard_death_fx.tscn`.
- `print_loops` is a new switch on `production_rig.gd`. With it, the production clip plays at its own speed for as long as something is made, instead of being scrubbed by progress. Buildings without it are unchanged.
- The Knights train is built at a Keep, not in the Yard, so the Yard doesn't play Work for a train.
- `scenes/gameplay/dragon_yard.tscn` takes the model in its `Visuals` slot. Before this it borrowed the House.
- Team paint repaints the roof, the pier banners, the banner, the pennant, the wagon's panel and the keeper's apron.
- The HUD images all come from `render_hud_images.gd -- dragon_yard`:
  - selection icon: `assets/ui/renders/dragon_yard.png` (`icon_name()` returns `dragon_yard`);
  - portrait: `assets/ui/portraits/dragon_yard.png`;
  - Build card: `sl_build_dragon_yard.png`.
- Rendered check: `tests/knights_rail_runtime_check.gd`. It shows the Yard half built, idle, at work and dying. It also checks that Work loops through production and that Idle returns when the unit leaves.

## Rebuilding

```
blender --background --python Blender/Buildings/DragonYard/build/build_dragon_yard.py
blender Blender/Buildings/DragonYard/DragonYard.blend --background --python Blender/Buildings/DragonYard/build/animate_dragon_yard.py
blender Blender/Buildings/DragonYard/DragonYard.blend --background --python Blender/Buildings/DragonYard/build/export_dragon_yard.py
blender Blender/Buildings/DragonYard/DragonYard.blend --background --python Blender/Buildings/Foundry/build/render_review.py -- Blender/Previews/DragonYard dragon_yard turnaround Idle Work Build Die
Godot --path . --script res://scripts/tools/render_hud_images.gd -- dragon_yard
```

The helpers come from `Blender/Buildings/Foundry/build/building_kit.py`. After an export, check that each GLB's size matches the length in its header.
