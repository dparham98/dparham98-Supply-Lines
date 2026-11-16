# Depot spacing

A new Depot's range may not overlap the range of any other friendly Depot or unfinished Depot plan. It must stand at least twice the Depot range away, centre to centre: 52.5 m with the 26.25 m range (`docs/DEPOT_RANGE.md`). The ranges may touch.

This began as step 6 of the economy report (`docs/ECONOMY_REPORT.md`, PR #66), accepted on 2026-11-14, as a fixed 70 m. That was twice the old 35 m range. After the range was halved, the playtest on 2026-11-15 asked for the rule to be only that ranges don't overlap, so the spacing now follows the range.

## Why

- A Depot costs 20 energy and 20 iron and comes with a free Infantry. Before this rule, three extra Depots beside the first mine gave four Infantry by 1:20 for 60 E / 60 I, far cheaper than a Barracks.
- With ranges kept apart, each new Depot is a real expansion, so the free Infantry still rewards expanding, as intended.
- If the range changes again (`docs/DEPOT_RANGE.md`), the spacing changes with it.
- The cost: a Depot can no longer be put anywhere. That is the trade the report names.

## Where it applies

- **Every way a new Depot is made:**
  - building one with a selected builder
  - placing a Depot plan from the Build page
  - building a Depot plan: checked again before each building step and at completion. A plan that has lost its spacing (for example when an enemy Depot beside it is captured) builds in no material and reads "Blocked · a new Depot must stand at least 35 m from every other friendly Depot, so the ranges don't overlap". Cancelling it leaves the materials delivered to the site as piles.
  - deploying a Depot truck
- **Checked against:**
  - the asking side's own Depots
  - other unfinished Depot plans
  - sites that Depot trucks of that side have been ordered to deploy on, current or Shift-queued, so two trucks can't both be sent to sites too close together
  - Enemy and neutral Depots are not counted.
- **Measured from:** the centre where the Depot will actually stand once snapped to its footprint (`depot_centre()`), not the clicked point.
- **Not checked:**
  - Depots authored in a scene, so maps keep their layouts.
  - Captured Depots: a Depot taken from the enemy stays where it is, however close it is to your own. This is the one way to have friendly Depots whose ranges overlap.
- **What the player sees:**
  - The placement ghost turns red.
  - A plan's status line and a refused order both give the rule: "at least 35 m from every other friendly Depot, so the ranges don't overlap".
  - A refused truck keeps its place.

## Settings

- `separate_ranges` on `assets/economy/depot_rules.tres` (`scripts/economy/depot_rules.gd`), on by default. Off allows any spacing.
- `min_depot_spacing()` is twice `construction_radius`. It replaces the fixed `min_depot_spacing` of 70.
- Code: `depot_network.gd`:
  - `depot_spacing_ok()`, used by `can_place()`, `queue_plan()`, `complete_plan()`, `finish_plan()` and both placement previews
  - `plan_spacing_ok()`, which construction plans also check while they are built
  - `spacing_reason()`, the one wording of the rule that every notice and status line uses

## Checks

`tests/depot_spacing_test.gd` (headless, balanced map):
- The spacing is twice the range (35 m), and follows the range when it changes.
- Plans 24 to 32 m from the main Depot are refused; 40 m and beyond are accepted.
- A second Depot plan near the first is refused; a Generator plan there is not.
- A plan doesn't block itself.
- A Depot truck can't deploy with an overlapping range and keeps its place; it can deploy beyond.
- The new Depot then keeps its own range clear.
- The status wording names 35 m and the ranges.
- Turning `separate_ranges` off allows any spacing.

Older checks that place Depots close together for other reasons (`depot_test`, `construction_site_model_test`, `hud_click_test`, `mobile_supply_test`, `pending_construction_test`, `playtest_fixes_test`, `production_batch_test`) turn `separate_ranges` off at their start. A truck deploy refused for spacing gives both rules: empty buildable land, and the spacing wording above.
