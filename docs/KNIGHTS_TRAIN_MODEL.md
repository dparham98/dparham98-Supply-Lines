# Knights train model

Asked for on 2026-11-25. This is the Arthurian Knights' coal-fired take on the maglev car (docs/KNIGHTS_RAIL.md). On 2026-11-26 it was rebuilt as an armoured streamliner after the Knights tech concept art. It has a faceted bullet nose with cyan headlights and a raked dark-glass cockpit, and an ivory armoured hull under a team-blue roof cowling. There is a cab door, a wide blue-framed boarding door, and brass cooling louvers over the glowing coal reactor at the rear. Shrouded bogie sleds carry it. The materials are named `kt_*`, plus `brass` and `team_color`.

## The contract

The car keeps the Astra Streamliner's runtime contract (`Blender/Vehicles/Maglev/Astra_Streamliner/validation/audit/accepted_contract.md`), so `scripts/rails/train_consist.gd` places it unchanged. All sizes are authored metres, and the game scales the car by 0.6. In glTF and Godot (Blender -Y is +Z):

| Node | Position (m) | Role |
|---|---|---|
| `train_cargo_root` | 0, 0, 0 | Root |
| `cargo_body` | 0, 2.50, 0 | Fixed body |
| `sled_cargo_front` / `sled_cargo_rear` | 0, 1.00, ±3.00 | Track followers |
| `cargo_coupler_F` / `cargo_coupler_R` | 0, 1.67, ±5.50 | Coupling markers |
| `cargo_car_indicator` | 0, 3.60, -3.55 | The cargo lantern, raised 0.32 when loaded |

The car spans about X ±1.75, Y 0.68–3.97 and Z ±5.45, like the Streamliner. Budget: about 6,900 triangles, with no textures and no clips. Under `cargo_body` there are also `firebox_glow` (the coal reactor's glow under the rear louvers), `firebox_embers` and `stack_smoke_1`..`5` (exhaust from the dorsal vents). The 2026-11-26 car has no pennants.

## In the game

- `scenes/models/knights_train_model.tscn` holds `Car1` (`assets/models/units/knights_train_cargo.glb`) at 0.6 scale. Its root runs `scripts/rails/knights_train_model.gd`, which extends `train_consist.gd` and so keeps `place`, `length` and `chord_back`.
- `train.gd` calls `set_running(moving)` and `set_out_of_fuel(empty)` each frame for a `coal_fuelled` train:
  - **Running:** the fire roars and flickers, and smoke puffs from the stack every 0.32 s, rising and trailing toward the tail. The tail is worked out from the sleds, so a reversing train trails the right way.
  - **Standing:** a low fire and a thin, slow wisp.
  - **Out of coal:** only the banked embers glow, and there is no smoke.
- Derailing uses the existing train's slew, roll and drop (`train.gd derail()`). Like the Streamliner, the car has no death clip.
- `scenes/gameplay/knights_train.tscn` takes the model in its `Visuals` slot. Before this it borrowed the Streamliner.
- Team paint repaints the roof cowling, the boarding-door frame and the cab-side panels.
- Selection icon: `assets/ui/renders/knights_train.png` (`icon_name()` returns `knights_train` for a coal-fuelled train). Portrait: `assets/ui/portraits/knights_train.png`. Production card (the Keep's Train tile): `sl_produce_knights_train.png`.
- Rendered check: `tests/knights_rail_runtime_check.gd`.

## Rebuilding

```
blender --background --python Blender/Vehicles/KnightsTrain/build/build_knights_train.py
blender Blender/Vehicles/KnightsTrain/KnightsTrain.blend --background --python Blender/Vehicles/KnightsTrain/build/export_knights_train.py
blender Blender/Vehicles/KnightsTrain/KnightsTrain.blend --background --python Blender/Buildings/Foundry/build/render_review.py -- Blender/Previews/KnightsTrain knights_train turnaround
Godot --path . --script res://scripts/tools/render_hud_images.gd -- knights_train
```
