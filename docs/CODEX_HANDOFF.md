# Codex handoff

Status as of 2026-10-29. Written by Claude Code for Codex picking up Supply Lines.

## State of `main`

- Repository: https://github.com/dparham98/dparham98-Supply-Lines
- `main` is at `213c0d2` (Merge PR #15). PRs #1–#15 are all merged with merge commits. No other branches have unmerged work.
- The user authorized every merge. **None of PRs #1–#15 has had an independent review or a human gameplay playtest.** The first job is that review (see "What Codex should do first").
- CI (`.github/workflows/validate.yml`) passed on `1082020` (PR #13). Runs for `5937b09` and `213c0d2` were in progress when this was written; check them before starting.

## Rules that still apply

Read [AGENTS.md](../AGENTS.md), [README.md](../README.md), [ARCHITECTURE.md](ARCHITECTURE.md) and [PROJECT_HANDOFF.md](PROJECT_HANDOFF.md) first. The short version:

- Work on feature branches with draft PRs. Use fresh clones in the cloud. Never force-push, and never merge into `main` without the user's explicit approval. Each approval covers only the merge it names.
- Merge with merge commits, not squash, so stacked branches stay consistent.
- `main` is the accepted playable baseline. The playable scene is `scenes/maps/resource_skirmish.tscn`.
- Keep `assets/maps/source_map.png` unchanged and `terrain_data.png` lossless. CPU terrain categories come from `terrain_cells.bin`.
- Rendering lives in saved editor scenes. Gameplay scripts must not recreate terrain, lighting, UI or actor visuals at runtime. Use reusable actor scenes and their `Visuals` model slots.
- Blender work files are in `Blender/` (hidden by `.gdignore`). Amend `Scout.blend` and `Infantry.blend` in place; no numbered copies.
- The bottom HUD has a fixed 260 px height and a fixed 250 px Context column. New panels must fit inside them; tests check both.
- Headless checks never count as visual or gameplay acceptance.

## How to verify

- **Headless** (clean tree required): `bash ci/run_headless_checks.sh`, with `GODOT` pointing at Godot 4.7.2 (`.godot-version`). It writes `ci-logs/summary.md`. On the last local run all 47 suites passed.
- **Rendered checks** (desktop with a GPU only): run each `tests/*_runtime_check.gd` without `--headless`, with `SUPPLY_LINES_TEST_OUTPUT` set. Each prints a `*_PASSED` marker and saves screenshots worth looking at.
- After adding a `class_name`, run Godot once with `--import` to refresh the class cache, or scripts that use it fail to parse.

## What was built (PRs #1–#15)

| PR | Area | Doc |
| --- | --- | --- |
| #1 | Cloud dev container, pinned Godot, headless CI | PROJECT_HANDOFF.md |
| #2 | Vehicle fuel (economy stage 5) | FUEL_BATCH.md |
| #3 | HUD hotkeys, additive selection, control groups | HUD_HOTKEYS.md |
| #4 | Playtest tools panel (F10) | PLAYTEST_TOOLS.md |
| #5 | Shift command queue with waypoint markers | COMMAND_QUEUE.md |
| #6 | HUD layout | HUD_LAYOUT.md |
| #7 | Post-merge review fixes | REVIEW_FIXES.md |
| #8–#12 | UI overhaul phases A–D and F: theme, command card, selection panels, map status, order feedback, compact grid and fixed HUD | UI_OVERHAUL_PLAN.md, UI_PHASE_*.md |
| #13 | Crate shipments (superseded by #15) | CRATE_SHIPMENTS.md |
| #14 | 2026-10-29 playtest fixes: HUD stability, hotkeys, valid deploy placement, edge pan, supply picker, Depot hover, armed-command cursor, attack-move | PLAYTEST_FIXES_2026_10_29.md |
| #15 | Crates as independent map containers, plus crate pips, batch packing and Refill on pickup | CRATE_CONTAINERS.md |

### Crate model (newest, least exercised)

- A crate (`scenes/gameplay/supply_crate.tscn`, `scripts/economy/supply_crate.gd`) is a map object holding up to 25 units of one resource, or empty. It is in group `supply_crates`, and also in `resources` while it holds anything, so workers can gather from it like a pile.
- Crates are **not** Depot storage. `ResourceStockpile` counts loose stock only. Crates aboard a vehicle live in `CargoVehicle.crates` (`{kind, amount}` entries) and reserve cargo space through `ResourceStockpile.reserved`.
- `scripts/economy/crate_yard.gd` (`CrateYard`) does placement and lookups: free tiles beside a Depot (south side first), packing, unpacking, contents for pips, and Refill on pickup (`restock`).
- Cargo vehicles load from a crate or the crates beside a Depot, unload into a Depot or onto any open ground tile, and repeat as trips. Trains use Depots only.
- The UI uses one reusable pip row, `scenes/ui/crate_pips.tscn`, in the Depot panel, the Cargo HUD and the hover card. `scripts/ui/map_overlay.gd` draws crate fill bars and vehicle pips on the map.

## Known issues and open questions

- **`mobile_supply_runtime_check` fails** at "Pile gather GUI did not stockpile materials". It failed before PRs #14 and #15 and hasn't been diagnosed.
- **Cargo label:** check in-game whether the vehicle `$Cargo` Label3D ("· n/m crates") reads well or clutters the map.
- **Terrain rebuild:** the rebuilt `terrain_landmarks.tscn` differs from the committed one and logs MultiMesh buffer-size errors in `forest_state_visuals.gd`. Not investigated (PROJECT_HANDOFF.md).
- **"Too close to a tree":** a playtest question from the user that hasn't been settled. No code produces that text; ask the user what they saw before changing placement rules.
- **Design gaps waiting on the user:** Drone fuel and landing, water generation and coal extraction, and the tentative (?) abilities in [DEVELOPMENT_BACKLOG.md](DEVELOPMENT_BACKLOG.md). Don't invent their rules.
- **Housekeeping:** `DEVELOPMENT_BACKLOG.md` still lists some items from before PRs #6–#15 as pending. GitHub Actions still use the Node 20 majors. `Blender/` (332 MB) is in plain Git, not LFS.
- **API access:** there is no `gh` CLI on the local Windows checkout. Use whatever GitHub access your own environment provides.

## What Codex should do first

1. **Independent review of `main`**, PR #14 and #15 above all (`git diff 1082020..213c0d2`). Report findings to the user, or fix them on a branch with a draft PR. Places likely to hide bugs:
   - crate deletion with `queue_free` while vehicle jobs or HUD pips still hold references (`CargoVehicle._crate_job`, `skirmish_hud.gd` `unpack_pip`);
   - `ResourceStockpile.reserved` staying in sync with `crates` after partial unloads and refuelling;
   - Refill on pickup repacking every frame from `Depot._process` and `CargoVehicle` while deployed;
   - ground unloads onto tiles that are occupied or not walkable;
   - the stop validation in `skirmish.gd` `issue_card_order` versus `CargoVehicle.stop_valid`.
2. **Diagnose `mobile_supply_runtime_check`**.
3. **Refresh `DEVELOPMENT_BACKLOG.md`** so it matches what's merged.

The user's gameplay playtest on Windows is still the acceptance gate for all of this.
