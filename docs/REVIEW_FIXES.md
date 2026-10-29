# Post-merge review fixes

Claude reviewed everything merged from `bbd1839` to `2b22786` (PRs #1–#6) at high effort, on 2026-10-29. This is not a substitute for an independent Codex review. It found eight issues. All eight are fixed on `fix/review-findings`.

| # | Finding | Fix |
| --- | --- | --- |
| 1 | Assigning a Train route from the HUD overwrote the round-trip fuel warning in the header. | `assign_route` adds the warning to its message. |
| 2 | Drop materials left Shift-queued orders running. | It clears the queue, like Stop and Deliver. |
| 3 | While paused, a command or placement armed from the HUD stayed stuck, because the paused skirmish ignores the click and Esc that finish it. | `skirmish.cancel_armed()` replaces the Esc block. Pausing calls it, and while paused SelectionManager calls it on Esc or a world click. |
| 4 | Every stopped, under-filled vehicle built and sorted the full source list every frame. | `choose_fuel_source` makes one pass, checks coal first, and keeps the nearest with the same instance-id tie break. |
| 5 | The double-fuel-tick fix relied on a one-shot `_skip_fuel_tick` flag. | `UnitAgent._process` ticks fuel and then calls `_order_process`. Cargo vehicles tick once and call `_order_process` directly. The flag is gone. |
| 6 | Button text was rewritten with its key letter every frame. | `set_label` builds the label with its key and assigns it only when it changes. Fixed Supply panel labels are set once. |
| 7 | The Supply panel's `SupplyRefuel` duplicated the card's `ToggleRefuel`. | Removed. Cargo vehicles use Auto-refuel (T) on the Orders page. |
| 8 | Alert throttle times were never pruned. | Expired keys are removed whenever a new key is recorded. |

## Validation

- `tests/review_fixes_test.gd` (headless) covers 1, 2, 3, 6, 7 and 8.
- 4 and 5 are covered by the existing nearest-source and refuel-rate checks in `vehicle_fuel_test` and `command_queue_test`.
- `vehicle_fuel_test`, `fuel_runtime_check` and `hud_hotkeys_test` were updated to reach the Cargo Auto-refuel button on the Orders page.
