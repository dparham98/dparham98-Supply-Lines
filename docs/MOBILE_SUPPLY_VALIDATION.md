# Mobile supply validation

Godot 4.7.2, 2026-10-16. All 18 headless regression suites passed:

- tests/mobile_supply_test.gd
- tests/harvesting_batch_test.gd
- tests/storage_batch_test.gd
- tests/depot_correction_test.gd
- tests/unit_stats_test.gd
- tests/combat_batch_test.gd
- tests/skirmish_test.gd
- tests/production_batch_test.gd
- tests/engineering_batch_test.gd
- tests/depot_test.gd
- tests/supply_test.gd
- tests/bottom_hud_test.gd
- tests/hud_click_test.gd
- tests/terrain_test.gd
- tests/camera_test.gd
- tests/edge_pan_test.gd
- tests/terrain_abilities_test.gd
- tests/rail_batch_test.gd

mobile_supply_test checks half-Depot radii, deployment/packing gates, normal movement after packing, mobile-only mine payment without pooling, insufficient funds, repair during packing, no source substitution after reopening Build, remote forest-to-truck harvesting, partial/full cargo delivery, hostile/unavailable targets, fuel/cargo separation, deliberate/death piles, bounded shared extraction, opposing Infantry gathering and stockpiling, explicit route pause/resume, train spending/delivery/movement, mobile-funded Barracks and Generator construction, explicit operating Depot assignment, nonempty queue reassignment rejection, and destruction of a latched mobile payer.

Rendered mobile_supply_runtime_check passed under Vulkan on NVIDIA GeForce RTX 5070 Ti. It synthesizes mouse motion/press/release through the viewport, including clicks in embedded OptionButton popup windows. It covers vehicle and Infantry selection, Deploy supplies, choosing a truck payer, placing/repairing a mine, Move with packing, remote forestry delivery, Drop materials, gathering a pile, right-click truck delivery, train-funded Barracks placement, explicit operating Depot selection and paid Infantry production. Screenshots were inspected at 1280x900 and 1440x960. No button signals were emitted by this rendered test. The test manually advances simulation while ordinary actor processing is disabled for repeatability.

Initial rendered failures exposed exercise placement outside supply coverage and test input routing into popup windows; the exercise placement and synthetic popup routing were corrected. The destruction regression also found a freed typed supply-source argument; source validation now safely checks freed references before access. Final runs passed.

Godot editor import and normal/mobile exercise startup checks passed. Protected original map image, terrain data image, cell data and baked terrain landmark hashes remain unchanged. Existing seven UnitStats resources were not changed.

No live physical mouse/keyboard testing was performed. This is regression and rendered synthetic input validation, not a certification of every physical input setup or large-scale performance. See MOBILE_SUPPLY.md for editor steps and exact limits: Depot-only rail construction/operating production, deferred vehicle salvage/fuel/generator burning, and nonpersistent nonmerging placeholder piles.
