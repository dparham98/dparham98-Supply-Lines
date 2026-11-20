# Bastion tank

The Bastion replaces the original tank model. It carries two weapons: the main gun and a roof gun. `assets/models/units/tank.glb` is the close-defence export, `Blender/Vehicles/Tank/Astra_Bastion/AutoTurret/export/Bastion_AutoTurret.glb`. It is the Bastion plus a roof turret on the hatch. Edit it in [Bastion_AutoTurret.blend](../Blender/Vehicles/Tank/Astra_Bastion/AutoTurret/source/Bastion_AutoTurret.blend); the plain Bastion's source is beside it in [Bastion.blend](../Blender/Vehicles/Tank/Astra_Bastion/source/Bastion.blend).

## Two weapons, two ranges

| | Main gun | Roof gun |
| --- | --- | --- |
| Range | 10–30 m | 0–10 m |
| Targets | Anything hostile, including buildings | Hostile units only |
| Damage | 12 every 1 s; 50 every 3 s against Tanks and buildings; 3 m splash round the burst; a shell whose target is gone bursts on the ground | 3 every 0.35 s |
| Round | Shell, damage on impact | Bullet at 18 m/s, damage on impact; a target that moves clear is missed |
| Orders | Follows attack and attack-move orders | Always on, picks the nearest hostile unit itself |

- The main gun has a **minimum range** of 10 m (`min_attack_range` in `assets/units/tank.tres`). It cannot target anything nearer: it does not pick such targets on its own and holds its fire at them.
- Order the Tank to attack something inside 10 m and it **backs off** until the target is at 10 m, then fires.
- The roof gun fires **only at short range**. Its reach equals the main gun's minimum, so between them the Tank covers 0–30 m without overlap.
- The roof gun turns through 360° at 360°/s, independently of the main turret, and fires when it is within 3° of its target.
- Each roof-gun shot shows a barrel flash, a plain round with no tracer, and a small burst where it lands. The flash is `AuxMuzzleFx` in `scenes/models/tank_model.tscn`, the main gun's muzzle flash at 0.45 scale. The burst is `scenes/gameplay/aux_bullet_impact.tscn`, the shell impact at 0.55 scale in a hotter orange; like a shell, the round stops on the near face of what it hits.
- Its settings are on the `CloseDefense` node in `scenes/gameplay/tank.tscn` (`scripts/components/close_defense.gd`, round `scenes/gameplay/aux_bullet.tscn`).
- The unit card shows the main gun's range as "10–30" and lists the roof gun on the abilities line.

The roof gun's numbers come from the art package and have not been balance-tested.

## Model

The model keeps the original tank's node paths, so the existing parts animate it as before:

- `scripts/components/turret_aim.gd` turns the turret through 360° at 240°/s, with the idle sway.
- `scripts/components/tank_rig.gd` recoils the barrel, rocks the hull, rolls the tread links, wheels and sprockets, and plays the muzzle flash at the brake.
- The three death scenes in `scripts/components/tank_death.gd` play on its hull, turret and gun mount. Bleed-out drops the left track and overload blows off both hatches. Loose debris still uses the old tank's effect models.

Six `team_color` surfaces take the team paint: four shoulder inserts, the turret panels and the roof stripe. The wrapper (`scenes/models/tank_model.tscn`) is unchanged, keeping its 180° turn and 0.6 scale. The selection marker, picking, ground cell, stats, fuel and shells are also unchanged.

| | Old tank | Bastion |
| --- | ---: | ---: |
| World width × length × height (m) | 3.384 × 6.885 × 3.000 | 3.348 × 6.885 × 2.454 |
| Triangles / materials | 3,200 / 1 | 7,412 / 12 (6,680 without the roof gun) |
| GLB surfaces | 68 | 117 |

The Bastion has no antenna mast, so it stands 0.55 m lower. The extra surfaces are the main rendering cost; many tanks on screen at once has not been benchmarked.

The package's production notes are in [REPORT.md](../Blender/Vehicles/Tank/Astra_Bastion/validation/REPORT.md) and its pivots in [CONTRACT.md](../Blender/Vehicles/Tank/Astra_Bastion/validation/audit/CONTRACT.md). The roof gun's own notes are in [AutoTurret/README.md](../Blender/Vehicles/Tank/Astra_Bastion/AutoTurret/README.md). The review ZIPs are not committed.

Checks: `roof_gun_runtime_check` (rendered: flash, round and hit), `bastion_weapons_test` (both ranges, backing off, the roof gun's hits and card line), `combat_batch_test`, `turret_aim_test`, `tank_tracks_test`, `tank_fire_test`, `tank_death_test`, `tank_factory_model_test`, `empty_tanks_test` (headless) and `tank_model_runtime_check`, `tank_factory_model_runtime_check` (rendered).
