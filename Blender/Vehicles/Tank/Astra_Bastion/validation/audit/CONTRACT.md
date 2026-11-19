# Accepted tank contract

The working source is `Blender/Vehicles/Tank/Tank.blend`, in metric units at 1 m per Blender unit. The editable vehicle lives in the `Tank` collection. The original's separate firing and death collections supply effects that the gameplay wrapper instances independently. The Blender body faces −Y with +Z up. The glTF export faces +Z with +Y up.

`scenes/gameplay/tank.tscn` instances `scenes/models/tank_model.tscn` in `Visuals/Model`. The wrapper imports `assets/models/units/tank.glb` at resource scale 1 and rotates Y 180° with uniform scale 0.6. An idle game unit faces −Z. The original whole vehicle measures 5.64 m across, 11.476 m including the gun and 5.0 m high including the mast. Its world dimensions are 3.384 × 6.885 × 3.0 m. The lowest tread touches the ground. The main hull’s underside is 0.55 m above it in Blender, or 0.33 world m.

| Source part | Original pivot in Blender XYZ (m) | Original extents or function |
| --- | --- | --- |
| `Tank_Root/Tank_Hull` | 0, 0, 0 | Main casting X ±1.55, Y −4.25 to 4.15, Z 0.55 to 2.05 |
| `Tank_Turret` | 0, 0.50, 2.16 | Original central casting X ±1.85, Y −1.60 to 2.70, Z 2.16 to 3.08 |
| `Barrel_Mount` and `Tank_Barrel` | 0, −1.45, 2.62 | Barrel recoils inside its mount |
| `Barrel_Muzzle_Brake` | 0, −6.65, 2.62 | Forward brake face and firing origin 0, −7.10, 2.62 |
| `Track_Links_L`, `Track_Links_R` | ±2.05, 0, 0 | Outer edges X ±2.48, Y −4.34 to 4.38, bottom Z 0, top Z 1.61 |

The built-in turret aim script provides unrestricted yaw, 240°/s slew and a 6° idle sway with a 7 s period. The barrel remains level throughout. The rig slides the barrel back 0.55 authored m in 0.06 s and returns it over 0.55 s. It also rocks the hull. The `MuzzleFx` instance stays on `Barrel_Mount`, 5.65 authored m forward. The projectile starts at the rested brake tip and the muzzle flash plays at that same attachment. The shader moves each row of 37 links by vertex ID in groups of 24. The same rig rolls the six merged link, wheel and roller meshes and rotates the four individual sprocket/idler nodes. The base vehicle GLB contains no clips or skeleton.

Death clips live in the three separate Godot effect scenes. They drive the real hull, turret and gun mount. Bleed-out hides `Track_Links_L`, and overload removes `Hull_Driver_Hatch` and `Turret_Hatch`. The scorch overlay applies to the model, and it switches off meshes whose names begin with `Neon_`.

Gameplay uses the 1 m terrain grid and reserves one cell per ground actor. The smoothed movement route checks a 0.35 m half-width. Picking instead uses the visible meshes’ local bounds, with the ground marker and FX excluded. The tank has no physics-body collider in its actor scene. The selected player's 4 × 6.8 m marker is centered at (0, 0.06, −0.4) world m in the actor.

Tank stats, fuel rules, forest clearance and shell logic all belong to the existing game resources. Unit stats specify 6 m/s movement, 90°/s chassis turning, 150 health, 30 m attack range and 52 m vision. The standard team system applies per-instance surface overrides to the imported material named `team_color`. The shipped player/enemy/neutral palette is green/red/gray. The separate art review supplies its blue player swatch.

## Repeating the checks

Run these commands from the repository root, using Blender 4.5 and the pinned Godot release.

```powershell
python Blender/Vehicles/Tank/Astra_Bastion/validation/audit/preservation.py
blender -b --factory-startup --python-exit-code 1 -P Blender/Vehicles/Tank/Astra_Bastion/validation/audit/measure.py
python Blender/Vehicles/Tank/Astra_Bastion/validation/audit/run_runtime.py --godot C:/Dev/Tools/Godot_v4.7.2-stable_win64_console.exe
```

The first command checks 53 SHA-256 digests captured before export. The geometry check reads both actual GLBs. The runtime check stages a complete disposable game copy outside the checkout, replaces its tank GLB, imports fresh and runs the repository's suites plus a real move-order and material-isolation check. The viewport test renders a pair of track poses with a graphics device. Add `--baseline` to run the same fixture against the accepted tank.
