# Motorcycle build prompt

Build the Motorcycle from `Blender/References/Motorcycle_concept.webp`, animate it, give it a pneumatic spike gun with a real moving shot, and put it in the game in place of `scenes/models/motorcycle_placeholder.tscn`. No model exists yet. This is an art and animation job: stats, abilities and combat rules stay as they are.

Read `AGENTS.md`, `Blender/README.md`, `docs/DRONE_MODEL.md` and `docs/TURRET_AIM.md` first. The Drone is the closest example of the Blender pipeline, and the Tank is the closest example of the game wiring.

## Ground rules

- Working file: `Blender/Vehicles/Motorcycle/Motorcycle.blend`. Keep editing that one file, with no numbered copies. Revisions go in `Blender/Backups/Motorcycle`, previews in `Blender/Previews/Motorcycle`. Set `save_version = 0` so no `.blend1` appears.
- Run Blender in the background. Do not use the Blender MCP tools or touch the user's open Blender window, which may hold unsaved work.

```
"C:\Program Files\Blender Foundation\Blender 4.5\blender.exe" <file.blend> --background --python <script> -- <args>
```

- Gameplay scripts must not create visuals at runtime. Everything is authored in Blender or a saved scene.
- No real-world insignia, flags or symbols. For the emblem on both sides of the fuel tank, reuse the `faction_fang` mesh from `Blender/Vehicles/Drone/Drone.blend`, not the sheet's drawing of it.

## How to read the sheet

The sheet is the target for shape, palette and character. Where it is unclear or contradicts itself, use these:

- **Gun position.** The front view shows the post off to one side, and the back and top views show it on the centre line. Build it on the centre line, directly behind the rider.
- **Gun height.** Raise the swivel so the barrel clears the rider's helmet through a full 360 degree turn. The sheet has it about level with the head.
- **Spike magazine.** The sheet shows none. Add a small box of visible iron spikes on the side of the receiver.
- **Rider's legs.** Keep them as drawn, an armoured rider with feet on the pegs.
- **Parking stand.** Not on the sheet. Add a small hydraulic stand on the frame's left side, which extends when the bike stops. The rider's feet never leave the pegs.
- **Top view.** Trust it for overall layout only, because the arms and pipes turn into a tangle there.
- **Pipework.** There is far more than a game model should carry. Keep the main copper runs, exhausts and firebox, and simplify the rest.

## Stage 1: the model, then stop

True scale in metres, facing -Y, Z up, tyres on Z = 0. About 2.6 m long with a rider of about 1.75 m, in proportion with the Scout (1.67 m). Budget about 25,000 triangles for the bike, rider and gun together. Flat PBR materials with no image textures, matching the other units.

**Silhouette first**, since this is an RTS seen from a high camera: (1) fat wheels and a long, low bike, (2) raised gun on its post, (3) coal hopper at the rear, (4) hunched rider, (5) glowing firebox.

**Palette.** Charcoal and worn gunmetal with oxblood red panels, brass and copper fittings. Amber glow only on the headlight, firebox, tail lights and rider's eye slits. Keep emission below the point where it clips to flat white in Godot, roughly power 2.

Build these as separate named objects, each with its origin on its pivot, so nothing needs re-cutting later:

```
bike_root (empty, on the ground under the bike's centre)
  frame            body, tank, engine, firebox, exhausts, seat, rear fender, hopper
  steer_F          empty on the steering head, turning about its own up axis
    fork_F         forks, front fender, headlight, handlebars
    wheel_F        origin on the axle, rolling about X
  wheel_R          origin on the axle, rolling about X
  stand            origin on its hinge
  gun_swivel       origin on the post's vertical axis, turning about Z
    gun_body       receiver, brass cylinder, magazine
      gun_barrel   slides along its axis for recoil
        muzzle     empty at the tip
  rider_torso      origin at the seat
    rider_head     origin at the neck
    rider_arm_L, rider_arm_R   origins at the shoulders
    rider_leg_L, rider_leg_R   origins at the hips
```

The fixed post sits on `frame`, and everything that turns sits on `gun_swivel`. The rider is rigid parts with no skeleton. Mesh and object names must be unique across the file because Godot needs unique node names.

Also model the **rail spike**, as a separate object facing -Y: a heavy tapered iron spike with a ribbed, flared head, as in the sheet's RAIL SPIKE panel.

**Show the user** a turnaround and a side-by-side against the sheet's SIDE and FRONT views, and wait for approval before animating.

## Stage 2: motion and the game

The Motorcycle is a vehicle with a turret, so it uses neither `character_animator.gd` nor a skeleton. `unit_agent.gd` needs no changes: it already calls these on the model root.

Add `scripts/components/motorcycle_rig.gd`, extending `turret_aim.gd` as `tank_rig.gd` does, on the root of a new `scenes/models/motorcycle_model.tscn`. It must provide `set_drive(speed, turn, delta)`, `set_hatches(open)` and `set_load(fraction)` (both no-ops), `fire()`, `has_death_clip()`, `dying()` and `play_death()`. Wrap the GLB in the usual `Transform3D(-1,0,0,0,1,0,0,0,-1,0,0,0)`. Take the wheel and steering logic from `vehicle_rig.gd`.

