# Infantry load

Asked for on 2026-11-19.

## The load on their back

- **What shows:** while a worker carries cargo, a small load of that kind rides on its back: three iron ingots, a
  bundle of three logs, or a sack of coal with lumps on top, each held by a strap. It goes when the cargo does.
- **Where it lives:** saved in `scenes/models/infantry_model.tscn` as `Rig/infantry_rig2/Skeleton3D/BackLoad`, a
  `BoneAttachment3D` on the `chest` bone with one hidden child per kind (`Iron`, `Wood`, `Coal`). It is built from
  plain meshes and materials in the scene, so it moves with the body's animation. The chest bone has no rotation,
  so its children are placed in the rig's own axes: the back is −Z and its surface is at z −0.24; the loads sit at
  y +0.12, z −0.37 from the bone.
- **Showing it:** `_show_back_load` in `scripts/gameplay/unit_agent.gd` shows the child named after `cargo_kind`
  (capitalised) while `cargo > 0`, and none otherwise. It only switches visibility; nothing is created at runtime.
- **Changing the art:** the nodes were written by a small generator script; edit them in the editor (or replace
  them with modelled loads under the same names).

## Hands full: no firing

- **The rule:** a worker carrying cargo (`carrying()`) cannot fire. To fight, drop the load first with Drop (X);
  the pile it leaves can be gathered again later.
- **Ordered to attack:** it walks into range and holds there with the state "Carrying cargo · drop it (X) to fire",
  and the message line says why.
- **Attack-move:** it keeps walking rather than stopping for a fight it cannot join.
- **Self-defence:** an idle worker with a load does not fire either.
- Vehicles are not affected: a Cargo truck's load is its business.

## Checks

`tests/infantry_load_test.gd` (headless) covers no load when empty, the right load for iron, wood and coal and none
once emptied, no fire on an attack order, in self-defence or on attack-move while carrying, the message, and
firing again after Drop.
