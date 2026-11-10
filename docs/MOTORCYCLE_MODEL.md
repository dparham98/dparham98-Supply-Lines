# Motorcycle model

The Motorcycle is `assets/models/units/motorcycle.glb`, wrapped by `scenes/models/motorcycle_model.tscn` and placed in `scenes/gameplay/motorcycle.tscn`. The working file is `Blender/Vehicles/Motorcycle/Motorcycle.blend`, modelled from `Blender/References/Motorcycle_concept.webp`. Stats, range and combat rules are unchanged.

It is 2.69 m long, 0.92 m wide and 2.04 m to the top of the gun, with about 24,600 triangles and flat materials only.

## Parts

The model has no skeleton. Its parts are separate objects, each with its origin on its pivot:

```
bike_root            on the ground under the bike's centre
  frame              body, tank, engine, firebox, exhausts, seat, rear mudguard, hopper, gun post
    faction_fang_L, faction_fang_R
  steer_F            empty on the steering head, raked 18 degrees; its up axis is the steering axis
    fork_F           forks, front mudguard, headlight
    handlebar_F      bars, grips and gauge
    wheel_F
  wheel_R
  stand              modelled down; its local X is the hinge
  gun_swivel
    gun_body         receiver, brass cylinder, spike magazine
      gun_barrel
        muzzle       holds the steam effect in the model scene
  rider_torso
    rider_head, rider_arm_L, rider_arm_R, rider_leg_L, rider_leg_R
```

The gun is on the centre line behind the rider, raised so the barrel clears the helmet by about 8 cm all the way round.

## Motion

`scripts/components/motorcycle_rig.gd` sits on the model scene's root and extends `turret_aim.gd`. `unit_agent.gd` calls it as it calls any vehicle rig and needed no changes. Everything below is done in code on the model's own nodes; only the death is a baked clip.

- **Wheels** roll with the ground distance covered.
- **Steering and lean.** The unit turns in a frame or two, so heading changes are gathered into one swing, in degrees turned lately, that fades over `steer_hold` (0.4 s). A swing of 40 degrees steers the fork to its 15 degree limit and one of 60 degrees leans the bike to its 18 degree limit. A jink one way then the other cancels out, which matters because every move order starts with one. The lean turns `bike_root`, so it pivots at the tyres.
- **Handlebars** follow 35% of the steer (`bar_follow`). The rider's arms are rigid, and a full 15 degrees would move each grip 9 cm out of the hand; at 35% the hand stays within 5 cm.
- **Stand.** It folds away when the bike moves and comes down 0.2 s after it stops, and the bike settles 5 degrees onto it toward its left.
- **Rumble and sway.** The frame shakes a few millimetres and the rider sways slowly, so a parked bike is not frozen.
- **Gun.** `gun_swivel` tracks the target through `turret_aim.gd` at 540 deg/s. The unit takes a target and fires on it in the same frame, so the rig's `aim_at` swings the gun straight onto a newly taken target; the spike then leaves along the barrel. `rider_head` turns with the gun up to 70 degrees.
- **Firing.** `fire()` slams `gun_barrel` back 12 cm, hops the rear of the bike and plays the steam effect. The bike never turns its body to aim.

## The shot

- `scenes/models/motorcycle_muzzle_fx.tscn` is the steam, on the `muzzle` node: a jet from the muzzle, two jets from the brass cylinder, puffs from the valve, then a wisp that tapers off over the 2 s reload. Its `Fire` clip is the length of the reload.
- `scenes/gameplay/rail_spike.tscn` is the spike, `projectile_scene` on `motorcycle.tscn`, flying at 38 m/s at 1.5 times its modelled size. With an attack range of 3 the flight lasts only two or three frames.
- `scenes/gameplay/rail_spike_impact.tscn` is where it lands: sparks and iron dust, and the spike stuck in the target for half a second before it drops away.

## Death

`Die` runs 5 s. The bike goes down on its right side and skids 3.4 m along its travel with the wheels spinning down. The rider is thrown clear at 0.22 s, tumbles, lands at about 1.1 s and comes to rest face down by 1.7 s. The wreck holds until 4 s, then sinks out of sight. `gun_swivel`, `stand` and `handlebar_F` are not keyed, so they stay as they were.

`scenes/models/motorcycle_death_fx.tscn` plays `assets/models/effects/motorcycle_death_fx.glb` as a child of the model: skid sparks, oil and severed cables from the rider, two oil pools, fire at the firebox and smoke. Its `Death` clip shares `Die`'s timeline. `Die` assumes flat ground at the model's height.

## Rebuilding

The `.blend` is made by scripts beside it, run in background Blender in this order:

1. `build_motorcycle.py` builds the static model from nothing and saves `Motorcycle.blend`.
2. `animate_motorcycle.py` (on the saved file) keys `Die` and builds the effect collections `motorcycle_death_fx`, `motorcycle_fire_fx` and `rail_spike_impact`, switched off in the view layer.
3. `export_motorcycle.py` writes the five GLBs.

`render_review.py -- <folder> turnaround compare death spike` renders the review images. After exporting, run Godot with `--headless --import` before any test.

## Checks

- `tests/motorcycle_model_test.gd` (headless) covers size and facing, wheels, steer and lean, hands on the grips, the stand, a shot taken on the move, the spike and its impact, and the death.
- `tests/motorcycle_model_runtime_check.gd` (rendered) saves ten views as `motorcycle_animation.png`; the last run is `Blender/Previews/Motorcycle/animation_ingame.png`.

## Limits

- The model is cleaner than the concept: less pipework, no weathering, a simpler rider.
- The spike's flight is too short to see much at range 3. The steam, the recoil and the stuck spike carry the shot.
- The gun jumps to a newly taken target in one frame.
- How the lean, the rumble and the death read at play speed needs a human look.
