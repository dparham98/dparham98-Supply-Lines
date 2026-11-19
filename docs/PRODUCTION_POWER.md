# Production queues and power

Asked for on 2026-11-18. Barracks and Tank Factories now queue up to five units. The player can put more energy into each building to print faster. Units at the base energy take longer than before.

## Build times

Before this change, every unit printed in a flat 3 seconds (`print_seconds` on the building's stats). Each unit now has its own `build_seconds` in `assets/units/*.tres`. That is the time at 1x power, its base energy cost:

| Building | Unit | Energy | Build time at 1x | At 4x |
|---|---|---|---|---|
| Barracks | Scout | 35 E | 8 s | 2 s |
| Barracks | Infantry | 100 E | 10 s | 2.5 s |
| Barracks | Grenadier | 85 E | 12 s | 3 s |
| Tank Factory | Motorcycle | 45 E | 14 s | 3.5 s |
| Tank Factory | Drone | 60 E | 16 s | 4 s |
| Tank Factory | Tank | 150 E | 28 s | 7 s |
| Tank Factory | Übermech | 250 E | 40 s | 10 s |

So Barracks units at full power print in about the old time or a little under it. A Tank never gets near it. The times and costs are provisional and can be edited.

## Power

Each production building has a power setting, from 1x up to `max_power` (4x) in steps of `power_step` (0.5). Both are on `assets/buildings/barracks.tres` and `tank_factory.tres`.

At power p a unit:

- prints in its build time divided by p;
- costs p times its base energy. The base cost is paid when it is queued, as before. The rest, (p − 1) times the base, is drawn from the assigned Depot while it prints, in step with the progress. Iron is unchanged.

At 2x an Infantry takes 5 s and 200 E. At 4x it takes 2.5 s and 400 E.

The setting belongs to the building and applies to whichever unit it is printing. Changing it part way changes the rest of that unit. If the assigned Depot cannot pay for the extra power, the unit carries on at 1x, without drawing anything, until there is energy again. The panel then says so.

The Depot's own queue (Cargo Vehicles, Depot Trucks, Trains) keeps its print times and limit of 3.

## The panel

Selecting one of your Barracks or Tank Factories shows a **Production speed** panel under the Depot panels (`ProductionPanel` in `scenes/ui/skirmish_hud.tscn`). It has:

- the power slider, with the setting next to it ("2.0x energy");
- a line with what that means for the unit printing now, or the building's first unit when it is idle, for example "Infantry: 5 s for 200 E (base 10 s, 100 E)".

The building's progress bar, its Status label and the minimap production rings all use the new times (`fraction()` in `production_building.gd`).

## Checks

`tests/production_power_test.gd`:

- checks the build times;
- checks that five units queue and a sixth is refused without payment;
- checks Infantry at 1x (10 s, no extra), 2x (5 s, 100 E extra) and 4x (2.5 s, 300 E extra);
- checks the snapping and limits of the setting;
- checks a Depot with no energy printing at 1x and the power coming back;
- checks a Tank at 4x (7 s, 450 E extra);
- checks the panel and slider.
