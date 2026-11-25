# Arthurian Azure Dragon

Rigged and animated armored **Azure Dragon** mount for the Arthurian Space Marines human faction in **Supply Lines**, built to match the Arthurian Marine palette (`Ivory_Armor`, `Heraldic_Brass`, `team_color`, `team_color_shadow`, `Harness_Leather`, `Recessed_Steel`) with a mounted knight fitted from the project's 1.93 m Round Table Marine.

| Asset | Path |
| --- | --- |
| Editable Blender file | [source/Azure_Dragon.blend](source/Azure_Dragon.blend) |
| Exported rigged & animated glTF Binary | [export/azure_dragon.glb](export/azure_dragon.glb) |
| Build orchestrator | [source/build_azure_dragon.py](source/build_azure_dragon.py) |
| Procedural skinning & NLA helpers | [source/rig_dragon.py](source/rig_dragon.py) |
| Walk, Rest & FireBreath animation baker | [source/animate_dragon.py](source/animate_dragon.py) |
| glTF exporter & clean-import verifier | [source/export_dragon.py](source/export_dragon.py) |
| Static studio renderer | [source/render_studio.py](source/render_studio.py) |
| Animation sheet & gameplay AOE renderer | [source/render_animations.py](source/render_animations.py) |
| Walk cycle contact sheet | [preview/walk_sheet.png](preview/walk_sheet.png) |
| FireBreath cone AOE contact sheet | [preview/fire_breath_sheet.png](preview/fire_breath_sheet.png) |
| FireBreath peak 3/4 hero render | [preview/fire_breath_hero.png](preview/fire_breath_hero.png) |
| FireBreath 50-deg RTS gameplay view | [preview/fire_breath_top.png](preview/fire_breath_top.png) |

## Rig & Bone Hierarchy (`Azure_Dragon_Rig`)

- **Orientation & Grounding:** Blender **Z up, −Y forward** (Godot **+Y up, +Z forward** on import), with all four clawed paws planted at ground level **`Z = 0.0`**.
- **Spine, Head & Jaw:** `root -> pelvis -> spine.01 -> chest -> neck.01 -> neck.02 -> head -> jaw`, plus `tail.01..tail.05` off `pelvis`.
- **Mounted knight.** The leather saddle tree and `Rider_Mount` sit at Blender (0, 0.35, 1.892) on `spine.01`. The knight has a sheathed sword, a blue-and-ivory crest, fitted stirrups and two reins. The `Rider_Upper` bone lets the torso counterbalance the stride and brace for fire. [Rider build source](source/mounted_knight.py)
- **Quadruped Limbs & Armor Followers:** `fore_upper.{L/R} -> fore_lower.{L/R} -> fore_foot.{L/R}` (with fractional `pauldron.{L/R}` for the shoulder barding), and `hind_thigh.{L/R} -> hind_shin.{L/R} -> hind_ankle.{L/R} -> hind_foot.{L/R}` (with fractional `flank_tasset.{L/R}` for the flank shields).
- **Articulated Wings:** `wing_arm.{L/R} -> wing_forearm.{L/R} -> wing_finger_1..4.{L/R}` driving smooth vertex-weight membrane folds.
- **Fire-Breath Long Cone Rig:** Parented under `head`: `breath_muzzle -> breath_origin -> breath_seg_0..3` (7.50 m total cone reach, ~3.3 m wide AOE) plus `breath_plume_0..5` and the `Breath_Light` point light. Outside the blast, `breath_origin` scales cleanly to `0.001` inside the closed skull.

## Animation Clips (24 fps NLA Tracks)

| Clip | Blender Frames | Duration | Details |
| --- | --- | --- | --- |
| `Rest` | `1–49` | `2.0 s` | Subtle breathing idle loop with grounded paws, folded wings that rise with the chest, and a slow sway through the trailing tail |
| `Walk` | `1–15` | `0.583 s` | Four-beat ground stride at the unit's 5.5 m/s movement speed. Each cycle travels 3.21 m. The four legs exchange the load, the wings stay tucked along the flanks, and the tapered tail follows the hips. |
| `FireBreath` | `1–73` | `3.0 s` | Inhale wind-up (`f1–18`), explosive jaw roar (`41°`), sweeping **7.5 m long × 3.3 m wide cone AOE** (`f19–54`) with progressive 4-segment whip lag, streaming flame plumes, and flickering `Breath_Light`, then clean cutoff/recovery (`f55–73`) |

> The editable file opens on frame 1 with Walk enabled. Play frames 1–14. Frame 15 repeats the opening pose. For Rest or FireBreath, solo the corresponding NLA track and set the playback range to its clip.

## In the game

`scenes/gameplay/azure_dragon.tscn` uses `scenes/models/azure_dragon_model.tscn`, which instances `assets/models/units/azure_dragon.glb` and drives it with `scripts/components/character_animator.gd`. Rest is the idle, Walk plays at normal rate at the dragon's 5.5 m/s (`run_reference_speed`), and FireBreath is the attack clip. The flame reaches its target from the `breath_muzzle` bone. `Breath_Light` shows only while it breathes. The HUD portrait is `assets/ui/portraits/azure_dragon.png` and includes the knight. Unit rules are in docs/ARTHURIAN_KNIGHTS.md.

The rider's source is the sibling `ArthurianMarines/export/round_table_marine.glb`. Only the mounted meshes are exported with the dragon.

## Rebuilding, Verifying & Rendering

Run these commands from `C:\Dev\Supply-Lines` in PowerShell:

```powershell
$blender = "C:/Program Files/Blender Foundation/Blender 4.5/blender.exe"

# Rebuild Azure_Dragon.blend, bind rig, bake Rest/Walk/FireBreath, and export azure_dragon.glb
& $blender -b --factory-startup --python-exit-code 1 -P "Blender/Characters/AzureDragon/source/build_azure_dragon.py"

# Re-export only from hand-edited Azure_Dragon.blend
& $blender -b --factory-startup "Blender/Characters/AzureDragon/source/Azure_Dragon.blend" --python-exit-code 1 -P "Blender/Characters/AzureDragon/source/export_dragon.py"

# Verify exported GLB in a clean Blender scene (skeleton, clips, Walk ground contact, FireBreath AOE bounds)
& $blender -b --factory-startup --python-exit-code 1 -P "Blender/Characters/AzureDragon/source/export_dragon.py" -- --verify

# Render Walk & FireBreath inspection sheets and RTS camera views
& $blender -b --factory-startup "Blender/Characters/AzureDragon/source/Azure_Dragon.blend" --python-exit-code 1 -P "Blender/Characters/AzureDragon/source/render_animations.py"
```
