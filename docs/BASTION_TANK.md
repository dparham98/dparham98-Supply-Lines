# Bastion tank

The Bastion replaces the original tank model. `assets/models/units/tank.glb` is now the Bastion export (`Blender/Vehicles/Tank/Astra_Bastion/export/Bastion.glb`, SHA-256 `38f43fdf…a9382`). Edit it in [Bastion.blend](../Blender/Vehicles/Tank/Astra_Bastion/source/Bastion.blend) and re-export with the package's `export_bastion.py`. Nothing else in the game changed.

The model keeps the original tank's node paths, so the existing parts animate it as before:

- `scripts/components/turret_aim.gd` turns the turret through 360° at 240°/s, with the idle sway.
- `scripts/components/tank_rig.gd` recoils the barrel, rocks the hull, rolls the tread links, wheels and sprockets, and plays the muzzle flash at the brake.
- The three death scenes in `scripts/components/tank_death.gd` play on its hull, turret and gun mount. Bleed-out drops the left track and overload blows off both hatches. Loose debris still uses the old tank's effect models.

Six `team_color` surfaces take the team paint: four shoulder inserts, the turret panels and the roof stripe. The wrapper (`scenes/models/tank_model.tscn`) is unchanged, keeping its 180° turn and 0.6 scale. The selection marker, picking, ground cell, stats, fuel and shells are also unchanged.

| | Old tank | Bastion |
| --- | ---: | ---: |
| World width × length × height (m) | 3.384 × 6.885 × 3.000 | 3.348 × 6.885 × 2.454 |
| Triangles / materials | 3,200 / 1 | 6,680 / 12 |
| GLB surfaces | 68 | 117 |

The Bastion has no antenna mast, so it stands 0.55 m lower. The extra surfaces are the main rendering cost; many tanks on screen at once has not been benchmarked.

The package's production notes are in [REPORT.md](../Blender/Vehicles/Tank/Astra_Bastion/validation/REPORT.md) and its pivots in [CONTRACT.md](../Blender/Vehicles/Tank/Astra_Bastion/validation/audit/CONTRACT.md). The review ZIPs and the AutoTurret variant (a roof close-defence gun with new gameplay) are not part of this change.

Checks: `turret_aim_test`, `tank_tracks_test`, `tank_fire_test`, `tank_death_test`, `tank_factory_model_test`, `empty_tanks_test` (headless) and `tank_model_runtime_check`, `tank_factory_model_runtime_check` (rendered).
