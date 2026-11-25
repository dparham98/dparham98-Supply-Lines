# Land mine model

The Derailer's mine (docs/MINES.md) is `assets/models/props/land_mine.glb`, wrapped by `scenes/models/land_mine_model.tscn` and placed in the `Visuals` model slot of `scenes/gameplay/land_mine.tscn`. Its blast is `scenes/models/land_mine_blast.tscn` (`assets/models/effects/land_mine_blast.glb`). The working file is `Blender/Props/LandMine/LandMine.blend`.

## Look

A squat Cyborg anti-vehicle mine, 0.9 m across and 0.18 m tall to the pressure plate, in the Derailer's gunmetal and oxblood. Four faction fangs (from the Drone) sit on the shoulder between four tilt rods. A thin band round the drum is team-painted (`mine_team`, listed in the model root's `team_materials`). About 3,000 triangles.

## Parts

```
mine_root          sinks as it beds in
  mine_body        casing, oxblood shoulder, team band, lugs, fangs
  mine_plate       hexagonal pressure plate
    mine_lamp      the fuse light (assets/materials/effects/mine_lamp.tres)
  mine_prong_1..4  tilt rods, modelled upright; local X is the fold hinge
mine_soil          dirt thrown up round it
mine_spotted       amber warning ring (assets/materials/effects/mine_spotted.tres)
```

## States

`scripts/components/land_mine_model.gd` poses the parts every frame; nothing is keyed. `land_mine.gd` calls `set_age(age, arm_seconds)` each frame and `set_detected(bool)` ten times a second.

- **Arming** (the `arm_seconds`, 3 s, after it is laid): the rods swing up over 8–45% of it, the plate rises over 30–60%, and the mine sinks 7.5 cm and throws up its soil ring over 55–100%. The lamp blinks from 1.5 to 9 Hz.
- **Armed:** bedded in, the lamp a slow dim pulse (0.4 Hz). Its own side always sees it.
- **Spotted:** when the viewer is the other side, it is armed, and one of that side's detectors covers it, an amber ring of chevrons 2.2 m across pulses round it.

The lamp and ring use the unshaded shaders `assets/shaders/mine_signal.gdshader` and `mine_warning.gdshader`, with a per-instance `glow`.

## Blast

`Impact`, 1.6 s, played by `land_mine.gd`'s `_blast()` through `burst_effect.gd` (the scene is reparented and freed on `animation_finished`, as before):
- a flash (which also drives the light) and a fireball;
- a dust ring that rolls out to exactly 3 m, the splash radius;
- dust puffs, clods thrown up to about 3 m, casing shards flung to the splash edge;
- a scorch that stays to the end.

## Rebuilding

Run in background Blender, from `Blender/Props/LandMine`:
1. `build/build_land_mine.py` builds the mine and the blast pieces and saves `LandMine.blend`.
2. `build/animate_land_mine.py` keys `Impact`.
3. `build/export_land_mine.py` writes the two GLBs.

`build/render_review.py` writes `Blender/Previews/LandMine/states.png` and `blast.png`. Shared helpers are in `build/mesh_kit.py`.

## Checks

- `tests/minelaying_test.gd` (headless) lays, arms and sets off mines with the model in place.
- `tests/minelaying_runtime_check.gd` (rendered) saves `minelaying_animation.png`: the Derailer with two mines, four steps of laying, arming, armed, spotted and two blast frames. The last run is `Blender/Previews/LandMine/minelaying_ingame.png`.
