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
  - building a Depot plan: checked again before each building step and at completion. A plan that has lost its spacing (for example when an enemy Depot beside it is captured) builds in no material and reads "Blocked · a new Depot must stand at least 70 m from every other friendly Depot". Cancelling it leaves the materials delivered to the site as piles.
  - deploying a Depot truck
- **Checked against:**
  - the asking side's own Depots
  - other unfinished Depot plans
  - sites that Depot trucks of that side have been ordered to deploy on, current or Shift-queued, so two trucks can't both be sent to sites too close together
  - Enemy and neutral Depots are not counted.
- **Measured from:** the centre where the Depot will actually stand once snapped to its footprint (`depot_centre()`), not the clicked point.
- **Not checked:**
  - Depots authored in a scene, so maps keep their layouts.
  - Captured Depots: a Depot taken from the enemy stays where it is, however close it is to your own. This is the one way to have friendly Depots closer than 70 m.
- **What the player sees:**
  - The placement ghost turns red.
  - A plan's status line says "70 m from every other Depot".
  - A refused order says "A new Depot must stand at least 70 m from every other friendly Depot."
  - A refused truck keeps its place.

## Settings

- `min_depot_spacing` on `assets/economy/depot_rules.tres` (`scripts/economy/depot_rules.gd`). 0 turns the rule off.
- Code: `depot_network.gd`:
  - `depot_spacing_ok()`, used by `can_place()`, `queue_plan()`, `complete_plan()`, `finish_plan()` and both placement previews
  - `plan_spacing_ok()`, which construction plans also check while they are built
  - `spacing_reason()`, the one wording of the rule that every notice and status line uses

## Checks

`tests/depot_spacing_test.gd` (headless, balanced map):
- Plans 40 to 60 m from the main Depot are refused; 75 m and beyond are accepted.
- A second Depot plan near the first is refused; a Generator plan there is not.
- A plan doesn't block itself.
- A Depot truck can't deploy inside 70 m and keeps its place; it can deploy beyond.
- The new Depot then keeps 70 m around itself.
- Setting the spacing to 0 turns the rule off.

Older checks that place Depots close together for other reasons (`depot_test`, `construction_site_model_test`, `hud_click_test`, `mobile_supply_test`, `pending_construction_test`, `playtest_fixes_test`, `production_batch_test`) set the spacing to 0 at their start. A truck deploy refused for spacing says both rules: "Can't deploy there: the Depot footprint must be empty buildable land, at least 70 m from every other friendly Depot."
