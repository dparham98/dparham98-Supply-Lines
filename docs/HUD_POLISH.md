# HUD and rules polish (2026-11-19)

A list of smaller changes asked for on 2026-11-19, after fog of war was merged. Each item below says what changed and where. `tests/hud_polish_test.gd` checks them on Two Lakes, headless.

## Warnings fade by themselves

- The alert feed (top left) and the header message (the line above the bottom panel) show for 3 s, then fade out over 0.6 s. Nothing needs closing by hand.
- `skirmish_hud.gd`: `FEED_SECONDS`, `FEED_FADE_SECONDS` and `warning_alpha`. `skirmish.gd` `notify` records when the message changed, in `message_time`.
- A win or loss stays in the header; it does not fade.
- Feed entries no longer count their seconds. Clicking one still moves the camera there while it shows.
- The minimap still pulses where a warning happened, for 6 s.

## Health number and vehicle fuel

- Health was already written as a number ("Health 80 / 80"), and vehicles already had a fuel bar.
- The bug: selecting several units hides the health line, the fuel and cargo bars and the details, to make room for the portraits. Nothing showed them again, so from the first group selection on, every single selection had no health number and no fuel.
- `update_portraits` now shows them again whenever the selection is one unit or building.

## Control groups take building sites

- Ctrl+number with a building site (a construction plan) selected saves it as the group, as a finished building already could be.
- When the site is built, every group holding it holds the building instead (`SelectionManager.replace_member`, called from `construction_plan.gd`). A cancelled site drops out of its groups.

## Manifests: right-click to take crates off

- On a Cargo vehicle's Load page, right-click a resource tile to take one of its crates off the manifest; Shift+right-click takes them all off (`CargoVehicle.manifest_remove`, `skirmish_hud.gd` `lower_manifest`).
- Left-click still adds one, Shift fills every free slot, and Clear empties the manifest.

## Depot ranges

- Every friendly Depot's Territory ring shows while the build page is open, and while any building or building site is selected, as well as while placing anything (`DepotNetwork.show_territories`, `ranges_wanted`). See `DEPOT_RANGE.md`.

## Empty tanks stay in Depot range

- A vehicle with an empty tank moves on Depot power inside a friendly Depot's range. It used to be able to drive straight out of the range and be stranded.
- Now it stops at the edge, says "No fuel · can't leave Depot range", and warns once in the feed. Its order waits: with fuel again it goes on (`unit_agent.gd` `_walk`, `NO_FUEL_EDGE`).
- A vehicle with some fuel may still leave the range and use it up out there. See `FUEL_BATCH.md`.

## Emptied crates leave the map

- A crate on the ground that is emptied, by workers gathering from it or a vehicle refuelling from it, disappears, as a dropped pile does (`supply_crate.gd` `extract`).
- A vehicle unloading on open ground no longer sets down crates that are empty.
- Workers can still deliver into a part-filled crate. See `CRATE_CONTAINERS.md`.

## Minimap deposits

- **Coal** is a black diamond in an amber rim: each coal field that still holds coal, and each mine built on a seam.
- **Iron** is a steel-blue peak: each mine site and mine, and each iron ore field.
- A selected mine is ringed in white.
- Before, coal was a small pale diamond, mines were grey "neutral building" squares, and iron ore fields were not drawn at all.
- `tactical_minimap.gd` `draw_coal`, `draw_iron`.

## Plans need sight

- A plan placed from the Build page needs sight of every cell of its site. Out of sight the preview is red, says "out of sight", and a click is refused with a note (`DepotNetwork.in_sight`, `OUT_OF_SIGHT`).
- A Cargo vehicle's Worksite is the exception: it can still place a site out of sight, since the trucks drive out to it. See `FOG_OF_WAR.md`.

## Depots wear their side's colour

- The Depot model, with its parked truck, has `team_color` surfaces that were never painted: team paint was only applied to units. It now takes its side's paint, and changes with it when the Depot is captured (`depot.gd` `paint_team`). See `TEAM_MARKERS.md`.

## The Deforester

- The worker unit is now called the **Deforester** everywhere the player reads it: its name, cards, notes and tooltips (`assets/units/infantry.tres` `display_name`). "Infantry" can then mean every Barracks unit.
- Its id stays `infantry`, so scenes, saves and code are unchanged.

## Rendered pictures

- The unit and building icons, the portraits and the production and build tiles are now pictures rendered from the game's own models. See `HUD_RENDERS.md`.

## Production picks its Depot

- The "Assign Depot" list on Barracks and Tank Factories is gone (asked for on 2026-11-19).
- A Barracks or Tank Factory pays from a friendly Depot whose range covers it, picked by the game (`production_building.gd` `source_friendly`, `payer_for`):
  - It keeps the Depot it has while that one stays friendly.
  - If that Depot is lost, it takes the nearest friendly Depot covering it.
  - If a unit costs more than that Depot holds, it pays from the nearest covering Depot that can, which becomes its Depot.
  - With no friendly Depot in range it can't produce, and says so.
- The production tiles grey out only when no covering Depot can pay, and their tooltip names the one that would.
- Capturing a Depot still cancels the queue it was paying for, as before.

The Ubermech got its renders once its walker model landed (`HUD_RENDERS.md`).
