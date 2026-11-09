# Development backlog

Working backlog for Supply Lines after the cloud migration. [EXPLICIT_DESIGN_BACKLOG.md](EXPLICIT_DESIGN_BACKLOG.md) is still the authoritative record of original design requirements. When this file and that one disagree, the design backlog wins. Items marked **(?)** are tentative in the original notes. Don't invent their rules; ask first.

The cloud baseline was verified on 2026-10-28 (see [PROJECT_HANDOFF.md](PROJECT_HANDOFF.md)); gameplay work proceeds on feature branches and draft PRs.

## 0. Infrastructure (this migration)

- [x] Timestamped local backup and initial GitHub baseline commit.
- [x] Pinned Godot version (`.godot-version`), dev container and headless CI workflow.
- [ ] Merge the `infra/cloud-dev-setup` PR after CI passes on GitHub.
- [ ] Decide whether `Blender/` (332 MB, plain Git) should move to Git LFS or a separate art repository before the history grows.
- [x] Portable test output (`tests/test_output.gd`, `$SUPPLY_LINES_TEST_OUTPUT`).
- [ ] Accept the terrain rebuild visually in the Windows/Forward Plus editor. The headless empty-buffer cause and serialization checks are addressed by [independent audit fixes](AUDIT_FIXES.md); editor/visual equivalence still needs human acceptance (see PROJECT_HANDOFF.md for the original issue).
- [ ] Bump GitHub Actions off the Node 20 majors (`checkout`, `cache`, `upload-artifact`).
- [ ] Rendered/visual checks need a GPU desktop. CI only proves headless import, startup and logic suites.

## 1. Confirmed design work still pending

- Vehicle fuel consumption and refueling: merged in PR #2 (FUEL_BATCH.md). Drone fuel/landing rules remain open.
- Water generation and coal extraction (ECONOMY_PLAN.md).
- Signals, rail demolition, research and upkeep: explicitly wanted, deferred by the user.
- Additional transport controls (user said "return to later").
- Drone attack and range: unspecified. Leave the current fallback in place until defined.
- Print durations and production prerequisites: unspecified.

## 2. Tentative abilities (blocked until the user defines them)

- Motorcycle derails trains (?)
- Motorcycle signal-jams drones (?)
- Übermech spawns something on death (?)

## 3. Suggested usability follow-ons (not yet requested)

- Additive selection and control groups: merged with command card hotkeys in PR #3 (HUD_HOTKEYS.md).
- Playtest tools panel (F10): merged in PR #4 (PLAYTEST_TOOLS.md).
- Shift command queue with waypoint markers: merged in PR #5 (COMMAND_QUEUE.md).
- HUD layout (compact bar, status bars, type strip, alert feed, cargo pages): implemented on `feature/hud-layout` (HUD_LAYOUT.md), pending review and playtest.
- Better mixed-group ability controls.
- Transport traffic and passing.
- Pending-plan editing, priority and save/load.

## 4. Deferred by the user

- Enemy AI and pressure.
- Construction timers, cover and salvage. These are not confirmed historical requirements.

## 4b. Site construction (2026-11-08)

- Buildings are built from materials delivered onto the footprint by Cargo trucks or workers, with Infantry building them in and the covering stockpile paying energy in step (docs/SITE_CONSTRUCTION.md). The skirmish starts with a fuelled empty Cargo truck. Rails stay Depot-paid. Open: wood as a building material, construction animation on the footprint itself, auto-assigning idle workers, and whether trains should unload at sites. Not yet playtested.

## 5. Art pipeline

- The Scout Blender model is static and unrigged and not exported.
- Infantry: `Blender/Characters/Infantry/Infantry.blend` (2026-11-08 rigged cyborg) is exported to `assets/models/units/infantry.glb` and used by `scenes/models/infantry_model.tscn` (turned to face -Z). `character_animator.gd` plays Run while walking, Hack with running saw teeth while gathering or repairing, Shoot on each shot and Rest otherwise (docs/INFANTRY_MODEL.md). `infantry_model_test` and `infantry_model_runtime_check` cover it. Not yet accepted in play.
- Cargo truck: `Blender/Vehicles/CargoTruck/CargoTruck.blend` (2026-11-08) is exported to `assets/models/units/cargo_truck.glb` and used by `scenes/models/cargo_truck_model.tscn` (scale 0.4, turned to face -Z). `vehicle_rig.gd` rolls and steers the wheels from the vehicle's travel, opens the lid and ramp while deployed or transferring, and raises the cargo indicator when anything is aboard (docs/CARGO_TRUCK_MODEL.md). Trains and Depot trucks keep their placeholders. Not yet accepted in play.
- Tank: `Blender/Vehicles/Tank/Tank.blend` (2026-11-08) is exported to `assets/models/units/tank.glb` and used by `scenes/models/tank_model.tscn` (scale 0.4, turned to face -Z). Re-export after edits: select the Tank collection, glTF Binary, +Y up, apply modifiers. `tank_model_runtime_check` renders it. The turret aims at the tank's target and sways when idle (docs/TURRET_AIM.md); `turret_aim_test` and the `tank_turret` screenshot cover it. Not yet accepted in play.
