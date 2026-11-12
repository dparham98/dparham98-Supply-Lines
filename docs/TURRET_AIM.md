# Turret aim and idle sway

The Tank's turret turns toward whatever the tank is shooting at and swings gently when it has no target. The hull no longer snaps to face a target when the tank fires; it only turns to drive.

## Pieces

- `scripts/components/turret_aim.gd` sits on the root of `scenes/models/tank_model.tscn`. It exports the turret node (`Tank/Tank_Root/Tank_Hull/Tank_Turret`), the muzzle node (`.../Barrel_Mount/MuzzleFx`, the fire effect on the barrel tip, which stays put while the barrel recoils), the barrel's rest axis in the turret parent's frame (+Z for the glTF export), the turn rate (240 deg/s), and the sway amplitude and period (6 deg, 7 s). Only yaw turns.
- `aim_at(point)` records a world-space aim point for the current frame. Aiming lapses after one frame without a call, so a lost target needs no explicit clear. `aiming()`, `turret_yaw()` and `muzzle_position()` read the state.
- Each frame the component moves the yaw toward its goal at the turn rate with `rotate_toward`, wraps it into one turn, and writes `Basis(UP, yaw) * rest` onto the turret. The goal is the aim point's bearing in the turret parent's frame, or the sway angle `sway * sin(2 pi t / period + phase)`; the phase is random per instance so parked tanks drift out of step.
- `scripts/gameplay/unit_agent.gd` asks the Visuals model for `aim_at` (`_turret()`). `_shoot` calls `aim_at` every frame the unit has a target in range, including while on cooldown, so the turret tracks between shots. When a shot fires the tracer starts at `muzzle_position()`; units without a turret keep the old body turn and chest-height tracer.

## Behaviour and limits

- Shots are not delayed until the turret is aligned; combat timing is unchanged. The turret covers 180 deg in 0.75 s, so only the first shot at a target behind the tank can leave the barrel noticeably off its line.
- The turret follows the hull while driving, so the sway rides along; firing on the move aims the turret, not the hull.
- Checks: `tests/turret_aim_test.gd` (headless: rate limit, settling right and behind, lapse and sway bounds, and a skirmish tank aiming at a hostile beside it without turning the hull) and the `tank_turret` screenshot in `tests/tank_model_runtime_check.gd`. How the sway reads at play speed needs a human look.

## Firing

- `scripts/components/tank_rig.gd` has `fire()`, which `unit_agent.gd` calls when a shot goes off. The barrel slides back and runs out (`recoil_distance`, `recoil_kick_time`, `recoil_return_time`) and the hull rocks and settles (`rock_degrees`, `rock_hertz`, `rock_damping`). Both are done in code; `tank.glb` has no animation.
- `scenes/models/tank_muzzle_fx.tscn` is the muzzle flash and smoke, on the end of the barrel. It sits on `Barrel_Mount`, so it stays put while the barrel recoils. `scenes/gameplay/tank_shell_impact.tscn` is the flash, smoke and debris where the shell lands. Both play clips authored in `Blender/Vehicles/Tank/Tank.blend` (collections `tank_fire_fx` and `tank_impact`) through `scripts/components/burst_effect.gd`, which also drives each light from the scale of the flash mesh.
- `scenes/gameplay/tank_shell.tscn` is the shell, `projectile_scene` on `tank.tscn`. It flies at 20 m/s and stops on the near face of the target body (`_shot_end` in `unit_agent.gd`). Damage still lands when the gun fires, so a target killed by the shot has its impact appear after it is gone.
- Tank `attack_range` is now 40 (see PATHING.md); before that it was 10 (was 5). The barrel tip is about 4.3 m from the centre of the Tank, so at 5 the shell had almost no flight. This is longer than the Tank vision of 7 and any other unit range, and is provisional until playtested.
- Check: `tests/tank_fire_test.gd` (headless).

## Death

A dead tank plays one of the three effects in `death_scenes` on `scenes/models/tank_model.tscn`, picked at random. The unit leaves the game at once and only the model stays behind, as with the Infantry and Scout, so a wreck cannot be selected, targeted or block anything.

- `tank_death_cookoff.tscn` (6 s): a moment of sparks, then the magazine goes. The turret is thrown clear and the charred hull burns in a spreading oil pool, with two smaller explosions.
- `tank_death_bleed.tscn` (5.5 s): the left track snaps and whips out behind. The hull lists onto its bare wheels, the gun droops and oil pumps from five wounds.
- `tank_death_overload.tscn` (5 s): blue arcs crawl over the tank while the turret spins out of control, then the core blows both hatches off.

`assets/models/units/tank.glb` must not be re-exported to carry clips, because the track shader depends on its vertex order. Instead each effect's GLB holds stand-in nodes keyed in Blender, and `scripts/components/tank_death.gd` copies `Drive_Hull`, `Drive_Turret` and `Drive_Mount` onto the real nodes every frame. `Drive_Light`, `Drive_Scorch` and `Drive_Hide` carry a number in their keyed scale: light strength, how burnt the tank looks, and the moment `hide_parts` come off. `turret_release` sets when the turret stops keeping its aim and takes the authored pose; effects mounted on `Drive_Turret` are only correct after that, so the bleed-out, which never releases, mounts nothing there.
