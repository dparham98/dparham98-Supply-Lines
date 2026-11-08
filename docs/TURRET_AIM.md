# Turret aim and idle sway

The Tank's turret turns toward whatever the tank is shooting at and swings gently when it has no target. The hull no longer snaps to face a target when the tank fires; it only turns to drive.

## Pieces

- `scripts/components/turret_aim.gd` sits on the root of `scenes/models/tank_model.tscn`. It exports the turret node (`Tank/Tank_Root/Tank_Hull/Tank_Turret`), the muzzle node (`.../Barrel_Mount/Tank_Barrel/Barrel_Muzzle_Brake`), the barrel's rest axis in the turret parent's frame (+Z for the glTF export), the turn rate (240 deg/s), and the sway amplitude and period (6 deg, 7 s). Only yaw turns.
- `aim_at(point)` records a world-space aim point for the current frame. Aiming lapses after one frame without a call, so a lost target needs no explicit clear. `aiming()`, `turret_yaw()` and `muzzle_position()` read the state.
- Each frame the component moves the yaw toward its goal at the turn rate with `rotate_toward`, wraps it into one turn, and writes `Basis(UP, yaw) * rest` onto the turret. The goal is the aim point's bearing in the turret parent's frame, or the sway angle `sway * sin(2 pi t / period + phase)`; the phase is random per instance so parked tanks drift out of step.
- `scripts/gameplay/unit_agent.gd` asks the Visuals model for `aim_at` (`_turret()`). `_shoot` calls `aim_at` every frame the unit has a target in range, including while on cooldown, so the turret tracks between shots. When a shot fires the tracer starts at `muzzle_position()`; units without a turret keep the old body turn and chest-height tracer.

## Behaviour and limits

- Shots are not delayed until the turret is aligned; combat timing is unchanged. The turret covers 180 deg in 0.75 s, so only the first shot at a target behind the tank can leave the barrel noticeably off its line.
- The turret follows the hull while driving, so the sway rides along; firing on the move aims the turret, not the hull.
- Checks: `tests/turret_aim_test.gd` (headless: rate limit, settling right and behind, lapse and sway bounds, and a skirmish tank aiming at a hostile beside it without turning the hull) and the `tank_turret` screenshot in `tests/tank_model_runtime_check.gd`. How the sway reads at play speed needs a human look.
