# Wainwright model

Asked for on 2026-11-25. The Wainwright is the Arthurian Knights' cartwright and track works (docs/KNIGHTS_RAIL.md). Once one stands, Keeps can lay track and build trains. Its palette is the Keep's, Chapterhouse's and House's: ivory stone, timber, brass and a team-blue roof. The materials are named `wwr_*`, plus `brass`, `team_color` and `team_color_shadow`.

## The model

- **Size.** True scale in metres. The plinth fills 3.96 x 3.96 m of the 4 x 4 footprint. The banner pole reaches 2.65 m and the chimney 3.1 m.
- **Facing.** The open yard faces -Y in Blender, which is +Z in the game, toward the default camera.
- **Budget.** About 5,750 triangles, with flat PBR materials and no image textures.

The parts (object names in the GLB):

- `plinth`: a stone kerb around a plank yard.
- `workshop`: an open-fronted timber-framed shed with ivory walls, wheels hung inside, an amber end window and a stone chimney. `roof` is the gabled team-blue roof.
- `wheel_bench`, with `wheel` (turns about its hub) and `chips` (flying shavings).
- `wainwright`: the cartwright in a leather apron, one hand on the rim. `wainwright_arm` (pivot at the shoulder) holds the adze, modelled at the cut.
- `rail_stack`: stacked sleepers and rails on chocks.
- `sheerlegs`: a three-legged timber crane with a windlass coil. `crane_load` (pivot at the head) is the rope, hook and a slung rail.
- `banner_pole` and `banner`: a team banner, hinged on its crossbar.
- `smoke_1`..`smoke_4`: chimney smoke.

`wainwright_death_fx.glb` holds `Flash_Wainwright`, `fx_fire_*`, `fx_smoke_*` and `fx_debris_*`.

## Clips (24 fps)

| Clip | Length | Use |
|---|---|---|
| Idle | 4 s loop | The wainwright dresses the wheel with the adze once a second, and chips fly at each cut. The wheel turns a spoke every 2 s. The slung rail sways, the banner stirs and a thread of smoke rises. |
| Build | 4.2 s | Scrubbed by construction progress: the yard, then the shed rises and the roof lowers on. The rails, bench, sheerlegs, banner and the wainwright follow. |
| Die | 2.7 s | The roof drops, the sheerlegs and banner pole fall, and the wreck sinks 5 m from 1.8 s. `wainwright_death_fx` plays `Death` on the same timeline. |

Idle loops through `_subresources` in `wainwright.glb.import`. The Wainwright makes no units, so it has no production clip.

## In the game

- `scenes/models/wainwright_model.tscn` instances the GLB as `Rig` and runs `scripts/components/production_rig.gd`. Idle plays while it stands, Build follows construction, and Die plays with `wainwright_death_fx.tscn`.
- `scenes/gameplay/wainwright.tscn` takes the model in its `Visuals` slot. Before this it borrowed the House.
- Team paint repaints the roof and the banner.
- Selection icon: `assets/ui/renders/wainwright.png` (`icon_name()` returns `wainwright`). Portrait: `assets/ui/portraits/wainwright.png`. Build card: `sl_build_wainwright.png`. All come from `render_hud_images.gd -- wainwright`.
- Rendered check: `tests/knights_rail_runtime_check.gd`.

## Rebuilding

```
blender --background --python Blender/Buildings/Wainwright/build/build_wainwright.py
blender Blender/Buildings/Wainwright/Wainwright.blend --background --python Blender/Buildings/Wainwright/build/animate_wainwright.py
blender Blender/Buildings/Wainwright/Wainwright.blend --background --python Blender/Buildings/Wainwright/build/export_wainwright.py
blender Blender/Buildings/Wainwright/Wainwright.blend --background --python Blender/Buildings/Foundry/build/render_review.py -- Blender/Previews/Wainwright wainwright turnaround Idle Build Die
Godot --path . --script res://scripts/tools/render_hud_images.gd -- wainwright
```

The helpers come from `Blender/Buildings/Foundry/build/building_kit.py`.
