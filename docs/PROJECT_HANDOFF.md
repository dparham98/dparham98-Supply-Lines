# Supply Lines project handoff

Status as of the cloud migration, 2026-10-28.

## What this is

Supply Lines is a Godot 4.7.2 (Forward Plus) 3D RTS prototype. Its central focus is keeping supply lines running and out-positioning the opponent. Every unit is a cyborg. Economy: separate per-Depot energy, iron, wood and coal inventories; trucks, trains and rails; generators; buildable shared mines; forestry. Production comes from Depot, Barracks and Tank Factory.

- Repository: https://github.com/dparham98/dparham98-Supply-Lines
- Baseline commit on `main`: `bbd183959f9626b1eb35677c124ca6263ad69590`. It is the unmodified local project; only `.gitignore` and `.gitattributes` were extended.
- Engine pin: `.godot-version` (4.7.2-stable). The Linux binary is SHA-512 verified by `ci/install_godot.sh`.
- Local working copy: `C:\Dev\Supply-Lines`. Pre-migration backup: `C:\Dev\Backups\Supply-Lines_20261028-132744`, with a SHA-256 manifest next to it.

## Start here

| Need | Read or open |
| --- | --- |
| Overview and where to edit | [README.md](../README.md) |
| Agent and working rules | [AGENTS.md](../AGENTS.md) |
| Original design requirements (authoritative) | [EXPLICIT_DESIGN_BACKLOG.md](EXPLICIT_DESIGN_BACKLOG.md), [RECOVERED_DESIGN.md](RECOVERED_DESIGN.md) |
| Economy rules | [ECONOMY_PLAN.md](ECONOMY_PLAN.md) |
| Scene and asset architecture | [ARCHITECTURE.md](ARCHITECTURE.md) |
| What to work on next | [DEVELOPMENT_BACKLOG.md](DEVELOPMENT_BACKLOG.md) |
| Playable entry | `scenes/maps/resource_skirmish.tscn` (main scene; F5) |
| Feature exercise scenes | `scenes/maps/*_exercise.tscn`, `supply_routes.tscn` (F6) |

## Layout

- `scenes/` holds the saved editor scenes. Rendering is authored in scenes, and scripts must not rebuild terrain, lighting, UI or actor visuals at runtime.
- `scripts/` holds gameplay, economy, rails, production, combat, camera, UI and editor tools.
- `assets/` holds resources (`.tres` rules and stats), shaders, materials and map data. Keep `assets/maps/source_map.png` unchanged and `terrain_data.png` lossless. CPU terrain categories come from `terrain_cells.bin`.
- `tests/` has two kinds of script:
  - `*_test.gd`: headless regression suites, each printing a `*_PASSED` marker.
  - `*_runtime_check.gd`: rendered checks that need a GPU and save screenshots.
- `Blender/` holds art work files, hidden from Godot by `.gdignore`. It's 332 MB in plain Git.

## Development environments

- **Local Windows**: open in Godot 4.7.2. Headless checks: `GODOT=C:/Dev/Tools/Godot_v4.7.2-stable_win64_console.exe bash ci/run_headless_checks.sh`.
- **Cloud (Codespaces or Dev Containers)**: `.devcontainer/` builds Ubuntu 24.04 with the pinned Godot on `PATH` as `godot`, and imports the project on create. Run `bash ci/run_headless_checks.sh`. There's no GPU or display, so the editor UI and rendered checks aren't available there.
- **CI**: `.github/workflows/validate.yml` runs on pushes to `main`, on PRs and on manual dispatch. It installs the pinned Godot, then runs the editor import, a main-scene startup (120 frames) and every `tests/*_test.gd` suite. Logs are uploaded as an artifact.

## What verification does and doesn't cover

Headless checks prove four things: the project imports without script or resource errors, the main scene starts, game logic behaves as the suites assert, and simulated GUI input is routed correctly. They don't verify visuals, rendering, shaders, lighting, animation, real mouse or keyboard feel, or performance. Visual gameplay still needs a person running the game on a desktop with a GPU, plus the rendered `*_runtime_check.gd` scripts.

Migration verification (local Windows, Godot 4.7.2, fresh clone of `main`):

- All 423 tracked files match the original. Text was compared after CRLF normalisation; binaries byte-for-byte.
- Editor import and main-scene startup: exit code 0, no errors.
- All 27 `*_test.gd` suites pass with 0 errors when run on a clean tree.

## Known issues

- `scene_setup_test.gd` regenerates `scenes/maps/terrain_landmarks.tscn`. Any suite that runs after it in the same checkout logs MultiMesh buffer-size errors, though its assertions still pass. The CI runner runs it last and restores the file. The test should eventually write to a temporary copy instead.
- Several tests hard-code a Windows ChatGPT workspace path for screenshots. It's only used when rendering, so headless runs are unaffected.
- Eleven script and shader `.uid` files were missing locally. Godot generated them during the fresh import, and they're committed on the infrastructure branch so UIDs stay stable across machines.
- Godot's editor uses LF line endings in Git (`.gitattributes`). Windows checkouts may show CRLF-to-LF warnings, which are harmless.
- `Blender/` is in plain Git rather than LFS. Revisit that before adding many more binary revisions.