**Driving.**
- Wheels roll with ground speed.
- `steer_F` turns into corners, with a steer limit of about 15 degrees. Check the rider's hands stay on the grips. If they don't, move the handlebars onto `frame`.
- **The whole bike leans into turns,** up to about 18 degrees, pivoting at the tyres, rising and easing smoothly. RTS heading changes happen in a frame or two, so hold and smooth the value as `steer_hold` does.
- The stand extends and the bike settles a few degrees onto it when stopped, and it retracts on moving off.
- A small engine rumble and a slight rider sway keep it from looking frozen.

**The moving shot. The user specifically asked for this, so it must look deliberate.** The bike keeps riding, leaning and steering while it fires, and it never turns its body to aim. `unit_agent.gd` already skips the body turn when the model has a turret.
- `gun_swivel` tracks the target through `turret_aim.gd`, all the way round.
- `rider_head` turns toward the gun's direction, clamped to what a neck can do.
- On `fire()`, `gun_barrel` slams back and returns, the brass cylinder vents a jet of steam, and the rear of the bike kicks slightly. Over the 2 s reload, a thin wisp of steam tapers off, so the slow rate of fire reads as recharging.
- Make the steam a muzzle effect scene with a `play()` method on the `muzzle` node, like `scenes/models/tank_muzzle_fx.tscn`.

**The spike.** Export it to `assets/models/projectiles/rail_spike.glb`, and add `scenes/gameplay/rail_spike.tscn` using `scripts/gameplay/projectile.gd`, as `scenes/gameplay/grenade_round.tscn` does: flying straight and fast (`speed` about 38) with `keep_body_material` on. Set it as `projectile_scene` on `scenes/gameplay/motorcycle.tscn`.

Damage lands the moment the shot is fired, and every shot hits, so the flight is purely visual and ends on the target's surface. Add an `impact_scene` with a burst of sparks and iron dust, and the spike staying embedded at the hit point for about half a second before it drops away.

**Death.** One death, about 4 to 5 s, keyed in Blender as a `Die` clip on the objects' NLA tracks, starting at frame 0, in the Drone's pattern.
- The bike goes down on its side and skids a few metres along its travel, throwing sparks, with the wheels spinning down.
- The rider is thrown clear, tumbles and lands limp, using the separate arm, leg and head pivots.
- Oil and severed cables spray from the rider, because the faction are cyborgs. Then a spreading oil pool, a small fire at the firebox and smoke.
- Hold the wreck for a couple of seconds, then sink it fully out of sight so it removes itself cleanly.
- Do not key `gun_swivel`, so the gun stays where it was pointing.

Put the effects in a separate GLB on the same timeline, `assets/models/effects/motorcycle_death_fx.glb`, with `scenes/models/motorcycle_death_fx.tscn`, using `scripts/components/burst_effect.gd` like `scenes/models/drone_death_fx.tscn`. `motorcycle_rig.gd` must stop writing to nodes while dying. Keep the effect collection in the `.blend`, switched off in the view layer.

**Wiring.** Export to `assets/models/units/motorcycle.glb` (glTF Binary, +Y up, apply modifiers, animations as NLA tracks, no cameras or lights). Point `model_scene` and the `Model` node in `scenes/gameplay/motorcycle.tscn` at the new model scene. If the bike sticks out past the `SelectionRing`, enlarge the ring in that scene.

## Checks

Godot is `C:\Dev\Tools\Godot_v4.7.2-stable_win64_console.exe`.

Add `tests/motorcycle_model_test.gd`, modelled on `tests/drone_model_test.gd` and `tests/tank_fire_test.gd`. It should cover:
- The model scene is used, it faces -Z, and its size is right.
- Wheels roll, and the bike steers and leans in a turn.
- The stand is down when stopped and up when moving.
- **A shot taken while moving:** the unit keeps moving, the wheels keep rolling, the bike's heading doesn't change to face the target, the gun does, and the spike leaves the muzzle.
- Death: the unit is gone at once, the model stays, and it removes itself.

Vehicles start with an empty fuel reserve, so see `tests/vehicle_fuel_test.gd` for how to fuel one before it can move.

Also run `unit_stats_test`, `combat_batch_test`, `production_batch_test` and `vehicle_fuel_test`. A test passes only with exit code 0, no `ERROR:` or `SCRIPT ERROR` lines, and its `*_PASSED` marker. Godot writes `.glb.import` and `.gd.uid` files on import, and they need to be committed.

Render it in Godot at the game's camera distance and close up: parked, riding, leaning, firing on the move and the death. Save that to `Blender/Previews/Motorcycle/animation_ingame.png`, look at it yourself, and fix what you see. Headless checks never count as visual verification.

## Finish

Work on a `feature/motorcycle-model` branch from `origin/main` in your own worktree. This prompt and `Motorcycle_concept.webp` may exist only in `C:\Dev\Supply-Lines`, so copy them in if they are missing. Commit and open a draft PR only when the user asks, and never merge without their explicit approval.

Add a Motorcycle entry to `Blender/README.md` and write `docs/MOTORCYCLE_MODEL.md`.

Out of scope: derailing trains, jamming drones, stat changes, and any new terrain rules.
