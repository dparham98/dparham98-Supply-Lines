# Rally points

Asked for on 2026-11-18: buildings send the units they make to a rally point.

## Setting one

- **Set:** select your Barracks, Tank Factory or Depot, with no units selected, and right-click the ground or the minimap.
- **Add stops:** Shift-right-click adds a stop after the last one, up to 8. A new unit goes through them in order, like Shift-queued orders.
- **Gather:** a right-click on a forest or another resource makes it a gather stop. Units that gather (Infantry) gather there; other units just drive to it.
- **Clear:** a right-click on the building itself clears its rally points. New units then wait by the exit, as before.
- **Show:** with the building selected, its rally path is drawn as a green dashed line from the building, with a flag at each stop.

## Which units

- **Barracks and Tank Factory:** everything they make.
- **Depot:** its Cargo vehicles, Depot trucks and the free construction Infantry of a new Depot. Trains stay on their track.

A unit made with a rally point starts on it straight away. An order you give it replaces the rally orders.

## Code and checks

- `scripts/production/rally.gd`: adding stops, sending a new unit along them, and the path to draw.
- `rally_points` on `production_building.gd` and `depot.gd`.
- `rally_building` and `set_rally` in `skirmish.gd`.
- `rally_path` in `map_overlay.gd`.
- `tests/rally_autofell_test.gd` (headless):
  - setting a stop, adding one with Shift, and the drawn path;
  - a new Infantry following both stops;
  - a forest stop that gathers;
  - a right-click with units selected still ordering them;
  - clearing the rally;
  - a Depot's cargo vehicle using it.
- `tests/rally_runtime_check.gd` (rendered) saves `rally_barracks` and `fell_autocast` in `rally_work/`.
