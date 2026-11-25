# Freed repair and heal targets

Item 1 of `docs/BALANCE_IMPLEMENTATION_HANDOFF.md` (2026-11-23).

**The bug.** When a worker's repair target or a Grail Sentinel's patient was destroyed, `_order_process` in `scripts/gameplay/unit_agent.gd` went on passing the freed object to `EngineeringWork.repairable` and `MedicalWork.can_heal`. Both take a typed `Node`, and Godot raises a script error when a freed object is passed to a typed argument, before the function's own `is_instance_valid` check runs. The error repeated every frame and the unit never left the order.

**The fix.** `_order_process` now checks `is_instance_valid(order_target)` for repair and heal orders before any typed call, and drops the order: the unit goes idle with "Repair target lost" or "Patient lost". `_repair` has the same guard. Attack, construct and capture orders already checked first.

**Check.** `tests/freed_target_test.gd` (headless): a worker repairing a Tank and a Sentinel healing an Infantry each lose their target on the way, and go idle with no script error. Without the fix it fails with "Invalid type in function 'repairable' ... (previously freed)".
