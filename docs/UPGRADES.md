# Attack and armour upgrades

Item 11 of the balance handoff (`docs/BALANCE_IMPLEMENTATION_HANDOFF.md` on the balance branch), 2026-11-25. Every number is a play-test starting point.

## Buildings

| Building | Side | Cost | Size | Researches |
| --- | --- | --- | --- | --- |
| **Foundry** (O on the Build page) | Cyborgs | 150 E / 80 I, built as any Cyborg building | 6 × 6 | Infantry Weapons, Infantry Armour, Vehicle Weapons, Vehicle Armour |
| **Forge** (O on the Build page) | Knights | 60 W / 80 I, from a covering Keep's stock, else on site | 6 × 6 | Arms, Mail |

Both work as the Temple of Science does (`docs/TEMPLE_OF_SCIENCE.md`, `scripts/buildings/temple_of_science.gd`):
- a research is paid when it starts, from a friendly stockpile whose range covers the building;
- Cancel gives the cost back;
- one research at a time per building;
- a finished level holds for the whole side.

**Who pays:** the Foundry pays in Energy and Iron from a Depot. The Forge pays in Food and Iron from a Keep.

**Models:** placeholders. The Foundry shows the Temple's model and the Forge the Chapterhouse's (`scenes/gameplay/foundry.tscn`, `forge.tscn`).

## Levels

Each line has three levels, researched in order. Level n needs level n−1 first.

| Level | Foundry pays | Forge pays | Time |
| --- | --- | --- | --- |
| I | 100 E / 150 I | 100 F / 150 I | 60 s |
| II | 150 E / 250 I | 150 F / 250 I | 90 s |
| III | 200 E / 350 I | 200 F / 350 I | 120 s |

Each level is its own research, `assets/research/upgrades/<line>_<n>.tres` (for example `infantry_weapons_2`). `ResearchStats` gained `food_cost`, `line` and `level`.

## Effects

`scripts/research/upgrades.gd` (`Upgrades`):
- **Attack:** each level adds 10% of the weapon's base damage, rounded, at least 1 (`with_attack`). With two levels a 4 becomes 6 and a 20 becomes 24. It applies in `CombatResolver.splash_damage`, so it covers splash and heavy damage too.
- **Armour:** each level takes 1 off every hit the unit takes, never below 1 (`after_armour`). It applies in `unit_agent.take_damage`, so it covers every source of damage.

**Which units a line covers:**
- **Cyborgs:** vehicles (anything with fuel, `EngineeringWork.is_vehicle`) get the Vehicle lines; everything else gets the Infantry lines.
- **Knights:** Arms and Mail cover every unit.

Buildings get no upgrades.

## HUD

The Foundry's and Forge's card shows one tile per line (Q, W, E, R), each offering the line's next level with its cost and time. When the line is done the tile is greyed out. The details line shows each line's level, such as "Infantry Weapons 1/3".

## Checks

`tests/upgrades_test.gd` (headless) covers:
- the Foundry's and Forge's plan specs and Build page tiles;
- the order of levels, the costs and times, and the refund on Cancel;
- the Foundry card's tiles;
- attack and armour numbers per level, and that infantry and vehicle lines stay apart;
- a real hit through the resolver;
- the Forge paid by a Keep in Food and Iron, its card and Arms and Mail on a Round Table Marine.

## Not done

- **AI:** neither AI builds a Foundry or a Forge, or researches upgrades.
- **Art:** no models or card art of their own.
- **Unit card:** the unit panel doesn't yet show the upgraded damage or armour.
