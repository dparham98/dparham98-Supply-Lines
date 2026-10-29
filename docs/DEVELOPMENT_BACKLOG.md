# Development backlog

Working backlog for Supply Lines after the cloud migration. [EXPLICIT_DESIGN_BACKLOG.md](EXPLICIT_DESIGN_BACKLOG.md) is still the authoritative record of original design requirements. When this file and that one disagree, the design backlog wins. Items marked **(?)** are tentative in the original notes. Don't invent their rules; ask first.

Gameplay development is on hold until the cloud baseline is verified (see [PROJECT_HANDOFF.md](PROJECT_HANDOFF.md)).

## 0. Infrastructure (this migration)

- [x] Timestamped local backup and initial GitHub baseline commit.
- [x] Pinned Godot version (`.godot-version`), dev container and headless CI workflow.
- [ ] Merge the `infra/cloud-dev-setup` PR after CI passes on GitHub.
- [ ] Decide whether `Blender/` (332 MB, plain Git) should move to Git LFS or a separate art repository before the history grows.
- [x] Portable test output (`tests/test_output.gd`, `$SUPPLY_LINES_TEST_OUTPUT`).
- [ ] Investigate why the rebuilt `terrain_landmarks.tscn` differs from the committed one and triggers MultiMesh buffer-size errors in `forest_state_visuals.gd` (see PROJECT_HANDOFF.md).
- [ ] Bump GitHub Actions off the Node 20 majors (`checkout`, `cache`, `upload-artifact`).
- [ ] Rendered/visual checks need a GPU desktop. CI only proves headless import, startup and logic suites.

## 1. Confirmed design work still pending

- Vehicle fuel consumption and refueling (ECONOMY_PLAN.md, STORAGE_BATCH.md).
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

- Additive selection and control groups.
- Better mixed-group ability controls.
- Transport traffic and passing.
- Pending-plan editing, priority and save/load.

## 4. Deferred by the user

- Enemy AI and pressure.
- Construction timers, cover and salvage. These are not confirmed historical requirements.

## 5. Art pipeline

- Scout and Infantry Blender models are static and unrigged. Nothing has been exported into `assets/models` yet.
- Tank.blend was copied unchanged and hasn't been validated.
