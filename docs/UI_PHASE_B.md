# UI phase B: selection panels

Phase B of `UI_OVERHAUL_PLAN.md`, on branch `feature/ui-selection-panels` from main `0afacd5`.

## Layout (top to bottom)

- **Header:** an icon for the object type, the name, and a muted state line (team and state, the route for a routed vehicle, or territory and generation for a Depot).
- **Health:** the health bar, with "Health N / M" right-aligned under it.
- **Bars:** a label, the bar and the value.
  - Fuel is labelled "Tank fuel" on Cargo vehicles and Trains.
  - The cargo bar is for Infantry ("4 / 10 iron").
- **Storage:** Depots, Cargo vehicles and Trains, plus a generator's assigned Depot. It's one bar split by resource (energy, iron, wood, coal) against capacity, with "1,760 / 2,000" and a legend of exact amounts.
- **Production:** shown only while something is queued, as "Producing · Cargo vehicle 62% · 1 more queued" with a progress bar. Mines reuse it for their remaining iron.
- **Route:** for a routed vehicle, a slim line from the load Depot to the unload Depot showing how far along it is.
- **Stats:** plain label and value pairs with no boxes: speed, range, damage, vision, damage against buildings, splash and cost. Generators show output, fuel, cycle and mode. Production buildings show their payer's funds and queue.
- **Abilities:** one muted line, for example "Fires while moving · Clears forest".
- **Train round trip:** a white tick on the fuel bar marks the estimated round-trip fuel. The amber warning line appears when the tank is short, and the notes say "Round trip needs about N coal".
- **Notes:** short muted lines: the nearest Depot, the fuel and auto-refuel state, and the Depot queue or capture state.

Four new SVG icons were added: depot, factory, mine and plan.

## Compatibility

- `Info/Name` moved to `Info/Head/Text/Name`. Nothing outside the HUD uses it.
- `HealthText` and `Details` keep their paths, and the strings that tests check ("N / M", "Nearest Depot", "LOW FUEL", "Auto-refuel off") stay in them.
- No existing test was changed.

## Not included

- Crated storage shown lighter, which waits for phase E.
- Map labels, which are phase C.
- Mixed selections still show the first unit's panel, with the type strip from the HUD layout phase.

## Validation

- `tests/selection_panels_test.gd` (headless) checks:
  - the Depot header, storage numbers, segments and legend;
  - production visible only while queued, with its label, value and progress;
  - the Infantry cargo value, stats and notes;
  - Tank fuel, stats including the building-damage pairs, the abilities line, and stat values with no box style;
  - Cargo vehicle storage, separate tank fuel and the route line;
  - generator stats and mine reserves;
  - the Train round-trip tick, note and warning.
- `tests/selection_panels_runtime_check.gd` (rendered) uses real clicks on a Tank, a Cargo vehicle, a producing Depot and a routed Train, and checks each panel fits the window. Its screenshots are `tank_panel`, `cargo_panel`, `depot_panel` and `train_panel`.
