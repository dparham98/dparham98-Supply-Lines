# Depot spacing

A new Depot must stand at least 70 m, centre to centre, from every other friendly Depot and every unfinished Depot plan. This is step 6 of the economy report (`docs/ECONOMY_REPORT.md`, PR #66), accepted on 2026-11-14. Nobody has played it.

## Why

- A Depot costs 20 energy and 20 iron and comes with a free Infantry. Before this rule, three extra Depots beside the first mine gave four Infantry by 1:20 for 60 E / 60 I, far cheaper than a Barracks.
- At 70 m apart, two Depots' 35 m service ranges never overlap. Each new Depot is a real expansion, so the free Infantry still rewards expanding, as intended.
- The cost: a Depot can no longer be put anywhere. That is the trade the report names.

## Where it applies

- **Every way a new Depot is made:**
  - building one with a selected builder
  - placing a Depot plan from the Build page
  - finishing a Depot plan, which is checked again
  - deploying a Depot truck
- **Checked against:** friendly Depots and other unfinished Depot plans. Enemy and neutral Depots are not counted.
- **Not checked:** Depots authored in a scene, so maps keep their layouts.
- **What the player sees:**
  - The placement ghost turns red.
  - A plan's status line says "70 m from every other Depot".
  - A refused order says "A new Depot must stand at least 70 m from every other friendly Depot."
  - A refused truck keeps its place.

## Settings

- `min_depot_spacing` on `assets/economy/depot_rules.tres` (`scripts/economy/depot_rules.gd`). 0 turns the rule off.
- Code: `depot_network.gd` `depot_spacing_ok()` and `spacing_notice()`, used by `can_place()`, `queue_plan()`, `complete_plan()` and both placement previews.

## Checks

`tests/depot_spacing_test.gd` (headless, balanced map):
- Plans 40 to 60 m from the main Depot are refused; 75 m and beyond are accepted.
- A second Depot plan near the first is refused; a Generator plan there is not.
- A plan doesn't block itself.
- A Depot truck can't deploy inside 70 m and keeps its place; it can deploy beyond.
- The new Depot then keeps 70 m around itself.
- Setting the spacing to 0 turns the rule off.

Older checks that place Depots close together for other reasons (`depot_test`, `construction_site_model_test`, `hud_click_test`, `mobile_supply_test`, `pending_construction_test`, `playtest_fixes_test`, `production_batch_test`) set the spacing to 0 at their start. A truck deploy refused for spacing says both rules: "Can't deploy there: the Depot footprint must be empty buildable land, at least 70 m from every other friendly Depot."
