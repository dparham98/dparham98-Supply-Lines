# Foundry model

Asked for on 2026-11-25. This is the Cyborgs' upgrade building (docs/UPGRADES.md): a works hall in the Barracks' style, with a crucible that pours, a stamping press, a rifling lathe and cooling stacks. It researches the Infantry and Vehicle weapon and armour lines. Its materials are the Barracks' dark steel, gunmetal and brass, renamed `fdy_*`, plus `brass` and `team_color`.

## The model

- **Size.** True scale in metres. The plinth fills 5.9 x 5.9 m of the 6 x 6 footprint. The stacks reach about 4.7 m.
- **Facing.** In Blender the door side faces -Y. In the game that is +Z, toward the default camera, as for the other buildings.
- **Budget.** About 10,800 triangles, with flat PBR materials and no image textures.

The parts (object names in the GLB):

- `plinth`: the stepped base, with hazard edging along the front.
- `hall`, with `hall_badge` and the faction fang `hall_fang` (from the Drone): the riveted works hall at the back. `hall_roof` carries the `vent_fan`.
- `stack_1`..`stack_3`: the cooling stacks, with brass bands. `smoke_1`..`smoke_9` are the smoke puffs above them.
- `furnace`, with `furnace_glow`: the brazier under the crucible gantry (`crucible_gantry`).
- `crucible`, with `crucible_melt`: it pivots on its trunnions to pour. `pour_stream` runs from its spout into the `mould`, and `mould_glow` fills the mould.
- `press_frame`: the stamping press. `press_ram` moves up and down, `press_plate` is the armour plate it stamps, and `press_sparks` fly from the plate.
- `lathe`: the rifling lathe. `lathe_barrel` turns, while `lathe_tool` and `lathe_sparks` slide along it.
- `plate_rack`: finished plates, ready to ship.

`foundry_death_fx.glb` holds `Flash_Foundry`, `fx_fire_*`, `fx_smoke_*`, `fx_plate_*` (thrown armour plates) and `fx_spill` (molten metal).

## Clips (24 fps)

| Clip | Length | Use |
|---|---|---|
| Idle | 4 s loop | The fan turns slowly, the glows pulse and thin smoke rises. |
| Research | 4 s loop | Plays while an upgrade is researched. The crucible tips 38° and pours into the mould (0.85 to 2.7 s). The press stamps twice, with sparks. The lathe turns a barrel at 1.5 turns a second while the tool travels. Heavy smoke comes from the stacks. |
| Build | 4.2 s | Scrubbed by construction progress: the plinth, then the hall, furnace and press, then the roof lowers on. The stacks and the glows come last. |
| Die | 2.7 s | The roof and stacks fall, the crucible spills, and the wreck sinks 5 m from 1.8 s. `foundry_death_fx` plays `Death` on the same timeline. |

Idle and Research loop through `_subresources` in `foundry.glb.import`.

## In the game

- `scenes/models/foundry_model.tscn` instances the GLB as `Rig`. Its root runs `scripts/components/research_rig.gd`, which extends `production_rig.gd`. `temple_of_science.gd` calls `show_research(active)` every frame, and the rig blends between Idle and Research over 0.4 s. Build and Die work as for the Barracks: the construction site scrubs Build, and `play_death` plays Die with `foundry_death_fx.tscn`.
- Team paint repaints every `team_color` surface: the hall's band and badge, and the stacks' bands.
- `scenes/gameplay/foundry.tscn` takes the model in its `Visuals` slot.
- Selection icon: `assets/ui/renders/foundry.png`. Portrait: `assets/ui/portraits/foundry.png`. Build card: `sl_build_foundry.png`. All come from `render_hud_images.gd -- foundry`.

## Rebuilding

```
blender --background --python Blender/Buildings/Foundry/build/build_foundry.py
blender Blender/Buildings/Foundry/Foundry.blend --background --python Blender/Buildings/Foundry/build/animate_foundry.py
blender Blender/Buildings/Foundry/Foundry.blend --background --python Blender/Buildings/Foundry/build/export_foundry.py
blender Blender/Buildings/Foundry/Foundry.blend --background --python Blender/Buildings/Foundry/build/render_review.py -- Blender/Previews/Foundry foundry turnaround Research Build Die
Godot --path . --script res://scripts/tools/render_hud_images.gd -- foundry
```

`building_kit.py`, in the same folder, holds the mesh and baking helpers. The Forge uses it too. `build_foundry.py` reads the faction fang from `Blender/Vehicles/Drone/Drone.blend`; set `SL_DRONE_BLEND` to use another copy.
